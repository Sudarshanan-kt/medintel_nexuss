import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/application/auth_controller.dart';
import '../../reminders/adherence_controller.dart';
import '../../reminders/data/medicines_repository.dart';
import '../../reminders/domain/medicine.dart';
import '../data/care_circle_repository.dart';
import '../domain/care_circle_models.dart';

/// A linked patient paired with their adherence, computed the same way the
/// patient's own device would (computeAdherenceState) but from remotely
/// fetched dose logs, readable via the additive RLS policy.
class LinkedPatientView {
  const LinkedPatientView({
    required this.member,
    required this.adherence,
    this.logs = const [],
    this.medicines = const [],
  });

  final CareCircleMember member;
  final AdherenceState adherence;

  /// The raw logs the adherence figure was computed from, newest first.
  ///
  /// Kept on the view so the detail screen can answer "which dose, and
  /// when?" without a second round trip — the dashboard has already paid
  /// for this data, and a caregiver who taps a worrying percentage should
  /// not then wait on a spinner to find out what caused it.
  final List<DoseLog> logs;

  /// The patient's current regimen, readable via the additive RLS policy.
  final List<Medicine> medicines;

  /// Doses that were logged as missed, newest first.
  List<DoseLog> get missedDoses =>
      logs.where((l) => l.isMissed).toList(growable: false);
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
      final (caregivers, members) = await (
        _repo.listMyCaregivers(uid),
        _repo.listLinkedPatients(uid),
      ).wait;

      // Fetched concurrently. Sequentially this was two round trips per
      // patient, serialised — a caregiver looking after three people paid
      // six in a row before the screen showed anything.
      final views = await Future.wait([
        for (final m in members) _loadPatient(m),
      ]);

      state = state.copyWith(
        myCaregivers: caregivers,
        linkedPatients: views,
        loading: false,
      );
    } catch (_) {
      // Deliberately clears the stale patient list rather than leaving last
      // refresh's numbers on screen. An adherence figure with no timestamp
      // is indistinguishable from a current one, and the screen exists to
      // be trusted at a glance.
      state = state.copyWith(
        linkedPatients: const [],
        loading: false,
        error: 'Could not load your care circle. Check your connection.',
      );
    }
  }

  /// One patient's adherence picture. Throws if either fetch fails, so
  /// [refresh] can tell a real failure from an empty circle.
  Future<LinkedPatientView> _loadPatient(CareCircleMember m) async {
    final (logs, medicines) = await (
      _medsRepo.fetchDoseLogsOrThrow(m.patientId),
      _medsRepo.fetchMedicinesOrThrow(m.patientId),
    ).wait;

    return LinkedPatientView(
      member: m,
      adherence: computeAdherenceState(logs),
      logs: logs,
      medicines: medicines,
    );
  }

  /// The linked patient with this id, or null if the caregiver is no longer
  /// linked to them — which is what a revoked link looks like after a
  /// refresh, and the detail screen has to handle it without crashing.
  LinkedPatientView? patientById(String patientId) {
    for (final p in state.linkedPatients) {
      if (p.member.patientId == patientId) return p;
    }
    return null;
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
