import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/emergency_event.dart';

/// Supabase repository for persisting Emergency SOS Events.
///
/// Table DDL (run once in the Supabase SQL editor):
/// ```sql
/// create table if not exists public.sos_events (
///   id         text primary key,
///   user_id    uuid not null references auth.users(id) on delete cascade,
///   payload    jsonb not null,
///   created_at timestamptz default now()
/// );
/// alter table public.sos_events enable row level security;
/// create policy "Users manage own SOS events"
///   on public.sos_events for all
///   using (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
/// ```
class SosRepository {
  SosRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _table = 'sos_events';

  Future<void> upsertEvent(String userId, EmergencyEvent event) async {
    await _supabase.from(_table).upsert(
      {
        'id': event.id,
        'user_id': userId,
        'payload': event.toJson(),
      },
      onConflict: 'id',
    );
  }

  Future<List<EmergencyEvent>> fetchAllEvents(String userId) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select('payload')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return rows
          .map((row) {
            try {
              final p = row['payload'];
              if (p is Map<String, dynamic>) {
                return EmergencyEvent.fromJson(p);
              }
              return null;
            } catch (_) {
              return null;
            }
          })
          .whereType<EmergencyEvent>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteEvent(String userId, String id) async {
    await _supabase.from(_table).delete().eq('user_id', userId).eq('id', id);
  }
}

final sosRepositoryProvider = Provider<SosRepository>((ref) {
  return SosRepository(Supabase.instance.client);
});
