#!/usr/bin/env bash
# Nightly WholeFlow backup (wholeflow-backup.timer, 02:30 India time).
#
#   /opt/wholeflow/backup/<YYYY-MM-DD_HHMM>/
#     globals.sql              roles and their password hashes (pg_dumpall --globals-only)
#     control_db.dump          the control database
#     biz_<slug>.dump          one per business (pg_dump custom format)
#     config.tar.gz            .env, control.env, api.env, businesses/*/env, nginx,
#                              systemd units, rclone config, /etc/letsencrypt
#     SHA256SUMS               checksums of the files above
#     OK | FAILED              written last: counts, or what failed
#
# Download the newest finished folder by hand (README "Backups"); the server
# keeps KEEP_DAYS (14) days, by the date in the folder name. Files are root
# only (700/600). With an age public key in /opt/wholeflow/backup.recipients
# every file is encrypted instead (*.age; docs/RUNBOOK_RESTORE.md).
# Each dump is checked with pg_restore --list. A failing database does not
# stop the others; it is listed in FAILED and the script exits 1 at the end.
#
# Built in a .tmp-<name> folder and renamed when complete, so a folder without
# a dot is always a finished run.
#
# Off-site (optional): with BACKUP_REMOTE=<rclone remote:path> in
# /opt/wholeflow/backup.env the finished folder is copied there (rclone copy:
# never deletes anything remote). Only encrypted backups are sent off-site.
# Result in <backup dir>/offsite.status (scripts/monitor.sh reads it).
#
# Afterwards runs public.purge_old_data() in every business database (data
# retention), when the function exists. The dump above is taken first.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=backup-lib.sh
. "$here/backup-lib.sh"
wf_load_backup_env

DEST=$WF_BACKUP_DIR
KEEP_DAYS=${KEEP_DAYS:-14}
FINAL_KEEP_DAYS=${FINAL_KEEP_DAYS:-90}
LOG_DIR=${LOG_DIR:-/var/log/wholeflow}
mkdir -p "$LOG_DIR" "$DEST"
chmod 700 "$DEST"
exec > >(tee -a "$LOG_DIR/backup.log") 2>&1

# One run at a time.
exec 9>"$DEST/.lock"
flock -n 9 || { wf_log "PROBLEM another backup is still running"; exit 1; }

# Plaintext left by a run that was killed mid-dump never survives to the next run.
find "$DEST" -name '.*.dump.plain' -delete 2>/dev/null

NAME=$(TZ=Asia/Kolkata date +%F_%H%M)
TMP="$DEST/.tmp-$NAME"
rm -rf "$TMP"
mkdir -m 700 "$TMP"
trap 'rm -f "$TMP"/.*.plain "$TMP"/*.part 2>/dev/null' EXIT

failures=()
purge_failed=()
purge_missing=()
dbs=0

finish() { # finish <OK|FAILED> <lines…>: marker, rename, summary
  local marker=$1; shift
  (cd "$TMP" && ls ./*.sql* ./*.dump* ./*.tar.gz* >/dev/null 2>&1 && sha256sum ./*.sql* ./*.dump* ./*.tar.gz* > SHA256SUMS)
  {
    echo "completed=$(TZ=Asia/Kolkata date -Iseconds)"
    echo "completed_epoch=$(date +%s)"
    printf '%s\n' "$@"
  } > "$TMP/$marker"
  local final="$DEST/$NAME"
  [ -e "$final" ] && final="$final-$$"
  mv "$TMP" "$final"
  FINAL=$final
}

if [ -e "$WF_RECIPIENTS" ] && ! reason=$(wf_check_encryption 2>&1); then
  finish FAILED "failed=encryption" "reason=$reason"
  wf_log "PROBLEM backup not taken: $reason (remove $WF_RECIPIENTS for plain backups)"
  exit 1
fi
wf_choose_encryption >/dev/null

wf_log "backup $NAME starting"
wf_dump_globals "$TMP/globals.sql$WF_EXT" || failures+=("globals")

if list=$(wf_psql -c "select datname from pg_database where datname not in ('template0','template1','postgres') and datallowconn order by 1"); then
  for db in $list; do
    dbs=$((dbs + 1))
    if ! wf_dump_db "$db" "$TMP/$db.dump$WF_EXT" "$TMP"; then
      failures+=("$db")
      wf_log "PROBLEM dump of $db failed"
    fi
  done
else
  failures+=("database-list")
fi

wf_config_bundle "$TMP/config.tar.gz$WF_EXT" || failures+=("config")

files=$(find "$TMP" -maxdepth 1 -type f \( -name '*.sql*' -o -name '*.dump*' -o -name '*.tar.gz*' \) ! -name '*.part' | wc -l)
size=$(du -sh "$TMP" | cut -f1)
if [ ${#failures[@]} -eq 0 ]; then
  finish OK "databases=$dbs" "files=$files" "size=$size" "encrypted=$([ "$WF_EXT" = .age ] && echo yes || echo no)"
else
  finish FAILED "failed=${failures[*]}" "databases=$dbs" "files=$files" "size=$size"
fi
wf_log "backup $(basename "$FINAL"): $dbs databases, $files files, $size${failures:+, FAILED: ${failures[*]}}"

# ---- off-site copy (encrypted files only; never deletes remote files)
if [ -n "${BACKUP_REMOTE:-}" ]; then
  if [ "$WF_EXT" != .age ]; then
    echo "failed $(date +%s) $(basename "$FINAL") not encrypted: add an age key to $WF_RECIPIENTS first" > "$DEST/offsite.status"
    wf_log "PROBLEM off-site copy refused: backups are not encrypted (add an age public key to $WF_RECIPIENTS)"
    failures+=("offsite")
  elif ! command -v rclone >/dev/null; then
    echo "failed $(date +%s) $(basename "$FINAL") rclone is not installed" > "$DEST/offsite.status"
    wf_log "PROBLEM off-site copy: rclone is not installed"
    failures+=("offsite")
  elif out=$(rclone copy --immutable --transfers 2 --retries 5 --low-level-retries 20 \
             "$FINAL" "${BACKUP_REMOTE%/}/$(basename "$FINAL")" 2>&1); then
    echo "ok $(date +%s) $(basename "$FINAL")" > "$DEST/offsite.status"
    echo "$(date +%s) $(basename "$FINAL")" > "$DEST/offsite.last-ok"
    wf_log "off-site copy ok: ${BACKUP_REMOTE%/}/$(basename "$FINAL")"
  else
    echo "failed $(date +%s) $(basename "$FINAL") $(echo "$out" | tail -1 | tr -d '\n' | cut -c1-200)" > "$DEST/offsite.status"
    wf_log "PROBLEM off-site copy failed: $(echo "$out" | tail -3)"
    failures+=("offsite")
  fi
else
  echo "manual $(date +%s)" > "$DEST/offsite.status"
fi

# ---- data retention inside each business database
for db in ${list:-}; do
  case "$db" in biz_*) ;; *) continue ;; esac
  has=$(wf_psql -d "$db" -c "select to_regprocedure('public.purge_old_data()') is not null") || { purge_failed+=("$db"); continue; }
  if [ "$has" != t ]; then
    purge_missing+=("$db")
    continue
  fi
  wf_psql -d "$db" -c "select public.purge_old_data()" >/dev/null || { purge_failed+=("$db"); wf_log "PROBLEM purge_old_data failed in $db"; }
done
[ ${#purge_missing[@]} -gt 0 ] && wf_log "note: purge_old_data() not installed in ${purge_missing[*]} (skipped)"
if [ ${#purge_failed[@]} -gt 0 ]; then
  echo "purge_failed=${purge_failed[*]}" >> "$FINAL/$( [ -e "$FINAL/OK" ] && echo OK || echo FAILED )"
fi

# ---- local retention, by the date in the folder name (never by mtime)
cutoff=$(TZ=Asia/Kolkata date -d "-$KEEP_DAYS days" +%F)
for dir in "$DEST"/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]*; do
  [ -d "$dir" ] || continue
  day=$(basename "$dir" | cut -c1-10)
  [[ "$day" < "$cutoff" ]] && rm -rf -- "$dir"
done
# Interrupted runs.
find "$DEST" -mindepth 1 -maxdepth 1 -type d -name '.tmp-*' -mtime +1 -exec rm -rf -- {} +
# Final dumps of deleted businesses (delete-business.sh).
[ -d "$DEST/final" ] && find "$DEST/final" -maxdepth 1 -type f -name 'final-*' -mtime +"$FINAL_KEEP_DAYS" -delete

[ ${#failures[@]} -eq 0 ] && [ ${#purge_failed[@]} -eq 0 ]
