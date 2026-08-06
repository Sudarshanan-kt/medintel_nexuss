import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/medicine.dart';

/// Supabase repository for syncing Medicines and Dose Logs.
///
/// Table DDLs (run once in the Supabase SQL editor):
/// ```sql
/// create table if not exists public.medicines (
///   id         text primary key,
///   user_id    uuid not null references auth.users(id) on delete cascade,
///   payload    jsonb not null,
///   created_at timestamptz default now()
/// );
/// alter table public.medicines enable row level security;
/// create policy "Users manage own medicines"
///   on public.medicines for all
///   using (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
///
/// create table if not exists public.medicine_logs (
///   id           text primary key,
///   user_id      uuid not null references auth.users(id) on delete cascade,
///   medicine_id  text not null,
///   payload      jsonb not null,
///   created_at   timestamptz default now()
/// );
/// alter table public.medicine_logs enable row level security;
/// create policy "Users manage own medicine logs"
///   on public.medicine_logs for all
///   using (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
/// ```
class MedicinesRepository {
  MedicinesRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _medsTable = 'medicines';
  static const _logsTable = 'medicine_logs';

  // ── Medicines ─────────────────────────────────────────────────────────────

  Future<void> upsertMedicine(String userId, Medicine med) async {
    await _supabase.from(_medsTable).upsert(
      {
        'id': med.id,
        'user_id': userId,
        'payload': med.toJson(),
      },
      onConflict: 'id',
    );
  }

  Future<List<Medicine>> fetchAllMedicines(String userId) async {
    try {
      final rows = await _supabase
          .from(_medsTable)
          .select('payload')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return rows
          .map((row) {
            try {
              final p = row['payload'];
              if (p is Map<String, dynamic>) {
                return Medicine.fromJson(p);
              }
              return null;
            } catch (_) {
              return null;
            }
          })
          .whereType<Medicine>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteMedicine(String userId, String id) async {
    await _supabase
        .from(_medsTable)
        .delete()
        .eq('user_id', userId)
        .eq('id', id);
  }

  // ── Dose Logs ─────────────────────────────────────────────────────────────

  Future<void> upsertDoseLog(String userId, DoseLog log) async {
    await _supabase.from(_logsTable).upsert(
      {
        'id': log.id,
        'user_id': userId,
        'medicine_id': log.medicineId,
        'payload': log.toJson(),
      },
      onConflict: 'id',
    );
  }

  Future<List<DoseLog>> fetchAllDoseLogs(String userId) async {
    try {
      final rows = await _supabase
          .from(_logsTable)
          .select('payload')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return rows
          .map((row) {
            try {
              final p = row['payload'];
              if (p is Map<String, dynamic>) {
                return DoseLog.fromJson(p);
              }
              return null;
            } catch (_) {
              return null;
            }
          })
          .whereType<DoseLog>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteDoseLog(String userId, String id) async {
    await _supabase
        .from(_logsTable)
        .delete()
        .eq('user_id', userId)
        .eq('id', id);
  }
}

final medicinesRepositoryProvider = Provider<MedicinesRepository>((ref) {
  return MedicinesRepository(Supabase.instance.client);
});
