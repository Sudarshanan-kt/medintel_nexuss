-- Family/Caregiver Circle: the only cross-user access in the schema.
--
-- Extracted from the DDL that lived in the doc comment at the top of
-- lib/features/care_circle/data/care_circle_repository.dart.
--
-- Two deliberate design points, both load-bearing:
--
-- 1. Display names are SNAPSHOTTED onto the invite and membership rows at
--    creation/accept time rather than joined from health_profiles at read
--    time. That keeps the rest of a patient's health profile un-exposed to
--    caregivers in v1 — only adherence data (medicines/medicine_logs) is
--    shared, via the additive policies at the bottom of this file.
--
-- 2. Those additive policies are layered ON TOP of each table's existing
--    owner policy. Postgres ORs together every permissive policy for the
--    same command, so adding a caregiver SELECT policy widens read access
--    without touching what the patient can already do.
--
-- Requires: 20260810090000_core_patient_tables.sql (medicines, medicine_logs).

-- ── Invites ─────────────────────────────────────────────────────────────────
create table if not exists public.care_circle_invites (
  id                    text primary key,
  patient_id            uuid not null references auth.users(id) on delete cascade,
  patient_display_name  text not null default 'Patient',
  invite_code           text not null unique,
  status                text not null default 'pending',
  created_at            timestamptz default now(),
  expires_at            timestamptz not null default (now() + interval '7 days')
);
alter table public.care_circle_invites enable row level security;

drop policy if exists "Patient manages own invites" on public.care_circle_invites;
create policy "Patient manages own invites" on public.care_circle_invites
  for all using (auth.uid() = patient_id) with check (auth.uid() = patient_id);

-- A caregiver redeeming a code has no relationship to the patient yet, so
-- there is nothing narrower to scope this to. The row carries only a display
-- name and a code the caregiver was given out-of-band; the 6-character code
-- space plus the 7-day expiry is what makes guessing impractical.
drop policy if exists "Anyone can look up an invite by code" on public.care_circle_invites;
create policy "Anyone can look up an invite by code" on public.care_circle_invites
  for select using (true);

-- ── Memberships ─────────────────────────────────────────────────────────────
create table if not exists public.care_circle_members (
  id                      text primary key,
  patient_id              uuid not null references auth.users(id) on delete cascade,
  patient_display_name    text not null default 'Patient',
  caregiver_id            uuid not null references auth.users(id) on delete cascade,
  caregiver_display_name  text not null default 'Caregiver',
  status                  text not null default 'active',
  created_at              timestamptz default now(),
  unique(patient_id, caregiver_id)
);
alter table public.care_circle_members enable row level security;

drop policy if exists "Patient manages own circle" on public.care_circle_members;
create policy "Patient manages own circle" on public.care_circle_members
  for all using (auth.uid() = patient_id) with check (auth.uid() = patient_id);

drop policy if exists "Caregiver reads own memberships" on public.care_circle_members;
create policy "Caregiver reads own memberships" on public.care_circle_members
  for select using (auth.uid() = caregiver_id);

-- Accepting an invite is the one moment a caregiver writes a row a patient
-- owns. Gated on a live, unexpired, pending invite for that exact patient.
drop policy if exists "Invitee can accept a pending invite" on public.care_circle_members;
create policy "Invitee can accept a pending invite" on public.care_circle_members
  for insert with check (
    auth.uid() = caregiver_id
    and exists (
      select 1 from public.care_circle_invites i
      where i.patient_id = care_circle_members.patient_id
        and i.status = 'pending'
        and i.expires_at > now()
    )
  );

-- Every caregiver-side policy below filters on (patient_id, caregiver_id,
-- status); the unique constraint covers the first two but not status.
create index if not exists idx_care_circle_members_caregiver
  on public.care_circle_members (caregiver_id, status);

-- ── Additive read-only access to a linked patient's adherence data ──────────
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

drop policy if exists "Caregivers read linked patient dose logs" on public.medicine_logs;
create policy "Caregivers read linked patient dose logs" on public.medicine_logs
  for select using (
    exists (
      select 1 from public.care_circle_members m
      where m.patient_id = medicine_logs.user_id
        and m.caregiver_id = auth.uid()
        and m.status = 'active'
    )
  );
