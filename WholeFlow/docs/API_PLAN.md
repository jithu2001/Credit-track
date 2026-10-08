# WholeFlow app API plan (moving the apps' work to the server)

Status (2026-10-08), branch `api-layer`: everything built and tested locally,
not deployed yet: phases 1–6, the Tally PC through the API, monitoring, sign-in
by the API, and provisioning without containers. Deploy once (section 5). That covers the `wholeflow-api` service and payment insights (`GET /payments`,
`GET /payments/shops/{id}`). The app's insights screen, shop Payments tab and
dashboard overdue card now use it, and the phone no longer downloads every voucher.
Parity check on the demo business's real data (2 companies, 462 shops, 5,170 vouchers):
company totals are identical to the old on-phone result. One shop differed by one
"paid bill" because the old code broke ties between same-day vouchers synced in the
same batch at random; the server now uses a fixed order.

Phase 2 (statement) built: `GET /shops/{id}/statement[?from=&to=]` gives the
ledger with running balances, or a period with the balance brought forward.
Owners and staff who may see the company's transactions can use it; other
staff get 403. The Statement tab and "Share statement" use it; the customer
PDF and text are still made on the phone.

Phase 3 (dashboard) built: `GET /dashboard?company=[&month=YYYY-MM]` returns
company totals, sync state, this month's sales (null for staff without
transaction access) and the top 10 dues in one call, instead of four requests
plus every sales row of the month.

Phase 4 (shops and reports) built: `GET /shops` (search, balance filter,
sites, sort, pages of 50), `GET /shops/{id}`, `GET /reports/outstanding` and
`GET /reports/overdue` (ageing by `overdue_shops()`, grouped by site A–Z,
"no site" last, with subtotals). The app only narrows a loaded report for the
on-screen search.

Phase 5 (stock, purchases, suppliers) built: `GET /stock` (items with status,
effective minimum, shortfall; totals; the stock alert in order), `GET
/stock/{id}`, `GET /stock/{id}/purchases`, `PUT /stock/minimum` (the API's
first write: read-write transaction, `set_stock_minimum()` still decides),
`GET /purchases` (search, supplier, pages of 50), `GET /purchases/{id}`,
`GET /purchases/months`, `GET /suppliers`, `GET /suppliers/{id}`. Purchases
and suppliers are owner only (403 for staff). The app still searches and
filters the loaded stock and supplier lists on screen.

Phase 6 (the rest) built: profile, companies, own access, areas, service
status and sync health (`/me`, `/me/access`, `/companies`, …); sites and shop
locations; visits (tasks, check-in, plans, notes); and staff management, which
moves from the Deno service into the API (`/staff`: the owner check, company
and site checks, logins through the business login service's admin API, and
changes as the business's service role). **The phone apps no longer read or
write the database directly.** They use the app API for data and the login
service only to sign in and change passwords.

What is left after deploying (see "After the move"): retire the Deno staff
service (its container and the `functions/v1` nginx rule) once every phone has
the new app; PostgREST stays for the Tally PC until it moves to the API too.

## 1. Goal

Today the Owner and Staff apps read tables straight from each business's
PostgREST and do much of the work on the phone: payment analysis, statements,
the outstanding report, and stock status and alerts. This plan moves that work
into a **WholeFlow app API** on the server, so that:

- the phone downloads finished answers instead of raw rows (one call for a
  shop's payment profile instead of every transaction of every shop);
- the same API can serve a **web app** later, with no business logic rewritten;
- business rules live in one place (Go on the server), tested once.

What "lighter" means: less code and less data on the phone, and fewer, faster
requests (each request from Kerala to the server in Germany costs ~200 ms). The APK size
(~80 MB) is mostly the Flutter engine and does not change much.

Out of scope: the Tally PC (it keeps writing through PostgREST with its PC
key), logins (GoTrue stays), the admin app (control service stays as it is).

## 2. Architecture

```
Phones / future web app
   │ login (unchanged):  https://api.<domain>/b/<slug>/auth/v1/*   → GoTrue
   │ data (new):         https://api.<domain>/b/<slug>/api/v1/*    → WholeFlow app API (Go)
   │ data (old, shrinking): https://api.<domain>/b/<slug>/rest/v1/* → PostgREST
   ▼
WholeFlow app API — one Go process (cmd/api → wholeflow-api, systemd), serves every business
   1. reads <slug> from the path; looks up the business in control_db (cached)
   2. checks the Bearer token with that business's JWT secret (same tokens GoTrue issues)
   3. per request, in a transaction on biz_<slug>, as the <slug>_api role (as PostgREST does):
        SET LOCAL ROLE authenticated;
        SELECT set_config('request.jwt.claims', <token claims>, true);
        SELECT public.check_request();      -- revoked PC → 403, subscription ended → 402
        … the feature's queries …
   4. computes the answer in Go and returns JSON
```

- **A separate service, not inside the control service.** The control service
  serves the admin app and the PCs' activation and heartbeat; the app API serves
  every phone. Separate processes can be restarted and scaled on their own. They
  share code (`internal/…`).
- **Row-level security stays the security boundary.** The API runs as the same
  database role and claims as PostgREST, so every existing rule keeps working
  unchanged: owner vs staff, `can_see_company`, staff site access, transaction
  permission, and the paused-subscription block. Go code never decides who may
  see what.
- **Same errors as today**: 402 + `subscription_ended` details, 401, 403, so
  the apps' `AppFailure` and paused screen work without changes.
- **New businesses need nothing extra**: the API finds a business through
  control_db and `businesses/<slug>/env` at request time, so `new-business.sh`
  and `delete-business.sh` don't change. nginx needs one rule for all
  businesses (`location ~ ^/b/<slug>/api/v1/` → 127.0.0.1:8300 in `wholeflow.conf`),
  like the staff service's.

## 3. How the apps move over

One repository at a time. Each Flutter `*Repository` already hides where data
comes from, and the screens and widget tests use fakes. Moving a feature means
its repository calls the API instead of PostgREST. Domain models, screens and
widget tests stay as they are. Features not yet moved keep using PostgREST, so
the app works at every step and old app versions keep working.

## 4. Order (biggest payoff first)

| # | Feature | Today on the phone | API |
|---|---------|--------------------|-----|
| 1 | Payment insights (owner) | downloads every transaction of the company, then FIFO bill matching, ageing, habits (`payment_analysis.dart`, 441 lines) | `GET /analytics?company=` (business summary), `GET /shops/{id}/payments` |
| 2 | Shop statement + share | all transactions of the shop, running balances, period statement | `GET /shops/{id}/statement?from=&to=` |
| 3 | Dashboard | 3 queries + month sales | `GET /dashboard?company=` (one call) |
| 4 | Shops list, dues, outstanding report | paging, grouping by site, totals | `GET /shops`, `GET /reports/outstanding`, `GET /reports/overdue` |
| 5 | Stock, purchases, suppliers | status, minimum stock, alerts, filters | `GET /stock`, `PUT /stock/minimum`, … |
| 6 | Sites, visits, staff | mostly database functions already | thin wrappers; fold the Deno staff service into the API |

Each step: Go handler + Go tests against a throwaway Postgres (seed data from
`db/tests`, checking the numbers **and** that staff / another business / a
paused business are refused); then switch the Flutter repository; then test on
the phone; then deploy.

Phase 1 delivers the API service itself plus feature 1, as the proof.

## 5. Deploying (once, when everything is finished)

Everything below is built and tested locally; nothing is on the server yet.
Each step can be undone on its own (in brackets).

**Before**
1. Merge `api-layer`. Build: `wholeflow-api` and `wholeflow-control`
   (`CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o <name> ./cmd/api|./cmd/control`),
   the Tally PC zip 0.6.0 (`deploy/build-release.sh`), and the hosted Owner and Staff apps.
2. With the **current** app on the phone, note the dashboard's overdue total and shop count
   (to compare with the new app).

**Server** (`ssh wholeflow`; copy files with scp first)
3. Copy: `bin/wholeflow-api`; `bin/wholeflow-control` (keep the old one as `wholeflow-control.prev`);
   `db/auth/auth_schema.sql` → `/opt/wholeflow/auth/`; `scripts/new-business.sh`, `monitor.sh`,
   `retire-containers.sh`; the `systemd/wholeflow-api.service` and four `wholeflow-monitor*` units
   → `/etc/systemd/system/`; `nginx/wholeflow.conf` (keep `wholeflow.conf.prev`).
4. Settings for the API, printing no secret:
   ```bash
   cd /opt/wholeflow && grep -E '^(CONTROL_DB_URL|MASTER_KEY)=' control.env > api.env \
     && printf 'KIT_DIR=/opt/wholeflow\nPG_HOST=127.0.0.1:5432\nLISTEN=127.0.0.1:8300\n' >> api.env && chmod 600 api.env
   systemctl daemon-reload && systemctl enable --now wholeflow-api && systemctl restart wholeflow-control
   curl -s 127.0.0.1:8300/health        # {"ok":true}
   ```
   [undo: `systemctl stop wholeflow-api`; old control from `.prev`]
5. `nginx -t && systemctl reload nginx`. **From here sign-in and the app API are live** for every
   business: `/b/<slug>/auth/v1/` and `/api/v1/` go to the API. Phones already signed in stay signed
   in (same tokens and sessions). Old app versions keep working (PostgREST is untouched).
   [undo: `wholeflow.conf.prev` + reload]
6. `systemctl enable --now wholeflow-monitor.timer wholeflow-monitor-daily.timer`; after 5 minutes,
   admin app → Server health shows the first check.

**Phones and the Tally PC**
7. Install the new Owner app: sign out and in once, compare the dashboard with step 2, then check
   payments, a statement (and sharing), stock, sites, visits and staff. Then the Staff app.
8. Install Tally PC 0.6.0 (README "Updating a PC") and run a sync; the Cloud Sync page and the
   admin app should show it.

**Retire the old containers** (`scripts/retire-containers.sh`, each reversible with `start`)
9. `stop gotrue` once step 7 works (sign-in no longer uses them).
10. `stop postgrest` once every Tally PC runs 0.6.0.
11. `stop staff` once every phone has the new apps.
12. After a week without problems in Server health: `remove --yes`, then delete the
    `functions/v1` location from `nginx/wholeflow.conf` and reload nginx.

New businesses created after step 3 get no containers at all.

Tests: `go test ./...`; with the throwaway database from `db/tests/run_local.sh`,
`WF_TEST_PG=postgres://postgres:pw@127.0.0.1:55432/wf go test ./internal/appapi ./internal/authn`
(every endpoint, sign-in, the Tally PC client end to end). With `WF_WRITE_FIXTURES=1` the
integration test also saves each endpoint's real answer to `wholeflow_app/test/fixtures/api/`,
read by the app's `api_contract_test.dart` and `auth_contract_test.dart`. Regenerate them
whenever an answer changes.

## 6. Later

- **Web app** (Flutter web or a separate one) uses the same API and login.
- Customer statement **PDFs on the server** (needed by a web app); the phone
  keeps making them until then.
- Retire PostgREST for the phone apps once every feature has moved (the Tally
  PC still uses it).

### After the move (agreed 2026-10-08)

1. **Fewer containers per business.** Done (2026-10-08). Logins: The app API
   signs people in itself (`internal/authn`, endpoints at the same
   `/b/<slug>/auth/v1/…` in GoTrue's format, so the apps don't change), on
   GoTrue's own tables (`db/auth/auth_schema.sql`): existing logins, password
   hashes and sessions keep working. Refresh tokens are replaced on every use;
   reusing an old one ends the session. Wrong passwords lock an email for 15
   minutes after 10 tries (and an address after 60). Staff management and the
   admin app's owner creation and password reset use it too. The app's own
   login library is tested against the server's real answers
   (`test/unit/auth_contract_test.dart`). New businesses get the login tables
   and no containers (`scripts/new-business.sh`); existing ones are retired
   step by step with `scripts/retire-containers.sh` (section 5).
2. **Tally PC through the API.** Done (2026-10-08): `/api/v1/pc/…` endpoints
   (PC keys only: role service_role + device_id, still checked by
   `check_request()` for revocation and the subscription pause; every row must
   be for the business the key belongs to), and the PC's new client
   `internal/cloud/hosted` with the shared row format `internal/cloud/wire`.
   Purchase bills and their lines are written in one transaction. The PC no
   longer manages mobile logins. Tally PC 0.6.0 needs the API on the server;
   PostgREST can be stopped once every PC runs 0.6.0.
3. **Monitoring.** Done (2026-10-08), as a log on the server, with no alerts
   (your choice): `deploy/server/scripts/monitor.sh` runs every 5 minutes
   (`wholeflow-monitor.timer`). It checks the API (incl. control_db), the
   control service, every business through HTTPS, the database, the services,
   disk, memory, the certificate and the newest backup, and writes one line to
   `/var/log/wholeflow/monitor-YYYY-MM-DD.log`. `wholeflow-monitor-daily.timer`
   writes `daily-YYYY-MM-DD.log` at 23:50 with the day's problems and the
   services' warnings. Logs are kept 30 days. The admin app shows them under
   **Server health**. Install: copy `scripts/monitor.sh` and the four
   `systemd/wholeflow-monitor*` units, `systemctl daemon-reload`, then
   `systemctl enable --now wholeflow-monitor.timer wholeflow-monitor-daily.timer`.

## 7. Decisions (made 2026-10-08)

1. A separate `wholeflow-api` service, not inside the control service.
2. Staff service (Deno): fold into the API in step 6.
3. PDFs: stay on the phone for now.
4. First feature: payment insights.
5. Deploy once, after every feature has moved to the API (not phase by phase).
