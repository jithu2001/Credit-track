#!/usr/bin/env bash
# Runs every migration and every SQL test against a throwaway local Postgres
# (Docker, postgres:15) with the login tables of db/auth/auth_schema.sql.
# Nothing touches a real server. The database is set up the way
# deploy/server/scripts/new-business.sh sets up a business database (roles,
# database privileges, default privileges), so grant mistakes show up here.
#
#   tests/run_local.sh                 database "wf"
#   WF_DB=wf_mine tests/run_local.sh   another database (parallel runs)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=wholeflow-sqltest
PORT=${PGPORT_TEST:-55432}
DB=${WF_DB:-wf}
[[ $DB =~ ^[a-z][a-z0-9_]{0,40}$ ]] || { echo "WF_DB: lowercase letters, digits, _" >&2; exit 1; }
export PGPASSWORD=pw
if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" -e POSTGRES_PASSWORD=pw -p 127.0.0.1:$PORT:5432 postgres:15 >/dev/null
fi
for _ in $(seq 1 30); do psql -h 127.0.0.1 -p "$PORT" -U postgres -tAc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
P="psql -h 127.0.0.1 -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists $DB with (force)" -c "create database $DB" >/dev/null
$P -tAc "select 1 from pg_roles where rolname = 'authenticated'" | grep -q 1 || $P <<'SQL'
create role anon nologin noinherit; create role authenticated nologin noinherit; create role service_role nologin noinherit bypassrls;
SQL
# As new-business.sh: nobody but the business's own login roles may connect,
# and there are no temporary-table rights.
$P -c "revoke all on database $DB from public" >/dev/null
# The data role the Go integration test signs in as (internal/appapi), like <slug>_api.
$P <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'wftest_api') then
    create role wftest_api login noinherit password 'pw';
  end if; end $$;
grant authenticated, service_role to wftest_api;
SQL
$P -c "grant connect on database $DB to wftest_api" >/dev/null
$P -d "$DB" <<'SQL'
grant usage on schema public to authenticated, service_role;
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges for role postgres in schema public grant usage, select on sequences to service_role;
alter default privileges for role postgres in schema public grant execute on functions to authenticated, service_role;
create table public.schema_migrations (name text primary key, applied_at timestamptz not null default now());
alter table public.schema_migrations enable row level security;
SQL
# The real login tables (as on the server), so sign-in can be tested too.
$P -d "$DB" -f "$HERE/../auth/auth_schema.sql" >/dev/null
for m in "$HERE"/../migrations/*.sql; do
  $P -d "$DB" -f "$m" >/dev/null || { echo "FAIL migration $(basename "$m")"; exit 1; }
  $P -d "$DB" -c "insert into public.schema_migrations (name) values ('$(basename "$m")')" >/dev/null
done
rc=0
for t in "$HERE"/*.sql; do
  if out=$($P -d "$DB" -f "$t" 2>&1); then echo "ok   $(basename "$t")"; else echo "FAIL $(basename "$t")"; echo "$out" | grep -E "ERROR|assertion" | head -5; rc=1; fi
done
exit $rc
