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
      // Row created concurrently (e.g. duplicate auth event). The row that
      // won is the one the account actually has, and it need not hold the
      // role we were about to write — so read it back rather than returning
      // a role that was never stored. Reporting the unstored one is how a
      // caregiver used to reach a caregiver dashboard on the sign-in itself
      // and the patient one on every launch after.
      if (e.code != '23505') rethrow;
      final winner = await _supabase
          .from(_table)
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      return _parseRole(winner?['role'] as String?);
    }
    return defaultRole;
  }

  /// Writes [role] onto [userId]'s own profile row.
  ///
  /// RLS confines this to the signed-in user's row, so this can only ever
  /// change the role of the account holding the session — never anyone
  /// else's. Callers are responsible for the *policy* question of whether
  /// this account should be allowed to change its own role; see
  /// [AuthController.claimCaregiverAccount], which is the only caller and
  /// refuses an account that holds patient health data.
  Future<void> setRole({
    required String userId,
    required UserRole role,
  }) async {
    await _supabase
        .from(_table)
        .update({'role': _roleString(role)}).eq('id', userId);
  }

  String _roleString(UserRole role) =>
      role == UserRole.caregiver ? 'caregiver' : 'patient';

  UserRole _parseRole(String? role) =>
      role == 'caregiver' ? UserRole.caregiver : UserRole.patient;
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(Supabase.instance.client),
);
