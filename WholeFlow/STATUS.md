# WholeFlow – Application Status

_Status as of 6 October 2026 (section 9 adds the WholeFlow server connection). Companion to `README.md` (build/run), `docs/SYNC_SETUP.md`, `docs/SYNC_ARCHITECTURE.md` and `docs/DATABASE_SCHEMA.md`._

## 1. What the app is

WholeFlow is **one executable, `wholeflow.exe`**, that does two things in one process on the customer's Tally PC, entirely behind **a login** (a WholeFlow account checked by the control service; there is no local account; it is a tool for the developer/administrator only):

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
| Windows service install (`install`/`start`/`stop`) | **Verified live** on the development PC: service installed; after the 28 Sep 2026 boot (09:33) it started by itself at 09:35 and synced 9 s later without anyone opening the app. Implemented with `x/sys/windows/svc` + `mgr`; `install` now upgrades in place. |
| Background process (`run -background`, `start`/`stop` without the service) | Verified live: hidden process (no window handle), `status` reports `running as background`, `stop` ends it through `POST /api/sync/quit` (control token only, tested). |
| Logon autostart (`autostart`, Task Scheduler, no Administrator) | Verified by `TestLogonTaskLifecycle` (registers, inspects and removes a real task under a test name). |
| Supabase migration | Written, **not yet applied to a real project**; PostgREST client verified against a fake in tests |
| Version control | Still **not a git repository**; `.gitignore` covers `bin/`, `logs/`, `.env` |

### Feature completeness

| Area | State |
|---|---|
| Web app (dashboard, shops, detail + reconciliation, outstanding, exports, Tally Status) | Done, unchanged |
| Single executable and process for web app + sync; one port; single log | Done |
| Tally: detect process, port from `tally.ini`, connect, discover companies, select/disable companies | Done |
| Tally: voucher fetch with server-side `ALTERID` filter, voucher GUID list | Done, verified live |
| Login protecting the whole app (WholeFlow account checked by the control service at every sign-in; no local account and no offline login, both removed in 0.4.1; PBKDF2, lockout, CSRF header, HttpOnly/Strict cookie; first-run account step removed in 0.4.0) | Done |
| Owner/staff accounts | Created and managed from the Cloud Sync page (Supabase Auth admin API + `users` row): create, list, reset password, disable/enable. Staff permission enforcement remains future work (`permissions` jsonb + RLS). |
| Background sync: immediate + interval (60–86400 s, default 300), backoff 30 s / 60 s / 5 min, "Sync now" | Done |
| Tally offline / internet offline handling; last successful sync preserved; no deletions on outage | Done, tested |
| Multiple companies, independent failure, deterministic order | Done, tested |
| Idempotent upserts; no duplicate transactions | Done, tested |
| Incremental transactions (ALTERID cursor), soft deletes, daily reconcile for deleted vouchers | Done, tested |
| Cloud abstraction (`cloud.Provider`), Supabase isolated, memory provider (dry run) | Done |
| Sync state and sync logs in cloud + local `state.json` | Done |
| Windows service: install/uninstall/start/stop/restart/status, auto start, recovery actions, in-place upgrade | Done, run live |
| Hidden background mode (`run -background`), logon autostart without Administrator (`autostart`), graceful `stop` over the control API | Done |
| Client installer: `deploy\Install-WholeFlow.cmd` (self-elevating, copy + install/upgrade/uninstall) | Done, parse-checked; not yet run on a fresh client PC |
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
2. Other commands (`check`/`-check`, `status`, `sync`, `config`, `install`, `uninstall`, `start`, `stop`, `restart`, `version`) reuse the same wiring; `status`/`sync` talk to a running instance over localhost with the control token so only one process ever syncs.
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
2. **Run `deploy\Install-WholeFlow.cmd` once on a fresh client PC** end to end (the service itself is verified here; the script is only parse-checked).
3. **Open the Cloud Sync page in a browser once** to confirm rendering; the API behind it is tested.
4. **Initialise git** before further work.
5. **Staff permissions** exist only as a `permissions` column and read-only RLS.
6. **Web app persistence** remains in-memory; it could read the cloud tables later.
7. **Area derivation** remains heuristic and tuned to this business's ledger naming.
8. **Owner account creation against a real Supabase project** has not been run in this session (verified against a fake Auth API in tests); check the first real one in Supabase → Authentication → Users.

## 8. Production hardening (28 Sep 2026, version 0.3.0)

Three independent reviews (security; sync correctness; Tally parsing, API and frontend), then fixes, each with tests:

| Area | Change |
|---|---|
| **Tally is read-only, enforced** | `internal/tally/readonly.go` checks every request against an allow-list (Export of a Collection only, fixed element vocabulary, five read-only `$$` functions) before it is sent; anything else is `TALLY_WRITE_BLOCKED` and never leaves the process. The send function is private to the Tally package. Verified: every real request passes; imports, `TALLYMESSAGE`, `ACTION`, function definitions and unknown functions are blocked; a live full sync sent 14 requests, 0 blocked. |
| Data folder | Protected ACL on every start (SYSTEM, Administrators, the running account). Before, every local user could read `control.token` (admin API access) and decrypt the Supabase key, and could plant a `.env`. |
| Web app | Host-header check against DNS rebinding; read/idle timeouts; login lockout counts attempts before the password check and ignores username case; password change signs out other sessions and is rate limited; control token compared in constant time; the stored key is only sent to the project URL it was saved for. |
| Service install | Refuses an exe outside Program Files (LocalSystem would run a user-replaceable file); `-allow-any-location` for development. |
| Sync | Reconcile re-reads every voucher (gaps heal on schedule); a newly appeared shop forces a reconcile; safety check skips mass soft-deletes after a suspicious read (`SYNC_ALLOW_MASS_DELETE` to override); purchases wait when the supplier or item step failed (no lost links); id lists per request halved (URL length); paging follows the server's real page size; env interval clamped. |
| Tally client / API | Response size cap (512 MB); waiting for Tally's single request slot honours the request deadline; Tally errors in the shop/supplier membership check no longer show as "not found"; compound quantities reported instead of misread; page numbers overflow-safe; exact area filter for dashboard links. |
| Exports | CSV formula injection defused; whole numbers written as numbers in CSV and Excel. |
| Installer | Fixed: exit code was mixed with output (success looked like failure) and `status` output was swallowed. |

Known limits, accepted for now:

1. A full voucher sync is one Tally request (about 33 MB for the sample company; capped at 512 MB). A company roughly 15 times larger would need windowed fetching.
2. While Tally is offline the cloud `sync_state` records the error, but `tally_companies.sync_status` keeps its last value; the mobile app should read `sync_state`.
3. `deploy\Install-WholeFlow.cmd` is syntax-checked but has not yet been run end to end on a client PC.

## 9. Multi-business hosting, desktop part (6 Oct 2026, version 0.4.0)

Phase 4 of `docs/MULTI_TENANT_PLAN.md` (sections 5.3, 5.4) on the PC side. Not yet run against the live control service from a real PC (no activation code was issued for testing); covered by unit tests with fakes.

| Area | Change |
|---|---|
| Connect by reference key | Cloud Sync step 1 is now *reference key + activation code → Connect* (`POST /control/activate`, control service default `https://api.jitsuji.xyz`, override `CONTROL_URL` / `cloud.controlUrl`). Stores business id/name, base URL, PC id, plan limit and the **PC key** (DPAPI, like the service key); shows "Connected to <business>" and *Disconnect*. Provider `wholeflow` = the existing Supabase client against `<base_url>` with the PC key. The Supabase URL + service-key form remains under *Advanced* for PCs already set up that way (JMJ until cut-over). |
| Subscription pause | HTTP 402 → run status `paused`, state `SUBSCRIPTION_ENDED`, "Subscription ended — sync paused" in the header pill, Cloud Sync page and `status`; logged once, no backoff, nothing deleted, resumes by itself. |
| PC revoked | HTTP 403 `device_revoked` (or heartbeat `revoked`) → sync stops, saved in config, "This PC's access was revoked. Connect again with a new activation code." |
| Heartbeat | `POST /control/heartbeat` with the app version at start and after runs (≤ every 5 min, also while sync is off); updates `max_companies` and subscription state; 402 → `ended`. |
| Company limit | Ticking more than `max_companies` is refused ("Your plan allows N companies. Ask WholeFlow support to upgrade."); if a downgrade leaves too many ticked, each run syncs the first N and warns (`OVER_PLAN_LIMIT`). Legacy connection: no limit. |
| Login | Email + password checked with `POST /control/pc/login`; nothing is stored on the PC and there is no offline login (0.4.1); logins stored by older versions are deleted at start. First-run "create an admin account" step removed (`/api/sync/setup` gone). No local account (`set-password` removed in 0.4.1). Lockout, CSRF header and cookies unchanged. The sync no longer requires a local password to be configured. |
| Owner/staff accounts | Unchanged code; verified by test that PostgREST and the Auth admin API are reached under a path-prefixed base URL (`…/b/demo/rest/v1`, `…/b/demo/auth/v1/admin/users`) with the PC key. |

Open points: `windows_user` sent at activation is the account the app runs as (LocalSystem for the service), not the person at the PC; `deploy\Install-WholeFlow.*` texts may still mention creating the admin account in the browser (not changed here).

