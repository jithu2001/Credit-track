# WholeFlow – Application Status

_Status as of 27 September 2026. Companion to `README.md` (build/run), `docs/SYNC_SETUP.md`, `docs/SYNC_ARCHITECTURE.md` and `docs/DATABASE_SCHEMA.md`._

## 1. What the app is

WholeFlow is **one executable, `wholeflow.exe`**, that does two things in one process on the customer's Tally PC, entirely behind **one admin login** (default username `admin`; it is a tool for the developer/administrator only):

- **Shop Outstanding web app** (http://127.0.0.1:8080): dashboard, searchable shop list, per-shop detail with a reconciled transaction summary, outstanding report and CSV/Excel export, read live from TallyPrime. Unchanged in scope.
- **Cloud Sync** (the app's *Cloud Sync* page): choose which Tally companies to synchronise, configure Supabase, run and monitor a **background sync** that upserts shops, balances and transactions into the cloud every few minutes for a future owner/staff mobile app.

It installs as the Windows service **WholeFlow**, so both start at boot without anyone logging in.

```
TallyPrime ──HTTP/XML──▶ wholeflow.exe (web app + sync, customer PC) ──HTTPS──▶ Supabase (PostgreSQL + RLS) ──▶ mobile app (later)
```

Principles that hold throughout: nothing is ever written to Tally; Tally is never exposed to the internet; `internal/tally` is the only package that knows Tally XML/TDL; all cloud writes are idempotent upserts keyed by Tally GUIDs; nothing in the cloud is deleted because Tally happens to be offline.

## 2. Current status

| Check | Result |
|---|---|
| `go build ./...`, `go vet ./...`, `gofmt -l .` | Clean (Go 1.27.1 toolchain, module `go 1.26`) |
| `go test ./...` | **PASS** – `tally`, `syncer`, `admin`, `auth`, `secrets`, `cloud/supabase` (memory provider exercised through `syncer`) |
| Dependencies | `golang.org/x/sys v0.48.0` only (Windows service control, DPAPI, console echo-off) |
| Live check, merged app, against TallyPrime 6 | Web API and `/api/sync/*` on one port; CLI `sync` through the running app: full sync 323 shops, 4,321 transactions from 5,909 vouchers, 14.2 s; earlier second run incremental with 0 vouchers fetched in 2.4 s; header summary reports `SYNCED` with the last success time |
| Admin API tests | Whole app locked without a session (dashboards, exports, sync), login, lockout, cookie flags, CSRF header on all mutations, key never echoed, CLI control token |
| Windows service install (`install`/`start`/`stop`) | **Not exercised live** (this session's console is not elevated). Implemented with `x/sys/windows/svc` + `mgr`; `status` from a non-elevated console verified. |
| Supabase migration | Written, **not yet applied to a real project**; PostgREST client verified against a fake in tests |
| Version control | Still **not a git repository**; `.gitignore` covers `bin/`, `logs/`, `.env` |

### Feature completeness

| Area | State |
|---|---|
| Web app (dashboard, shops, detail + reconciliation, outstanding, exports, Tally Status) | Done, unchanged |
| Single executable and process for web app + sync; one port; single log | Done |
| Tally: detect process, port from `tally.ini`, connect, discover companies, select/disable companies | Done |
| Tally: voucher fetch with server-side `ALTERID` filter, voucher GUID list | Done, verified live |
| Admin login protecting the whole app (first-run account creation in the browser, PBKDF2, no default, `set-password` reset, lockout, CSRF header, HttpOnly/Strict cookie) | Done |
| Owner/staff accounts | Created and managed from the Cloud Sync page (Supabase Auth admin API + `users` row): create, list, reset password, disable/enable. Staff permission enforcement remains future work (`permissions` jsonb + RLS). |
| Background sync: immediate + interval (60–86400 s, default 300), backoff 30 s / 60 s / 5 min, "Sync now" | Done |
| Tally offline / internet offline handling; last successful sync preserved; no deletions on outage | Done, tested |
| Multiple companies, independent failure, deterministic order | Done, tested |
| Idempotent upserts; no duplicate transactions | Done, tested |
| Incremental transactions (ALTERID cursor), soft deletes, daily reconcile for deleted vouchers | Done, tested |
| Cloud abstraction (`cloud.Provider`), Supabase isolated, memory provider (dry run) | Done |
| Sync state and sync logs in cloud + local `state.json` | Done |
| Windows service: install/uninstall/start/stop/restart/status, auto start, recovery actions | Implemented, not run live |
| Cloud Sync page: 5-step flow, per-company status, last run table, log tail, password change; header "Cloud sync" pill on every page | Done |
| Structured rotating log, secrets redacted | Done |
| Local database for the web app | Not started (in-memory snapshots) |
| Mobile app, owner dashboard, notifications | Out of scope, not started |

## 3. Technology stack

| Layer | Technology |
|---|---|
| Language / runtime | Go 1.26 module, built with 1.27.1, Windows target |
| HTTP | `net/http` `ServeMux` (Go 1.22 patterns); web app API, `/api/sync/*` and embedded static files on `APP_ADDR` (default 127.0.0.1:8080) |
| Tally transport | `net/http` POST of TDL collection envelopes; one mutex (Tally handles one request at a time); sanitiser for Tally's illegal XML |
| Cloud transport | Supabase PostgREST over HTTPS with the service-role key: upserts (`resolution=merge-duplicates`), `Range` paging, `PATCH … id=in.(…)` soft deletes; standard library only |
| Persistence on the PC | `%ProgramData%\WholeFlow\config.json` (settings, DPAPI-encrypted key, password hash), `state.json` (per-company cursor/status), atomic writes |
| Secrets | Windows DPAPI, machine scope; `plain:` fallback elsewhere, clearly labelled |
| Auth (developer) | PBKDF2-SHA256 600k iterations, in-memory sessions, per-user lockout |
| Windows service | `golang.org/x/sys/windows/svc` + `mgr`: delayed auto-start, restart on failure |
| Logging | `log/slog` text to `logs\app.log`, rotated at 20 MB × 5 |
| Frontend | Vanilla JS/CSS single page, embedded via `embed.FS`; routes `#/dashboard #/shops #/outstanding #/status #/sync` |
| Database | PostgreSQL (Supabase) with RLS; 8 tables, 2 `security_invoker` views |
| Tests | `testing` + `httptest` fakes for TallyPrime and PostgREST; in-memory cloud provider |

## 4. How it runs

1. `wholeflow.exe` (no arguments, or `run`) loads `.env` from the working directory, the exe directory and the data directory, reads `config.json`/`state.json`, opens the log, builds one `tally.Service`, registers the login/sync API and the web app API (wrapped in the login check) and the static files on one mux, writes `control.token`, starts the HTTP server and the sync scheduler. The browser shows a login screen first; after login the dashboards and the Cloud Sync page share the session. Ctrl+C or a service stop shuts both down.
2. Other commands (`check`/`-check`, `status`, `sync`, `config`, `set-password`, `install`, `uninstall`, `start`, `stop`, `restart`, `version`) reuse the same wiring; `status`/`sync` talk to a running instance over localhost with the control token so only one process ever syncs.
3. A sync run: authenticate to the cloud → list open Tally companies → connection row → per selected company: company row, full shop snapshot with diff-based soft deletes, vouchers with `ALTERID > cursor` (full first time; light GUID list every 24 h for deletions) → sync state, sync log, local state. Details in `docs/SYNC_ARCHITECTURE.md`.

## 5. Verified facts about TallyPrime 6 (worth keeping)

- Vouchers, ledgers and companies expose stable `GUID`s; vouchers and ledgers expose `ALTERID` and `MASTERID`.
- A `<FILTER>` with `$AlterID > N` on a Voucher collection is applied server-side (845 of 5,909 vouchers, 1 MB instead of 33 MB). A `Number`-typed TDL variable did not work; the constant is inlined.
- `SVFROMDATE`/`SVTODATE` are ignored by Voucher collection exports.
- A full voucher export with ledger entries is ~33 MB and ~11 s for this company; the GUID-only list is ~7 MB.

## 6. Code layout

| Path | Role |
|---|---|
| `cmd/server` | The executable: CLI, service wrapper, wiring of web app + sync |
| `internal/tally` | Tally XML/TDL, parsing, error kinds; `vouchers.go` added |
| `internal/api`, `internal/export`, `web/static` | Web app API, exports, frontend (incl. Cloud Sync page) |
| `internal/cloud` (+ `supabase`, `memory`) | Provider contract, Supabase implementation, in-memory implementation |
| `internal/syncer` | Settings, state, transformer, engine, backoff, scheduler, provider factory |
| `internal/admin` | Admin login wrapping every `/api/*` route; `/api/sync/*`: settings, tests, run, logs, summary |
| `internal/auth`, `internal/secrets`, `internal/logging`, `internal/config` | Developer auth, DPAPI, rotating log, env/tally.ini config |
| `supabase/migrations/0001_init.sql` | Schema + RLS |
| `docs/` | Setup runbook, architecture, schema |

Roughly 8,000 lines of Go (including ~1,700 of tests), 800 lines of frontend, 330 lines of SQL. The Cloud Sync page's JavaScript was exercised through its API in this session, not rendered in a browser.

## 7. Known gaps and next steps

1. **Apply the migration to the real Supabase project and run one sync with `CLOUD_PROVIDER=supabase`**, watching the log on the Cloud Sync page.
2. **Install the Windows service from an elevated console** (`install`, reboot, `status`). Not yet exercised.
3. **Open the Cloud Sync page in a browser once** to confirm rendering; the API behind it is tested.
4. **Initialise git** before further work.
5. **Staff permissions** exist only as a `permissions` column and read-only RLS.
6. **Web app persistence** remains in-memory; it could read the cloud tables later.
7. **Area derivation** remains heuristic and tuned to this business's ledger naming.
8. **Owner account creation against a real Supabase project** has not been run in this session (verified against a fake Auth API in tests); check the first real one in Supabase → Authentication → Users.
