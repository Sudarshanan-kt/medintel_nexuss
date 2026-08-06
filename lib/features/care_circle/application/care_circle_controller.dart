import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/auth_controller.dart';
import '../../reminders/adherence_controller.dart';
import '../../reminders/data/medicines_repository.dart';
import '../data/care_circle_repository.dart';
import '../domain/care_circle_models.dart';

/// A linked patient paired with their adherence, computed the same way the
/// patient's own device would (computeAdherenceState) but from remotely
/// fetched dose logs, readable via the additive RLS policy.
class LinkedPatientView {
  const LinkedPatientView({required this.member, required this.adherence});
  final CareCircleMember member;
  final AdherenceState adherence;
}

class CareCircleState {
  const CareCircleState({
    this.myCaregivers = const [],
    this.linkedPatients = const [],
    this.loading = false,
    this.error,
  });

  /// Caregivers linked to *me* as a patient — my own "who can see my data".
  final List<CareCircleMember> myCaregivers;

  /// Patients *I* (as a caregiver) am linked to, with their adherence.
  final List<LinkedPatientView> linkedPatients;

  final bool loading;
  final String? error;

  CareCircleState copyWith({
    List<CareCircleMember>? myCaregivers,
    List<LinkedPatientView>? linkedPatients,
    bool? loading,
    String? error,
  }) {
    return CareCircleState(
      myCaregivers: myCaregivers ?? this.myCaregivers,
      linkedPatients: linkedPatients ?? this.linkedPatients,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class CareCircleController extends Notifier<CareCircleState> {
  CareCircleRepository get _repo => ref.read(careCircleRepositoryProvider);
  MedicinesRepository get _medsRepo => ref.read(medicinesRepositoryProvider);

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  String get _displayName =>
      ref.read(authControllerProvider).valueOrNull?.user?.displayName ??
      'there';

  @override
  CareCircleState build() {
    Future.microtask(refresh);
    return const CareCircleState();
  }

  Future<void> refresh() async {
    final uid = _userId;
    if (uid == null) return;
    state = state.copyWith(loading: true, error: null);
    try {
      final caregivers = await _repo.listMyCaregivers(uid);
      final members = await _repo.listLinkedPatients(uid);

      final views = <LinkedPatientView>[];
      for (final m in members) {
        final logs = await _medsRepo.fetchAllDoseLogs(m.patientId);
        views.add(
          LinkedPatientView(
            member: m,
            adherence: computeAdherenceState(logs),
          ),
        );
      }

      state = state.copyWith(
        myCaregivers: caregivers,
        linkedPatients: views,
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'Could not load your care circle. Check your connection.',
      );
    }
  }

  /// Creates a new invite and returns the shareable code.
  Future<String> createInvite() async {
    final uid = _userId;
    if (uid == null) {
      throw Exception('Session expired. Please sign in again.');
    }
    final code = await _repo.createInvite(
      patientId: uid,
      patientDisplayName: _displayName,
    );
    await refresh();
    return code;
  }

  Future<void> removeCaregiver(String memberId) async {
    await _repo.removeCaregiver(memberId);
    await refresh();
  }

  /// Accepts an invite as the signed-in user (acting as caregiver).
  Future<void> acceptInvite(String code) async {
    final uid = _userId;
    if (uid == null) {
      throw Exception('Session expired. Please sign in again.');
    }
    await _repo.acceptInvite(
      code: code,
      caregiverId: uid,
      caregiverDisplayName: _displayName,
    );
    await refresh();
  }
}

final careCircleControllerProvider =
    NotifierProvider<CareCircleController, CareCircleState>(
  CareCircleController.new,
);
