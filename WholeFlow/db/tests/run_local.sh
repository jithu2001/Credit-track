#!/usr/bin/env bash
# Runs every migration and every SQL test against a throwaway local Postgres
# (Docker, postgres:15) with the login tables of db/auth/auth_schema.sql. Nothing touches a real server. Usage: tests/run_local.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=wholeflow-sqltest
PORT=${PGPORT_TEST:-55432}
export PGPASSWORD=pw
if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" -e POSTGRES_PASSWORD=pw -p 127.0.0.1:$PORT:5432 postgres:15 >/dev/null
fi
for _ in $(seq 1 30); do psql -h 127.0.0.1 -p "$PORT" -U postgres -tAc 'select 1' >/dev/null 2>&1 && break; sleep 1; done
P="psql -h 127.0.0.1 -p $PORT -U postgres -v ON_ERROR_STOP=1 -q"
$P -c "drop database if exists wf" -c "create database wf" >/dev/null 2>&1
$P -tAc "select 1 from pg_roles where rolname = 'authenticated'" | grep -q 1 || $P <<'SQL'
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
SQL
$P -d wf <<'SQL'
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
SQL
# The real login tables (as on the server), so sign-in can be tested too.
$P -d wf -f "$HERE/../auth/auth_schema.sql" >/dev/null
for m in "$HERE"/../migrations/*.sql; do $P -d wf -f "$m" >/dev/null || { echo "FAIL migration $(basename "$m")"; exit 1; }; done
rc=0
for t in "$HERE"/*.sql; do
  if out=$($P -d wf -f "$t" 2>&1); then echo "ok   $(basename "$t")"; else echo "FAIL $(basename "$t")"; echo "$out" | grep -E "ERROR|assertion" | head -5; rc=1; fi
done
exit $rc
