import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/vital_reading.dart';

/// Supabase repository for self-logged vitals (blood pressure, weight,
/// blood sugar) — the patient's own ongoing journal, distinct from
/// MedicalReport.metrics (which come from OCR'd lab documents).
///
/// Table DDL (run once in the Supabase SQL editor):
/// ```sql
/// create table if not exists public.vitals (
///   id         text primary key,
///   user_id    uuid not null references auth.users(id) on delete cascade,
///   payload    jsonb not null,
///   created_at timestamptz default now()
/// );
/// alter table public.vitals enable row level security;
/// create policy "Users manage own vitals" on public.vitals
///   for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
/// ```
class VitalsRepository {
  VitalsRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _table = 'vitals';

  Future<void> upsertReading(String userId, VitalReading reading) async {
    await _supabase.from(_table).upsert(
      {
        'id': reading.id,
        'user_id': userId,
        'payload': reading.toJson(),
      },
      onConflict: 'id',
    );
  }

  Future<List<VitalReading>> fetchAll(String userId) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select('payload')
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return rows
          .map((row) {
            final p = row['payload'];
            if (p is Map<String, dynamic>) return VitalReading.fromJson(p);
            return null;
          })
          .whereType<VitalReading>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteReading(String userId, String id) async {
    await _supabase.from(_table).delete().eq('user_id', userId).eq('id', id);
  }
}

final vitalsRepositoryProvider = Provider<VitalsRepository>((ref) {
  return VitalsRepository(Supabase.instance.client);
});
