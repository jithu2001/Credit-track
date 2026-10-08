#!/usr/bin/env bash
# Nightly WholeFlow backup (wholeflow-backup.timer, 02:30 India time).
#
#   /var/backups/wholeflow/<YYYY-MM-DD_HHMM>/
#     globals.sql.age          roles and their password hashes (pg_dumpall --globals-only)
#     control_db.dump.age      the control database
#     biz_<slug>.dump.age      one per business (pg_dump custom format)
#     config.tar.gz.age        .env, control.env, api.env, businesses/*/env, nginx,
#                              systemd units, rclone config, /etc/letsencrypt
#     SHA256SUMS               checksums of the .age files
#     OK | FAILED              written last: counts, or what failed
#
# Every file is encrypted with age to the public key(s) in
# /opt/wholeflow/backup.recipients; the private key is never on this server
# (docs/RUNBOOK_RESTORE.md). No key, no backup: the run writes FAILED and
# exits 1. Each dump is checked with pg_restore --list before it is encrypted.
# A failing database does not stop the others; it is listed in FAILED and the
# script exits 1 at the end.
#
# Built in a .tmp-<name> folder and renamed when complete, so a folder without
# a dot is always a finished run. Kept KEEP_DAYS (14) days here, by the date in
# the folder name.
#
# Off-site: with BACKUP_REMOTE=<rclone remote:path> in /opt/wholeflow/backup.env
# the finished folder is copied there (rclone copy: never deletes anything
# remote; remote retention is the bucket's lifecycle / object-lock policy).
# Result in /var/backups/wholeflow/offsite.status (scripts/monitor.sh reads it).
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
  (cd "$TMP" && ls ./*.age >/dev/null 2>&1 && sha256sum ./*.age > SHA256SUMS)
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

if ! reason=$(wf_check_encryption); then
  finish FAILED "failed=encryption" "reason=$reason"
  wf_log "PROBLEM backup not taken: $reason"
  exit 1
fi

wf_log "backup $NAME starting"
wf_dump_globals "$TMP/globals.sql.age" || failures+=("globals")

if list=$(wf_psql -c "select datname from pg_database where datname not in ('template0','template1','postgres') and datallowconn order by 1"); then
  for db in $list; do
    dbs=$((dbs + 1))
    if ! wf_dump_db "$db" "$TMP/$db.dump.age" "$TMP"; then
      failures+=("$db")
      wf_log "PROBLEM dump of $db failed"
    fi
  done
else
  failures+=("database-list")
fi

wf_config_bundle "$TMP/config.tar.gz.age" || failures+=("config")

files=$(find "$TMP" -maxdepth 1 -name '*.age' | wc -l)
size=$(du -sh "$TMP" | cut -f1)
if [ ${#failures[@]} -eq 0 ]; then
  finish OK "databases=$dbs" "files=$files" "size=$size"
else
  finish FAILED "failed=${failures[*]}" "databases=$dbs" "files=$files" "size=$size"
fi
wf_log "backup $(basename "$FINAL"): $dbs databases, $files files, $size${failures:+, FAILED: ${failures[*]}}"

# ---- off-site copy (encrypted files only; never deletes remote files)
if [ -n "${BACKUP_REMOTE:-}" ]; then
  if ! command -v rclone >/dev/null; then
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
  echo "not-configured $(date +%s)" > "$DEST/offsite.status"
  wf_log "PROBLEM off-site copy not configured (BACKUP_REMOTE in $WF_KIT/backup.env)"
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
