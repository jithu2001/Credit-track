#!/usr/bin/env bash
# Permanently removes a business: its database, login roles, legacy containers
# and route, files and its control_db records. The admin app runs this
# (business -> Danger zone).
#   scripts/delete-business.sh <slug> --yes
#
# First takes a FINAL encrypted backup (database + its env folder) to
#   /var/backups/wholeflow/final/final-biz_<slug>-<time>.dump.age
#   /var/backups/wholeflow/final/final-<slug>-<time>-files.tar.gz.age
# (copied off-site too when BACKUP_REMOTE is set). If that backup fails,
# nothing is deleted. Final backups are kept 90 days here (backup.sh) and are
# deliberately not removed by the admin app's "delete backups" option, which
# only removes this server's nightly copies; off-site copies follow the
# bucket's retention policy (README "Backups").
# Every later step stops the script on error: nothing is dropped after a
# failed nginx check.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd /opt/wholeflow
# shellcheck source=backup-lib.sh
. "$here/backup-lib.sh"
wf_load_backup_env

SLUG=${1:?usage: delete-business.sh <slug> --yes}
[ "${2:-}" = --yes ] || { echo "This deletes all data of $SLUG. Run again with --yes." >&2; exit 1; }
[[ $SLUG =~ ^[a-z][a-z0-9]{1,19}$ ]] || { echo "bad slug" >&2; exit 1; }
DB=biz_$SLUG

# ---- final backup (must succeed)
if ! reason=$(wf_check_encryption); then
  echo "Not deleted: the final backup cannot be encrypted ($reason)." >&2
  exit 1
fi
exists=$(wf_psql -c "select 1 from pg_database where datname = '$DB'")
FINAL_DIR=$WF_BACKUP_DIR/final
mkdir -p "$FINAL_DIR"
chmod 700 "$WF_BACKUP_DIR" "$FINAL_DIR"
find "$FINAL_DIR" -name '.*.dump.plain' -delete   # left by an interrupted earlier run
stamp=$(TZ=Asia/Kolkata date +%F_%H%M%S)
saved=()
if [ "$exists" = 1 ]; then
  out="$FINAL_DIR/final-$DB-$stamp.dump.age"
  wf_dump_db "$DB" "$out" "$FINAL_DIR" || { echo "Not deleted: the final backup of $DB failed." >&2; exit 1; }
  saved+=("$out")
fi
if [ -d "businesses/$SLUG" ]; then
  out="$FINAL_DIR/final-$SLUG-$stamp-files.tar.gz.age"
  # Paths inside: businesses/<slug>/… (extract in /opt/wholeflow).
  tar -czf - "businesses/$SLUG" | wf_encrypt "$out" || { rm -f "$out"; echo "Not deleted: saving businesses/$SLUG failed." >&2; exit 1; }
  saved+=("$out")
fi
echo "final backup: ${saved[*]:-nothing to save}"
if [ -n "${BACKUP_REMOTE:-}" ] && [ ${#saved[@]} -gt 0 ] && command -v rclone >/dev/null; then
  for f in "${saved[@]}"; do
    rclone copy --immutable "$f" "${BACKUP_REMOTE%/}/final/" </dev/null \
      || echo "warning: off-site copy of $(basename "$f") failed (kept on this server)" >&2
  done
fi

# ---- legacy containers and route
if [ -f "businesses/$SLUG/compose.yml" ]; then
  docker compose -p "biz-$SLUG" -f "businesses/$SLUG/compose.yml" --env-file "businesses/$SLUG/env" down </dev/null
fi
conf=/etc/nginx/wholeflow-businesses/$SLUG.conf
for f in "$conf" "$conf.retired"; do
  [ -e "$f" ] || continue
  mv "$f" "/tmp/wholeflow-$SLUG.conf.removed"
  if ! nginx -t 2>/dev/null; then
    mv "/tmp/wholeflow-$SLUG.conf.removed" "$f"
    echo "Not deleted: nginx -t fails without $f (restored)." >&2
    exit 1
  fi
  systemctl reload nginx
  rm -f "/tmp/wholeflow-$SLUG.conf.removed"
done

# ---- database, roles, control_db records, files
# WITH (FORCE) ends the app API's open connections to this database. Copies
# left by restore.sh (biz_<slug>_old_…, scratch biz_<slug>_…) go too: slugs
# have no "_", so no other business's database matches.
for db in $(wf_psql -c "select datname from pg_database where datname = '$DB' or datname ~ '^${DB}_'"); do
  wf_psql -c "drop database if exists $db with (force)"
done
wf_psql -d control_db -c "delete from businesses where slug = '$SLUG'"
wf_psql -c "drop role if exists ${SLUG}_auth" -c "drop role if exists ${SLUG}_api"
rm -rf "businesses/$SLUG"
echo "business $SLUG deleted"
