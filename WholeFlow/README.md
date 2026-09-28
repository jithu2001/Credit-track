# WholeFlow — Shop Outstanding (TallyPrime) with Cloud Sync

One executable, `wholeflow.exe`, one process, one port, one login:

- **Web app** (http://127.0.0.1:8080): dashboard, shop list, shop detail with reconciled transaction summary, outstanding report, suppliers (payables), purchase register with item lines, inventory with purchase history per item, CSV/Excel export — read live from a running TallyPrime. Suppliers, purchases (with item lines) and inventory are also synced to the cloud (migration `0003_purchasing.sql`).
- **Cloud Sync** (the app's *Cloud Sync* page): select which Tally companies to synchronise, configure Supabase, run and monitor the **background sync** that upserts shops, balances and transactions into the cloud every few minutes for the future owner/staff mobile app.
- **Admin login for everything.** The app is for the developer/administrator only: every page and every API call requires the single admin account. On the first run the browser asks you to create it (default username `admin`; there is no default password); `set-password` resets it from the console. The business owner and staff never use this app; they will use the mobile app against the cloud.
- **Runs unattended in the background.** Installed as the Windows service **WholeFlow** it starts at every boot, before anyone logs in, with no window. Where Administrator rights are not available, `autostart` starts it hidden at every logon instead. Nobody has to open anything for the sync to run. See [Deploying on a client PC](#deploying-on-a-client-pc).

**Nothing is ever written to Tally**, and Tally's data files are never touched. This is enforced in code, not just by convention:

- The app talks to Tally only over Tally's HTTP/XML port, through one private function in `internal/tally/client.go`. No other code can send anything to Tally, and the app never opens Tally's data folder.
- Before any request leaves the app, `internal/tally/readonly.go` checks it against an allow-list. The header must say `TALLYREQUEST=Export`, `TYPE=Collection`. Only collection-definition elements may appear, and formulas may call only five read-only functions. Anything else is refused with `TALLY_WRITE_BLOCKED`, logged, and never sent. That covers imports, `TALLYMESSAGE` data, `ACTION`s, report or function definitions and unknown `$$` functions.
- Names typed by users or read from Tally (company, ledger, item) only ever travel as escaped text, so they cannot turn into Tally commands. A name containing `$$` is refused rather than sent.
- Tests (`internal/tally/readonly_test.go`) run every real request through the check and prove that write-shaped requests are blocked before they reach the port.

The only third-party dependency is `golang.org/x/sys` (Windows service and DPAPI).

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
.\bin\wholeflow.exe run -background  # same, but hidden: no console window; returns at once. Stop with "stop"
.\bin\wholeflow.exe check            # Tally + cloud connection test, prints status and exits  (also -check)
.\bin\wholeflow.exe set-password     # reset the admin account (first-time creation happens in the browser)
.\bin\wholeflow.exe install          # Windows service "WholeFlow": starts at boot, hidden (Administrator); re-run to upgrade
.\bin\wholeflow.exe autostart        # no Administrator: start hidden at every logon of this user  ("autostart off" removes it)
.\bin\wholeflow.exe status           # service / autostart / process state + cloud sync state per company
.\bin\wholeflow.exe start | stop | restart   # the service if installed, otherwise the background process
.\bin\wholeflow.exe sync | config | uninstall
```

Cloud sync in one minute: run the app → open http://127.0.0.1:8080, create the admin account → Cloud Sync → business id, Supabase URL + service-role key, discover & tick companies, Save, Sync now, enable background sync, Save → `install`.

Data lives in `%ProgramData%\WholeFlow` (`config.json` with the key DPAPI-encrypted, `state.json`, `logs\app.log`).
Environment variables / `.env` override the file (see `.env.example`). `CLOUD_PROVIDER=memory` is a dry run.

While the service runs from `bin\wholeflow.exe`, `go build` cannot overwrite that file: build to another name, or `wholeflow.exe stop` first and `install` (Administrator) afterwards to pick up the new build. Because the service runs as LocalSystem, `install` refuses an exe outside Program Files; on a development PC add `-allow-any-location`.

The data folder is locked to SYSTEM, Administrators and the account the app runs as; the app sets this on every start. With the service installed, run `status`, `sync`, `check`, `config` and `set-password` from an **Administrator** console. A normal console gets "access denied".

## Deploying on a client PC

Goal: the customer's Tally PC syncs to the cloud on its own, every few minutes, from the moment Windows starts, with nothing to open and no window on screen. Two ways, pick one per PC:

| | **A. Windows service** (recommended) | **B. Logon autostart** (no Administrator) |
|---|---|---|
| Needs | An Administrator account once, at install time | Nothing |
| Starts | At boot, before anyone logs in | 20 s after the Windows user logs in |
| Runs as | LocalSystem, hidden | The logged-in user, hidden |
| Survives crashes | Restarted by Windows (30 s, 60 s, 5 min) | Started again at next logon |
| Command | `install` (or the script below) | `autostart` |

Tally itself must be open with the company loaded for a sync to succeed; while it is closed the app waits and retries, and nothing is deleted in the cloud.

### Before you start: create the business in Supabase

Each client (business) needs one row in the `businesses` table. Its id is the **business id** you enter on the Cloud Sync page. In the Supabase dashboard open **SQL Editor** and run:

```sql
insert into public.businesses (name)
values ('Client Business Name')
returning id, name, created_at;
```

Copy the `id` from the result. Only the name is needed; `id`, `created_at` and `updated_at` fill themselves in. The *Test cloud connection* button on the Cloud Sync page checks that this row exists, so a mistyped id shows up straight away.

To list existing businesses and their ids later:

```sql
select id, name, created_at from public.businesses order by created_at;
```

Several clients can share one Supabase project, one row each; Row Level Security keeps their data apart. A second Tally PC of the **same** business uses the same id (each PC must have a different Windows computer name). Owner and staff logins for the mobile app are created afterwards from the Cloud Sync page.

### A. Windows service, step by step

1. **Prepare one folder** (USB stick or `Downloads\WholeFlow` on the client PC) with:
   - `wholeflow.exe` — from `go build -o bin\wholeflow.exe ./cmd/server`
   - `deploy\Install-WholeFlow.cmd` and `deploy\Install-WholeFlow.ps1`
   - optional `.env` (from `.env.example`) only if you need overrides such as `APP_ADDR`, `TALLY_PORT` or `TALLY_TIMEOUT_SECONDS`
2. **TallyPrime**: Help (F1) → Settings → Connectivity → Client/Server configuration → *TallyPrime acts as* = **Server** (or Both). Note the port; the app reads it from `tally.ini`.
3. **Double-click `Install-WholeFlow.cmd`** and accept the UAC prompt. It copies the exe to `C:\Program Files\WholeFlow`, registers and starts the service (delayed automatic start, restart on failure) and opens http://127.0.0.1:8080. Doing it by hand instead: copy the exe there, open an Administrator console in that folder, run `.\wholeflow.exe install`.
4. **Create the admin account** on the page that opens (username, password ≥ 10 characters). Do this immediately: the first person to open the page claims the account. The app only listens on 127.0.0.1, so that is whoever sits at this PC.
5. **Cloud Sync page** (`/#/sync`): business id (from [the query above](#before-you-start-create-the-business-in-supabase)), Supabase URL and service-role key → *Test cloud connection* → *Test Tally & discover companies* → tick the companies → *Save* → *Sync now* → tick *Background synchronisation enabled* → *Save*. Details: [docs/SYNC_SETUP.md](docs/SYNC_SETUP.md).
6. **Verify**: close the browser, reboot the PC, do not log in yet or log in and open nothing. After a few minutes, from an Administrator console:
   ```powershell
   & "C:\Program Files\WholeFlow\wholeflow.exe" status
   ```
   Expect `Windows service: running (automatic start)`, `Process: running as service`, and `Last successful sync` on each ticked company (needs Tally open).

Upgrade: see [Rolling out an update](#rolling-out-an-update). Remove: `Install-WholeFlow.cmd -Uninstall` (add `-PurgeData` to delete `C:\ProgramData\WholeFlow` too).

### B. Logon autostart (no Administrator)

1. Copy `wholeflow.exe` to a permanent folder the user can read, e.g. `C:\Users\<user>\WholeFlow` (not Downloads or a USB stick).
2. Open a normal console in that folder and run:
   ```powershell
   .\wholeflow.exe autostart
   ```
   This registers the Task Scheduler task **WholeFlow** for the current Windows user (runs `wholeflow.exe run -background` at logon, no time limit, no elevation) and starts the app hidden right away.
3. Create the admin account and configure Cloud Sync exactly as in steps 4–5 above.
4. Verify: log off and on again (or reboot and log in), wait half a minute, run `.\wholeflow.exe status`: expect `Logon autostart: ready (runs at logon of PC\user)` and `Process: running as background`.

The app then runs only while that user is logged in; a locked screen is fine, a logged-off PC is not. `.\wholeflow.exe autostart off` removes the task; `stop` ends the running process. `install` later (Administrator) removes the task automatically and replaces it with the service.

### Daily operation

The customer sees nothing: no window, no tray icon, no login. Sync runs every interval (default 5 minutes) while Tally is open. `wholeflow.exe status` shows what is happening; `C:\ProgramData\WholeFlow\logs\app.log` has the details; http://127.0.0.1:8080 shows the dashboards and the Cloud Sync log behind the admin login. If port 8080 is taken on that PC, put `APP_ADDR=127.0.0.1:8090` in the `.env` next to the exe before installing.

### Rolling out an update

An update replaces only `wholeflow.exe`. The admin login, the Cloud Sync settings, the encrypted Supabase key and the sync progress all live in `C:\ProgramData\WholeFlow` and are kept, so there is nothing to set up again.

**On your PC, once per release:**

1. Raise the version in `internal/syncer/settings.go` (`const Version`, e.g. `0.3.0` → `0.3.1`). It is how you tell an updated PC from an old one.
2. Build the package. This runs `go vet` and `go test` first and stops if anything fails:
   ```powershell
   powershell -ExecutionPolicy Bypass -File deploy\Build-Release.ps1
   ```
   Result: `dist\WholeFlow-<version>.zip` with `wholeflow.exe`, `Install-WholeFlow.cmd` / `.ps1`, `README.txt`, `.env.example` and `migrations\`. The script prints the exe's SHA-256 so you can check the copy on the client.
3. **Database first.** If the release adds a file under `supabase/migrations/`, run that file in Supabase → SQL Editor before updating any PC, once per Supabase project. Migrations are additive, so the old version keeps working against the new schema. Releases so far:

   | Version | Migration to apply | What it adds |
   |---|---|---|
   | 0.2.0 | `0001_init.sql`, `0002_mobile_app.sql` | shops, transactions, staff access |
   | 0.3.0 | `0003_purchasing.sql` | suppliers, stock items, purchase bills; background mode and autostart |

   Skipping a migration does not break the sync: shops and transactions still go through, and the new parts show a warning on the Cloud Sync page until the migration is applied.

**On each client PC** (in person or over AnyDesk / TeamViewer):

1. Copy the zip to the PC and extract it (right-click → *Extract All*). Run from the extracted folder, not from inside the zip.
2. Double-click **`Install-WholeFlow.cmd`** and accept the UAC prompt. It prints `Upgrading WholeFlow <old> -> <new>`, stops the service, waits until Windows releases the old exe, copies the new one to `C:\Program Files\WholeFlow`, points the service at it, starts it again and prints `status`.
3. Check the `status` output at the end: `Process: running as service, version <new>`. Within a few minutes each company shows a new *Last successful sync*.

The sync is down only for the few seconds of the restart; nothing is lost, because the next run picks up everything changed in Tally since the last one. If the release changes what is synced (0.3.0 adds purchases and stock), the first run after the update uploads that data in full, which takes about half a minute for a company like the sample one.

**By hand**, from an Administrator console, if the script cannot be used:

```powershell
cd "C:\Program Files\WholeFlow"
.\wholeflow.exe stop
Copy-Item "<extracted folder>\wholeflow.exe" . -Force   # retry after a few seconds if Windows says "in use"
.\wholeflow.exe install                                   # re-points and restarts the existing service
.\wholeflow.exe status
```

**PCs set up with logon autostart** (no Administrator): log in as that user, run `.\wholeflow.exe stop` in the program folder, overwrite `wholeflow.exe` with the new one, then `.\wholeflow.exe start`. The logon task keeps pointing at the same path.

**Rollback:** keep the previous release zip. Installing it the same way puts the old version back. Settings and data are untouched, and extra tables from a newer migration are simply not used by the older version.

Documentation:

- [deploy/](deploy/README.md) — what to copy to a client PC; `Install-WholeFlow.cmd` installs/upgrades/removes the service
- [docs/SYNC_SETUP.md](docs/SYNC_SETUP.md) — developer setup runbook, Windows service and logon autostart installation
- [docs/SYNC_ARCHITECTURE.md](docs/SYNC_ARCHITECTURE.md) — how a run works, incremental sync by Tally `ALTERID`, retry/backoff, offline rules, security model
- [docs/DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) — Supabase tables, RLS for owner/staff, example queries
- [supabase/migrations/0001_init.sql](supabase/migrations/0001_init.sql) — the schema
- [supabase/migrations/0002_mobile_app.sql](supabase/migrations/0002_mobile_app.sql), [0003_purchasing.sql](supabase/migrations/0003_purchasing.sql) — staff access; suppliers, stock items, purchase bills
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
| Suppliers | Ledgers under **Sundry Creditors** incl. sub-groups (`SUPPLIER_GROUPS`). Cr = we owe the supplier (payable), Dr = advance paid. Transaction summary grouped into purchases, payments, debit notes and other, reconciled like shops. |
| Purchases | Every voucher whose type derives from **Purchase** (filtered inside Tally with `$$IsPurchase`), with item lines (stock item, godown, billed qty, rate, discount, amount) and the accounting entries. Bill total = amount credited to the party ledger; taxable = sum of item lines; tax & other = the difference. Cancelled and optional vouchers are left out. Debit notes (purchase returns) are not in the register; they show on the supplier page. |
| Inventory | Stock items with group, unit, part no. (alias), opening and closing quantity, Tally valuation rate and closing value, reorder level. Status: in stock, low (at or below reorder level), out of stock, negative. The item total equals the sum of Tally's stock groups plus items directly under Primary (verified on the sample company: ₹32,94,711.54). |
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
its transactions are always read live. The supplier list, the purchase register
and the stock items are also pulled on first use and kept in memory per company;
**Refresh from Tally** drops them so they reload on the next visit. Supplier detail
pages are read live. The purchase register is one request of about 7.7 MB / 3 s for
~400 bills on the sample company. No local database yet.

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
| `GET /api/suppliers?q=&type=dr\|cr\|zero&sort=balance_desc\|balance_asc\|name_asc\|name_desc` | suppliers with payable / advance totals |
| `GET /api/suppliers/{id}` · `GET /api/suppliers/{id}/transactions` | one supplier live; summary + reconciliation |
| `GET /api/purchases?from=&to=&supplier=&item=&q=&page=&pageSize=` | register (bills without lines), totals, by-supplier totals; dates `YYYY-MM-DD`, inclusive |
| `GET /api/purchases/items?from=&to=&supplier=&q=` | quantity, amount, average and last rate per item |
| `GET /api/purchases/{id}` | one bill with item lines and accounting entries |
| `GET /api/inventory?q=&group=&status=available\|low\|zero\|negative&sort=name_asc\|value_desc\|qty_desc\|qty_asc\|group_asc&page=&pageSize=` | stock items, stock value and status counts |
| `GET /api/inventory/{id}` · `GET /api/inventory/{id}/purchases` | one item (id = Tally GUID or the item name); its purchase lines |
| `GET /api/export/{customers\|outstanding\|suppliers\|purchases\|purchase-lines\|purchase-items\|inventory}?format=csv\|xlsx` | same filters as the lists |

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

Install as described in [Deploying on a client PC](#deploying-on-a-client-pc),
enable Server mode in TallyPrime, run `wholeflow.exe check`. Then open Tally Status →
Inspect ledger groups to confirm shops are under Sundry Debtors (adjust
`SHOP_GROUPS` if not). Note: a company with many years of vouchers will make the
shop *transaction summary* slower (it scans from the start of the books; about
2.7 s for ~5,900 vouchers here); raise `TALLY_TIMEOUT_SECONDS` if needed.
