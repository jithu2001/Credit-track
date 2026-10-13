#!/usr/bin/env bash
# Updates the WholeFlow server (https://api.jitsuji.xyz) from this computer:
# builds the app API and the control service for Linux, copies them up,
# swaps them in one at a time and checks each one's health. A service that
# does not come back healthy is rolled back to its previous binary at once.
# New database migrations are uploaded and applied (after asking).
#
#   deploy/update-server.sh                   # tests, then api + control (+ migrations)
#   deploy/update-server.sh --only api        # just the app API (or: --only control)
#   deploy/update-server.sh --skip-tests --yes
#   deploy/update-server.sh --allow-lockdown  # also apply 0009_lockdown.sql (see below)
#
# Needs the `ssh wholeflow` alias with an unlocked key (ssh-add ~/.ssh/wholeflow_vps).
# WF_SSH overrides the host. Nothing here creates businesses or touches the
# website (website/deploy.sh) or the phone apps.
#
# On the server, the previous binaries stay as /opt/wholeflow/bin/<name>.prev.
# Roll back by hand with:
#   cp /opt/wholeflow/bin/wholeflow-api.prev /opt/wholeflow/bin/wholeflow-api && systemctl restart wholeflow-api
set -euo pipefail
cd "$(dirname "$0")/.."                       # the WholeFlow folder

HOST=${WF_SSH:-wholeflow}
ROOT=/opt/wholeflow
only="" skip_tests=0 yes=0 allow_lockdown=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --only) only=${2:?--only needs api or control}; shift ;;
    --skip-tests) skip_tests=1 ;;
    --yes) yes=1 ;;
    --allow-lockdown) allow_lockdown=1 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
case $only in "" | api | control) ;; *) echo "--only: api or control" >&2; exit 2 ;; esac

die() { echo "error: $*" >&2; exit 1; }
ask() { [[ $yes = 1 ]] && return 0; read -r -p "$1 [y/N] " a; [[ $a == [yY]* ]]; }
remote() { ssh -o BatchMode=yes "$HOST" "$@" < /dev/null; }

# name of the binary on the server -> Go package, systemd unit, health URL on the server
declare -A PKG=([wholeflow-api]=./cmd/api [wholeflow-control]=./cmd/control)
declare -A UNIT=([wholeflow-api]=wholeflow-api [wholeflow-control]=wholeflow-control)
declare -A HEALTH=([wholeflow-api]=http://127.0.0.1:8300/health [wholeflow-control]=http://127.0.0.1:8100/control/health)
services=(wholeflow-api wholeflow-control)
[[ -n $only ]] && services=("wholeflow-$only")

echo "== checking the server ($HOST)"
remote true 2>/dev/null || die "cannot reach '$HOST' over ssh (unlock the key: ssh-add ~/.ssh/wholeflow_vps)."
for s in "${services[@]}"; do
  state=$(remote "systemctl is-active ${UNIT[$s]}" || true)
  # The app API must already be set up (docs/API_PLAN.md section 5); this
  # script only updates it.
  [[ $state == active ]] || die "${UNIT[$s]} is '$state' on the server. First-time setup is docs/API_PLAN.md section 5, not this script."
done

# ---- migrations the server does not have yet
mapfile -t remote_migs < <(remote "ls $ROOT/migrations" | grep '\.sql$' || true)
new_migs=()
for f in db/migrations/*.sql; do
  n=$(basename "$f")
  printf '%s\n' "${remote_migs[@]}" | grep -qx "$n" || new_migs+=("$n")
done
for n in "${new_migs[@]}"; do
  # 0009_lockdown removes the grants PostgREST and Tally PCs before 0.6.0 rely on.
  if [[ $n == 0009_lockdown.sql && $allow_lockdown = 0 ]]; then
    die "0009_lockdown.sql is not on the server yet. Apply it only after every Tally PC runs 0.6.0 and PostgREST is stopped (API_PLAN.md section 5), with --allow-lockdown."
  fi
done

echo
echo "Will update: ${services[*]}"
if [[ ${#new_migs[@]} -gt 0 ]]; then echo "New migrations: ${new_migs[*]} (each business database is dumped first)"; else echo "Migrations: none new"; fi
ask "Continue?" || exit 1

# ---- build
if [[ $skip_tests = 0 ]]; then
  echo "== go vet + go test"
  go vet ./...
  go test ./... >/dev/null || die "tests failed; nothing was uploaded."
fi
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
for s in "${services[@]}"; do
  echo "== build $s (linux/amd64)"
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o "$out/$s" "${PKG[$s]}"
done

# ---- migrations first: new binaries may need them, old ones keep working
if [[ ${#new_migs[@]} -gt 0 ]]; then
  echo "== upload migrations"
  for n in "${new_migs[@]}"; do scp -q "db/migrations/$n" "$HOST:$ROOT/migrations/$n"; done
  echo "== apply migrations to every business"
  remote "cd $ROOT && scripts/migrate.sh --all" || die "migrate.sh failed (binaries not changed). Its output above says which business; pre-migrate dumps are in $ROOT/backup/pre-migrate."
fi

# ---- swap each binary, check health, roll back if it is not healthy
for s in "${services[@]}"; do
  echo "== update $s"
  scp -q "$out/$s" "$HOST:$ROOT/bin/$s.new"
  remote "set -e; cd $ROOT/bin; chmod 755 $s.new; cp -p $s $s.prev; mv $s.new $s; systemctl restart ${UNIT[$s]}"
  ok=0
  for _ in $(seq 1 15); do
    sleep 2
    code=$(remote "curl -s -o /dev/null -m 5 -w '%{http_code}' ${HEALTH[$s]}" || true)
    [[ $code == 200 ]] && { ok=1; break; }
  done
  if [[ $ok = 1 ]]; then
    echo "   healthy (${HEALTH[$s]})"
  else
    echo "   NOT healthy after 30 s: rolling back $s" >&2
    remote "cd $ROOT/bin && cp -p $s.prev $s && systemctl restart ${UNIT[$s]}"
    remote "journalctl -u ${UNIT[$s]} -n 30 --no-pager" >&2 || true
    die "$s was rolled back to the previous version (log above)."
  fi
done

echo
echo "Server updated: ${services[*]}."
echo "Previous binaries: $ROOT/bin/<name>.prev   Logs: ssh $HOST journalctl -u wholeflow-api -u wholeflow-control --since today"
