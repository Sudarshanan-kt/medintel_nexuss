-- Closes two holes in the invite flow as originally specified.
--
-- What was wrong, both verified against Postgres 15 before this was written:
--
-- 1. PRIVILEGE ESCALATION. The invites table had `for select using (true)`,
--    so any signed-in user could read every row — patient_ids and codes for
--    everyone with an invite open. The membership insert policy then only
--    required that *some* pending invite existed for that patient, never
--    that the caller held its code. Together: read the table, pick a
--    patient, insert yourself as their active caregiver, and their
--    medicines and dose logs become readable to you. No code needed.
--
-- 2. INVITES WERE NEVER CONSUMED. The client marks an invite accepted with
--    an UPDATE, but a caregiver has no update policy on the table, so RLS
--    matched zero rows and the statement succeeded silently. Every invite
--    stayed 'pending' for its full 7 days, holding the window in (1) open
--    long after it should have closed.
--
-- The fix: the invites table is now patient-only for direct access, and the
-- two things a caregiver legitimately does — preview a code, redeem a code —
-- go through security-definer functions that require the exact code. Knowing
-- the code is the authorization; there is no longer any way to act on an
-- invite you were not given.

-- ── Direct table access is patient-only from here on ────────────────────────
drop policy if exists "Anyone can look up an invite by code" on public.care_circle_invites;

-- Superseded by accept_care_circle_invite() below.
drop policy if exists "Invitee can accept a pending invite" on public.care_circle_members;

create index if not exists idx_care_circle_invites_code
  on public.care_circle_invites (invite_code);

-- ── Preview: "whose circle am I joining?" ───────────────────────────────────
-- Exact-match on the code only. Returning the row to someone who already
-- holds the code leaks nothing they are not about to be told anyway; what
-- matters is that there is no way to ask for a list.
create or replace function public.peek_care_circle_invite(p_code text)
returns setof public.care_circle_invites
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select *
  from public.care_circle_invites
  where invite_code = upper(trim(p_code))
  limit 1;
$$;

-- ── Redeem ──────────────────────────────────────────────────────────────────
-- Caregiver identity comes from auth.uid(), never from an argument, so a
-- caller cannot link somebody else. Insert and consume happen in one
-- statement-level transaction: an invite cannot be redeemed twice.
create or replace function public.accept_care_circle_invite(
  p_code text,
  p_caregiver_display_name text default 'Caregiver'
)
returns public.care_circle_members
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_caregiver uuid := auth.uid();
  v_invite    public.care_circle_invites;
  v_member    public.care_circle_members;
begin
  if v_caregiver is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  -- FOR UPDATE serialises two devices redeeming the same code at once.
  select * into v_invite
  from public.care_circle_invites
  where invite_code = upper(trim(p_code))
  for update;

  if v_invite.id is null then
    raise exception 'This invite is invalid or has expired.' using errcode = '22023';
  end if;
  if v_invite.status <> 'pending' or v_invite.expires_at <= now() then
    raise exception 'This invite is invalid or has expired.' using errcode = '22023';
  end if;
  if v_invite.patient_id = v_caregiver then
    raise exception 'You can''t join your own care circle.' using errcode = '22023';
  end if;

  -- on conflict: a caregiver who was removed and re-invited is reactivated
  -- rather than rejected by the unique(patient_id, caregiver_id) constraint.
  insert into public.care_circle_members
    (id, patient_id, patient_display_name,
     caregiver_id, caregiver_display_name, status)
  values
    ('mem_' || replace(gen_random_uuid()::text, '-', ''),
     v_invite.patient_id, v_invite.patient_display_name,
     v_caregiver, coalesce(nullif(trim(p_caregiver_display_name), ''), 'Caregiver'),
     'active')
  on conflict (patient_id, caregiver_id) do update
    set status = 'active',
        caregiver_display_name = excluded.caregiver_display_name
  returning * into v_member;

  update public.care_circle_invites
     set status = 'accepted'
   where id = v_invite.id;

  return v_member;
end;
$$;

-- Signed-in users only. anon holds no session, so it has no business here.
revoke all on function public.peek_care_circle_invite(text) from public, anon;
revoke all on function public.accept_care_circle_invite(text, text) from public, anon;
grant execute on function public.peek_care_circle_invite(text) to authenticated;
grant execute on function public.accept_care_circle_invite(text, text) to authenticated;
