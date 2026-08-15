-- Demo sign-in: show the real OTP on screen instead of texting it.
--
-- Caregiver sign-in has no SMS provider — delivering to an Indian number
-- needs DLT registration with TRAI, which this project has no entity for.
-- Rather than fake the code in the app, Auth generates and verifies it as
-- normal and a Send SMS hook writes it here for the app to display. The
-- session that results is a real one; only delivery changes.
--
-- READ THIS BEFORE ENABLING. A code readable without a session is a code
-- anyone holding the anon key can read, and reading it is enough to sign in
-- as that number. The allowlist below is the whole of the containment: only
-- numbers listed in demo_otp_phones ever have their code exposed. Put your
-- own demo numbers in it, nothing else, and drop this migration entirely
-- before the project holds anyone's real health data.

-- ── Numbers allowed to show their code on screen ────────────────────────────
create table if not exists public.demo_otp_phones (
  -- Digits only, no "+": Auth normalises with formatPhoneNumber before the
  -- hook sees it, so "+91 76049 66149" arrives as "917604966149".
  phone      text primary key,
  note       text,
  created_at timestamptz not null default now()
);
alter table public.demo_otp_phones enable row level security;
-- No policy at all: nobody reads this through the API. The hook and the
-- policy below both run as definer/owner, which RLS does not apply to.

insert into public.demo_otp_phones (phone, note)
values ('917604966149', 'demo handset')
on conflict (phone) do nothing;

-- ── The most recent code per number ─────────────────────────────────────────
-- One row per phone, overwritten on each send: there is never a reason to
-- keep a code that has already been superseded, and not keeping it means a
-- stale code cannot be replayed.
create table if not exists public.demo_otp_codes (
  phone      text primary key,
  code       text not null,
  created_at timestamptz not null default now()
);
alter table public.demo_otp_codes enable row level security;

-- The allowlist check has to run as definer. A policy body is evaluated as
-- the calling role, so an `exists (select ... from demo_otp_phones)` written
-- inline reads that table as anon, finds nothing behind its own RLS, and
-- silently denies every row.
create or replace function public.is_demo_otp_phone(p_phone text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (select 1 from public.demo_otp_phones p where p.phone = p_phone);
$$;
grant execute on function public.is_demo_otp_phone(text) to anon, authenticated;

drop policy if exists "Allowlisted demo numbers expose their code" on public.demo_otp_codes;
create policy "Allowlisted demo numbers expose their code"
  on public.demo_otp_codes
  for select
  to anon, authenticated
  -- anon is deliberate: the app has no session yet when it needs to show
  -- the code. The allowlist is what keeps that from being every account.
  using (public.is_demo_otp_phone(phone));

-- ── The hook ────────────────────────────────────────────────────────────────
-- Auth calls this instead of an SMS provider, once per code, with
--   {"user": {"phone": "917604966149", ...}, "sms": {"otp": "483920"}}
-- Returning an empty object means "delivered". Returning an error object
-- would fail the sign-in, which is what we want if the number isn't ours:
-- better a caregiver told it failed than one waiting on a code that was
-- never going to appear anywhere.
create or replace function public.send_sms_hook(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := event -> 'user' ->> 'phone';
  v_code  text := event -> 'sms'  ->> 'otp';
begin
  if not exists (select 1 from public.demo_otp_phones p where p.phone = v_phone) then
    return jsonb_build_object(
      'error', jsonb_build_object(
        'http_code', 400,
        'message', 'This number is not set up for demo sign-in.'
      )
    );
  end if;

  insert into public.demo_otp_codes as c (phone, code, created_at)
  values (v_phone, v_code, now())
  on conflict (phone) do update
    set code = excluded.code, created_at = now();

  return '{}'::jsonb;
end;
$$;

-- Auth runs hooks as supabase_auth_admin and nothing else may call this —
-- an arbitrary caller could otherwise plant a code of their choosing.
grant execute on function public.send_sms_hook(jsonb) to supabase_auth_admin;
revoke execute on function public.send_sms_hook(jsonb) from authenticated, anon, public;
