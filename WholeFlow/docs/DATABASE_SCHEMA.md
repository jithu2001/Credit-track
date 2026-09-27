# Database Schema (Supabase / PostgreSQL)

Migration: `supabase/migrations/0001_init.sql`. Apply it in the Supabase SQL editor or with `supabase db push`.

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
One row per Supabase Auth user; `id` references `auth.users(id)`.

| Column | Type | Notes |
|---|---|---|
| business_id | uuid | tenant |
| role | text | `OWNER` or `STAFF` |
| name, email | text | |
| is_active | boolean | owner can disable staff |
| permissions | jsonb | reserved for staff restrictions, e.g. `{"areas":["Pala"],"transactions":false}` |
| created_by | uuid | the owner who created a staff user |

The developer never has a row here. Owners (and staff) are created from the app's Cloud Sync page, section "Business owner & staff accounts": it calls the Supabase Auth admin API (`POST /auth/v1/admin/users` with `email_confirm: true`) and then inserts the `users` row with the service role; disabling an account sets `is_active = false` and bans the auth user. The manual equivalent is: create the auth user in the dashboard, then `insert into users (id, business_id, role) values (<auth uid>, <business>, 'OWNER')`.

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
- `users`: owners can insert and update `STAFF` rows of their own business (create, rename, disable, set permissions). Nobody can change their own role through RLS.
- No `INSERT`/`UPDATE`/`DELETE` policies exist on data tables for `authenticated`, and `anon` has no grants: only the service-role key (which bypasses RLS) writes data. That key lives only inside the sync service on the customer's PC.

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

## Future backends

The sync engine only depends on `internal/cloud.Provider`. A different PostgreSQL host, a custom REST API or another database can reuse this schema shape; the identity columns (`tally_company_id`, `tally_ledger_id`, `tally_voucher_id` + `tally_ledger_id`) and the soft-delete convention are what the engine relies on.
