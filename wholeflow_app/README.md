# WholeFlow Mobile

Flutter app (Material 3) for a business owner and their staff. It shows shop balances, statements and the outstanding report. The WholeFlow sync service on the Tally PC keeps this data up to date in Supabase ([../WholeFlow](../WholeFlow)).

```
TallyPrime ─▶ wholeflow.exe (Tally PC) ─▶ Supabase (Postgres + RLS) ─▶ this app
```

- **Read-only for business data.** The app never writes shops, transactions or any other table the sync service fills.
- **Owners** see every company and manage staff: create accounts, assign companies with per-company area limits and transaction visibility, reset passwords, and disable or enable accounts.
- **Staff** see only the companies the owner assigned them, limited to their areas. Row Level Security enforces this in the database, so the app only hides what RLS already refuses.

## Prerequisites

- Flutter stable (built with 3.47 / Dart 3.13)
- The Supabase project with `WholeFlow/supabase/migrations/0001_init.sql` **and** `0002_mobile_app.sql` applied, and the `manage-staff` Edge Function deployed (see below)
- An owner account created from the WholeFlow **Cloud Sync** page ("Business owner & staff accounts")

## Configure and run

The app needs only the project URL and the **publishable (anon) key**. Never put the service-role key here: it bypasses RLS.

```bash
cp env/example.json env/dev.json      # fill in SUPABASE_URL and SUPABASE_ANON_KEY
flutter pub get
flutter run --dart-define-from-file=env/dev.json
flutter build apk --release --dart-define-from-file=env/dev.json
```

`env/*.json` is gitignored except `example.json`. A build without these values shows a "missing Supabase settings" screen.

## Backend pieces (in `WholeFlow/supabase/`)

| Path | What it does |
|---|---|
| `migrations/0002_mobile_app.sql` | `staff_company_access` table (which companies each staff member works for, with areas and transaction visibility per company), RLS read policies that enforce it, and two service-role-only functions used by `manage-staff` |
| `functions/manage-staff/` | Edge Function holding the service-role key; owner-only `create_staff`, `update_staff`, `set_companies`, `set_active`, `reset_password` |
| `tests/rls_mobile.sql` | Impersonates owner and staff users and asserts what each can see; everything is rolled back |

### Deploy

From `WholeFlow/`:

```bash
# once: link the CLI to the project (run `supabase init` first if supabase/config.toml doesn't exist)
npx supabase login
npx supabase link --project-ref <project-ref>

# database: apply 0002, then run the RLS checks (they roll back)
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/0002_mobile_app.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/rls_mobile.sql

# Edge Function (SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected by the platform)
npx supabase functions deploy manage-staff
```

Edge Function tests (Deno):

```bash
cd WholeFlow/supabase/functions && deno test manage-staff/handler_test.ts
```

## How access works

- A **staff member sees a company only when the owner assigned it** (`staff_company_access` row). There is no "all companies" default. A newly synced company stays hidden from staff until the owner assigns it. A staff member with no assignment sees a "not assigned to any company" screen.
- Each assignment has **areas** (empty = every area of that company, case-insensitive) and **can view transactions** (off hides the Statement tab, and RLS returns no transactions).
- New staff and password resets set `must_change_password`, so the app asks for a new password at the next sign-in.
- Disabling an account sets `users.is_active = false` and bans the Auth user. RLS hides all data immediately. The app notices on the next refresh or resume and signs the user out.

## Payment analytics (owner only)

The **Analytics** tab and the dashboard's **Overdue** card show how each shop pays, computed on the phone from the synced data. Nothing is stored, and Tally isn't touched.

- **Credit period** is a filter on the Analytics screen (15/30/45/60/90 days or custom). It's kept in memory only. A bill is late once it's more than that many days old.
- **Oldest bill first (FIFO):** every receipt settles the oldest unpaid bill first. Returns (credit notes) and credit adjustments also settle the oldest bill, but don't count as *paying* in the timing figures.
- **Opening balance** counts as one bill dated where the synced vouchers begin (the current Tally period). A Cr opening balance, or a payment that arrives before any bill, is held as an advance and settles the next bills.
- **Per shop:** overdue amount, oldest late bill (days past due), share of paid bills paid on time, receipt-weighted average days to pay and days paid after the due date, last payment, unpaid bills with due dates, and how each paid bill was paid.
- **Whole business:** total overdue and number of shops, unpaid bills by age (not due / 1–30 / 31–60 / 61–90 / 90+ days late), on-time share, and average days to pay.
- **Check:** for every shop, unpaid bills minus advances must equal the Tally balance. A shop that doesn't reconcile shows a warning.

Settings is opened from the avatar at the top right of every tab. Material 3 allows at most five tabs, and owners now have five: Dashboard, Shops, Outstanding, Analytics and Staff.

## Code layout

```
lib/
  main.dart, app.dart        Supabase init from dart-defines, ProviderScope, MaterialApp.router
  core/                      env, theme (M3 + semantic Dr/Cr/warning colours), router, money (paise), errors, shared widgets
  features/
    auth/                    session controller, login, forced password change
    company/                 visible companies, staff access, company switcher
    dashboard/               totals, top dues, freshness banner (sync_state)
    shops/                   paged list with search/filter/sort
    shop_detail/             details, contact actions, statement with running balance + reconciliation
    outstanding/             area-grouped report, share as text or PDF
    analytics/               FIFO payment analysis (owner): credit-days filter, ageing, per-shop bills
    staff/                   staff list/form/detail → manage-staff Edge Function
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
