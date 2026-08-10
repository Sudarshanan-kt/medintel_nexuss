import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/care_circle_models.dart';

/// Supabase repository for the Family/Caregiver Circle feature.
///
/// Schema lives in `supabase/migrations/`, not in this comment — the DDL
/// that used to sit here drifted out of sync with what the feature actually
/// needs and shipped two holes with it (see
/// `20260810090400_care_circle_invite_hardening.sql`). Apply with
/// `supabase db push`.
///
/// Two things about the design that this file depends on:
///
/// Display names are snapshotted onto the invite/membership rows at
/// creation/accept time rather than joined from `health_profiles` at read
/// time. That deliberately keeps the rest of a patient's health profile
/// un-exposed to caregivers in v1 — only adherence data (medicines and
/// medicine_logs) is shared, via additive read-only policies.
///
/// A caregiver has no direct access to `care_circle_invites` whatsoever.
/// Previewing and redeeming a code both go through security-definer
/// functions that require the exact code, so there is no query that returns
/// a list of invites and no way to act on one you were not given.
class CareCircleRepository {
  CareCircleRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _invitesTable = 'care_circle_invites';
  static const _membersTable = 'care_circle_members';

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  // ── Invites (patient side) ───────────────────────────────────────────────

  /// Creates a new pending invite for [patientId] and returns the shareable
  /// code. Retries on the rare 6-character code collision — the table's
  /// unique constraint on invite_code makes this safe either way.
  Future<String> createInvite({
    required String patientId,
    required String patientDisplayName,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final code = _generateCode();
      try {
        await _supabase.from(_invitesTable).insert({
          'id': 'inv_${DateTime.now().microsecondsSinceEpoch}',
          'patient_id': patientId,
          'patient_display_name': patientDisplayName,
          'invite_code': code,
          'status': 'pending',
        });
        return code;
      } on PostgrestException catch (e) {
        if (e.code == '23505' && attempt < 2) continue; // unique violation
        rethrow;
      }
    }
    throw Exception('Could not generate a unique invite code — try again.');
  }

  /// Looks up an invite by its exact code, for the "whose circle am I
  /// joining?" preview.
  ///
  /// Goes through an RPC rather than selecting the table: a caregiver has no
  /// read policy on `care_circle_invites` at all, deliberately. The table
  /// used to be world-readable to any signed-in user, which handed out the
  /// patient_id of everyone with an invite open — see
  /// `20260810090400_care_circle_invite_hardening.sql`.
  Future<CareCircleInvite?> lookupInvite(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return null;
    final rows = await _supabase
        .rpc('peek_care_circle_invite', params: {'p_code': trimmed}) as List;
    if (rows.isEmpty) return null;
    return CareCircleInvite.fromRow(rows.first as Map<String, dynamic>);
  }

  // ── Accept (caregiver side) ──────────────────────────────────────────────

  /// Accepts an invite as the currently-signed-in caregiver.
  ///
  /// The whole redemption — validate the code, link the caregiver, consume
  /// the invite — happens in one server-side function. Doing it client-side
  /// could not be made safe: the caregiver has no policy that lets them mark
  /// an invite accepted, so the old code's "mark accepted" UPDATE matched
  /// zero rows and failed silently, leaving every invite live for its full
  /// seven days.
  ///
  /// [caregiverId] is not sent. The function reads the caller's identity
  /// from the JWT, so a tampered client cannot link a different account.
  Future<void> acceptInvite({
    required String code,
    required String caregiverId,
    required String caregiverDisplayName,
  }) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) {
      throw Exception('This invite is invalid or has expired.');
    }
    try {
      await _supabase.rpc(
        'accept_care_circle_invite',
        params: {
          'p_code': trimmed,
          'p_caregiver_display_name': caregiverDisplayName,
        },
      );
    } on PostgrestException catch (e) {
      // The function raises the patient-facing wording already; surface it
      // rather than a generic failure.
      throw Exception(e.message);
    }
  }

  // ── Members (patient's own "My Circle" view) ─────────────────────────────

  Future<List<CareCircleMember>> listMyCaregivers(String patientId) async {
    final rows = await _supabase
        .from(_membersTable)
        .select()
        .eq('patient_id', patientId)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return rows.map(CareCircleMember.fromRow).toList();
  }

  Future<void> removeCaregiver(String memberId) async {
    await _supabase
        .from(_membersTable)
        .update({'status': 'removed'}).eq('id', memberId);
  }

  // ── Linked patients (caregiver's own view) ───────────────────────────────

  Future<List<CareCircleMember>> listLinkedPatients(String caregiverId) async {
    final rows = await _supabase
        .from(_membersTable)
        .select()
        .eq('caregiver_id', caregiverId)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return rows.map(CareCircleMember.fromRow).toList();
  }
}

final careCircleRepositoryProvider = Provider<CareCircleRepository>((ref) {
  return CareCircleRepository(Supabase.instance.client);
});
