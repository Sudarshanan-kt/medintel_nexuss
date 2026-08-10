# RLS tests

The Care Circle is the only place in this schema where one user reads
another user's health data. That makes its row-level security policies the
part most worth testing and the part where a mistake is worst — a wrong
`using` clause does not throw, it silently returns somebody else's rows.

These tests were written after two real holes were found in the original
policy set (both fixed in
`../migrations/20260810090400_care_circle_invite_hardening.sql`): the invites
table was readable by every signed-in user, and redeeming an invite never
required holding its code. `care_circle_rls_test.sql` reproduces both attacks
and asserts they now fail, alongside the legitimate flows.

## Running them

Needs Docker. Nothing here touches your Supabase project — it all runs
against a throwaway local Postgres.

```bash
docker run -d --name medintel-pg-test \
  -e POSTGRES_PASSWORD=pw -p 55432:5432 postgres:15-alpine

docker exec medintel-pg-test psql -U postgres -q \
  -c "create role authenticated nologin; create role anon nologin;"

docker cp supabase/tests   medintel-pg-test:/tmp/tests
docker cp supabase/migrations medintel-pg-test:/tmp/migrations

# The auth schema Supabase provides, stubbed just enough to run policies.
docker exec medintel-pg-test psql -U postgres -v ON_ERROR_STOP=1 -q \
  -f /tmp/tests/00_auth_shim.sql

for f in $(ls supabase/migrations); do
  docker exec medintel-pg-test psql -U postgres -v ON_ERROR_STOP=1 -q \
    -f /tmp/migrations/$f
done

docker exec medintel-pg-test psql -U postgres -q \
  -f /tmp/tests/care_circle_rls_test.sql

docker rm -f medintel-pg-test
```

Every check prints `PASS` or raises. A failing test aborts the script, so
silence at the end means something did not run — read the output, don't
just check the exit code.

## The one thing the shim cannot model

`auth.uid()` here reads `request.jwt.claim.sub` from a GUC, and the tests set
it directly. Real Supabase derives it from a verified JWT. So these tests
prove the *policies* are right; they do not prove token verification is. That
part is Supabase's.
