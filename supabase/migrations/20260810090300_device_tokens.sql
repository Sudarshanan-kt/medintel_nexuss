-- FCM device tokens, for the missed-dose alerts the Care Circle sends.
--
-- Extracted from the DDL that lived in the doc comment at the top of
-- lib/features/push/data/push_token_repository.dart.
--
-- The client writes its own token directly under RLS — no backend involved in
-- registration. Only *sending* a push needs to read tokens across users, and
-- that runs in supabase/functions/send-missed-dose-alerts with the service
-- role key, which bypasses RLS. So there is deliberately no cross-user read
-- policy here: nothing that holds a user JWT can enumerate other people's
-- devices.

create table if not exists public.device_tokens (
  id          text primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  fcm_token   text not null,
  platform    text not null default 'android',
  updated_at  timestamptz default now(),
  unique(user_id, fcm_token)
);
alter table public.device_tokens enable row level security;

drop policy if exists "Users manage own device tokens" on public.device_tokens;
create policy "Users manage own device tokens" on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
