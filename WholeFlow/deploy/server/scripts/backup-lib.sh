# shellcheck shell=bash
# Shared by backup.sh and delete-business.sh (sourced, not run).
#
# Backups go to /opt/wholeflow/backup (root only, 700/600) and are copied off
# the server by hand (scp/rsync; deploy/server/README.md "Backups").
#
# Encryption is optional: with an age (https://age-encryption.org) PUBLIC key
# in /opt/wholeflow/backup.recipients every file is encrypted (*.age) and the
# private key stays off the server; without that file the files are plain.
# Plain backups hold every customer's data and the server's secrets
# (MASTER_KEY, database passwords): keep downloaded copies on an encrypted
# disk or in an encrypted archive.

WF_KIT=${KIT:-/opt/wholeflow}
WF_BACKUP_DIR=${BACKUP_DIR:-$WF_KIT/backup}
WF_RECIPIENTS=${BACKUP_RECIPIENTS:-$WF_KIT/backup.recipients}
# ".age" when backups are encrypted, "" when plain (wf_choose_encryption).
WF_EXT=""

wf_log() { echo "$(TZ=Asia/Kolkata date -Iseconds) $*"; }

# psql as postgres inside the db container; stops at the first SQL error.
wf_psql() { (cd "$WF_KIT" && docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -tAq "$@" </dev/null); }

# Settings for backups (optional): BACKUP_REMOTE, BACKUP_LETSENCRYPT, KEEP_DAYS.
wf_load_backup_env() {
  if [ -r "$WF_KIT/backup.env" ]; then
    # shellcheck disable=SC1091
    . "$WF_KIT/backup.env"
  fi
}

# Is encryption usable? Prints the reason when not.
wf_check_encryption() {
  command -v age >/dev/null || { echo "age is not installed (apt-get install -y age)"; return 1; }
  [ -s "$WF_RECIPIENTS" ] || { echo "no public key in $WF_RECIPIENTS (see docs/RUNBOOK_RESTORE.md, 'Backup key')"; return 1; }
  grep -Eq '^(age1|ssh-ed25519 |ssh-rsa )' "$WF_RECIPIENTS" || { echo "$WF_RECIPIENTS holds no age1... public key"; return 1; }
  echo probe | age -R "$WF_RECIPIENTS" >/dev/null 2>&1 || { echo "age cannot use the keys in $WF_RECIPIENTS"; return 1; }
}

# Encrypt when a recipients file exists (and then it must work), else plain.
# Sets WF_EXT. Prints the reason and fails when the key file is unusable.
wf_choose_encryption() {
  if [ -e "$WF_RECIPIENTS" ]; then
    wf_check_encryption || return 1
    WF_EXT=.age
  else
    WF_EXT=""
  fi
}

# wf_encrypt <out>: stdin -> file (encrypted when WF_EXT=.age), written to
# .part and renamed, readable by root only.
wf_encrypt() {
  if [ "$WF_EXT" = .age ]; then
    age -R "$WF_RECIPIENTS" -o "$1.part" && mv "$1.part" "$1"
  else
    (umask 077; cat >"$1.part") && mv "$1.part" "$1"
  fi
}

# wf_dump_db <database> <out> <work dir>
# pg_dump (custom format), checks the dump reads back (pg_restore --list),
# then stores it (encrypted when WF_EXT=.age). The check copy is inside the
# root-only work dir and removed straight after.
wf_dump_db() {
  local db=$1 out=$2 work=$3
  local plain="$work/.${db}.dump.plain"
  local ok=0
  (umask 077; cd "$WF_KIT" && docker compose exec -T db pg_dump -U postgres -Fc "$db" </dev/null >"$plain") || ok=1
  if [ "$ok" = 0 ] && [ ! -s "$plain" ]; then ok=1; fi
  if [ "$ok" = 0 ]; then
    (cd "$WF_KIT" && docker compose exec -T db pg_restore --list <"$plain" >/dev/null) || ok=1
  fi
  if [ "$ok" = 0 ]; then
    wf_encrypt "$out" <"$plain" || ok=1
  fi
  rm -f "$plain" "$out.part"
  return "$ok"
}

# wf_dump_globals <out>: roles (with password hashes) and tablespaces.
wf_dump_globals() {
  local out=$1
  (cd "$WF_KIT" && docker compose exec -T db pg_dumpall -U postgres --globals-only </dev/null) | wf_encrypt "$out"
  local rc=("${PIPESTATUS[@]}")
  [ "${rc[0]}" = 0 ] && [ "${rc[1]}" = 0 ] || { rm -f "$out" "$out.part"; return 1; }
}

# wf_config_paths: the server's configuration and secrets, as paths relative to /
# (only those that exist). Restoring them needs the same layout.
wf_config_paths() {
  local p
  for p in \
    "$WF_KIT/.env" "$WF_KIT/control.env" "$WF_KIT/api.env" "$WF_KIT/backup.env" \
    "$WF_KIT/backup.recipients" "$WF_KIT/businesses" "$WF_KIT/nginx" \
    /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/wholeflow-businesses \
    /etc/nginx/wholeflow-admin-allow.conf /etc/systemd/journald.conf.d/wholeflow.conf \
    /root/.config/rclone/rclone.conf
  do
    [ -e "$p" ] && echo "${p#/}"
  done
  for p in /etc/systemd/system/wholeflow-*; do
    [ -e "$p" ] && echo "${p#/}"
  done
  # Certificates can be issued again (certbot), but restoring them saves the
  # wait for DNS and Let's Encrypt limits. BACKUP_LETSENCRYPT=0 leaves them out.
  if [ "${BACKUP_LETSENCRYPT:-1}" = 1 ] && [ -d /etc/letsencrypt ]; then echo etc/letsencrypt; fi
}

# wf_config_bundle <out>
wf_config_bundle() {
  local out=$1
  local -a paths
  mapfile -t paths < <(wf_config_paths)
  [ "${#paths[@]}" -gt 0 ] || return 1
  tar -C / -czf - "${paths[@]}" | wf_encrypt "$out"
  local rc=("${PIPESTATUS[@]}")
  [ "${rc[0]}" = 0 ] && [ "${rc[1]}" = 0 ] || { rm -f "$out" "$out.part"; return 1; }
}
