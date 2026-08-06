import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/medical_report.dart';

/// Supabase-backed persistence for the patient's report library.
///
/// Table DDL (run once in the Supabase SQL editor):
/// ```sql
/// create table if not exists public.reports (
///   id         text primary key,
///   user_id    uuid not null references auth.users(id) on delete cascade,
///   payload    jsonb not null,
///   created_at timestamptz default now()
/// );
/// alter table public.reports enable row level security;
/// create policy "Users manage own reports"
///   on public.reports for all
///   using  (auth.uid() = user_id)
///   with check (auth.uid() = user_id);
/// ```
class ReportsRepository {
  ReportsRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _table = 'reports';

  // ── Upsert ────────────────────────────────────────────────────────────────

  /// Saves or updates a single report row. Fire-and-forget safe.
  Future<void> upsert(String userId, MedicalReport report) async {
    await _supabase.from(_table).upsert(
      {
        'id': report.id,
        'user_id': userId,
        'payload': report.toJson(),
      },
      onConflict: 'id',
    );
  }

  // ── Fetch all ─────────────────────────────────────────────────────────────

  /// Returns all reports for [userId], ordered newest-first.
  /// Returns an empty list on any error.
  Future<List<MedicalReport>> fetchAll(String userId) async {
    try {
      final rows = await _supabase
          .from(_table)
          .select('payload')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return rows
          .map((row) {
            try {
              final payload = row['payload'];
              if (payload is Map<String, dynamic>) {
                return MedicalReport.fromJson(payload);
              }
              return null;
            } catch (_) {
              return null;
            }
          })
          .whereType<MedicalReport>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Deletes a single report row. Fire-and-forget safe.
  Future<void> delete(String userId, String reportId) async {
    await _supabase
        .from(_table)
        .delete()
        .eq('user_id', userId)
        .eq('id', reportId);
  }
}

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) {
  return ReportsRepository(Supabase.instance.client);
});
