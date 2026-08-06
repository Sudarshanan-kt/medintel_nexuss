import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase repository for FCM device token registration.
///
/// The client writes its own token directly (RLS `auth.uid() = user_id`) —
/// no backend involvement needed for registration. Only *sending* a push
/// (reading tokens across users from a server-side job) needs elevated
/// access, which lives in a Supabase Edge Function, not here.
///
/// Table DDL (run once in the Supabase SQL editor):
/// ```sql
/// create table if not exists public.device_tokens (
///   id          text primary key,
///   user_id     uuid not null references auth.users(id) on delete cascade,
///   fcm_token   text not null,
///   platform    text not null default 'android',
///   updated_at  timestamptz default now(),
///   unique(user_id, fcm_token)
/// );
/// alter table public.device_tokens enable row level security;
/// create policy "Users manage own device tokens" on public.device_tokens
///   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
/// ```
class PushTokenRepository {
  PushTokenRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _table = 'device_tokens';

  Future<void> registerToken({
    required String userId,
    required String fcmToken,
    required String platform,
  }) async {
    await _supabase.from(_table).upsert(
      {
        'id': '${userId}_$fcmToken'.hashCode.toString(),
        'user_id': userId,
        'fcm_token': fcmToken,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'user_id,fcm_token',
    );
  }

  /// Called on sign-out so a shared/reset device stops receiving this
  /// user's pushes.
  Future<void> removeToken({
    required String userId,
    required String fcmToken,
  }) async {
    await _supabase
        .from(_table)
        .delete()
        .eq('user_id', userId)
        .eq('fcm_token', fcmToken);
  }
}

final pushTokenRepositoryProvider = Provider<PushTokenRepository>((ref) {
  return PushTokenRepository(Supabase.instance.client);
});
