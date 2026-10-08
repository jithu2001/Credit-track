#!/usr/bin/env bash
# Creates one business: database biz_<slug> with its own roles, signing secret
# and login tables, and applies every migration. Prints the base URL and keys.
# No containers: the WholeFlow app API (wholeflow-api) serves its logins and
# data at /b/<slug>/auth/v1/ and /b/<slug>/api/v1/ (one nginx rule for every
# business). The control service runs this when the admin app creates a business.
#
#   scripts/new-business.sh <slug> "<Business name>"
#
# Safe to run again after a failure: whatever this run created (roles,
# database, businesses/<slug>/) is removed when it fails, and roles or an
# empty database left by a run that was killed are cleared first.
#
# businesses/<slug>/env holds the business's secrets. It is readable by root
# and group `wholeflow` (the app API runs as user wholeflow-api in that group).
#
# Overridable for tests: WF_ROOT, WF_PSQL (as in migrate.sh).
set -euo pipefail
ROOT=${WF_ROOT:-/opt/wholeflow}
cd "$ROOT"
SLUG=${1:?usage: new-business.sh <slug> "<name>"}
NAME=${2:?usage: new-business.sh <slug> "<name>"}
[[ $SLUG =~ ^[a-z][a-z0-9]{1,19}$ ]] || { echo "slug: 2-20 lowercase letters/digits, starting with a letter" >&2; exit 1; }
DIR=businesses/$SLUG
[ -e "$DIR" ] && { echo "business $SLUG already exists" >&2; exit 1; }
. ./.env
PUBLIC_URL=${PUBLIC_URL:?PUBLIC_URL missing in .env}
DB=biz_$SLUG
GROUP=wholeflow

read -r -a PSQL <<< "${WF_PSQL:-docker compose exec -T db psql}"
psql_admin() { "${PSQL[@]}" -U postgres -v ON_ERROR_STOP=1 -X -q "$@"; }
exists() { [ "$(psql_admin -tAc "$1" < /dev/null)" = 1 ]; }

# ---- leftovers of an earlier run that was killed before it could clean up
if exists "select 1 from pg_database where datname = '$DB'"; then
  # Only an empty database (no migration applied) may be replaced.
  if [ "$(psql_admin -d "$DB" -tAc "select count(*) from public.schema_migrations" < /dev/null 2>/dev/null || echo 0)" != 0 ]; then
    echo "database $DB already exists and has data, but $DIR does not; not touching it" >&2
    exit 1
  fi
  echo "== removing the empty database $DB left by an earlier run"
  psql_admin -c "drop database $DB with (force)" < /dev/null
fi
for r in "${SLUG}_auth" "${SLUG}_api"; do
  if exists "select 1 from pg_roles where rolname = '$r'"; then
    echo "== removing role $r left by an earlier run"
    psql_admin -c "drop role $r" < /dev/null
  fi
done

# ---- undo this run's work if anything below fails
CREATED=""
cleanup() {
  local rc=$?
  [ "$rc" = 0 ] && return
  [ -z "$CREATED" ] && exit "$rc"
  echo "== failed (exit $rc): removing what this run created" >&2
  set +e
  rm -rf "$DIR"
  psql_admin -c "drop database if exists $DB with (force)" < /dev/null
  psql_admin -c "drop role if exists ${SLUG}_api" -c "drop role if exists ${SLUG}_auth" < /dev/null
  exit "$rc"
}
trap cleanup EXIT

# No containers, so no ports (0 = none; kept in env for older tools).
AUTH_PORT=0; REST_PORT=0

AUTH_PW=$(openssl rand -hex 24); API_PW=$(openssl rand -hex 24); JWT_SECRET=$(openssl rand -hex 32)
jwt() { python3 - "$JWT_SECRET" "$1" "$SLUG" <<'PY'
import base64, hashlib, hmac, json, sys, time
secret, role, slug = sys.argv[1:4]
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
now = int(time.time())
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
body = b64(json.dumps({"iss": "wholeflow", "ref": slug, "role": role, "iat": now, "exp": now + 10 * 365 * 86400}, separators=(",", ":")).encode())
sig = b64(hmac.new(secret.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
print(f"{head}.{body}.{sig}")
PY
}
ANON_KEY=$(jwt anon); SERVICE_KEY=$(jwt service_role)

echo "== database $DB"
CREATED=1
psql_admin <<SQL
create role ${SLUG}_auth login password '$AUTH_PW';
create role ${SLUG}_api login noinherit password '$API_PW';
-- The app API switches into these per request (never anon).
grant authenticated, service_role to ${SLUG}_api;
alter role ${SLUG}_auth set search_path = auth;
create database $DB;
-- Private: only this business's login roles connect; no temporary tables.
revoke all on database $DB from public;
grant connect on database $DB to ${SLUG}_auth, ${SLUG}_api;
grant create on database $DB to ${SLUG}_auth;
SQL
psql_admin -d "$DB" <<SQL
create schema auth authorization ${SLUG}_auth;
grant usage on schema auth to authenticated, service_role;
grant usage on schema public to authenticated, service_role;
-- Objects that migrations (run as postgres) create: the PC uploads and staff
-- management (service_role) may read and write them; signed-in people
-- (authenticated) get nothing by default — each migration grants SELECT and
-- any write explicitly, next to the table's RLS policies. anon gets nothing.
alter default privileges for role postgres in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges for role postgres in schema public grant usage, select on sequences to service_role;
alter default privileges for role postgres in schema public grant execute on functions to authenticated, service_role;
create table public.schema_migrations (name text primary key, applied_at timestamptz not null default now());
alter table public.schema_migrations enable row level security;
revoke all on public.schema_migrations from public;
SQL

echo "== login tables"
# GoTrue's tables (db/auth/auth_schema.sql, copied to auth/ on the server),
# owned by the business's login role, which the app API signs people in as.
{ echo "set role ${SLUG}_auth;"; cat auth/auth_schema.sql; } | psql_admin -d "$DB" >/dev/null
# auth_schema.sql (a GoTrue dump) also grants anon; anon has no use here.
psql_admin -d "$DB" -c "revoke all on schema auth from anon" < /dev/null

echo "== settings"
umask 077
mkdir -p businesses "$DIR"
cat > "$DIR/env" <<ENV
SLUG=$SLUG
NAME=$NAME
AUTH_PORT=$AUTH_PORT
REST_PORT=$REST_PORT
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_KEY=$SERVICE_KEY
AUTH_DB_URL=postgres://${SLUG}_auth:$AUTH_PW@db:5432/$DB?search_path=auth
API_DB_URL=postgres://${SLUG}_api:$API_PW@db:5432/$DB
BASE_URL=$PUBLIC_URL/b/$SLUG
ENV
# The app API (user wholeflow-api, group wholeflow) reads this file.
chmod 750 "$DIR"; chmod 640 "$DIR/env"
if getent group "$GROUP" > /dev/null; then
  chgrp "$GROUP" businesses "$DIR" "$DIR/env"
  chmod g+rx,o-rwx businesses
else
  echo "warning: group $GROUP does not exist yet; $DIR/env stays root-only (run: chgrp -R $GROUP $ROOT/businesses)" >&2
fi

echo "== migrations"
scripts/migrate.sh "$SLUG"
CREATED=""

cat <<OUT

Business "$NAME" is ready.
  Base URL:    $PUBLIC_URL/b/$SLUG
  Anon key:    $ANON_KEY
  Service key: stored in $ROOT/$DIR/env (keep secret)
OUT
