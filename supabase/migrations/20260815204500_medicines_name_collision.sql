-- Give `public.medicines` back to the app.
--
-- This project was created against an earlier, organisation-shaped schema
-- (patient_id, org_members, ai_analysis) and that design's drug catalogue —
-- rxnorm_code, generic_name, atc_code — holds the `medicines` name. The app
-- wants the name for its own per-user table, so the core migration's
-- `create table if not exists public.medicines` quietly did nothing here and
-- the policy after it failed on a `user_id` column that does not exist.
--
-- The catalogue is renamed rather than dropped. It was empty when this ran,
-- but `medicine_interactions` has two foreign keys into it and it carries an
-- updated-at trigger; both follow the rename, so the old schema stays
-- internally consistent and nothing has to be reconstructed if it is ever
-- picked back up.

-- Only move a table that is actually the catalogue. On a project where the
-- app's own medicines table already exists, or on a fresh one, this is a
-- no-op — rxnorm_code is the discriminator, since the app's table has no
-- such column.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'medicines'
      and column_name = 'rxnorm_code'
  ) then
    alter table public.medicines rename to medicines_catalog;
  end if;
end
$$;

-- ── The app's medicines, verbatim from the core migration ───────────────────
create table if not exists public.medicines (
  id         text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  payload    jsonb not null,
  created_at timestamptz default now()
);
alter table public.medicines enable row level security;
drop policy if exists "Users manage own medicines" on public.medicines;
create policy "Users manage own medicines" on public.medicines
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── And the caregiver's read-only view of them, from the care circle one ────
-- Read, never write. A caregiver can see that a dose was missed; only the
-- patient can record one.
drop policy if exists "Caregivers read linked patient medicines" on public.medicines;
create policy "Caregivers read linked patient medicines" on public.medicines
  for select using (
    exists (
      select 1 from public.care_circle_members m
      where m.patient_id = medicines.user_id
        and m.caregiver_id = auth.uid()
        and m.status = 'active'
    )
  );
