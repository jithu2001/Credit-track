#!/usr/bin/env bash
# Applies, in order, every migrations/*.sql not yet recorded in the business
# database's schema_migrations.
#   scripts/migrate.sh <slug>      one business
#   scripts/migrate.sh --all       every business (a failure does not stop the others)
#
# * One run at a time (flock); a second run waits up to 10 minutes.
# * Before the first pending migration of a business that already has some,
#   its database is dumped to /var/backups/wholeflow/pre-migrate/<date>/.
# * Each file runs in ONE transaction together with its schema_migrations
#   row, with lock_timeout 10s: it is applied and recorded, or neither.
#   Files may keep their own top-level `begin;` / `commit;` lines (each on a
#   line of its own); they are removed here, so a file must not depend on
#   committing part-way.
# * Stops a business at its first failing file; prints a summary and exits
#   non-zero when any business failed.
#
# Overridable for tests: WF_ROOT, WF_PSQL, WF_PG_DUMP, WF_BACKUP_DIR, WF_MIGRATE_LOCK.
set -uo pipefail
ROOT=${WF_ROOT:-/opt/wholeflow}
cd "$ROOT" || exit 1
read -r -a PSQL <<< "${WF_PSQL:-docker compose exec -T db psql}"
read -r -a PG_DUMP <<< "${WF_PG_DUMP:-docker compose exec -T db pg_dump}"
BACKUP_BASE=${WF_BACKUP_DIR:-/var/backups/wholeflow/pre-migrate}
LOCK=${WF_MIGRATE_LOCK:-/run/lock/wholeflow-migrate.lock}

exec 9>"$LOCK" || { echo "cannot open lock file $LOCK" >&2; exit 1; }
if ! flock -w 600 9; then
  echo "another migrate.sh is still running; try again later" >&2
  exit 1
fi

sql() { "${PSQL[@]}" -U postgres -v ON_ERROR_STOP=1 -X -q "$@"; }

# The file without its top-level begin;/commit; lines (plpgsql's "begin" has no semicolon).
body() { sed -E '/^[[:space:]]*(begin|commit)[[:space:]]*;[[:space:]]*(--.*)?$/Id' "$1"; }

migrate_one() {
  local slug=$1 db=biz_$1 applied f name pending=()
  if ! applied=$(sql -d "$db" -tAc "select name from public.schema_migrations" < /dev/null); then
    echo "  $db: cannot read schema_migrations" >&2
    return 1
  fi
  for f in migrations/*.sql; do
    name=$(basename "$f")
    [[ $name =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "  $db: bad migration file name $name" >&2; return 1; }
    grep -qxF "$name" <<< "$applied" || pending+=("$f")
  done
  [ ${#pending[@]} -eq 0 ] && return 0

  # A fresh database (nothing applied yet) has nothing worth saving.
  if [ -n "$applied" ]; then
    local dir; dir=$BACKUP_BASE/$(date +%F)
    local out; out=$dir/$db-$(date +%H%M%S).dump
    (umask 077; mkdir -p "$dir") || return 1
    if ! (umask 077; "${PG_DUMP[@]}" -U postgres -Fc -d "$db" < /dev/null > "$out"); then
      echo "  $db: backup before migrating failed; nothing applied" >&2
      rm -f "$out"
      return 1
    fi
    echo "  $db: backup $out"
  fi

  for f in "${pending[@]}"; do
    name=$(basename "$f")
    echo "  $db: $name"
    if ! { echo "begin;"
           echo "set local lock_timeout = '10s';"
           body "$f"
           echo ";"
           echo "insert into public.schema_migrations (name) values ('$name');"
           echo "commit;"
         } | sql -d "$db" > /dev/null; then
      echo "  $db: $name FAILED (rolled back; later files not tried)" >&2
      return 1
    fi
  done
}

if [ "${1:-}" = --all ]; then
  slugs=()
  for d in businesses/*/; do [ -d "$d" ] && slugs+=("$(basename "$d")"); done
else
  slugs=("${1:?usage: migrate.sh <slug> | --all}")
fi

ok=() failed=()
for s in "${slugs[@]}"; do
  if migrate_one "$s"; then ok+=("$s"); else failed+=("$s"); fi
done
find "$BACKUP_BASE" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null || true

echo "migrate: ${#ok[@]} up to date${ok:+ (${ok[*]})}; ${#failed[@]} failed${failed:+ (${failed[*]})}"
[ ${#failed[@]} -eq 0 ]
