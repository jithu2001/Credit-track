# WholeFlow app API plan (moving the apps' work to the server)

Status (2026-10-08), branch `api-layer`: phase 1 built and tested locally, not
deployed yet. That covers the `wholeflow-api` service and payment insights (`GET /payments`,
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

## 5. Deploying phase 1

```bash
cd WholeFlow
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o wholeflow-api ./cmd/api
scp wholeflow-api wholeflow:/opt/wholeflow/bin/
scp deploy/server/systemd/wholeflow-api.service wholeflow:/etc/systemd/system/
# on the server (prints no secret):
cd /opt/wholeflow && grep -E '^(CONTROL_DB_URL|MASTER_KEY)=' control.env > api.env \
  && printf 'KIT_DIR=/opt/wholeflow\nPG_HOST=127.0.0.1:5432\nLISTEN=127.0.0.1:8300\n' >> api.env && chmod 600 api.env
cp nginx/wholeflow.conf nginx/wholeflow.conf.prev   # before copying the new one over
systemctl daemon-reload && systemctl enable --now wholeflow-api
nginx -t && systemctl reload nginx
scp deploy/server/nginx/wholeflow.conf wholeflow:/opt/wholeflow/nginx/wholeflow.conf   # then nginx -t && reload
curl -s https://api.<domain>/b/<slug>/api/v1/payments   # → 401 UNAUTHENTICATED
```

The business database is first reached on the first signed-in request, so a
wrong setting shows up then as a 500. `journalctl -u wholeflow-api -n 20` shows why.

Deploy the server **before** installing the new app: the new app's payment
insights need it. Old app versions keep working (PostgREST is unchanged).

Tests: `go test ./internal/appapi` (FIFO cases); with the throwaway database
from `db/tests/run_local.sh`, `WF_TEST_PG=postgres://postgres:pw@127.0.0.1:55432/wf
go test ./internal/appapi` also runs the endpoints against every migration
(numbers, owner only, other business, paused business → 402, bad tokens).

## 6. Later

- **Web app** (Flutter web or a separate one) uses the same API and login.
- Customer statement **PDFs on the server** (needed by a web app); the phone
  keeps making them until then.
- Retire PostgREST for the phone apps once every feature has moved (the Tally
  PC still uses it).

### After the move (agreed 2026-10-08)

1. **Fewer containers per business.** Today each business runs its own GoTrue
   and PostgREST containers (~128 MB each), so 30–40 businesses would fill
   the 8 GB server. Once the phones use only the app API, the API (or one
   shared login service) handles logins for every business. Each business
   keeps only its own database, so adding a business costs almost no memory.
2. **Tally PC through the API.** Move the PC's uploads from PostgREST to app
   API endpoints (same PC keys and revocation), so PostgREST can be retired.
3. **Monitoring before going live.** A health check on the API (and the
   control service) with an alert when it is down or returns errors, and a
   short daily error summary from `journalctl`.

## 7. Decisions (made 2026-10-08)

1. A separate `wholeflow-api` service, not inside the control service.
2. Staff service (Deno): fold into the API in step 6.
3. PDFs: stay on the phone for now.
4. First feature: payment insights.
5. Deploy once, after every feature has moved to the API (not phase by phase).
