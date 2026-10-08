#!/usr/bin/env bash
# WholeFlow server monitor: writes what it checks to a log on this server
# (no alerts are sent). Run every 5 minutes by wholeflow-monitor.timer; with
# --daily (wholeflow-monitor-daily.timer, late evening) it also writes the
# day's warnings and errors from the WholeFlow services.
#
#   /var/log/wholeflow/monitor-YYYY-MM-DD.log   one line per run: OK … or PROBLEM …
#   /var/log/wholeflow/daily-YYYY-MM-DD.log      the day's summary
#
# Kept 30 days. The admin app shows them under Server health.
set -uo pipefail

KIT=${KIT:-/opt/wholeflow}
LOG_DIR=${LOG_DIR:-/var/log/wholeflow}
BACKUP_DIR=${BACKUP_DIR:-/var/backups/wholeflow}
CONTROL_URL=${CONTROL_URL:-http://127.0.0.1:8100/control/health}
API_URL=${API_URL:-http://127.0.0.1:8300/health}
DISK_LIMIT=${DISK_LIMIT:-85}      # % used
MEM_LIMIT=${MEM_LIMIT:-10}        # % available, at least
CERT_DAYS=${CERT_DAYS:-14}        # days before the HTTPS certificate expires
BACKUP_HOURS=${BACKUP_HOURS:-30}  # newest backup older than this is a problem
KEEP_DAYS=${KEEP_DAYS:-30}

mkdir -p "$LOG_DIR"
chmod 750 "$LOG_DIR"
now=$(TZ=Asia/Kolkata date -Iseconds)
today=$(TZ=Asia/Kolkata date +%F)
problems=()
notes=()

problem() { problems+=("$1"); }
note() { notes+=("$1"); }

# A URL answers with one of the expected HTTP codes.
check_http() { # name url codes…
  local name=$1 url=$2; shift 2
  local code
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url" 2>/dev/null)
  code=${code:0:3}
  [ -n "$code" ] || code=000
  for want in "$@"; do [ "$code" = "$want" ] && { note "$name"; return; }; done
  problem "$name answered $code ($url)"
}

check_http control "$CONTROL_URL" 200
check_http api "$API_URL" 200

# Every business through nginx: the app API refuses a request without a login (401).
public=""
[ -r "$KIT/control.env" ] && public=$(grep -E '^PUBLIC_URL=' "$KIT/control.env" | cut -d= -f2- | tr -d '"')
if [ -n "$public" ] && [ -d "$KIT/businesses" ]; then
  for dir in "$KIT"/businesses/*/; do
    [ -d "$dir" ] || continue
    slug=$(basename "$dir")
    check_http "b/$slug" "${public%/}/b/$slug/api/v1/me" 401
  done
fi

# PostgreSQL.
if [ -f "$KIT/docker-compose.yml" ] && command -v docker >/dev/null; then
  if (cd "$KIT" && docker compose exec -T db pg_isready -U postgres -q < /dev/null); then note db; else problem "database not ready"; fi
fi

# Services.
if command -v systemctl >/dev/null; then
  for unit in wholeflow-control wholeflow-api nginx docker; do
    state=$(systemctl is-active "$unit" 2>/dev/null || true)
    [ "$state" = active ] || problem "$unit is ${state:-unknown}"
  done
fi

# Disk and memory.
disk=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')
[ "${disk:-0}" -ge "$DISK_LIMIT" ] && problem "disk ${disk}% used"
note "disk=${disk}%"
if [ -r /proc/meminfo ]; then
  mem=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%d", a*100/t}' /proc/meminfo)
  [ "$mem" -lt "$MEM_LIMIT" ] && problem "only ${mem}% memory available"
  note "mem_free=${mem}%"
fi

# HTTPS certificate.
if [ -n "$public" ]; then
  host=$(echo "$public" | sed -E 's#^https?://##; s#/.*$##')
  end=$(echo | timeout 10 openssl s_client -servername "$host" -connect "$host:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
  if [ -n "$end" ]; then
    left=$(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
    [ "$left" -lt "$CERT_DAYS" ] && problem "HTTPS certificate expires in $left days"
    note "cert=${left}d"
  else
    problem "could not read the HTTPS certificate of $host"
  fi
fi

# Newest backup.
if [ -d "$BACKUP_DIR" ]; then
  newest=$(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
  if [ -n "$newest" ]; then
    age=$(( ($(date +%s) - ${newest%.*}) / 3600 ))
    [ "$age" -gt "$BACKUP_HOURS" ] && problem "newest backup is ${age}h old"
    note "backup=${age}h"
  else
    problem "no backups in $BACKUP_DIR"
  fi
fi

line="$now"
if [ ${#problems[@]} -eq 0 ]; then
  line+=" OK ${notes[*]}"
else
  joined=$(printf '%s; ' "${problems[@]}")
  line+=" PROBLEM ${joined%; } | ${notes[*]}"
fi
echo "$line" >> "$LOG_DIR/monitor-$today.log"

if [ "${1:-}" = "--daily" ] && command -v journalctl >/dev/null; then
  {
    echo "WholeFlow daily summary $today (written $now)"
    echo
    echo "Monitor runs: $(grep -c . "$LOG_DIR/monitor-$today.log" 2>/dev/null || echo 0), with a problem: $(grep -c ' PROBLEM ' "$LOG_DIR/monitor-$today.log" 2>/dev/null || echo 0)"
    grep ' PROBLEM ' "$LOG_DIR/monitor-$today.log" 2>/dev/null | tail -20
    for unit in wholeflow-api wholeflow-control; do
      echo
      count=$(journalctl -u "$unit" --since today -p warning -o cat --no-pager 2>/dev/null | grep -c . || true)
      echo "$unit: $count warnings/errors today"
      journalctl -u "$unit" --since today -p warning -o short-iso --no-pager 2>/dev/null | tail -20
    done
  } > "$LOG_DIR/daily-$today.log"
fi

find "$LOG_DIR" -maxdepth 1 -name '*.log' -mtime +"$KEEP_DAYS" -delete
exit 0
