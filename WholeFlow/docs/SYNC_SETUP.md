# Cloud Sync — Developer Setup and Windows Service Installation

WholeFlow is one executable, `wholeflow.exe`. It serves the shop-outstanding web app and, in the same process, runs the background synchronisation of selected Tally companies to the cloud. Sync is configured on the app's **Cloud Sync** page. The whole app, dashboards included, is behind a single **admin login**; it is a tool for the developer/administrator only. This is the runbook for installing it on a customer's PC; the business owner never needs any of this and uses the mobile app.

## 0. Prerequisites

- Windows 10/11 PC with TallyPrime (Silver is fine) and the company data.
- TallyPrime acting as **Server** or **Both**: Help (F1) > Settings > Connectivity > Client/Server configuration. Note the port (default 9000); the app reads it from `tally.ini` automatically.
- A Supabase project with `supabase/migrations/0001_init.sql`, `0002_mobile_app.sql` and `0003_purchasing.sql` applied in that order (SQL Editor → paste → Run). Without 0003, shops and transactions still sync; suppliers, stock items and purchases show a warning on the Cloud Sync page until it is applied.
- A row in `businesses` for this customer; note its `id`.
- The project's **service-role key** (Supabase dashboard > Project Settings > API). Treat it like a root password.
- `bin\wholeflow.exe` built with `go build -o bin\wholeflow.exe ./cmd/server`.

## 1. Copy the executable

Create `C:\Program Files\WholeFlow\` and copy `wholeflow.exe` there. Data (config, state, logs) lives in `C:\ProgramData\WholeFlow\` and is created automatically. Override with `-data <dir>` or `WHOLEFLOW_DATA_DIR`.

Shortcut for the whole of sections 1 and 4: put `wholeflow.exe` next to `deploy\Install-WholeFlow.cmd` + `.ps1` and double-click the `.cmd` (UAC prompt). It copies, installs and starts the service and opens the browser; sections 2 and 3 are then done against the running service. Re-running it with a newer exe upgrades in place. No Administrator account at all? See section 4b.

## 2. First run: create the admin account in the browser

```powershell
.\wholeflow.exe
```

Open http://127.0.0.1:8080. On the very first run the app shows **Welcome — create the admin account**: choose a username (default `admin`) and a password of at least 10 characters, and you are logged in. The password is stored as a salted PBKDF2 hash in `C:\ProgramData\WholeFlow\config.json`; there is no default password, and the form disappears for good once an account exists. Do this yourself right after installing — whoever opens the page first claims the account (the app listens on 127.0.0.1 only, so that is whoever sits at the Tally PC). Keep these credentials to yourself; they are not for the owner.

To reset a forgotten password later, from a console on that PC:

```powershell
.\wholeflow.exe set-password
```

`install` and `autostart` work before an account exists too (the installer script relies on that); they remind you to open the page and create it straight away.

## 3. Configure cloud sync

After logging in, the Dashboard, Shops, Outstanding and Tally Status pages work as before. Open **Cloud Sync** in the navigation and work through the numbered sections:

1. **Business** – paste the `businesses.id` UUID and a name.
2. **Cloud backend** – Provider *Supabase*, project URL (`https://xxxx.supabase.co`), service-role key. Click **Test cloud connection**: it verifies the key and that the business row exists. The key is encrypted with Windows DPAPI when saved and never displayed again.
3. **TallyPrime companies** – click **Test Tally & discover companies**. Tick the companies to synchronise. Untick anything that must not leave the PC; only ticked companies are ever read.
4. **Sync settings** – interval (default 5 minutes), whether to sync transactions (recommended), how often to look for deleted vouchers (default 24 h). Leave *Background synchronisation* off for now. Click **Save settings**.
5. **Run & verify** – click **Sync now**. Watch the status table and log. A first full sync of ~6,000 vouchers takes about 15 s. Check that shops created matches Tally's Sundry Debtor count, then spot-check a shop's balance in the Supabase table editor against the Shops page.
6. Tick **Background synchronisation enabled** and save. From now on the app syncs on its own; the header shows "Cloud sync: SYNCED · time" on every page.
7. **Business owner & staff accounts** – create the owner's mobile-app login: email, name, password (min 8 characters), role *Owner*. The app creates the Supabase Auth user (email pre-confirmed, no verification mail) and the matching `users` row tied to this business. Give the email and password to the owner. The same section lists existing accounts, resets a password and disables/enables an account (a disabled account is also banned in Supabase Auth, so an open mobile session stops working). Staff can be added here too, or later by the owner from the mobile app.

Press Ctrl+C in the console when done.

Headless alternative: put the values in `C:\ProgramData\WholeFlow\.env` (see `.env.example`: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `BUSINESS_ID`, `SYNC_COMPANIES=<guid,guid>`, `SYNC_ENABLED=true`) and run `wholeflow.exe check` then `wholeflow.exe sync`. Environment values override the page and are never written to config.json; prefer the page so the key is stored encrypted rather than in a text file.

## 4. Install as a Windows service

```powershell
.\wholeflow.exe install
```

This registers the service **WholeFlow** with automatic (delayed) start and restart-on-failure (30 s, 60 s, 5 min), and starts it. The service runs as LocalSystem, hidden, so it starts before anyone logs in; Tally is reached over `localhost:9000` even though Tally runs in the user's session. Both the service and your console can decrypt the stored key (DPAPI machine scope). The web app and the Cloud Sync page stay available at http://127.0.0.1:8080 while the service runs. If the service already exists, `install` re-points it at the executable you ran and restarts it (that is how upgrades work). If a background process or a logon task from section 4b exists, `install` stops and removes it first so only one instance ever owns the port.

Managing it:

```powershell
.\wholeflow.exe status      # service / autostart / process state + cloud sync state per company
.\wholeflow.exe stop
.\wholeflow.exe start
.\wholeflow.exe restart
.\wholeflow.exe uninstall
```

`status`, `sync` and `check` work while the service runs: the CLI talks to the running app over localhost using a per-process token in `control.token`, so there is never more than one process syncing. If port 8080 is taken, set `APP_ADDR` in `.env` before installing.

Verified on the development PC on 28 Sep 2026: Windows booted at 09:33, the service started on its own at 09:35 (delayed start) and completed its first sync 9 s later, with nobody opening anything.

## 4b. Without Administrator rights: logon autostart

Some client PCs only offer a standard user account. Then:

```powershell
.\wholeflow.exe autostart        # register + start now
.\wholeflow.exe autostart off    # remove the registration
```

`autostart` creates the Task Scheduler task **WholeFlow** for the current Windows user: trigger *at logon of this user*, 20 s delay, no execution time limit, least privilege, action `wholeflow.exe run -background -data <data dir>`. `run -background` launches the app as a detached process with no console window and returns once it answers on its port; the logon task therefore finishes immediately while the app keeps running. Copy the exe to a permanent folder first (the task points at its absolute path). Differences from the service: the app runs only while that user is logged in (locked is fine), and it is not restarted by Windows after a crash, only at the next logon. `install` (Administrator) later removes the task automatically.

`run -background` is also handy on its own: `start` uses it whenever the service is not installed, and `stop` ends the process cleanly through the control API (the app logs `shutdown requested over the control API`, finishes any running sync step, and exits).

## 5. Daily operation (what the customer sees)

Nothing. PC boots → service starts → when Tally is opened the next cycle succeeds → cloud is updated every 5 minutes → mobile app shows fresh data. The customer does not open http://127.0.0.1:8080 at all; it needs the admin login. While Tally is closed the sync reports `TALLY_OFFLINE`, retries with backoff (30 s, 60 s, then every 5 min) and never deletes anything in the cloud.

## 6. Troubleshooting

| Symptom | Where to look | Likely cause |
|---|---|---|
| `TALLY_OFFLINE` | `status`, Tally Status page | Tally closed, not in Server mode, wrong port (the page shows the port and its source), firewall |
| `COMPANY_NOT_OPEN` | Cloud Sync status table | The selected company is not loaded in Tally; open it, or untick it |
| `AUTH_ERROR` / `CLOUD_AUTH_ERROR` | Cloud Sync → Test cloud connection | Wrong service-role key or URL; key encrypted on another PC ("re-enter it") |
| `CLOUD_NOT_FOUND` | Test cloud connection | `BUSINESS_ID` has no row in `businesses`, or migration not applied |
| `CLOUD_OFFLINE` | log | No internet / Supabase down; resolves itself |
| `TALLY_TIMEOUT` on the first sync | log | Very large company; set `TALLY_TIMEOUT_SECONDS=600` in `.env` and restart |
| `SYNC_ERROR` with `TALLY_INVALID_RESPONSE` | `logs\raw-errors\` | Tally returned XML we could not parse; send the file for analysis (contains accounting data) |
| Service does not start | `C:\ProgramData\WholeFlow\startup-error.txt`, `logs\app.log` | Bad config file, port in use |
| `another WholeFlow is already running` | `status` | A second copy was started (double-clicked exe while the service runs); harmless, close it |
| Nothing runs after reboot | `status` | Neither the service nor the logon task is registered: run `install` (Administrator) or `autostart`. With `autostart`, the user must log in first |
| Logon task registered but `Process: not running` | Task Scheduler → WholeFlow → History; `logs\app.log` | Exe moved or deleted after `autostart` (re-run it), or port in use |
| `access denied` from `status`, `sync`, `config` | — | The data folder is restricted to SYSTEM and Administrators: open the console with *Run as administrator* |
| Warning "… would be deleted; skipped as a safety check" | Cloud Sync status table | Tally returned far fewer shops, suppliers, items, bills or transactions than the cloud has (group renamed, `SHOP_GROUPS` typo, wrong company). Fix the setting; if the deletions are real, set `SYNC_ALLOW_MASS_DELETE=true` in `.env` for one run |
| `TALLY_WRITE_BLOCKED` | log | A request was refused before reaching Tally because it was not a read-only export (e.g. a name containing `$$`). Nothing was sent to Tally |
| Login refused | — | 8 failed attempts lock the account for 5 minutes; reset with `set-password` (console) |

Logs: `C:\ProgramData\WholeFlow\logs\app.log` (rotated at 20 MB, 5 kept): every Tally request, every cloud request, every web request under `/api/`, every run summary and every error; credentials never. `wholeflow.exe config` prints the effective configuration with secrets redacted.

## 7. Moving to a different PC / reinstalling

Copy nothing but the executable. Re-run `set-password`, set up through the Cloud Sync page (the key must be re-entered because DPAPI is machine-bound), tick the same companies. The first run is a full sync; because all writes are upserts keyed by Tally GUIDs, the cloud rows are updated in place, not duplicated.

## 8. Uninstall

```powershell
.\wholeflow.exe uninstall        # service (Administrator)   — or:  .\wholeflow.exe autostart off ; .\wholeflow.exe stop
Remove-Item -Recurse C:\ProgramData\WholeFlow
```

Or `Install-WholeFlow.cmd -Uninstall -PurgeData`. Cloud data is untouched by uninstalling.
