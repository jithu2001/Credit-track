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
#   staff      the Deno staff service (container wholeflow-staff-1): obsolete, the
#              app manages staff through the app API. It is no longer in
#              docker-compose.yml, so it is handled by container name here
#              (docker compose up -d --remove-orphans also removes it).
#
# "stop" keeps the containers (restart policy unless-stopped leaves them stopped
# after a reboot). "remove" is for when everything has run without them for a while.
#
# nginx: the legacy per-business routes (/etc/nginx/wholeflow-businesses/<slug>.conf,
# /b/<slug>/auth/v1/ and /rest/v1/) accept the same keys as the app API, so
# they must not outlive the switch. "stop postgrest" disables them (renamed to
# <slug>.conf.retired, which nginx does not include), "start postgrest" puts
# them back, "remove" deletes them. Their auth/v1 route is already shadowed by
# the app API's regex location.
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

STAFF=wholeflow-staff-1
ROUTES=/etc/nginx/wholeflow-businesses

reload_nginx_or_undo() { # undo-function: nginx -t, reload; on failure run the undo and stop
  if nginx -t 2>/dev/null; then
    systemctl reload nginx
  else
    "$1"
    echo "nginx -t failed; routes put back as they were" >&2
    exit 1
  fi
}
routes_off() { for f in "$ROUTES"/*.conf; do [ -e "$f" ] && mv "$f" "$f.retired"; done; return 0; }
routes_on() { for f in "$ROUTES"/*.conf.retired; do [ -e "$f" ] && mv "$f" "${f%.retired}"; done; return 0; }

case "$action" in
  stop|start)
    case "$kind" in
      staff)
        if docker inspect "$STAFF" >/dev/null 2>&1; then docker "$action" "$STAFF" >/dev/null; else echo "no $STAFF container (already removed)"; fi
        ;;
      postgrest)
        each_business "$action" rest
        if [ "$action" = stop ]; then routes_off; reload_nginx_or_undo routes_on; echo "legacy nginx routes disabled"
        else routes_on; reload_nginx_or_undo routes_off; echo "legacy nginx routes enabled"; fi
        ;;
      *) each_business "$action" "$(service_of "$kind")" ;;
    esac
    echo "$kind: $action done"
    ;;
  status)
    docker ps -a --format '{{.Names}}\t{{.Status}}' | grep -E '^(biz-|wholeflow-staff)' || echo "no per-business containers"
    ls "$ROUTES" 2>/dev/null | sed 's/^/nginx route: /' || true
    ;;
  remove)
    [ "$kind" = --yes ] || { echo "This deletes the GoTrue, PostgREST and Deno containers and their nginx routes. Run with: remove --yes" >&2; exit 1; }
    each_business down
    for dir in businesses/*/; do rm -f "$dir/compose.yml"; done
    rm -f "$ROUTES"/*.conf "$ROUTES"/*.conf.retired
    if docker inspect "$STAFF" >/dev/null 2>&1; then docker rm -f "$STAFF" >/dev/null; fi
    docker volume rm wholeflow_deno-cache >/dev/null 2>&1 || true   # the staff service's cache
    nginx -t
    systemctl reload nginx
    echo "Removed the legacy containers and nginx routes."
    ;;
  *) echo "usage: $0 stop|start gotrue|postgrest|staff | status | remove --yes" >&2; exit 2 ;;
esac
