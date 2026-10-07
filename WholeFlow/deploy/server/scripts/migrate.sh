#!/usr/bin/env bash
# Applies, in order, every migrations/*.sql not yet recorded in the business
# database's schema_migrations. Stops at the first failure.
#   scripts/migrate.sh <slug>      one business
#   scripts/migrate.sh --all       every business
set -euo pipefail
cd /opt/wholeflow
migrate_one() {
  local db=biz_$1
  for f in migrations/*.sql; do
    local name; name=$(basename "$f")
    local done; done=$(docker compose exec -T db psql -U postgres -d "$db" -tAc "select 1 from public.schema_migrations where name = '$name'" < /dev/null)
    [ "$done" = 1 ] && continue
    echo "  $db: $name"
    docker compose exec -T db psql -U postgres -d "$db" -v ON_ERROR_STOP=1 -q < "$f" > /dev/null
    docker compose exec -T db psql -U postgres -d "$db" -qc "insert into public.schema_migrations (name) values ('$name')" < /dev/null
  done
  # The data API caches the list of tables and functions: have it reload.
  docker compose exec -T db psql -U postgres -d "$db" -qc "notify pgrst, 'reload schema'" < /dev/null
}
if [ "${1:-}" = --all ]; then
  for d in businesses/*/; do migrate_one "$(basename "$d")"; done
else
  migrate_one "${1:?usage: migrate.sh <slug> | --all}"
fi
