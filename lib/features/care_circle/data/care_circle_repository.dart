import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/care_circle_models.dart';

/// Supabase repository for the Family/Caregiver Circle feature.
///
/// Table DDLs (run once in the Supabase SQL editor). Display names are
/// snapshotted onto the invite/membership rows at creation/accept time
/// rather than joined from `health_profiles` at read time — deliberately
/// keeps the rest of a patient's health profile un-exposed to caregivers in
/// v1; only adherence data (medicines/medicine_logs) is shared, via the
/// additive policies at the bottom.
/// ```sql
/// create table if not exists public.care_circle_invites (
///   id                    text primary key,
///   patient_id            uuid not null references auth.users(id) on delete cascade,
///   patient_display_name  text not null default 'Patient',
///   invite_code           text not null unique,
///   status                text not null default 'pending',
///   created_at            timestamptz default now(),
///   expires_at            timestamptz not null default (now() + interval '7 days')
/// );
/// alter table public.care_circle_invites enable row level security;
/// create policy "Patient manages own invites" on public.care_circle_invites
///   for all using (auth.uid() = patient_id) with check (auth.uid() = patient_id);
/// create policy "Anyone can look up an invite by code" on public.care_circle_invites
///   for select using (true);
///
/// create table if not exists public.care_circle_members (
///   id                      text primary key,
///   patient_id              uuid not null references auth.users(id) on delete cascade,
///   patient_display_name    text not null default 'Patient',
///   caregiver_id            uuid not null references auth.users(id) on delete cascade,
///   caregiver_display_name  text not null default 'Caregiver',
///   status                  text not null default 'active',
///   created_at              timestamptz default now(),
///   unique(patient_id, caregiver_id)
/// );
/// alter table public.care_circle_members enable row level security;
/// create policy "Patient manages own circle" on public.care_circle_members
///   for all using (auth.uid() = patient_id) with check (auth.uid() = patient_id);
/// create policy "Caregiver reads own memberships" on public.care_circle_members
///   for select using (auth.uid() = caregiver_id);
/// create policy "Invitee can accept a pending invite" on public.care_circle_members
///   for insert with check (
///     auth.uid() = caregiver_id
///     and exists (
///       select 1 from public.care_circle_invites i
///       where i.patient_id = care_circle_members.patient_id
///         and i.status = 'pending'
///         and i.expires_at > now()
///     )
///   );
///
/// -- Additive read-only policies layered on top of the patient's own
/// -- ownership policy (Postgres RLS policies OR together for the same
/// -- command) so a linked, active caregiver can read — never write —
/// -- a patient's medicines and dose logs.
/// create policy "Caregivers read linked patient medicines" on public.medicines
///   for select using (
///     exists (
///       select 1 from public.care_circle_members m
///       where m.patient_id = medicines.user_id
///         and m.caregiver_id = auth.uid()
///         and m.status = 'active'
///     )
///   );
/// create policy "Caregivers read linked patient dose logs" on public.medicine_logs
///   for select using (
///     exists (
///       select 1 from public.care_circle_members m
///       where m.patient_id = medicine_logs.user_id
///         and m.caregiver_id = auth.uid()
///         and m.status = 'active'
///     )
///   );
/// ```
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

  Future<CareCircleInvite?> lookupInvite(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return null;
    final rows = await _supabase
        .from(_invitesTable)
        .select()
        .eq('invite_code', trimmed)
        .limit(1);
    if (rows.isEmpty) return null;
    return CareCircleInvite.fromRow(rows.first);
  }

  // ── Accept (caregiver side) ──────────────────────────────────────────────

  /// Accepts an invite as the currently-signed-in caregiver. RLS
  /// independently re-checks the invite is pending & unexpired at insert
  /// time, so this is safe even if the local check races with expiry.
  Future<void> acceptInvite({
    required String code,
    required String caregiverId,
    required String caregiverDisplayName,
  }) async {
    final invite = await lookupInvite(code);
    if (invite == null || !invite.isPending) {
      throw Exception('This invite is invalid or has expired.');
    }
    if (invite.patientId == caregiverId) {
      throw Exception("You can't join your own care circle.");
    }
    await _supabase.from(_membersTable).insert({
      'id': 'mem_${DateTime.now().microsecondsSinceEpoch}',
      'patient_id': invite.patientId,
      'patient_display_name': invite.patientDisplayName,
      'caregiver_id': caregiverId,
      'caregiver_display_name': caregiverDisplayName,
      'status': 'active',
    });
    await _supabase
        .from(_invitesTable)
        .update({'status': 'accepted'}).eq('id', invite.id);
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
