#!/usr/bin/env bash
# Retires the per-business containers the WholeFlow app API replaced, one kind
# at a time and reversibly (docs/API_PLAN.md, "After the move"):
#
#   scripts/retire-containers.sh stop  gotrue|postgrest|staff   stop them (kept; start undoes it)
#   scripts/retire-containers.sh start gotrue|postgrest|staff   start them again
#   scripts/retire-containers.sh status                         what is running
#   scripts/retire-containers.sh remove --yes                   delete them and their nginx routes (final)
#
#   gotrue     each business's login container: sign-in is served by the app API
#              (nginx's /b/<slug>/auth/v1/ rule) from the moment the API is deployed
#   postgrest  each business's data API: only Tally PCs older than 0.6.0 use it;
#              stop it once every PC runs 0.6.0
#   staff      the Deno staff service: only phone apps older than the API build use it
#
# "stop" keeps the containers (restart policy unless-stopped leaves them stopped
# after a reboot). "remove" is for when everything has run without them for a while.
set -euo pipefail
cd /opt/wholeflow
action=${1:-status}
kind=${2:-}

service_of() {
  case "$1" in
    gotrue) echo auth ;;
    postgrest) echo rest ;;
    *) echo "unknown kind '$1' (gotrue, postgrest or staff)" >&2; exit 2 ;;
  esac
}

each_business() { # runs: docker compose … <args> for every business that still has a compose file
  for dir in businesses/*/; do
    slug=$(basename "$dir")
    [ -f "$dir/compose.yml" ] || continue
    echo "-- $slug"
    docker compose -p "biz-$slug" -f "$dir/compose.yml" --env-file "$dir/env" "$@" </dev/null
  done
}

case "$action" in
  stop|start)
    case "$kind" in
      staff) docker compose "$action" staff </dev/null ;;
      *) each_business "$action" "$(service_of "$kind")" ;;
    esac
    echo "$kind: $action done"
    ;;
  status)
    docker ps -a --format '{{.Names}}\t{{.Status}}' | grep -E '^(biz-|wholeflow-staff)' || echo "no per-business containers"
    ;;
  remove)
    [ "$kind" = --yes ] || { echo "This deletes the GoTrue, PostgREST and Deno containers and their nginx routes. Run with: remove --yes" >&2; exit 1; }
    each_business down
    for dir in businesses/*/; do rm -f "$dir/compose.yml"; done
    rm -f /etc/nginx/wholeflow-businesses/*.conf
    docker compose rm -sf staff </dev/null || true
    nginx -t && systemctl reload nginx
    echo "Removed. Also delete the functions/v1 location from nginx/wholeflow.conf (the Deno staff service) and reload nginx."
    ;;
  *) echo "usage: $0 stop|start gotrue|postgrest|staff | status | remove --yes" >&2; exit 2 ;;
esac
