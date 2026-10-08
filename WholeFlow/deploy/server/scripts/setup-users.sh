#!/usr/bin/env bash
# One-time (and safe to re-run) server setup for running the app API without
# root, plus the journald limits. Run as root before installing the
# wholeflow-api.service that has User=wholeflow-api:
#
#   /opt/wholeflow/scripts/setup-users.sh
#
# What it does:
#   - system group "wholeflow" and system user "wholeflow-api" (no shell, no
#     home, cannot log in);
#   - /opt/wholeflow/businesses: root:wholeflow, mode 2750 (setgid), with a
#     default ACL so every business folder and env file created later (by
#     new-business.sh, which runs with umask 077) is readable by the group:
#     folders 750, env files 640, owner root;
#   - existing businesses/<slug>/ folders 750 and their env files 640 root:wholeflow;
#   - api.env, control.env, .env, backup.env: 600 root:root (systemd reads
#     api.env as root before dropping privileges; the API never opens it);
#   - /etc/systemd/journald.conf.d/wholeflow.conf (90-day journal, 1 GB cap).
set -euo pipefail
KIT=${KIT:-/opt/wholeflow}
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
command -v setfacl >/dev/null || { echo "setfacl missing: apt-get install -y acl" >&2; exit 1; }

getent group wholeflow >/dev/null || groupadd --system wholeflow
if ! id -u wholeflow-api >/dev/null 2>&1; then
  useradd --system --gid wholeflow --no-create-home --home-dir /nonexistent \
    --shell /usr/sbin/nologin --comment "WholeFlow app API" wholeflow-api
fi
usermod --gid wholeflow --shell /usr/sbin/nologin wholeflow-api
passwd --lock wholeflow-api >/dev/null 2>&1 || true

# The API needs to reach /opt/wholeflow/businesses/<slug>/env and run
# bin/wholeflow-api; nothing else in the kit.
chmod o+x "$KIT" "$KIT/bin" 2>/dev/null || true
[ -e "$KIT/bin/wholeflow-api" ] && chmod 755 "$KIT/bin/wholeflow-api"

mkdir -p "$KIT/businesses"
chown root:wholeflow "$KIT/businesses"
chmod 2750 "$KIT/businesses"
# Default ACL: what new folders/files under businesses/ get, whatever the
# creating script's umask (umask is ignored when a default ACL exists).
setfacl -m g::r-x,o::--- "$KIT/businesses"
setfacl -d -m u::rwx,g::r-x,o::---,m::r-x "$KIT/businesses"

for dir in "$KIT"/businesses/*/; do
  [ -d "$dir" ] || continue
  chgrp -R wholeflow "$dir"
  chmod 2750 "$dir"
  setfacl -d -m u::rwx,g::r-x,o::---,m::r-x "$dir"
  # Every file inside: owner read/write, group read, others nothing.
  find "$dir" -maxdepth 1 -type f -exec chmod 640 {} +
done

for f in api.env control.env .env backup.env; do
  [ -e "$KIT/$f" ] || continue
  chown root:root "$KIT/$f"
  chmod 600 "$KIT/$f"
done
[ -e "$KIT/backup.recipients" ] && chmod 644 "$KIT/backup.recipients"  # public keys only

# Journald: keep at most 90 days / 1 GB of logs (they contain e-mail addresses and IPs).
here=$(cd "$(dirname "$0")" && pwd)
dropin=""
for c in "$KIT/systemd/journald.conf.d/wholeflow.conf" "$here/../systemd/journald.conf.d/wholeflow.conf"; do
  [ -f "$c" ] && { dropin=$c; break; }
done
[ -n "$dropin" ] || { echo "systemd/journald.conf.d/wholeflow.conf not found (copy the kit's systemd/ folder to $KIT/systemd)" >&2; exit 1; }
install -d -m 755 /etc/systemd/journald.conf.d
install -m 644 "$dropin" /etc/systemd/journald.conf.d/wholeflow.conf
systemctl restart systemd-journald

# Check: the API user can read every business's env and nothing secret else.
fail=0
for env in "$KIT"/businesses/*/env; do
  [ -e "$env" ] || continue
  if ! runuser -u wholeflow-api -- test -r "$env"; then echo "PROBLEM: wholeflow-api cannot read $env" >&2; fail=1; fi
done
for f in control.env .env api.env backup.env; do
  [ -e "$KIT/$f" ] || continue
  if runuser -u wholeflow-api -- test -r "$KIT/$f"; then echo "PROBLEM: wholeflow-api can read $f" >&2; fail=1; fi
done
[ "$fail" = 0 ] && echo "setup-users: ok (user wholeflow-api, group wholeflow, businesses/ readable by the group, journald 90 days)"
exit "$fail"
