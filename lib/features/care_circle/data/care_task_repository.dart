import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/care_circle_models.dart';

/// Supabase repository for the Care Circle task board.
///
/// Table DDL (run once in the Supabase SQL editor). Access mirrors the
/// additive-policy pattern already used for `medicines`/`medicine_logs` in
/// `care_circle_repository.dart`: the patient owns their own tasks, and any
/// *active* linked caregiver gets the same read/write access — anyone in
/// the circle can post a request, claim one, or mark it done.
/// ```sql
/// create table if not exists public.care_circle_tasks (
///   id                 text primary key,
///   patient_id         uuid not null references auth.users(id) on delete cascade,
///   title              text not null,
///   note               text,
///   due_date           timestamptz,
///   created_by_id      uuid not null,
///   created_by_name    text not null default 'Someone',
///   claimed_by_id      uuid,
///   claimed_by_name    text,
///   status             text not null default 'open',
///   created_at         timestamptz default now()
/// );
/// alter table public.care_circle_tasks enable row level security;
///
/// create policy "Patient manages own tasks" on public.care_circle_tasks
///   for all using (auth.uid() = patient_id) with check (auth.uid() = patient_id);
///
/// create policy "Linked caregivers read circle tasks" on public.care_circle_tasks
///   for select using (
///     exists (
///       select 1 from public.care_circle_members m
///       where m.patient_id = care_circle_tasks.patient_id
///         and m.caregiver_id = auth.uid()
///         and m.status = 'active'
///     )
///   );
///
/// create policy "Linked caregivers post circle tasks" on public.care_circle_tasks
///   for insert with check (
///     auth.uid() = created_by_id
///     and exists (
///       select 1 from public.care_circle_members m
///       where m.patient_id = care_circle_tasks.patient_id
///         and m.caregiver_id = auth.uid()
///         and m.status = 'active'
///     )
///   );
///
/// create policy "Linked caregivers claim/update circle tasks" on public.care_circle_tasks
///   for update using (
///     exists (
///       select 1 from public.care_circle_members m
///       where m.patient_id = care_circle_tasks.patient_id
///         and m.caregiver_id = auth.uid()
///         and m.status = 'active'
///     )
///   );
/// ```
class CareTaskRepository {
  CareTaskRepository(this._supabase);

  final SupabaseClient _supabase;
  static const _table = 'care_circle_tasks';

  Future<List<CareTask>> listTasks(String patientId) async {
    final rows = await _supabase
        .from(_table)
        .select()
        .eq('patient_id', patientId)
        .order('status', ascending: true) // 'claimed' < 'done' < 'open' isn't
        // meaningful alphabetically, so the UI itself groups by status —
        // this ordering only keeps results stable, not sorted by priority.
        .order('created_at', ascending: false);
    return rows.map(CareTask.fromRow).toList();
  }

  Future<void> createTask({
    required String patientId,
    required String title,
    String? note,
    DateTime? dueDate,
    required String createdById,
    required String createdByName,
  }) async {
    await _supabase.from(_table).insert({
      'id': 'task_${DateTime.now().microsecondsSinceEpoch}',
      'patient_id': patientId,
      'title': title,
      'note': note,
      'due_date': dueDate?.toIso8601String(),
      'created_by_id': createdById,
      'created_by_name': createdByName,
      'status': 'open',
    });
  }

  Future<void> claimTask({
    required String taskId,
    required String claimedById,
    required String claimedByName,
  }) async {
    await _supabase.from(_table).update({
      'claimed_by_id': claimedById,
      'claimed_by_name': claimedByName,
      'status': 'claimed',
    }).eq('id', taskId);
  }

  Future<void> unclaimTask(String taskId) async {
    await _supabase.from(_table).update({
      'claimed_by_id': null,
      'claimed_by_name': null,
      'status': 'open',
    }).eq('id', taskId);
  }

  Future<void> completeTask(String taskId) async {
    await _supabase.from(_table).update({'status': 'done'}).eq('id', taskId);
  }

  Future<void> deleteTask(String taskId) async {
    await _supabase.from(_table).delete().eq('id', taskId);
  }
}

final careTaskRepositoryProvider = Provider<CareTaskRepository>((ref) {
  return CareTaskRepository(Supabase.instance.client);
});
