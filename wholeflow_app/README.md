# WholeFlow Mobile

Flutter app (Material 3) for a business owner and their staff, in two flavors: **WholeFlow Owner** and **WholeFlow Staff**. It shows shop balances, statements, the outstanding and overdue reports, stock, purchases, sites and visits. The WholeFlow program on the Tally PC keeps this data up to date in the business's own database on the WholeFlow server ([../WholeFlow](../WholeFlow), [../README.md](../README.md)).

```
TallyPrime ─▶ wholeflow.exe (Tally PC) ─▶ WholeFlow server: the business's database + login + data API ─▶ this app
```

- **Read-only for business data.** The app never writes shops, transactions or any other table the Tally PC fills.
- **Owners** see every company and manage staff: create accounts, assign companies or sites and transaction visibility, reset passwords, and disable or enable accounts.
- **Staff** see only the companies and sites the owner assigned them. Row Level Security enforces this in the database, so the app only hides what the server already refuses.

## Prerequisites

- Flutter stable (built with 3.47 / Dart 3.13)
- The business created in the admin app (https://admin.jitsuji.xyz). That gives its **reference key** and the owner's login.

## Configure and run

The apps contain no business address or key. `env/hosted.json` holds only the WholeFlow server address (`CONTROL_URL`).

- **First launch:** the app asks for the business's **reference key**, typed or scanned from the QR code in the admin app. It shows "Connect to <business>?", remembers the answer, then shows the normal login.
- **Switching:** Settings → **Switch business** forgets the connection.
- **Subscription:**
  - Owners see a "renewal due" banner.
  - Owners and staff see a red banner in the grace period.
  - Once the subscription has ended, or the business is suspended, both apps show only a "paused" screen with a Refresh button. The server enforces this too (HTTP 402).

```bash
flutter pub get

# WholeFlow Owner (full business control, insights, staff admin, sync health, stock valuation)
flutter run --flavor owner -t lib/main_owner.dart --dart-define-from-file=env/hosted.json

# WholeFlow Staff (lean, for 1-2 GB phones: assigned shops, dues, quantities, visits)
flutter run --flavor staff -t lib/main_staff.dart --dart-define-from-file=env/hosted.json
```

Both apps can be installed side by side on the same phone (`com.wholeflow.wholeflow_app` and `com.wholeflow.staff`). Owner is the default flavor, so a plain `flutter run` builds it. `env/*.json` is git-ignored except `hosted.json`, which holds no secrets.

The app talks to the server's login (GoTrue) and data API (PostgREST) through the `supabase_flutter` package, which is only the client library for those open-source servers. There is no Supabase account or project.

## Release builds (Google Play)

Release builds are signed with the **upload key** from `android/key.properties` (git-ignored), shrunk with R8 and with obfuscated Dart code. Without `key.properties` a release build stops with an error; debug builds and `flutter test` don't need it.

**Once: create the upload key** (keep it outside the repo, back it up with its passwords; losing it means asking Google for an upload-key reset):

```bash
mkdir -p ~/keys
keytool -genkey -v -keystore ~/keys/wholeflow-upload.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties   # then fill in the path and passwords
```

**Play App Signing:** when creating each app in Play Console (Owner `com.wholeflow.wholeflow_app`, Staff `com.wholeflow.staff`), keep "Let Google manage and protect your app signing key" (the default). Google signs what users install; your key above is only the upload key, so it can be reset through Play Console if it is ever lost. Use the same upload key for both apps.

**Each release:**

1. Raise the build number in `pubspec.yaml` (`version: 1.0.1+2`: the part after `+` is the Android versionCode and must go up with every upload).
2. Build both bundles:

   ```bash
   tool/build_release.sh
   # which runs, for each flavor:
   flutter build appbundle --release --flavor owner -t lib/main_owner.dart \
     --obfuscate --split-debug-info=build/symbols/owner --dart-define-from-file=env/hosted.json
   flutter build appbundle --release --flavor staff -t lib/main_staff.dart \
     --obfuscate --split-debug-info=build/symbols/staff --dart-define-from-file=env/hosted.json
   ```

3. Upload `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab`, keep `build/symbols/<flavor>/` for that version (needed to read obfuscated stack traces with `flutter symbolize`), and tag it: `git tag app-<version>`.

`-P wfLocal=true` (local server testing) is refused for release builds.

**Too-old apps:** every request carries `X-App-Version` (`<version>+<build>`) and `X-App-Platform`. When the server's minimum version is raised, older apps get HTTP 426 and show only an "Update required" screen with a Google Play button.

**Crash reports:** uncaught errors are sent (signed in only, at most 5 per run, message and stack trace only, tokens removed) to the business's `POST /api/v1/client-errors`.

## Backend pieces (in `WholeFlow/`)

| Path | What it does |
|---|---|
| `db/migrations/0001`–`0009` | The business database: tables, Row Level Security, reports (`overdue_shops`, `site_report`), sites and visits, subscription status. The WholeFlow server applies them to every business (`scripts/migrate.sh`, or admin app → Settings → *Update all businesses*). |
| `internal/appapi/staff_http.go` | Staff management for every business (`/b/<slug>/api/v1/staff`): owner-only create, update, companies and sites, enable/disable, reset password |
| `db/tests/*.sql` + `db/tests/run_local.sh` | Run every migration and SQL test on a throwaway Postgres in Docker; everything is rolled back |

Tests: `WholeFlow/db/tests/run_local.sh` (SQL) and the Go tests in `WholeFlow` (`go test ./...`; with `WF_TEST_PG` they cover every endpoint).

## How access works

- A **staff member sees a company only when the owner assigned it** (`staff_company_access` row). There is no "all companies" default. A newly synced company stays hidden from staff until the owner assigns it. A staff member with no assignment sees a "not assigned to any company" screen.
- Each assignment has **areas** (empty = every area of that company, case-insensitive) and **can view transactions** (off hides the Statement tab, and RLS returns no transactions).
- New staff and password resets set `must_change_password`, so the app asks for a new password at the next sign-in.
- Disabling an account sets `users.is_active = false` and bans the login. RLS hides all data immediately. The app notices on the next refresh or resume and signs the user out.

## Payment analytics (owner only)

The **Analytics** tab and the dashboard's **Overdue** card show how each shop pays, computed on the phone from the synced data. Nothing is stored, and Tally isn't touched.

- **Credit period** is a filter on the Analytics screen (15/30/45/60/90 days or custom). It's kept in memory only. A bill is late once it's more than that many days old.
- **Oldest bill first (FIFO):** every receipt settles the oldest unpaid bill first. Returns (credit notes) and credit adjustments also settle the oldest bill, but don't count as *paying* in the timing figures.
- **Opening balance** counts as one bill dated where the synced vouchers begin (the current Tally period). A Cr opening balance, or a payment that arrives before any bill, is held as an advance and settles the next bills.
- **Per shop:** overdue amount, oldest late bill (days past due), share of paid bills paid on time, receipt-weighted average days to pay and days paid after the due date, last payment, unpaid bills with due dates, and how each paid bill was paid.
- **Whole business:** total overdue and number of shops, unpaid bills by age (not due / 1–30 / 31–60 / 61–90 / 90+ days late), on-time share, and average days to pay.
- **Check:** for every shop, unpaid bills minus advances must equal the Tally balance. A shop that doesn't reconcile shows a warning.

Settings is opened from the avatar at the top right of every tab. Material 3 allows at most five tabs, so owners have Dashboard, Shops, Outstanding, Analytics and Stock, and open **Staff** from Settings. Staff have Dashboard, Shops, Outstanding and Inventory.

## Stock: inventory, purchases and suppliers

The sync service fills `stock_items`, `purchases`, `purchase_lines` and `suppliers` (`0003_purchasing.sql`). The app only reads them.

- **Owners** get a **Stock** tab with three sub-tabs:
  - **Inventory:** quantity, status, stock value, valuation rate, last purchase rate and supplier, and recent bills for each item.
  - **Purchases:** bills grouped by month (newest first), totals for this month and last month, and each bill's item lines, taxes and total.
  - **Suppliers:** amount owed or advance paid, contact details, GSTIN, and the last 12 months of purchases with their bills.
- **Staff** get an **Inventory** tab: quantities and stock status for the companies they are assigned to. RLS returns suppliers, purchases and purchase lines to the owner only. The router also sends staff away from `/purchases` and `/suppliers`.
- For staff, the app reads only the quantity columns of `stock_items`, so it never loads purchase prices or stock values. RLS still lets staff read those columns. Blocking them in the database would need a column-limited view or grant.
- Supplier `payable` has the opposite sign from shops. Positive means you owe the supplier (shown as Cr). Negative means you paid an advance (Dr).

## Code layout

```
lib/
  main_owner.dart, main_staff.dart, bootstrap.dart
                             connect screen or saved business, API client init, ProviderScope, MaterialApp.router
  core/                      env, theme (M3 + semantic Dr/Cr/warning colours), router, money (paise), errors, shared widgets
  features/
    auth/                    session controller, login, forced password change
    company/                 visible companies, staff access, company switcher
    dashboard/               totals, top dues, freshness banner (sync_state)
    shops/                   paged list with search/filter/sort
    shop_detail/             details, contact actions, statement with running balance + reconciliation
    outstanding/             area-grouped report, share as text or PDF
    analytics/               FIFO payment analysis (owner): credit-days filter, ageing, per-shop bills
    stock/                   Stock tab: Inventory | Purchases | Suppliers for owners, Inventory only for staff
    inventory/               stock items: search, status/group filters, item detail with recent purchases (owner)
    purchases/               paged purchase bills, month totals, bill detail (owner)
    suppliers/               supplier list and detail with their bills (owner)
    staff/                   staff list/form/detail → manage-staff Edge Function (owner, from Settings)
    sync_health/             Tally PC, per-company status, recent sync logs (owner)
    settings/                theme, change password, sign out
    home/                    navigation shell (NavigationBar / NavigationRail ≥ 600 dp), refresh
```

Money is held as integer paise (`Money`) and formatted with Indian grouping (`₹34,18,745.27`, compact `₹34.2 L`).

## Checks

```bash
dart run build_runner build     # after changing freezed / json / riverpod annotated code
flutter analyze
dart format --set-exit-if-changed lib test
flutter test                    # unit + widget + golden tests
flutter test --update-goldens   # after an intentional UI change
```
