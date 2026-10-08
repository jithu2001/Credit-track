# Database Schema (one PostgreSQL database per business)

Migrations: `db/migrations/0001_init.sql`, `0002_mobile_app.sql`, `0003_purchasing.sql`, `0004_overdue.sql`, `0005_sites_visits.sql`, `0006_small_radius.sql`, `0007_service_control.sql`, `0008_stock_minimums.sql`, `0009_lockdown.sql`, applied in that order to every business database by the WholeFlow server (`scripts/migrate.sh`, or admin app → Settings → *Update all businesses*). The WholeFlow app API (`internal/appapi`, Go) signs people in against the `auth` tables and reads and writes this schema as `authenticated` (RLS) or, for Tally PC uploads and staff management, as `service_role`. See *Privileges, migrations and data retention (migration 0009)* below.

```
businesses ─┬─ users (auth.users)            OWNER | STAFF
            ├─ tally_connections             one per PC running the sync service
            ├─ tally_companies ─┬─ shops ──── transactions
            │                   ├─ sync_state (per entity)
            │                   └─ sync_logs
```

Every business-owned table has `business_id`; every row written by the sync service is tagged with the `BUSINESS_ID` it was configured with. Timestamps are `timestamptz`; `updated_at` is maintained by trigger.

## Tables

### businesses
| Column | Type | Notes |
|---|---|---|
| id | uuid PK | The `BUSINESS_ID` the sync service is configured with |
| name | text | |

Create one row per customer before configuring the sync service:
```sql
insert into businesses (name) values ('JMJ Marketing') returning id;
```

### users
One row per login account; `id` references `auth.users(id)` (the login service's table).

| Column | Type | Notes |
|---|---|---|
| business_id | uuid | tenant |
| role | text | `OWNER` or `STAFF` |
| name, email | text | |
| is_active | boolean | owner can disable staff |
| permissions | jsonb | reserved for staff restrictions, e.g. `{"areas":["Pala"],"transactions":false}` |
| created_by | uuid | the owner who created a staff user |

Admins (you) never have a row here. The owner is created with the business in the admin app; staff are created by the owner in the Owner app (through the app API's `/staff` routes), or from the Tally PC's Cloud Sync page, section "Business owner & staff accounts". Each calls the login service's admin API (`POST /auth/v1/admin/users` with `email_confirm: true`) and then inserts the `users` row with the service key; disabling an account sets `is_active = false` and bans the login.

### tally_connections
| Column | Notes |
|---|---|
| machine_identifier | hostname of the PC; unique per business |
| hostname, tally_host, tally_port, app_version | diagnostics |
| status, last_seen_at | `online` and the time of the last run |

Readable by owners only (not staff).

### tally_companies
| Column | Notes |
|---|---|
| tally_company_id | Tally company **GUID**; unique per business; survives renames |
| company_name, company_number | |
| financial_year_from, books_from, ending_at, period_from, period_to, last_voucher_date | dates from Tally |
| enabled, sync_enabled | mirror of the local selection |
| sync_status | `SYNCING`, `SYNCED`, `TALLY_OFFLINE`, … |
| last_sync_at | last successful sync |

### shops (current state)
| Column | Notes |
|---|---|
| tally_ledger_id | Tally ledger GUID; unique with `company_id` |
| tally_master_id, tally_alter_id | Tally identifiers (diagnostics) |
| name, aliases[] , ledger_group | |
| phone, phones[], phone_source | primary phone; all phones; `ledger` or `address` (extracted from address lines) |
| contact_person, email, gstin, gst_registration_type | |
| address (text), address_lines[] , state, pincode, country | |
| area | derived from the ledger-name suffix; **not** a Tally field |
| opening_balance_amount / _type | rupees, `DR` / `CR` / `''` |
| balance_amount / balance_type | Tally closing balance (absolute value + side) |
| receivable | signed rupees: **positive = shop owes the business**, negative = credit/advance |
| synced_at | last time the sync wrote this row |
| deleted_at | soft delete; `null` = active. Set when Tally no longer lists the ledger under the shop groups |

### transactions (history)
| Column | Notes |
|---|---|
| shop_id | FK to shops |
| tally_voucher_id | voucher GUID |
| tally_ledger_id | shop ledger GUID; unique with company + voucher |
| tally_master_id, tally_alter_id | `tally_alter_id` is the incremental cursor |
| transaction_date | |
| voucher_number, voucher_type, base_voucher_type | e.g. `CB/26-27/0001`, `B2c Gst Sales`, `Sales` |
| category | `sales`, `receipts`, `returns` (credit notes), `adjustments` (everything else) |
| narration | |
| debit, credit | positive rupees; at most one non-zero |
| amount | signed effect on receivable = `debit - credit` |
| synced_at, deleted_at | soft delete when the voucher is deleted, cancelled, made optional/post-dated, or no longer touches this shop |

Optional, cancelled and post-dated vouchers are never stored, matching how Tally computes balances. `opening_balance + sum(amount) over active transactions` should equal `receivable`; the web app's reconciliation logic is the reference.

### sync_state
One row per company and entity (`company`, `shops`, `transactions`).

| Column | Notes |
|---|---|
| last_successful_sync_at | preserved across failed attempts |
| last_attempt_at | |
| last_cursor | transactions: highest Tally AlterID synced |
| records_processed | |
| status | `ok` or `error` |
| error_code, error_message | classified code (see architecture doc) |

The mobile app can show "last updated" from `sync_state` where `entity_type = 'company'`, and a warning when `status = 'error'` and `last_attempt_at` is recent.

### sync_logs
One row per company per run that actually started syncing (Tally reachable). Outages only update `sync_state`, so an overnight outage does not create hundreds of rows.

| Column | Notes |
|---|---|
| started_at, completed_at, status | `success`, `partial`, `failed`, `skipped` |
| mode | `full`, `incremental`, `reconcile` |
| records_processed / created / updated / deleted / failed | shops + transactions |
| shops_processed, transactions_fetched | |
| error_code, error_message | |

## Views

- `v_shop_outstanding`: active shops with balances and company name.
- `v_company_summary`: per company: shops, shops with dues, total outstanding, total credit, sync status.

Both are `security_invoker`, so RLS applies to whoever selects from them.

## Row Level Security

- `current_business_id()` returns the caller's business from `users` (active users only); `is_owner()` checks the role.
- `SELECT` on every table is limited to `business_id = current_business_id()`; `tally_connections` additionally requires `is_owner()`.
- `users`: owners may update `STAFF` rows of their own business, and since 0009 only the columns `name`, `is_active`, `requires_check_in` (column grants). The app API itself changes staff as `service_role`. Nobody can change a role, business or email through RLS.
- Data tables have no `INSERT`/`UPDATE`/`DELETE` for `authenticated` except `sites` and `visit_plans` (owners); `anon` has no grants at all. Tally data is written as `service_role` (the PC's own key, through the app API). The exact list is in the 0009 section.

Verifying isolation: sign in as a user of business A and run `select count(*) from shops` – only A's rows appear; with a user of business B, only B's. Service-role queries see everything.

## Suggested mobile-app queries

```sql
-- Outstanding list
select * from v_shop_outstanding where company_id = $1 and receivable > 0 order by receivable desc;

-- Shop statement
select transaction_date, voucher_type, voucher_number, category, debit, credit, narration
from transactions where shop_id = $1 and deleted_at is null order by transaction_date desc, created_at desc;

-- Freshness
select last_successful_sync_at, status, error_code from sync_state where company_id = $1 and entity_type = 'company';
```

## Mobile app additions (migration 0002)

Migration: `db/migrations/0002_mobile_app.sql` (additive; the sync service is unaffected). Checks: `db/tests/rls_mobile.sql` (rolled back).

### staff_company_access
Which companies each STAFF user works for. **No row, no data:** a staff member sees only the companies the owner assigned, and a newly synced company stays hidden from staff until assigned. Owners always see every company of their business and have no rows here.

| Column | Notes |
|---|---|
| user_id, company_id | primary key; both cascade on delete |
| business_id | must equal the user's and the company's business (trigger) |
| full_company | since 0005: true = every shop of the company; false = only shops in the sites listed in `staff_site_access` (the `areas` column was dropped) |
| can_view_transactions | false hides that company's `transactions` |
| created_by | the owner who granted it |

A trigger rejects rows for non-STAFF users and for companies of another business. There are no write policies: the `manage-staff` Edge Function writes through two service-role-only functions, `admin_insert_staff` (users row + assignments) and `admin_set_staff_companies` (replaces the whole set in one transaction). `users.permissions` is left untouched and reserved.

### Policy changes

| Table | Read policy after 0002 |
|---|---|
| tally_companies | business match **and** `can_see_company(id)` |
| shops | business match **and** `can_see_site_shop(company_id, site_id)` (since 0005; was `can_see_area`) |
| transactions | business match **and** `can_see_transactions(company_id)` **and** `can_see_shop(shop_id)` |
| sync_state, sync_logs | business match **and** `can_see_company(company_id)` (run-level `sync_logs` rows with no company: owners only) |
| users | own row (even when disabled), or all users of the business for an owner |
| staff_company_access | owners: all rows of the business; staff: their own |

The helpers are `security definer`. They return true for an active owner, and for an active staff member only through a matching assignment. The views are `security_invoker`, so `v_company_summary` for a staff member lists only their companies, with totals covering only their shops.

## Sites and staff visits (migration 0005)

Migration: `db/migrations/0005_sites_visits.sql`. **Not additive**: staff access by Tally area is replaced by access by site, so the mobile app and the staff service (`manage-staff`) must be deployed with it. The sync service is unaffected (it never writes `shops.site_id`). Checks: `db/tests/sites_visits.sql`, plus the updated `rls_mobile.sql` and `overdue.sql` (all rolled back).

| Table / column | Content |
|---|---|
| `sites` | Owner-made named group of shops in one company; name unique per company (case-insensitive). Owners write directly (RLS); staff read the sites they have. |
| `shops.site_id` | The shop's site (at most one). Changed only through `set_site_shops(site, shop_ids[])` (owners). |
| `staff_company_access.full_company` | Whole company, or only the sites in `staff_site_access`. Shops in no site: owners and full-company staff only. |
| `staff_site_access` | `(user_id, site_id)`; written by `admin_set_staff_companies` (`p_companies[].full_company`, `site_ids`). |
| `users.requires_check_in` | Staff member must check in at shops on planned days (set by `manage-staff` `set_check_in`). |
| `businesses.timezone` | Business clock for visit days (`business_today()`), default `Asia/Kolkata`. |
| `shop_locations` | Shop pin: lat/lng, radius 5–2000 m (default 100; 5 m allowed since `0006_small_radius.sql`). Written by `set_shop_location` / `clear_shop_location` (owners) or an approved suggestion. |
| `shop_location_suggestions` | A staff member's position at an unpinned shop; `review_location_suggestion(id, approve, radius)` (owners). |
| `visit_plans` | Site + staff member + one date, or a weekday from `starts_on` to `ends_on`. Owners write directly; a trigger requires active staff with check-in on who have the site. |
| `visit_tasks` | One shop per staff member per day, made by `ensure_visit_tasks(from, to)`; days before today are only added to, later unvisited tasks follow the current plans. Shop and site names are copied. |
| `shop_visits` | One per task, insert-only through `check_in(task, lat, lng, accuracy, is_mocked, developer_mode, note)`: server time and distance, status `verified`, `location_pending` (no pin yet) or `unverified` (suggestion rejected / outside the approved pin). One note can be added the same day with `add_visit_note`. |
| `visit_failed_attempts` | Rejected check-ins (`mock_location`, `developer_options`, `poor_accuracy` > 50 m, `out_of_range`); owners read only. |

Functions for the app: `site_report(company, from, to)` (per site: shops, shops with dues, outstanding, advance, sales, returns, collections; money is null without transaction access; a null-site row for shops in no site), `overdue_shops` (now returns `site_id`, `site_name`), and the view `v_visit_tasks` (each task with its visit and a `state`: `verified`, `location_pending`, `unverified`, `pending` or `missed`). `v_shop_outstanding` gains `site_id`, `site_name`.

## Suppliers, stock and purchases (migration 0003)

Migration: `db/migrations/0003_purchasing.sql` (additive). Written by the sync service after shops and transactions; each part can be switched off on the Cloud Sync page (step 4) or with `SYNC_SUPPLIERS`, `SYNC_PURCHASES`, `SYNC_INVENTORY` in `.env`. A failure in these steps is a warning: the company is still `SYNCED`, the error goes to that entity's `sync_state` row and to the sync log (`error_code = STEP_WARNINGS`).

| Table | Key | Content | How it is synced |
|---|---|---|---|
| `suppliers` | `(company_id, tally_ledger_id)` | Ledgers under `SUPPLIER_GROUPS` (default Sundry Creditors): contact, GSTIN, opening and current balance. `payable` is signed: > 0 we owe the supplier (Cr), < 0 advance paid (Dr). | Full snapshot every run; missing ledgers soft-deleted. |
| `stock_items` | `(company_id, tally_item_id)` | Name, part no. (`aliases`), stock group, unit, opening and closing qty and value, Tally valuation rate, reorder level, `stock_status` (`in_stock`, `low`, `zero`, `negative`). | Full snapshot every run; missing items soft-deleted. |
| `purchases` | `(company_id, tally_voucher_id)` | One row per purchase bill (voucher types deriving from Purchase): date, voucher and supplier bill no., `supplier_id` (null when the party is not a synced supplier) and `supplier_name`, taxable / tax & other / total, qty, `ledger_entries` jsonb. | Incremental by AlterID (`sync_state.last_cursor` for `purchases`); a full read every `fullReconcileHours` soft-deletes bills deleted in Tally. Cancelled or optional bills are soft-deleted. |
| `purchase_lines` | `(purchase_id, line_no)` | Item lines: `stock_item_id` (null if not a synced item), `item_name`, godown, qty, rate, discount %, amount. | Replaced wholesale whenever their bill is synced. |

`sync_state.entity_type` gains `suppliers`, `stock_items`, `purchases`.

Read access: `suppliers`, `purchases` and `purchase_lines` are **owner only**. `stock_items` is readable by the owner and by staff assigned to the company.

Views: `v_stock_items` (each active item with its last purchase date, rate and supplier) and `v_purchases_by_supplier_month`.

Example queries for the mobile app:

```sql
-- Stock on hand, highest value first
select name, closing_qty, unit, closing_value, stock_status, last_purchase_rate
from v_stock_items where company_id = :company and closing_qty > 0 order by closing_value desc;

-- What we owe suppliers
select name, payable from suppliers
where company_id = :company and deleted_at is null and payable > 0 order by payable desc;

-- Purchase history of one item
select p.purchase_date, p.supplier_name, l.qty, l.rate, l.amount
from purchase_lines l join purchases p on p.id = l.purchase_id and p.deleted_at is null
where l.stock_item_id = :item order by p.purchase_date desc;
```

Verified on 28 Sep 2026 against the live project: first run created 19 suppliers, 592 stock items and 442 bills for the two companies; the next run found every row in place (updated only, nothing created or deleted).

## Privileges, migrations and data retention (migration 0009)

Migration: `db/migrations/0009_lockdown.sql`. Checks: `db/tests/privileges.sql` (catalog), `db/tests/retention.sql`. Apply **only after every app and PC uses the app API**: the old PostgREST data API relied on the grants it removes.

**Who may do what** (enforced by `tests/privileges.sql`):

| Role | Tables |
|---|---|
| `anon` | Nothing (no table, function, schema or temp rights). The app API never uses it. |
| `authenticated` | `SELECT` on every table and view except `schema_migrations`, `revoked_devices`; RLS picks the rows. Writes: `sites` INSERT (`id, business_id, company_id, name`), UPDATE (`name`), DELETE; `visit_plans` INSERT (`id, business_id, site_id, staff_id, plan_date, weekday, starts_on, ends_on`), UPDATE (`active`), DELETE; `users` UPDATE (`name, is_active, requires_check_in`). Everything else goes through `SECURITY DEFINER` functions (`check_in`, `set_site_shops`, `set_shop_location`, `set_stock_minimum`, …). |
| `service_role` | `SELECT, INSERT, UPDATE, DELETE` (no `TRUNCATE`/`TRIGGER`/`REFERENCES`); `service_status` read-only; nothing on `schema_migrations`, `revoked_devices`. |

No API role may create temporary tables, and `PUBLIC` cannot connect to a business database (only `<slug>_api` and `<slug>_auth`). Every `SECURITY DEFINER` function runs with `search_path = public, pg_temp`; no WholeFlow function is executable by `anon`/`PUBLIC`.

RLS policies call `current_business_id()`, `is_owner()` and `auth.uid()` as `(select …)`, so each is evaluated once per query; for owners the per-row `can_see_*` checks are skipped (they are always true for owners).

**Writing a new migration**

- Keep the `begin;` … `commit;` lines (each on a line of its own). `migrate.sh` removes them and runs the file in one transaction together with its `schema_migrations` row and `lock_timeout = 10s`, so a file is applied and recorded, or neither. A file cannot commit part-way (no `create index concurrently`, no `vacuum`).
- New tables get **no** rights for `authenticated` by default: `alter table … enable row level security`, add policies, then `grant select` (and any write, column-limited) explicitly, and update `tests/privileges.sql` when a write is added. `service_role` gets read/write by default.
- New functions: `revoke all on function … from public, anon;` then grant `authenticated` / `service_role` as needed; `SECURITY DEFINER` functions must `set search_path = public, pg_temp`.
- `migrate.sh` dumps the business database to `/var/backups/wholeflow/pre-migrate/<date>/` before applying anything to a database that already has migrations (kept 14 days), runs one at a time (`flock`), carries on with the other businesses when one fails and exits non-zero with a summary.

**Data retention** — `public.purge_old_data()`, run daily per business database as `postgres` (`select public.purge_old_data();`; returns counts as jsonb). Not executable by `anon`/`authenticated`. Periods (constants in the function):

| Data | Kept | Then |
|---|---|---|
| `shop_visits.device_lat`, `device_lng` (staff GPS position at check-in) | 12 months after `checked_in_at` | set to null; the visit (time, status, distance, accuracy, note) stays |
| `visit_failed_attempts` | 12 months after `attempted_at` | deleted |
| `shop_location_suggestions` with status `rejected` | 12 months after `reviewed_at` | deleted (pending ones are kept; approved ones are the shop's pin) |
| `sync_logs` | 180 days after `started_at` | deleted |

Change a period by a new migration that redefines the function, and update this table.

## Future backends

The sync engine only depends on `internal/cloud.Provider`. A different PostgreSQL host, a custom REST API or another database can reuse this schema shape; the identity columns (`tally_company_id`, `tally_ledger_id`, `tally_voucher_id` + `tally_ledger_id`) and the soft-delete convention are what the engine relies on.
