# Sync Architecture

How the WholeFlow Tally Sync Service moves data from TallyPrime to the cloud, and why it is built the way it is.

```
                         CUSTOMER WINDOWS PC
┌──────────────────────────────────────────────────────────────────────┐
│  TallyPrime Silver  ──HTTP/XML (localhost:9000)──▶  wholeflow.exe    │
│                                                     ┌──────────────┐ │
│   internal/tally  (only place that knows Tally XML) │ Web app :8080│ │
│   internal/api    (dashboard / shops / exports)     │ Cloud Sync   │ │
│   internal/syncer (engine, state, transformer)      │   page+API   │ │
│   internal/cloud  (provider-neutral contract)       │ Scheduler    │ │
│   internal/cloud/supabase  (PostgREST client)       │ Engine       │ │
│   %ProgramData%\WholeFlow  config.json state.json   └──────┬───────┘ │
└────────────────────────────────────────────────────────────┼─────────┘
                                                      HTTPS  │ service-role key
                                                             ▼
                                                   Supabase (PostgreSQL + RLS)
                                                             │
                                                      HTTPS  │ Supabase Auth (owner / staff)
                                                             ▼
                                                        Mobile app (future)
```

The mobile app never talks to Tally and Tally is never exposed to the internet. The only path is Tally → local sync service → cloud → mobile app.

## Packages

| Package | Responsibility | Knows about |
|---|---|---|
| `internal/tally` | TallyPrime HTTP/XML transport, TDL requests, parsing, error classification. Unchanged from the web app, plus `GetVouchers` / `GetVoucherIDs` and `AlterID` fields. | Tally only |
| `internal/cloud` | `Provider` interface and plain Go models (`Company`, `Shop`, `Transaction`, `SyncState`, `SyncLog`) and cloud error kinds. | Nothing else |
| `internal/cloud/supabase` | `Provider` implementation over Supabase's PostgREST API (standard library HTTP). Upserts, paging, soft deletes, error mapping. | Supabase only |
| `internal/cloud/memory` | In-process `Provider` used by tests and the `memory` dry-run mode. Reference for upsert/soft-delete semantics. | Nothing |
| `internal/syncer` | Settings (config.json), local state (state.json), transformer, engine (one run), backoff, scheduler (background loop), provider factory. | `tally` types and `cloud` interface |
| `internal/auth` | Developer password hashing (PBKDF2-SHA256), sessions, login throttling. | Nothing |
| `internal/secrets` | Encrypts the service-role key at rest (Windows DPAPI, machine scope). | OS |
| `internal/admin` | Admin login (wraps the whole app) and the Cloud Sync API at `/api/sync/*`. | `syncer`, `tally`, `auth` |
| `internal/api`, `web/` | The existing web app API and frontend; the frontend now includes the Cloud Sync page. | `tally` |
| `internal/logging` | Size-rotated structured log file. | Nothing |
| `cmd/server` | The single executable: CLI, Windows service wrapper, process wiring of web app + sync. | Everything |

The engine imports `cloud` but never `cloud/supabase`; the only place Supabase is named is the provider factory in `syncer/provider.go`. Adding a backend means implementing `cloud.Provider` in a new sub-package and adding one case to that factory.

## One synchronisation run

`Engine.Run` performs the steps below and never returns an error: every failure ends up in the `RunResult`, the local state file and the cloud `sync_state` row.

1. **Settings snapshot.** If nothing is configured (no password, business, cloud key or selected company) the run is `skipped`.
2. **Cloud authenticate.** `Provider.Authenticate` proves the key works and the business row exists. Failure: every selected company is marked `AUTH_ERROR` / `CLOUD_OFFLINE`; Tally is not touched.
3. **Tally company list.** Failure: every selected company is marked `TALLY_OFFLINE`; the cloud `sync_state` row (entity `company`) records the error but keeps `last_successful_sync_at`; no data rows change; no `sync_logs` row is written (an overnight outage must not produce hundreds of log rows).
4. **Connection row.** `tally_connections` is upserted with hostname, host/port, version and `last_seen_at`.
5. **For each selected company, independently**, in configuration order:
   1. Not open in Tally → `COMPANY_NOT_OPEN`, recorded, continue with the next company.
   2. `tally_companies` upsert with status `SYNCING`.
   3. **Shops**: `GetCustomers` (ledgers under `SHOP_GROUPS`), transform, list existing active cloud shops, upsert all, soft-delete shops Tally no longer lists. Created/updated counts come from the diff against the existing list.
   4. **Transactions** (if enabled), see below.
   5. `tally_companies` upsert with status `SYNCED` and `last_sync_at`, `sync_state` rows, one `sync_logs` row, local state (cursor, counts, timestamps).
6. Run status: `success` if every company synced, `partial` if some did, `failed` if none did.

A company is only marked `SYNCED` when every step succeeded. If transactions fail after shops were written, the company shows the error, the voucher cursor does not advance, and the next run redoes the transaction step; because everything is an upsert keyed by Tally identifiers, redoing is harmless.

## Identity and idempotency

The local cursors (`state.json`) belong to one cloud company row. When a run gets a different cloud id for a company than the one it last wrote to (another business id, a switched provider, or cloud data that was wiped), the transaction and purchase cursors are reset and the company gets a full sync, instead of receiving only changes made from then on.

| Entity | Cloud key | Tally source |
|---|---|---|
| Company | `(business_id, tally_company_id)` | Company GUID |
| Shop | `(company_id, tally_ledger_id)` | Ledger GUID |
| Transaction | `(company_id, tally_voucher_id, tally_ledger_id)` | Voucher GUID + shop ledger GUID (a journal touching two shops yields two rows) |
| Sync state | `(company_id, entity_type)` | — |

All writes are PostgREST upserts with `resolution=merge-duplicates` on those keys, so `sync(); sync(); sync()` leaves the row counts unchanged (`TestIdempotentRepeatedSync`, and verified live: second run fetched 0 vouchers, updated 323 shops, created nothing).

## Incremental transactions

Tally exposes no reliable `updated_at`, but every master and voucher carries an **`ALTERID`**: a company-wide counter that is assigned anew whenever the object is created or altered. Verified live on TallyPrime 6 (Sep 2026):

- A `<FILTER>` of `$AlterID > N` on a Voucher collection is applied server-side. Fetching everything above a cursor of 60,000 returned 845 of 5,909 vouchers in 1 MB instead of 33 MB.
- `SVFROMDATE`/`SVTODATE` are **not** honoured by a Voucher collection export, so date windows cannot be used for this; ALTERID is the cursor.

Modes per company:

| Mode | When | Tally reads | Deletions found |
|---|---|---|---|
| `full` | cursor = 0 (first sync, or state.json lost) | all vouchers | everything not in the snapshot |
| `incremental` | normal | vouchers with `AlterID > cursor` | entries of touched vouchers that no longer hit a shop |
| `reconcile` | every `fullReconcileHours` (default 24) | incremental fetch + a light list of every voucher GUID (~7 MB, no entries) | vouchers Tally no longer lists |

The cursor is the highest ALTERID seen in a run and is persisted locally (`state.json`) and in the cloud (`sync_state.last_cursor`) only after the transaction step succeeded.

Excluded vouchers (optional, cancelled, post-dated) are not stored, matching how Tally itself leaves them out of balances; if one was stored earlier it is soft-deleted the next time it is touched.

Shops are always a full snapshot: 323 ledgers is ~640 KB and 140 ms, not worth an incremental path, and it makes shop deletions trivial.

## Never deleting because Tally is offline

Deletions (always soft: `deleted_at`) happen only inside a company step that successfully read the relevant data from Tally. A refused connection, a timeout, a malformed response or a closed company all abort the step before any diff is computed. `TestTallyUnavailableKeepsCloudData` asserts that a run during an outage leaves every cloud count unchanged and keeps the last successful sync time and cursor.

## Scheduling and retry

`Scheduler.Run` loops forever:

- Runs immediately at start, then waits `SYNC_INTERVAL_SECONDS` (default 300).
- After a failed or partial run it waits 30 s, then 60 s, then 5 min (never longer than the normal interval), and returns to the normal interval after the next success.
- `TriggerNow` (UI "Sync now", CLI `sync`) wakes it early and also works while background sync is disabled, which is how the initial sync is run before enabling automation.
- While disabled it idles, polling settings every 5 s.

`Engine.Run` holds a mutex, so a manual run and a scheduled run never overlap. The engine builds the provider from the current settings on every run, so configuration changes in the UI take effect at the next run.

## Local state and offline behaviour

`%ProgramData%\WholeFlow\state.json` holds per-company status, timestamps, counts and the voucher cursor, written atomically (temp file + rename). Losing or corrupting it is safe: the company falls back to a full sync. Internet loss produces `CLOUD_OFFLINE` runs with backoff; Tally loss produces `TALLY_OFFLINE`; both preserve the last successful state and resume automatically.

## Status vocabulary

Company / service states: `PENDING`, `SYNCING`, `SYNCED`, `TALLY_OFFLINE`, `CLOUD_OFFLINE`, `AUTH_ERROR`, `SYNC_ERROR`, `COMPANY_NOT_OPEN`, `DISABLED`; service-level additions `NOT_CONFIGURED`, `CONNECTED` (configured, no run yet).

Error codes are the existing Tally kinds (`TALLY_UNREACHABLE`, `TALLY_TIMEOUT`, `TALLY_ERROR`, `TALLY_HTTP_ERROR`, `TALLY_INVALID_RESPONSE`, `NO_COMPANY_SELECTED`, `COMPANY_NOT_FOUND`, `NOT_FOUND`) plus cloud kinds (`CLOUD_UNREACHABLE`, `CLOUD_TIMEOUT`, `CLOUD_AUTH_ERROR`, `CLOUD_NOT_FOUND`, `CLOUD_ERROR`, `CLOUD_NOT_CONFIGURED`). The mapping to states is in `syncer.statusFor`.

## Security model

- **Admin account protects the whole app**: every `/api/*` endpoint (dashboards, exports, sync configuration) requires a session; only `POST /api/sync/login`, `GET /api/sync/session` and `POST /api/sync/setup` (first-run account creation, refused with 409 once an account exists) are open. Username + PBKDF2 hash live in config.json; created in the browser on first run or with `set-password`; default username `admin`, no default password; 8 failures lock the account for 5 minutes; sessions are in memory with a 12 h sliding expiry; cookies are `HttpOnly` + `SameSite=Strict`; every non-GET request needs an `X-Requested-With` header (CSRF). The CLI authenticates with a random per-process token in `control.token`. `APP_ADDR` defaults to 127.0.0.1, so the app is not reachable from the LAN unless deliberately changed.
- **Owner / staff** live in Supabase Auth and `public.users`; RLS restricts them to their `business_id`. The sync service never creates or touches these accounts.
- **Service-role key** is stored DPAPI-encrypted in machine scope so the service (LocalSystem) and the developer console can both read it; it is redacted from error messages and never logged, returned by the API, or accepted from a non-localhost request.
- Logs contain identifiers, counts and error text, never credentials. Raw Tally XML is only written to disk when `TALLY_DEBUG_RAW=true` (development).

## Measured on the sample company (TallyPrime 6, Sep 2026)

| Operation | Size | Time |
|---|---|---|
| Shops (323 ledgers, all fields) | 640 KB | 0.14 s |
| Full voucher fetch (5,909 vouchers with ledger entries) | 33 MB | 11.4 s |
| Incremental fetch, nothing changed | 1.5 KB | < 0.1 s |
| Voucher GUID list for reconcile | 7 MB | ~3 s |
| First full run end to end (memory provider) | — | 12.9 s |

The default Tally timeout is therefore 180 s. The web app and the sync share one `tally.Service` and its request mutex, so a dashboard request during a full voucher fetch waits for it; after the first sync, incremental fetches take well under a second.
