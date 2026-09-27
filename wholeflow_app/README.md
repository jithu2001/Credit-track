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
