#!/usr/bin/env bash
# Nightly backup of every WholeFlow database (control_db and biz_*) plus the
# server-wide roles, as custom-format dumps. Keeps 14 days on this server.
# Off-site copy: set B2_* in /opt/wholeflow/.env (later); see README.
set -euo pipefail
cd /opt/wholeflow
DEST=/var/backups/wholeflow
DAY=$(date +%F)
mkdir -p "$DEST/$DAY"
chmod 700 "$DEST"
psql() { docker compose exec -T db psql -U postgres -tAc "$1" < /dev/null; }
docker compose exec -T db pg_dumpall -U postgres --globals-only < /dev/null > "$DEST/$DAY/globals.sql"
for db in $(psql "select datname from pg_database where datname not in ('template0','template1','postgres') and datallowconn order by 1"); do
  docker compose exec -T db pg_dump -U postgres -Fc "$db" < /dev/null > "$DEST/$DAY/$db.dump"
done
# Check every dump is readable before calling it a good backup.
for f in "$DEST/$DAY"/*.dump; do
  [ -e "$f" ] || continue
  docker compose exec -T db pg_restore --list < "$f" > /dev/null
done
find "$DEST" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
echo "$(date -Is) backup ok: $(ls "$DEST/$DAY" | wc -l) files, $(du -sh "$DEST/$DAY" | cut -f1)"
