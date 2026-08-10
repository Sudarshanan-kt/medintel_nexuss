-- Care Circle task board.
--
-- Extracted from the DDL that lived in the doc comment at the top of
-- lib/features/care_circle/data/care_task_repository.dart.
--
-- Access mirrors the additive-policy pattern used for medicines/medicine_logs
-- in 20260810090100_care_circle.sql, but wider: the patient owns their own
-- tasks, and any *active* linked caregiver gets read AND write. Anyone in the
-- circle can post a request, claim one, or mark it done — a task board where
-- only one person can write is not a task board.
--
-- Requires: 20260810090100_care_circle.sql (care_circle_members).

create table if not exists public.care_circle_tasks (
  id                 text primary key,
  patient_id         uuid not null references auth.users(id) on delete cascade,
  title              text not null,
  note               text,
  due_date           timestamptz,
  created_by_id      uuid not null,
  created_by_name    text not null default 'Someone',
  claimed_by_id      uuid,
  claimed_by_name    text,
  status             text not null default 'open',
  created_at         timestamptz default now()
);
alter table public.care_circle_tasks enable row level security;

drop policy if exists "Patient manages own tasks" on public.care_circle_tasks;
create policy "Patient manages own tasks" on public.care_circle_tasks
  for all using (auth.uid() = patient_id) with check (auth.uid() = patient_id);

drop policy if exists "Linked caregivers read circle tasks" on public.care_circle_tasks;
create policy "Linked caregivers read circle tasks" on public.care_circle_tasks
  for select using (
    exists (
      select 1 from public.care_circle_members m
      where m.patient_id = care_circle_tasks.patient_id
        and m.caregiver_id = auth.uid()
        and m.status = 'active'
    )
  );

-- auth.uid() = created_by_id keeps a caregiver from posting a task under
-- someone else's name.
drop policy if exists "Linked caregivers post circle tasks" on public.care_circle_tasks;
create policy "Linked caregivers post circle tasks" on public.care_circle_tasks
  for insert with check (
    auth.uid() = created_by_id
    and exists (
      select 1 from public.care_circle_members m
      where m.patient_id = care_circle_tasks.patient_id
        and m.caregiver_id = auth.uid()
        and m.status = 'active'
    )
  );

drop policy if exists "Linked caregivers claim/update circle tasks" on public.care_circle_tasks;
create policy "Linked caregivers claim/update circle tasks" on public.care_circle_tasks
  for update using (
    exists (
      select 1 from public.care_circle_members m
      where m.patient_id = care_circle_tasks.patient_id
        and m.caregiver_id = auth.uid()
        and m.status = 'active'
    )
  );

create index if not exists idx_care_circle_tasks_patient
  on public.care_circle_tasks (patient_id, status);
