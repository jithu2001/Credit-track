#!/usr/bin/env bash
# Permanently removes a business: its containers, route, database, login roles,
# files and its control_db records. Take a backup first (scripts/backup.sh).
#   scripts/delete-business.sh <slug> --yes
set -euo pipefail
cd /opt/wholeflow
SLUG=${1:?usage: delete-business.sh <slug> --yes}
[ "${2:-}" = --yes ] || { echo "This deletes all data of $SLUG. Run again with --yes." >&2; exit 1; }
[[ $SLUG =~ ^[a-z][a-z0-9]{1,19}$ ]] || { echo "bad slug" >&2; exit 1; }
if [ -d "businesses/$SLUG" ]; then
  docker compose -p "biz-$SLUG" -f "businesses/$SLUG/compose.yml" --env-file "businesses/$SLUG/env" down </dev/null >/dev/null 2>&1 || true
fi
rm -f "/etc/nginx/wholeflow-businesses/$SLUG.conf"
nginx -t 2>/dev/null && systemctl reload nginx
docker compose exec -T db psql -U postgres -q </dev/null \
  -c "drop database if exists biz_$SLUG" -c "drop role if exists ${SLUG}_auth" -c "drop role if exists ${SLUG}_api"
docker compose exec -T db psql -U postgres -d control_db -q </dev/null -c "delete from businesses where slug = '$SLUG'" 2>/dev/null || true
rm -rf "businesses/$SLUG"
echo "business $SLUG deleted"
