# Implementation Prompt — WholeFlow Mobile App (Flutter, Material 3)

> Hand this whole file to the coding agent as its task. It is self-contained, but the agent must read the referenced WholeFlow files before writing code.

---

## Role and goal

You are building **WholeFlow Mobile**, a Flutter app for a wholesale business owner and their staff. It shows shop outstanding balances and transaction history that are already being synced from TallyPrime into Supabase by the existing **WholeFlow** sync service. The owner can also **create and manage staff accounts** from the app.

The app is **read-only for business data**. It never writes to shops, transactions, or any Tally-derived table. The only writes it makes are account management (staff) and the signed-in user's own password.

## Where the code goes

| What | Location |
|---|---|
| Flutter app (all Dart code, assets, tests) | `Credit-track/wholeflow_app/` (new folder; create with `flutter create --org com.wholeflow --project-name wholeflow_app --platforms android,ios wholeflow_app`) |
| New SQL migration | `Credit-track/WholeFlow/supabase/migrations/0002_mobile_app.sql` |
| Supabase Edge Function | `Credit-track/WholeFlow/supabase/functions/manage-staff/index.ts` |

The migration and Edge Function go under `WholeFlow/supabase/` because that folder already holds the Supabase project's schema. **Do not change any Go code, the web app, or `0001_init.sql` in `WholeFlow/`.** The sync service is live in production.

## Read these first (the source of truth)

1. `WholeFlow/supabase/migrations/0001_init.sql`: tables, RLS, helper functions `current_business_id()` / `is_owner()`, and views `v_shop_outstanding` / `v_company_summary`.
2. `WholeFlow/docs/DATABASE_SCHEMA.md`: column meanings, sign conventions, suggested mobile queries.
3. `WholeFlow/docs/SYNC_ARCHITECTURE.md`: sync states and error codes (section near "Company / service states").
4. `WholeFlow/internal/cloud/supabase/users.go`: how the sync service's admin page creates owner/staff accounts today. The Edge Function must produce the **same shape**: an Auth user with `email_confirm: true`, then a `public.users` row, with the Auth user rolled back if the row insert fails. Disabling an account sets `is_active = false` **and** bans the Auth user (`ban_duration: "876000h"`).
5. `WholeFlow/README.md` → "How the data is interpreted": shops = Sundry Debtors ledgers; `area` is derived from the ledger name.

### Data facts you must respect

- `shops.receivable` is signed rupees. **Positive means the shop owes the business (Dr)**. Negative means the shop is in credit or has paid an advance (Cr). `balance_amount` + `balance_type` are the same value as an absolute amount plus a side.
- `transactions.amount = debit - credit`. `category` ∈ `sales | receipts | returns | adjustments`.
- Every query filters out soft-deleted rows with `deleted_at is null`. The views already do this.
- Reconciliation: `opening_balance_amount (signed by opening_balance_type) + sum(active transactions.amount) = receivable`. The shop detail screen shows a subtle warning if this doesn't hold to the paisa.
- Freshness: read `sync_state` where `entity_type = 'company'`. It gives `last_successful_sync_at`, `status`, and `error_code`. `tally_companies.sync_status` values: `PENDING, SYNCING, SYNCED, TALLY_OFFLINE, CLOUD_OFFLINE, AUTH_ERROR, SYNC_ERROR, COMPANY_NOT_OPEN, DISABLED`.
- A business can have **several Tally companies**. Every data screen is scoped to one selected company.
- `numeric(14,2)` comes back from PostgREST as a JSON number or string. Parse it into **integer paise** (or a decimal type) and never do money arithmetic in `double`.

## Accounts and security model

- **No self sign-up screen.** The developer creates owners from the WholeFlow Cloud Sync page. Owners create staff in this app.
- Login is email + password through Supabase Auth (`supabase_flutter`). The app ships with **only the anon key and project URL**, passed via `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`. **The service-role key must never appear in the app, repo, or build config.**
- After login, load the caller's `public.users` row. If it is missing or `is_active = false`, sign out and show "Your account is not active. Contact your business owner."
- Role drives navigation: `OWNER` sees everything, including Staff and Sync Health. `STAFF` sees only data screens, limited by their permissions. The limits are enforced in RLS; the UI only hides what the user can't see.

### Staff account creation: why an Edge Function

The app can't create Supabase Auth users itself because that needs the service-role key. Build a **`manage-staff` Edge Function** (Deno/TypeScript, `@supabase/supabase-js` v2) that holds the service-role key as a function secret:

1. Read the caller's JWT from the `Authorization` header and resolve the user with an anon client. Then use the service-role client to load the caller's `users` row. Reject with 403 unless `role = 'OWNER' and is_active`.
2. Actions (JSON body `{ "action": ..., ... }`):
   - `create_staff` `{ email, password, name, companies: [{ company_id, areas, can_view_transactions }] }`: require **at least one** company, and every `company_id` must belong to the caller's business. Lowercase and trim the email, enforce a password of at least 8 characters, and call `auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { name, business_id, role: 'STAFF', must_change_password: true } })`. Then insert `users { id, business_id: caller.business_id, role: 'STAFF', name, email, is_active: true, created_by: caller.id }` and the `staff_company_access` rows. If either insert fails, delete the Auth user (the cascade removes the rest).
   - `update_staff` `{ user_id, name? }`
   - `set_companies` `{ user_id, companies: [{ company_id, areas, can_view_transactions }] }`: replace the staff member's full assignment set in one transaction (use a SQL function called via RPC with the service role, or delete-then-insert with a compensating restore on failure). An empty list is allowed: the staff member then keeps their login but sees no data.
   - `set_active` `{ user_id, active }`: update `is_active` and ban (`876000h`) or unban (`none`) the Auth user.
   - `reset_password` `{ user_id, password }`: also sets `must_change_password: true`.
3. For every action on `user_id`, verify the target is `role = 'STAFF'` **in the caller's business**. An owner can never create, edit, disable, or reset an owner, and can never touch another business.
4. Return `{ data }` or `{ error: { code, message } }` with codes `NOT_OWNER`, `INVALID_INPUT`, `EMAIL_TAKEN`, `NOT_FOUND`, `INTERNAL`. Never echo passwords or log them.
5. Include a README section with deploy steps: `supabase functions deploy manage-staff`, plus setting secrets if the CLI doesn't inject `SUPABASE_SERVICE_ROLE_KEY` automatically. If `WholeFlow/supabase/config.toml` doesn't exist, run `supabase init` there without touching `migrations/`.

### Staff company assignment and permissions (migration `0002_mobile_app.sql`)

A business usually has several Tally companies, and **each staff member works only for the companies the owner assigns them**. Company assignment is explicit: a staff member with no assigned company sees no business data at all. There is no "all companies" default. The owner decides company by company, and a newly synced company is hidden from all staff until the owner assigns it. Owners always see every company of their business.

Store assignments in a new table, not in `users.permissions`. A table gives foreign keys, cascades when a company or user is removed, and simple RLS joins:

```sql
create table public.staff_company_access (
  user_id                uuid not null references public.users (id) on delete cascade,
  company_id             uuid not null references public.tally_companies (id) on delete cascade,
  business_id            uuid not null references public.businesses (id) on delete cascade,
  areas                  text[] not null default '{}',   -- empty = every area of this company
  can_view_transactions  boolean not null default true,
  created_by             uuid references public.users (id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (user_id, company_id)
);
```

- A row means "this staff member may work in this company". Area limits and transaction visibility are set **per company**, because area names differ between companies.
- `areas` matching is case-insensitive on `shops.area`. `can_view_transactions = false` hides the Statement tab for that company.
- Add a trigger or check that `user_id` is a `STAFF` user and that `company_id` belongs to the same `business_id` as the user.
- Leave `users.permissions` untouched and reserved. The app doesn't read or write it.

The migration must be **additive and safe to run on the live database**. Wrap it in a transaction.

- Enable RLS on `staff_company_access`. Owners can read all rows of their business. Staff can read only their own rows. Add no write policies: the Edge Function writes this table with the service role, so assignment always passes the owner check.
- Add `security definer` helpers with `set search_path = public`: `can_see_company(company_id uuid)`, `can_see_shop(shop_id uuid)` (company assigned, and the shop's area allowed by that assignment), and `can_see_transactions(company_id uuid)`. Owners always get `true`. Staff get `true` only through a matching `staff_company_access` row.
- Replace the read policies on `tally_companies`, `shops`, `transactions`, `sync_state`, and `sync_logs` so they keep the existing `business_id = current_business_id()` check **and** apply the helpers above. Drop and recreate each policy by name. The views are `security_invoker`, so they inherit this automatically. Check that `v_company_summary` for a staff member lists only their assigned companies, with totals covering only their allowed shops.
- Staff can read their **own** `users` row. Only owners can list all users of the business: tighten `users_read` to `id = auth.uid() or (business_id = current_business_id() and is_owner())`.
- Add the indexes the new policies need, for example `lower(area)` on shops and `staff_company_access (company_id)`.
- Grant nothing new to `anon`. Add no write policies on data tables.
- Ship `WholeFlow/supabase/tests/rls_mobile.sql`: a script that impersonates several users (`set local role authenticated; set local request.jwt.claims = …`), asserts row counts, and rolls back. Cover an owner, a staff member assigned to company A only, a staff member assigned to A and B with an area limit in B, a staff member with no assignments (sees nothing), and a staff member of another business.

## Tech stack (Flutter)

- Flutter stable (latest), Dart 3, null safety, `flutter_lints` (or `very_good_analysis`), zero analyzer warnings.
- `supabase_flutter` for auth, PostgREST, and Edge Function calls (`functions.invoke('manage-staff')`).
- `flutter_riverpod` (with `riverpod_generator`) for state. Use `go_router` with a role-aware redirect guard.
- `freezed` + `json_serializable` for models.
- `intl` for **Indian number formatting**: `₹34,18,745.27` (lakh/crore grouping, `en_IN`). Add a compact form (`₹34.2 L`) for dashboard tiles. Show Dr/Cr with colour **and** a text label, never colour alone.
- `url_launcher` for Call and WhatsApp (`https://wa.me/91XXXXXXXXXX`) from a shop's phone.
- `dynamic_color` for Material You on Android 12+, falling back to a seed colour.
- `shared_preferences` for small preferences (selected company, theme mode). Store nothing sensitive there. Supabase handles session storage.

### Material 3 design system

- `ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(...))` with light and dark schemes and a system/light/dark switch. Put all colours, text styles, and spacing in `lib/core/theme/`. Hard-coded colours or font sizes in widgets are not allowed.
- Use M3 components throughout: `NavigationBar` on phones and `NavigationRail` on tablets/landscape (≥ 600 dp), `SearchBar`/`SearchAnchor`, `FilterChip`/`ChoiceChip`, `Card` (filled/outlined), `ListTile`, `SegmentedButton`, `FilledButton`/`FilledButton.tonal`, `ModalBottomSheet`, `SnackBar`, `Badge`, `LinearProgressIndicator`, `RefreshIndicator`.
- Add semantic colour extensions for **amount owed (Dr)**, **in credit (Cr)**, and **sync warning**, derived from the scheme via a `ThemeExtension`. Contrast must meet WCAG AA in both themes.
- Include empty, loading (skeletons, not spinners, for lists), and error states on every screen. Errors map to friendly copy, with a Retry button on every error state.
- Tap targets are at least 48 dp. The layout supports dynamic text scaling up to 200% without overflow.

## Screens

**Common to owner and staff**

1. **Splash/Auth gate**: restore the session, then route by role.
2. **Login**: email, password, show/hide toggle, and "Forgot password? Ask your business owner" (no email reset flow). Show inline errors.
3. **Force password change**: shown when `user_metadata.must_change_password` is true. Calls `auth.updateUser(password, data: {must_change_password: false})`.
4. **Company switcher**: a top app bar dropdown or bottom sheet listing the companies the user can see. For staff, that means only their assigned companies. Remember the last selection, but drop it if the company is no longer visible (for example, the owner removed the assignment). Skip the switcher if there is only one company. A staff member with **no assigned companies** gets an empty-state screen: "You haven't been assigned to any company yet. Ask your business owner." Profile and sign out stay available.
5. **Dashboard**: total outstanding, shops with dues, total credit, and number of shops (from `v_company_summary`). Show the top 10 shops by receivable and a **freshness banner** ("Updated 4 min ago" from `sync_state`). Turn the banner into a warning (M3 error container) when the status is not `SYNCED`/ok or the last success is older than 1 hour, with human wording for `TALLY_OFFLINE` ("Tally PC is offline — figures may be out of date"), `CLOUD_OFFLINE`, and so on.
6. **Shops**: search by name, phone, or area. Filter chips: Owes us / In credit / Settled, plus an area multi-select. Sort by balance ↓↑, name, or area. Use infinite scroll with PostgREST `range()` pagination (page size 50) and pull-to-refresh. Each row shows name, area, and a signed balance with a Dr/Cr label.
7. **Shop detail**: a balance header card, contact card (phone(s) with Call/WhatsApp, address, GSTIN, contact person), opening balance, and a **Statement** tab. The statement shows transactions newest first with date, voucher type/number, category chip, and debit/credit, with a **running balance**. Category filter chips, a date-range picker, and paging. Show the reconciliation warning if it doesn't match. Hide the Statement tab when the staff member's assignment for the current company has `can_view_transactions = false`.
8. **Outstanding report**: shops with `receivable > 0`, grouped by area with area subtotals and a grand total. Include a share action that exports a plain-text or PDF summary via the OS share sheet (the `share_plus` and `pdf` packages).
9. **Profile/Settings**: name, role, business, theme mode, change password, app version, sign out.

**Owner only**

10. **Staff list**: all users of the business with role badge, active/disabled state, and the **names of their assigned companies** as chips (for example "JMJ Marketing · JK Tyres"). Flag staff with no companies with a "No company" warning badge. Add a filter by company ("Who works for JMJ Marketing?") and a FAB labelled "Add staff".
11. **Add/Edit staff**: a stepped form or sections.
    - **Details**: name, email, and an initial password with a generate button and copy-to-clipboard.
    - **Companies (required, at least one)**: a checkbox list of every company in the business. Each checked company expands to its own settings: an area multi-select built from distinct `shops.area` **of that company** (none selected = all areas) and a "Can view transactions" switch.
    - Show a summary before saving, for example "Ravi will see: JMJ Marketing (all areas), JK Tyres (Pala, Rajakkad; no transactions)".
    - After creation, show a one-time sheet with the login email and password for the owner to share.
12. **Staff detail**: assigned companies with their area and transaction settings. Actions: **Change companies** (the same company section as above, saved via `set_companies`; removing a company takes effect on the staff member's next refresh), edit name, reset password, and disable/enable (the confirmation dialog explains they will be signed out). Owner rows are view-only.
13. **Sync health**: `tally_connections` (hostname, status, last seen, app version), per-company `sync_status` / `last_sync_at`, and the last 20 `sync_logs` with status, mode, counts, and error.

## Architecture

Use a feature-first folder layout:

```
wholeflow_app/lib/
  main.dart                 # Supabase.initialize from dart-defines, ProviderScope
  app.dart                  # MaterialApp.router, themes
  core/                     # theme/, router/, money/ (paise parsing + INR formatting), errors/, widgets/ (shared M3 widgets), env.dart
  features/
    auth/                   # data/ domain/ presentation/
    company/
    dashboard/
    shops/
    shop_detail/
    outstanding/
    staff/                  # calls manage-staff Edge Function
    sync_health/
    settings/
```

- Each feature has `data` (Supabase repositories, DTOs), `domain` (models, pure logic such as running balance and reconciliation), and `presentation` (widgets, Riverpod controllers).
- Widgets never call Supabase directly; they go through repositories. Map Supabase and Edge Function errors to a typed `AppFailure`.
- Handle expired or revoked sessions (for example, a disabled staff member) by returning to Login with a message.
- Realtime is optional for later. For now, refresh on pull, on app resume, and every 5 minutes while the dashboard is visible.

## Testing and quality gates

- **Unit tests**: paise parsing and INR formatting (lakh grouping, negatives, zero), Dr/Cr from signed receivable, running balance, reconciliation, permission-driven navigation, and error-to-copy mapping.
- **Repository tests** against a mocked Supabase client, checking query shape, pagination, and `deleted_at is null`.
- **Widget tests**: login errors, shops list states (loading/empty/error/data), the staff form with validation, and the hidden Statement tab for restricted staff.
- **Golden tests** for key screens in light and dark themes.
- **Edge Function tests** (Deno test): a non-owner gets 403, an owner creating an owner is rejected, a cross-business `user_id` is rejected, `create_staff` with no companies is rejected, a `company_id` from another business is rejected, `set_companies` replaces the assignment set atomically, and rollback runs when an insert fails.
- **Widget tests** also cover the staff form requiring at least one company, per-company area lists, and the "no company assigned" empty state.
- `flutter analyze` and `dart format --set-exit-if-changed .` are clean and `flutter test` passes.

## Delivery order

Work in phases and finish each one (running, tested) before the next:

1. Scaffold, theme, env config, auth gate, login, role routing, profile/sign-out.
2. Company switcher, dashboard, freshness banner.
3. Shops list and shop detail with statement.
4. Outstanding report and share.
5. Migration 0002 with the RLS test script, the `manage-staff` Edge Function, and the staff screens.
6. Sync health, force password change, polish (accessibility, text scaling, tablet layout), and README.

## Deliverables

- `wholeflow_app/README.md`: prerequisites, run commands with `--dart-define`s, how to create the first owner (via the WholeFlow Cloud Sync page), and how to deploy the migration and the Edge Function.
- `WholeFlow/supabase/migrations/0002_mobile_app.sql`, `WholeFlow/supabase/functions/manage-staff/`, and `WholeFlow/supabase/tests/rls_mobile.sql`.
- A short `WholeFlow/docs/DATABASE_SCHEMA.md` addendum describing `staff_company_access` and the new policies. Change nothing else in `WholeFlow/`.
- `.gitignore` entries so no `.env`, keys, or build outputs are committed.

## Acceptance criteria

- An owner signs in and sees dashboard totals equal to `v_company_summary` for the selected company. For the sample company this is 323 shops, 153 with dues, and ₹35,95,244.95 outstanding.
- The owner creates a staff member assigned to company A only. That staff member signs in, is forced to change their password, and sees only company A in the switcher, dashboard, and lists. A direct PostgREST query with their JWT returns no rows from other companies.
- The owner then adds company B with a one-area limit. After a refresh the staff member sees A in full and only that area of B. When the owner removes A, it disappears from the staff member's app on the next refresh.
- A staff member whose last company is removed sees the "not assigned to any company" screen.
- Disabling the staff member signs them out on their next request, and they can't sign in again.
- Any Tally/cloud outage surfaces as a clear banner. The app never shows stale data without the "last updated" time.
- No service-role key exists anywhere in `wholeflow_app/`, and the app makes no writes to Tally-derived tables.

## Open decisions (ask the user before Phase 5 if still unresolved)

1. **Staff without email:** many staff may not have an email address. One option is to let the owner enter a **username** and have the Edge Function map it to a synthetic address such as `username@<business-id>.staff.wholeflow` (no mail is ever sent because `email_confirm: true`). The alternative is to require real emails.
2. **Offline cache:** decide whether a local cache (for example `drift`) of the last-loaded shops and statement is needed for poor connectivity in the field, or whether online-only is acceptable for v1.
3. **App name, icon, and seed colour** for branding.
