#!/usr/bin/env bash
# Creates one business: database biz_<slug>, its own login roles and signing
# secret, a GoTrue (login) and PostgREST (data API) container, the nginx route
# /b/<slug>/, and applies every migration. Prints the base URL and keys.
#
#   scripts/new-business.sh <slug> "<Business name>"
#
# Phase 1 tool; the control service (phase 2) does the same steps.
set -euo pipefail
cd /opt/wholeflow
SLUG=${1:?usage: new-business.sh <slug> "<name>"}
NAME=${2:?usage: new-business.sh <slug> "<name>"}
[[ $SLUG =~ ^[a-z][a-z0-9]{1,19}$ ]] || { echo "slug: 2-20 lowercase letters/digits, starting with a letter" >&2; exit 1; }
DIR=businesses/$SLUG
[ -e "$DIR" ] && { echo "business $SLUG already exists" >&2; exit 1; }
. ./.env
PUBLIC_URL=${PUBLIC_URL:?PUBLIC_URL missing in .env}
DB=biz_$SLUG

psql_admin() { docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

# Ports: next free slot (10000+n login, 11000+n data API), bound to localhost only.
N=1; while ls businesses/*/env >/dev/null 2>&1 && grep -qx "SLOT=$N" businesses/*/env; do N=$((N+1)); done
AUTH_PORT=$((10000+N)); REST_PORT=$((11000+N))

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
psql_admin <<SQL
create role ${SLUG}_auth login password '$AUTH_PW';
create role ${SLUG}_api login noinherit password '$API_PW';
grant anon, authenticated, service_role to ${SLUG}_api;
alter role ${SLUG}_auth set search_path = auth;
create database $DB;
revoke all on database $DB from public;
grant connect on database $DB to ${SLUG}_auth, ${SLUG}_api;
-- Signed-in API roles may use temporary tables (anon may not).
grant temporary on database $DB to authenticated, service_role;
grant create on database $DB to ${SLUG}_auth;
SQL
psql_admin -d "$DB" <<SQL
create schema auth authorization ${SLUG}_auth;
grant usage on schema auth to anon, authenticated, service_role;
-- What the data API (PostgREST) expects: the API roles may use the public schema, and
-- objects that migrations (run as postgres) create are granted to them.
grant usage on schema public to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
create table public.schema_migrations (name text primary key, applied_at timestamptz not null default now());
revoke all on public.schema_migrations from anon, authenticated;
SQL

echo "== containers"
umask 077
mkdir -p "$DIR"
cat > "$DIR/env" <<ENV
SLUG=$SLUG
SLOT=$N
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
sed "s/__SLUG__/$SLUG/g" templates/business-compose.yml > "$DIR/compose.yml"
docker compose -p "biz-$SLUG" -f "$DIR/compose.yml" --env-file "$DIR/env" up -d 2>&1 | tail -2

echo "== waiting for the login service to create its tables"
for i in $(seq 1 60); do curl -fs "http://127.0.0.1:$AUTH_PORT/health" >/dev/null && break; sleep 2; done
curl -fs "http://127.0.0.1:$AUTH_PORT/health" >/dev/null || { echo "login service did not start; see: docker compose -p biz-$SLUG logs" >&2; exit 1; }

echo "== migrations"
scripts/migrate.sh "$SLUG"

echo "== nginx route"
sed -e "s/__SLUG__/$SLUG/g" -e "s/__AUTH_PORT__/$AUTH_PORT/g" -e "s/__REST_PORT__/$REST_PORT/g" \
  templates/business-nginx.conf > "/etc/nginx/wholeflow-businesses/$SLUG.conf"
nginx -t 2>/dev/null && systemctl reload nginx

cat <<OUT

Business "$NAME" is ready.
  Base URL:    $PUBLIC_URL/b/$SLUG
  Anon key:    $ANON_KEY
  Service key: stored in /opt/wholeflow/$DIR/env (keep secret)
OUT
