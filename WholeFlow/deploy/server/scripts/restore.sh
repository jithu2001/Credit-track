#!/usr/bin/env bash
# Restores WholeFlow backups made by scripts/backup.sh. Run as root on the
# server. Plain backups need nothing else; encrypted ones (*.age) need the age
# PRIVATE key brought over for the occasion (-i KEY; never kept on the
# server). Step by step guide: docs/RUNBOOK_RESTORE.md.
#
#   restore.sh fetch  <run>                       copy a run from BACKUP_REMOTE to /opt/wholeflow/backup/<run>
#   restore.sh verify <run>                       checksums + OK marker
#   restore.sh config <run> [-i KEY]              unpack config.tar.gz into /root/restore-config-<run>/ (review, then copy)
#   restore.sh globals <run> [-i KEY]              roles and password hashes (errors for roles that exist are normal)
#   restore.sh all    <run> [-i KEY]              fresh server: globals + every database under its own name
#   restore.sh db     <run> <slug> <scratch> [-i KEY]  one business into a NEW scratch database (live one untouched)
#   restore.sh swap   <slug> <scratch>            make the scratch database the live biz_<slug> (old one kept, renamed)
#
# <run> is a folder name in /opt/wholeflow/backup (e.g. 2026-10-08_0230) or a
# path, e.g. a folder you uploaded back from your computer.
# KEY (encrypted backups only) is the age identity file (age-keygen output), plain or passphrase-protected
# (age -p); a protected one is decrypted once into /dev/shm and wiped on exit.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=backup-lib.sh
. "$here/backup-lib.sh"
wf_load_backup_env

die() { echo "restore: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root"

action=${1:-}; shift || true
args=(); IDENTITY=""
while [ $# -gt 0 ]; do
  case "$1" in
    -i|--identity) IDENTITY=${2:?-i needs a file}; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
# Paths given relative to where you are, before moving into the kit.
[ -n "$IDENTITY" ] && IDENTITY=$(realpath -- "$IDENTITY")
[ ${#args[@]} -gt 0 ] && [ -d "${args[0]}" ] && args[0]=$(realpath -- "${args[0]}")
cd "$WF_KIT"

run_dir() {
  local r=${1:?which backup run? (ls $WF_BACKUP_DIR)}
  if [ -d "$r" ]; then echo "$r"; else echo "$WF_BACKUP_DIR/$r"; fi
}

KEYFILE=""
cleanup() { [ -n "$KEYFILE" ] && [ "$KEYFILE" != "$IDENTITY" ] && shred -u "$KEYFILE" 2>/dev/null || true; }
trap cleanup EXIT
need_key() {
  command -v age >/dev/null || die "age is not installed (apt-get install -y age)"
  [ -n "$IDENTITY" ] || die "needs the private key: -i /path/to/wholeflow-backup-key.txt"
  [ -r "$IDENTITY" ] || die "cannot read $IDENTITY"
  if head -c 40 "$IDENTITY" | grep -Eq '^(age-encryption.org|-----BEGIN AGE ENCRYPTED)'; then
    KEYFILE=$(mktemp -p /dev/shm wf-key.XXXXXX)
    chmod 600 "$KEYFILE"
    echo "Passphrase for the backup key:" >&2
    age -d -o "$KEYFILE" "$IDENTITY" || die "could not open the key"
  else
    KEYFILE=$IDENTITY
  fi
}
# bfile <run dir> <name>: the plain or encrypted (.age) file of that name.
bfile() { if [ -e "$1/$2" ]; then echo "$1/$2"; else echo "$1/$2.age"; fi; }
# key_for <run dir>: unlock the private key once, here (not inside a pipe),
# when the run holds encrypted files.
key_for() { if compgen -G "$1/*.age" >/dev/null; then need_key; fi; }
# dec <file>: its contents, decrypted when it is a .age file.
dec() {
  case "$1" in
    *.age) [ -n "$KEYFILE" ] || die "encrypted backup: needs -i KEY"; age -d -i "$KEYFILE" "$1" ;;
    *) cat "$1" ;;
  esac
}
# dumps <run dir>: the database dumps in it, plain or encrypted.
dumps() { local f; for f in "$1"/*.dump "$1"/*.dump.age; do [ -e "$f" ] && echo "$f"; done; }
dbname() { local b; b=$(basename "$1"); b=${b%.age}; echo "${b%.dump}"; }

psql_pg() { docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
db_exists() { [ "$(docker compose exec -T db psql -U postgres -tAc "select 1 from pg_database where datname = '$1'" </dev/null)" = 1 ]; }

verify() {
  local d=$1
  [ -d "$d" ] || die "no such backup: $d"
  [ -e "$d/OK" ] || echo "WARNING: $d has no OK marker: $(cat "$d/FAILED" 2>/dev/null | tr '\n' ' ')" >&2
  (cd "$d" && sha256sum -c --quiet SHA256SUMS) || die "checksums do not match in $d"
  echo "verified: $d"
}

case "$action" in
  fetch)
    [ -n "${BACKUP_REMOTE:-}" ] || die "BACKUP_REMOTE is not set in $WF_KIT/backup.env"
    r=${args[0]:?which run? (rclone lsf ${BACKUP_REMOTE%/}/)}
    mkdir -p "$WF_BACKUP_DIR"; chmod 700 "$WF_BACKUP_DIR"
    rclone copy "${BACKUP_REMOTE%/}/$r" "$WF_BACKUP_DIR/$r"
    verify "$WF_BACKUP_DIR/$r"
    ;;
  verify)
    verify "$(run_dir "${args[0]:-}")"
    ;;
  config)
    d=$(run_dir "${args[0]:-}"); key_for "$d"
    out=/root/restore-config-$(basename "$d")
    mkdir -m 700 -p "$out"
    dec "$(bfile "$d" config.tar.gz)" | tar -C "$out" -xzf -
    echo "Unpacked into $out (paths as under /). Review, then copy what you need, e.g.:"
    echo "  cp -a $out/opt/wholeflow/{.env,control.env,api.env} $out/opt/wholeflow/businesses $WF_KIT/"
    ;;
  globals)
    d=$(run_dir "${args[0]:-}"); key_for "$d"
    # Not ON_ERROR_STOP: "role postgres already exists" and similar are expected.
    dec "$(bfile "$d" globals.sql)" | docker compose exec -T db psql -U postgres -q -v ON_ERROR_STOP=0 >/dev/null
    echo "roles restored"
    ;;
  all)
    d=$(run_dir "${args[0]:-}"); verify "$d"; key_for "$d"
    for f in $(dumps "$d"); do
      db=$(dbname "$f")
      db_exists "$db" && die "database $db already exists; 'all' is for an empty server (use db/swap for one business)"
    done
    dec "$(bfile "$d" globals.sql)" | docker compose exec -T db psql -U postgres -q -v ON_ERROR_STOP=0 >/dev/null
    echo "roles restored"
    for f in $(dumps "$d"); do
      db=$(dbname "$f")
      echo "== $db"
      # --create: makes the database with its own grants and settings.
      dec "$f" | docker compose exec -T db pg_restore -U postgres --create --exit-on-error -d postgres
    done
    echo "All databases restored. Next: config files, services (docs/RUNBOOK_RESTORE.md)."
    ;;
  db)
    d=$(run_dir "${args[0]:-}"); slug=${args[1]:?slug}; scratch=${args[2]:?scratch database name, e.g. biz_${slug}_restore}
    [[ $slug =~ ^[a-z][a-z0-9]{1,19}$ ]] || die "bad slug"
    [[ $scratch =~ ^[a-z_][a-z0-9_]{1,62}$ ]] || die "bad scratch name"
    [ "$scratch" != "biz_$slug" ] || die "restore into a scratch database, not the live biz_$slug"
    db_exists "$scratch" && die "$scratch already exists (drop it first if it is an old scratch copy)"
    f=$(bfile "$d" "biz_$slug.dump"); [ -e "$f" ] || die "no biz_$slug.dump in $d"
    verify "$d"; key_for "$d"
    psql_pg </dev/null -c "create database $scratch"
    dec "$f" | docker compose exec -T db pg_restore -U postgres --exit-on-error -d "$scratch"
    echo "Restored biz_$slug from $(basename "$d") into $scratch. Live data is untouched."
    echo "Check it, e.g.: docker compose exec db psql -U postgres -d $scratch -c 'select count(*) from public.transactions'"
    echo "Then: $0 swap $slug $scratch   (or drop it: drop database $scratch)"
    ;;
  swap)
    slug=${args[0]:?slug}; scratch=${args[1]:?scratch database}
    [[ $slug =~ ^[a-z][a-z0-9]{1,19}$ ]] || die "bad slug"
    db_exists "$scratch" || die "no database $scratch"
    live=biz_$slug; old=${live}_old_$(date +%Y%m%d%H%M)
    # Database-level grants are not in a dump restored without --create:
    # the same ones new-business.sh gives (only its own roles may connect).
    psql_pg </dev/null \
      -c "revoke all on database $scratch from public" \
      -c "grant connect on database $scratch to ${slug}_auth, ${slug}_api" \
      -c "grant create on database $scratch to ${slug}_auth"
    # Keep the app API out while renaming, then end its open connections.
    if db_exists "$live"; then
      psql_pg </dev/null -c "alter database $live allow_connections false" \
        -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$live' and pid <> pg_backend_pid()" >/dev/null
      psql_pg </dev/null -c "alter database $live rename to $old"
    fi
    psql_pg </dev/null -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$scratch'" >/dev/null
    psql_pg </dev/null -c "alter database $scratch rename to $live"
    echo "biz_$slug now holds the restored data. The previous database is kept as $old"
    echo "(it does not accept connections; drop it once you are satisfied: drop database $old)."
    echo "The app API reconnects by itself; check sign-in and a PC sync for this business."
    ;;
  *)
    sed -n '2,20p' "$0"; exit 2 ;;
esac
