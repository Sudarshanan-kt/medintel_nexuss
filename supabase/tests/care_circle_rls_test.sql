\set ON_ERROR_STOP on
\pset pager off

drop role if exists app_user;
create role app_user nologin in role authenticated;
grant usage on schema public, auth to app_user;
grant select, insert, update, delete on all tables in schema public to app_user;
grant execute on all functions in schema auth to app_user;

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'mallory@example.com');

insert into public.medicines (id, user_id, payload)
values ('med_alice_1', '11111111-1111-1111-1111-111111111111', '{"name":"Warfarin"}');
insert into public.medicine_logs (id, user_id, medicine_id, payload)
values ('log_alice_1', '11111111-1111-1111-1111-111111111111', 'med_alice_1', '{"status":"missed"}');

-- Alice opens an invite for Bob. Mallory is an unrelated signed-in user.
insert into public.care_circle_invites (id, patient_id, patient_display_name, invite_code, status)
values ('inv_1', '11111111-1111-1111-1111-111111111111', 'Alice', 'ABC234', 'pending');

\echo ''
\echo '=== ATTACK 1: enumerate the invites table (previously leaked everything) ==='
set role app_user;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
select count(*) as mallory_can_see_invites from public.care_circle_invites;

\echo ''
\echo '=== ATTACK 2: self-link without holding the code (previously succeeded) ==='
do $$
begin
  insert into public.care_circle_members
    (id, patient_id, caregiver_id, caregiver_display_name, status)
  values ('mem_forged', '11111111-1111-1111-1111-111111111111',
          '33333333-3333-3333-3333-333333333333', 'Mallory', 'active');
  raise exception 'FAIL: self-linked with no code';
exception
  when insufficient_privilege then raise notice 'PASS: direct self-link blocked';
end $$;

\echo ''
\echo '=== ATTACK 3: redeem a code that was never given out ==='
do $$
begin
  perform public.accept_care_circle_invite('ZZZZZZ', 'Mallory');
  raise exception 'FAIL: redeemed a nonexistent code';
exception
  when sqlstate '22023' then raise notice 'PASS: unknown code rejected';
end $$;

\echo ''
\echo '=== LEGITIMATE: Bob holds the code and redeems it ==='
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select (public.peek_care_circle_invite('abc234')).patient_display_name as preview_shows;
select (public.accept_care_circle_invite('abc234', 'Bob')).status as membership_status;
select count(*) as bob_now_reads_medicines from public.medicines;
select count(*) as bob_now_reads_dose_logs from public.medicine_logs;

\echo ''
\echo '=== The invite is now actually consumed (previously stayed pending) ==='
reset role;
select status as invite_status_after_accept from public.care_circle_invites where id = 'inv_1';

\echo ''
\echo '=== ATTACK 4: replay the same code from another account ==='
set role app_user;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
  perform public.accept_care_circle_invite('ABC234', 'Mallory');
  raise exception 'FAIL: consumed invite was replayed';
exception
  when sqlstate '22023' then raise notice 'PASS: replay of a consumed invite rejected';
end $$;
select count(*) as mallory_still_reads_medicines from public.medicines;

\echo ''
\echo '=== ATTACK 5: patient redeems their own invite ==='
reset role;
insert into public.care_circle_invites (id, patient_id, patient_display_name, invite_code, status)
values ('inv_2', '11111111-1111-1111-1111-111111111111', 'Alice', 'SELF11', 'pending');
set role app_user;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
do $$
begin
  perform public.accept_care_circle_invite('SELF11', 'Alice');
  raise exception 'FAIL: joined own circle';
exception
  when sqlstate '22023' then raise notice 'PASS: self-join rejected';
end $$;

\echo ''
\echo '=== ATTACK 6: expired invite ==='
reset role;
insert into public.care_circle_invites (id, patient_id, invite_code, status, expires_at)
values ('inv_3', '11111111-1111-1111-1111-111111111111', 'OLD999', 'pending', now() - interval '1 day');
set role app_user;
select set_config('request.jwt.claim.sub', '33333333-3333-3333-3333-333333333333', false);
do $$
begin
  perform public.accept_care_circle_invite('OLD999', 'Mallory');
  raise exception 'FAIL: expired invite accepted';
exception
  when sqlstate '22023' then raise notice 'PASS: expired invite rejected';
end $$;

\echo ''
\echo '=== Caregiver still cannot WRITE to the patient (read-only) ==='
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
do $$
begin
  insert into public.medicine_logs (id, user_id, medicine_id, payload)
  values ('log_forged', '11111111-1111-1111-1111-111111111111', 'med_alice_1', '{"status":"taken"}');
  raise exception 'FAIL: caregiver forged a dose log';
exception
  when insufficient_privilege then raise notice 'PASS: caregiver write still blocked';
end $$;

\echo ''
\echo '=== Removed caregiver can be re-invited and reactivated ==='
reset role;
update public.care_circle_members set status = 'removed'
  where caregiver_id = '22222222-2222-2222-2222-222222222222';
insert into public.care_circle_invites (id, patient_id, patient_display_name, invite_code, status)
values ('inv_4', '11111111-1111-1111-1111-111111111111', 'Alice', 'AGAIN1', 'pending');
set role app_user;
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select (public.accept_care_circle_invite('AGAIN1', 'Bob')).status as reactivated_status;
select count(*) as bob_reads_again from public.medicines;
reset role;
