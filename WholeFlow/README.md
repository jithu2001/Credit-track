# WholeFlow — Shop Outstanding (TallyPrime) with Cloud Sync

One executable, `wholeflow.exe`, one process, one port, one login:

- **Web app** (http://127.0.0.1:8080): dashboard, shop list, shop detail with reconciled transaction summary, outstanding report, CSV/Excel export — read live from a running TallyPrime.
- **Cloud Sync** (the app's *Cloud Sync* page): select which Tally companies to synchronise, configure Supabase, run and monitor the **background sync** that upserts shops, balances and transactions into the cloud every few minutes for the future owner/staff mobile app.
- **Admin login for everything.** The app is for the developer/administrator only: every page and every API call requires the single admin account. On the first run the browser asks you to create it (default username `admin`; there is no default password); `set-password` resets it from the console. The business owner and staff never use this app; they will use the mobile app against the cloud.
- Installable as the Windows service **WholeFlow**, so both start at boot without anyone logging in.

**Nothing is ever written to Tally**, and Tally's data files are never touched. The only third-party dependency is `golang.org/x/sys` (Windows service and DPAPI).

```
TallyPrime  ──HTTP/XML──▶  wholeflow.exe (this PC: web app + sync)  ──HTTPS──▶  Supabase  ──▶  Mobile app (owner / staff)
```

## Build

```powershell
go build -o bin\wholeflow.exe ./cmd/server
```

Tests (Windows Application Control on this PC blocks test binaries in `%TEMP%`, so point Go's temp dir inside the project):

```powershell
$env:GOTMPDIR = "F:\WholeFlow\bin\gotmp"; New-Item -ItemType Directory -Force $env:GOTMPDIR | Out-Null
go test ./...
```

## Run

```powershell
.\bin\wholeflow.exe                  # foreground: web app + sync at http://127.0.0.1:8080  (Ctrl+C to stop)
.\bin\wholeflow.exe check            # Tally + cloud connection test, prints status and exits  (also -check)
.\bin\wholeflow.exe set-password     # reset the admin account (first-time creation happens in the browser)
.\bin\wholeflow.exe install          # Windows service "WholeFlow", automatic start (Administrator)
.\bin\wholeflow.exe status | sync | config | stop | start | restart | uninstall
```

Cloud sync in one minute: run the app → open http://127.0.0.1:8080, create the admin account → Cloud Sync → business id, Supabase URL + service-role key, discover & tick companies, Save, Sync now, enable background sync, Save → `install`.

Data lives in `%ProgramData%\WholeFlow` (`config.json` with the key DPAPI-encrypted, `state.json`, `logs\app.log`).
Environment variables / `.env` override the file (see `.env.example`). `CLOUD_PROVIDER=memory` is a dry run.

Documentation:

- [docs/SYNC_SETUP.md](docs/SYNC_SETUP.md) — developer setup runbook and Windows service installation
- [docs/SYNC_ARCHITECTURE.md](docs/SYNC_ARCHITECTURE.md) — how a run works, incremental sync by Tally `ALTERID`, retry/backoff, offline rules, security model
- [docs/DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) — Supabase tables, RLS for owner/staff, example queries
- [supabase/migrations/0001_init.sql](supabase/migrations/0001_init.sql) — the schema
- [STATUS.md](STATUS.md) — current project status

---

# Web app reference

## TallyPrime setup

1. TallyPrime running with the company open.
2. Help (F1) > Settings > Connectivity > Client/Server configuration:
   *TallyPrime acts as* = **Server** (or Both), note the **Port**.
3. The app reads the port from `tally.ini` (`ServerPort=`) automatically; set
   `TALLY_PORT` in `.env` to override (see `.env.example`). The Tally Status page
   shows where the port came from and warns if they disagree.

## How the data is interpreted (verified on the sample company)

| Item | Source in Tally |
|---|---|
| Shops | Ledgers under **Sundry Debtors** incl. sub-groups (`SHOP_GROUPS`). The status page's "Inspect ledger groups" shows the group breakdown for a new company. |
| Current balance | Ledger `ClosingBalance`. Tally sign: negative = **Dr** (shop owes us), positive = **Cr** (advance / we owe). |
| Opening balance | Ledger `OpeningBalance` (at the start of the books). |
| Phone | `Ledger Phone/Mobile`; if empty, extracted from address lines like `PH 98xxxxxxxx` (marked "found in address"). |
| GSTIN / address / state / pincode | Legacy ledger fields, falling back to the newer date-wise GST/mailing details. |
| Area | **Not a Tally field** – derived from the town at the end of the ledger name (`PRINCE TYRES -- RAJAKKAD` → Rajakkad). Abbreviations such as `KPLY` stay as-is. |
| Transaction summary | All vouchers touching the ledger, grouped by base voucher type: Sales, Receipt, Credit Note (returns), everything else (adjustments). Optional/cancelled/post-dated vouchers are excluded. Every summary is **reconciled**: opening + movement must equal Tally's closing balance, otherwise the page warns. |

Sample company check: 323 shops, 153 with dues totalling ₹35,95,244.95 Dr,
27 in credit (₹1,76,499.68 Cr), net ₹34,18,745.27 Dr — identical to Tally's own
ledger totals; 13 sampled shops reconciled to the paisa.

## Data refresh

The shop list is pulled from Tally on first use and kept in memory; **Refresh from
Tally** re-pulls it (the "as of" time is always shown). The shop detail page and
its transactions are always read live. No local database yet.

## API

| | |
|---|---|
| `GET /api/tally/status` | connection, port source, hints, open companies |
| `GET /api/companies` | companies open in Tally (name, GUID, FY, books from, current period) |
| `POST /api/tally/refresh?company=` | re-pull shops from Tally |
| `GET /api/customers?company=&q=&field=all\|name\|phone\|area&type=dr\|cr\|zero&sort=name_asc\|name_desc\|balance_desc\|balance_asc\|area_asc&page=&pageSize=` | |
| `GET /api/customers/balances` | `[{id, customer, balance, balanceType}]` |
| `GET /api/customers/{id}` | one shop, live (id = Tally GUID) |
| `GET /api/customers/{id}/transactions` | summary + reconciliation |
| `GET /api/dashboard` · `GET /api/reports/outstanding` · `GET /api/ledgers` | |
| `GET /api/export/{customers\|outstanding}?format=csv\|xlsx` | same filters as the lists |

`company` may be omitted when exactly one company is open. Errors are
`{"error":{"code","message","details"}}` with codes `TALLY_UNREACHABLE` (503),
`TALLY_TIMEOUT` (504), `TALLY_ERROR` / `TALLY_INVALID_RESPONSE` (502),
`NO_COMPANY_SELECTED` (400), `COMPANY_NOT_FOUND` (409), `NOT_FOUND` (404).

## Logs

`logs/app.log`: every Tally request (time, request type, endpoint, HTTP status,
bytes, duration) and every error. Responses that fail to parse are saved to
`logs/raw-errors/`; with `TALLY_DEBUG_RAW=true` all responses go to `logs/raw/`.
These files contain accounting data – keep them local.

## Layout

```
cmd/server             the executable: web app + sync API + scheduler, CLI commands, Windows service wrapper
internal/config        .env + tally.ini port detection (shared)
internal/tally         TallyService: XML/TDL requests, parsing, balances, transactions, vouchers (ONLY place that knows Tally XML)
internal/api           web app REST API, snapshot, filters, exports
internal/export        CSV and .xlsx writers
internal/cloud         provider-neutral cloud contract + models;  cloud/supabase (PostgREST), cloud/memory (tests, dry run)
internal/syncer        settings, local state, transformer, engine, backoff, scheduler
internal/auth          admin login: PBKDF2 hashes, sessions, lockout
internal/secrets       DPAPI encryption of the service-role key
internal/admin         admin login (protects the whole app) + Cloud Sync API (/api/sync/*)
internal/logging       rotating structured log
supabase/migrations    SQL schema with Row Level Security
docs/                  setup, architecture, schema
web/static             frontend incl. the Cloud Sync page (embedded into the exe)
```

## Moving to the customer's TallyPrime Silver

Copy `bin\wholeflow.exe` (and optionally `.env`) to the customer PC, enable
Server mode in TallyPrime, run `wholeflow.exe -check`. Then open Tally Status →
Inspect ledger groups to confirm shops are under Sundry Debtors (adjust
`SHOP_GROUPS` if not). Note: a company with many years of vouchers will make the
shop *transaction summary* slower (it scans from the start of the books; about
2.7 s for ~5,900 vouchers here); raise `TALLY_TIMEOUT_SECONDS` if needed.
