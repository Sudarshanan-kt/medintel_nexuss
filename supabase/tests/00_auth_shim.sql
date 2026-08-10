-- Minimal stand-in for the pieces of Supabase's auth schema the migrations
-- reference, so plain Postgres can parse and enforce them.
create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key,
  email text
);

-- Supabase reads the JWT claims out of a GUC; mirror that so tests can
-- impersonate a user with set_config('request.jwt.claim.sub', ...).
create or replace function auth.uid() returns uuid
language sql stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
