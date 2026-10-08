# shellcheck shell=bash
# Shared by backup.sh and delete-business.sh (sourced, not run).
#
# Every backup file is encrypted with age (https://age-encryption.org) to the
# PUBLIC key(s) in /opt/wholeflow/backup.recipients. The matching private key
# never comes to this server: it lives offline with the owner (password
# manager / USB key). Without the recipients file nothing is backed up and the
# run fails loudly (FAILED marker, monitor PROBLEM line).

WF_KIT=${KIT:-/opt/wholeflow}
WF_BACKUP_DIR=${BACKUP_DIR:-/var/backups/wholeflow}
WF_RECIPIENTS=${BACKUP_RECIPIENTS:-$WF_KIT/backup.recipients}

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

# wf_encrypt <out.age>: stdin -> encrypted file (written to .part, then renamed).
wf_encrypt() {
  age -R "$WF_RECIPIENTS" -o "$1.part" && mv "$1.part" "$1"
}

# wf_dump_db <database> <out.dump.age> <work dir>
# pg_dump (custom format), checks the dump reads back (pg_restore --list),
# then encrypts it. The plaintext dump exists only for that check, inside the
# root-only work dir, and is removed straight after.
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

# wf_dump_globals <out.sql.age>: roles (with password hashes) and tablespaces.
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

# wf_config_bundle <out.tar.gz.age>
wf_config_bundle() {
  local out=$1
  local -a paths
  mapfile -t paths < <(wf_config_paths)
  [ "${#paths[@]}" -gt 0 ] || return 1
  tar -C / -czf - "${paths[@]}" | wf_encrypt "$out"
  local rc=("${PIPESTATUS[@]}")
  [ "${rc[0]}" = 0 ] && [ "${rc[1]}" = 0 ] || { rm -f "$out" "$out.part"; return 1; }
}
