-- Core per-patient tables. Every one is owned by exactly one auth user and
-- readable by nobody else; the Care Circle migration layers the only
-- cross-user access in the schema on top of two of them.
--
-- Extracted from the DDL that lived in the repository doc comments:
--   profiles         lib/features/auth/data/profile_repository.dart
--   health_profiles  lib/features/profile/data/health_profile_repository.dart
--   medicines        lib/features/reminders/data/medicines_repository.dart
--   medicine_logs    lib/features/reminders/data/medicines_repository.dart
--   reports          lib/features/reports/data/reports_repository.dart
--   vitals           lib/features/vitals/data/vitals_repository.dart
--   sos_events       lib/features/sos/data/sos_repository.dart
--
-- Idempotent throughout: policies are dropped before being created, so this
-- can be applied to a project where some tables were already made by hand
-- in the SQL editor.

-- ── Account role ────────────────────────────────────────────────────────────
-- Separate from health_profiles (patient-only medical data) so a caregiver
-- account is never required to complete health onboarding.
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         text not null default 'patient' check (role in ('patient', 'caregiver')),
  display_name text,
  created_at   timestamptz default now()
);
alter table public.profiles enable row level security;
drop policy if exists "Users manage their own profile row" on public.profiles;
create policy "Users manage their own profile row" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);

-- ── Health profile ──────────────────────────────────────────────────────────
create table if not exists public.health_profiles (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  blood_group        text,
  gender             text,
  date_of_birth      date,
  height_cm          numeric,
  weight_kg          numeric,
  allergies          text[] default '{}',
  medical_conditions text[] default '{}',
  current_medicines  text[] default '{}',
  emergency_contacts jsonb  default '[]',
  created_at         timestamptz default now(),
  updated_at         timestamptz default now(),
  unique(user_id)
);
alter table public.health_profiles enable row level security;
drop policy if exists "Users can manage their own health profile" on public.health_profiles;
create policy "Users can manage their own health profile" on public.health_profiles
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── Medicines and dose logs ─────────────────────────────────────────────────
-- The Care Circle migration adds read-only caregiver policies to both.
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

create table if not exists public.medicine_logs (
  id           text primary key,
  user_id      uuid not null references auth.users(id) on delete cascade,
  medicine_id  text not null,
  payload      jsonb not null,
  created_at   timestamptz default now()
);
alter table public.medicine_logs enable row level security;
drop policy if exists "Users manage own medicine logs" on public.medicine_logs;
create policy "Users manage own medicine logs" on public.medicine_logs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- The missed-dose Edge Function scans recent logs across all patients on a
-- 5-minute cron; without this it degrades into a full table scan as the log
-- grows.
create index if not exists idx_medicine_logs_user_created
  on public.medicine_logs (user_id, created_at desc);

-- ── Report library ──────────────────────────────────────────────────────────
create table if not exists public.reports (
  id         text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  payload    jsonb not null,
  created_at timestamptz default now()
);
alter table public.reports enable row level security;
drop policy if exists "Users manage own reports" on public.reports;
create policy "Users manage own reports" on public.reports
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── Self-logged vitals ──────────────────────────────────────────────────────
-- The patient's own ongoing journal, distinct from report metrics (which
-- come from OCR'd lab documents).
create table if not exists public.vitals (
  id         text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  payload    jsonb not null,
  created_at timestamptz default now()
);
alter table public.vitals enable row level security;
drop policy if exists "Users manage own vitals" on public.vitals;
create policy "Users manage own vitals" on public.vitals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ── Emergency SOS events ────────────────────────────────────────────────────
create table if not exists public.sos_events (
  id         text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  payload    jsonb not null,
  created_at timestamptz default now()
);
alter table public.sos_events enable row level security;
drop policy if exists "Users manage own SOS events" on public.sos_events;
create policy "Users manage own SOS events" on public.sos_events
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
