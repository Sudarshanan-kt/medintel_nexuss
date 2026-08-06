import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_user.dart';

/// Resolves and persists which [UserRole] an account holds — patient or
/// caregiver — separate from `health_profiles` (patient-only medical data)
/// so a caregiver account is never required to complete health onboarding.
///
/// The `profiles` table schema (create via Supabase SQL editor):
/// ```sql
/// create table if not exists public.profiles (
///   id           uuid primary key references auth.users(id) on delete cascade,
///   role         text not null default 'patient' check (role in ('patient', 'caregiver')),
///   display_name text,
///   created_at   timestamptz default now()
/// );
/// alter table public.profiles enable row level security;
/// create policy "Users manage their own profile row" on public.profiles
///   for all using (auth.uid() = id) with check (auth.uid() = id);
/// ```
class ProfileRepository {
  ProfileRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _table = 'profiles';

  /// Returns the stored role for [userId], creating the row with
  /// [defaultRole] if none exists yet.
  ///
  /// Every account gets a row lazily on first resolution rather than
  /// eagerly at sign-up time, so this also self-heals accounts created
  /// before email confirmation completed (no session existed yet to write
  /// with) — the intended role travels as `pending_role` in Supabase auth
  /// user metadata (set at sign-up regardless of session state) and is
  /// read back into [defaultRole] by the caller.
  Future<UserRole> ensureAndFetchRole({
    required String userId,
    required UserRole defaultRole,
    String? displayName,
  }) async {
    final existing = await _supabase
        .from(_table)
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    if (existing != null) {
      return _parseRole(existing['role'] as String?);
    }
    try {
      await _supabase.from(_table).insert({
        'id': userId,
        'role': _roleString(defaultRole),
        if (displayName != null && displayName.isNotEmpty)
          'display_name': displayName,
      });
    } on PostgrestException catch (e) {
      // Row created concurrently (e.g. duplicate auth event) — harmless.
      if (e.code != '23505') rethrow;
    }
    return defaultRole;
  }

  String _roleString(UserRole role) =>
      role == UserRole.caregiver ? 'caregiver' : 'patient';

  UserRole _parseRole(String? role) =>
      role == 'caregiver' ? UserRole.caregiver : UserRole.patient;
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(Supabase.instance.client),
);
