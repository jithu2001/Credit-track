-- WholeFlow — suppliers, stock items and purchase bills.
--
-- Additive and safe to run on the live database: four new tables, the new
-- sync_state entity types, read policies and two views. Nothing existing is
-- changed except the sync_state.entity_type check, which is widened.
--
-- Written only by the sync service (service-role key, bypasses RLS), exactly
-- like shops and transactions: upserts keyed by Tally GUIDs, soft deletes
-- (deleted_at) for suppliers, stock items and bills. Bill lines are replaced
-- wholesale whenever their bill is synced.
--
-- Who can read:
--   * suppliers, purchases, purchase_lines: the OWNER only (purchase prices
--     and supplier dues are not staff information);
--   * stock_items: the owner, and staff assigned to the company
--     (staff_company_access), e.g. so a salesman can check stock.
--
-- Apply in the Supabase dashboard: SQL Editor → paste this file → Run.

begin;

-- ---------------------------------------------------------------- suppliers

create table public.suppliers (
  id                      uuid primary key default gen_random_uuid(),
  business_id             uuid not null references public.businesses (id) on delete cascade,
  company_id              uuid not null references public.tally_companies (id) on delete cascade,
  tally_ledger_id         text not null,              -- Tally ledger GUID
  tally_master_id         integer,
  tally_alter_id          bigint,
  name                    text not null,
  aliases                 text[] not null default '{}',
  ledger_group            text,                       -- e.g. Sundry Creditors (SUPPLIER_GROUPS)
  phone                   text,
  phones                  text[] not null default '{}',
  contact_person          text,
  email                   text,
  gstin                   text,
  gst_registration_type   text,
  address                 text,
  address_lines           text[] not null default '{}',
  state                   text,
  pincode                 text,
  country                 text,
  opening_balance_amount  numeric(14,2) not null default 0,
  opening_balance_type    text not null default '' check (opening_balance_type in ('DR', 'CR', '')),
  balance_amount          numeric(14,2) not null default 0,
  balance_type            text not null default '' check (balance_type in ('DR', 'CR', '')),
  payable                 numeric(14,2) not null default 0, -- signed: > 0 we owe the supplier (Cr), < 0 advance paid (Dr)
  synced_at               timestamptz not null,
  deleted_at              timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (company_id, tally_ledger_id)
);
create index suppliers_business_idx on public.suppliers (business_id);
create index suppliers_company_active_idx on public.suppliers (company_id) where deleted_at is null;
create index suppliers_payable_idx on public.suppliers (company_id, payable desc) where deleted_at is null;

-- ---------------------------------------------------------------- stock items

create table public.stock_items (
  id              uuid primary key default gen_random_uuid(),
  business_id     uuid not null references public.businesses (id) on delete cascade,
  company_id      uuid not null references public.tally_companies (id) on delete cascade,
  tally_item_id   text not null,                      -- Tally stock item GUID
  name            text not null,
  aliases         text[] not null default '{}',       -- part numbers / alternate names
  stock_group     text,
  category        text,
  unit            text,
  gst_applicable  boolean not null default false,
  opening_qty     numeric(16,3) not null default 0,
  opening_value   numeric(14,2) not null default 0,
  closing_qty     numeric(16,3) not null default 0,
  closing_rate    numeric(14,2) not null default 0,   -- Tally's valuation rate per unit
  closing_value   numeric(14,2) not null default 0,
  reorder_level   numeric(16,3) not null default 0,
  min_order_qty   numeric(16,3) not null default 0,
  stock_status    text not null default 'zero' check (stock_status in ('in_stock', 'low', 'zero', 'negative')),
  synced_at       timestamptz not null,
  deleted_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (company_id, tally_item_id)
);
create index stock_items_business_idx on public.stock_items (business_id);
create index stock_items_company_active_idx on public.stock_items (company_id, name) where deleted_at is null;
create index stock_items_group_idx on public.stock_items (company_id, stock_group) where deleted_at is null;

-- ---------------------------------------------------------------- purchase bills

create table public.purchases (
  id                    uuid primary key default gen_random_uuid(),
  business_id           uuid not null references public.businesses (id) on delete cascade,
  company_id            uuid not null references public.tally_companies (id) on delete cascade,
  tally_voucher_id      text not null,                -- Tally voucher GUID
  tally_alter_id        bigint,                       -- incremental sync cursor
  supplier_id           uuid references public.suppliers (id) on delete set null, -- null when the party is not under SUPPLIER_GROUPS
  supplier_name         text not null default '',     -- party ledger name as in Tally
  purchase_date         date not null,
  voucher_number        text,
  voucher_type          text,                         -- e.g. "Purchase Tcs"
  supplier_bill_number  text,                         -- Tally "Reference"
  narration             text,
  taxable_amount        numeric(14,2) not null default 0, -- sum of the item lines
  tax_and_other_amount  numeric(14,2) not null default 0, -- GST, TCS, freight, round off
  total_amount          numeric(14,2) not null default 0, -- credited to the supplier
  total_qty             numeric(16,3) not null default 0,
  line_count            integer not null default 0,
  ledger_entries        jsonb not null default '[]'::jsonb, -- [{"ledger","amount","type"}], supplier's entry excluded
  synced_at             timestamptz not null,
  deleted_at            timestamptz,                  -- deleted, cancelled or made optional in Tally
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (company_id, tally_voucher_id)
);
create index purchases_business_idx on public.purchases (business_id);
create index purchases_company_date_idx on public.purchases (company_id, purchase_date desc) where deleted_at is null;
create index purchases_supplier_idx on public.purchases (supplier_id, purchase_date desc) where deleted_at is null;

create table public.purchase_lines (
  id                uuid primary key default gen_random_uuid(),
  business_id       uuid not null references public.businesses (id) on delete cascade,
  company_id        uuid not null references public.tally_companies (id) on delete cascade,
  purchase_id       uuid not null references public.purchases (id) on delete cascade,
  line_no           integer not null,
  stock_item_id     uuid references public.stock_items (id) on delete set null,
  item_name         text not null,
  godown            text,
  qty               numeric(16,3) not null default 0,  -- billed quantity
  actual_qty        numeric(16,3) not null default 0,
  unit              text,
  rate              numeric(14,2) not null default 0,
  discount_percent  numeric(6,2) not null default 0,
  amount            numeric(14,2) not null default 0,
  created_at        timestamptz not null default now(),
  unique (purchase_id, line_no)
);
create index purchase_lines_business_idx on public.purchase_lines (business_id);
create index purchase_lines_item_idx on public.purchase_lines (stock_item_id);
create index purchase_lines_company_item_idx on public.purchase_lines (company_id, item_name);

-- ---------------------------------------------------------------- sync bookkeeping

alter table public.sync_state drop constraint if exists sync_state_entity_type_check;
alter table public.sync_state add constraint sync_state_entity_type_check
  check (entity_type in ('company', 'shops', 'transactions', 'suppliers', 'stock_items', 'purchases'));

-- ---------------------------------------------------------------- updated_at triggers

create trigger suppliers_set_updated_at   before update on public.suppliers   for each row execute function public.set_updated_at();
create trigger stock_items_set_updated_at before update on public.stock_items for each row execute function public.set_updated_at();
create trigger purchases_set_updated_at   before update on public.purchases   for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------- Row Level Security

alter table public.suppliers      enable row level security;
alter table public.stock_items    enable row level security;
alter table public.purchases      enable row level security;
alter table public.purchase_lines enable row level security;

create policy suppliers_owner_read on public.suppliers for select to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

create policy purchases_owner_read on public.purchases for select to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

create policy purchase_lines_owner_read on public.purchase_lines for select to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

create policy stock_items_read on public.stock_items for select to authenticated
  using (business_id = public.current_business_id() and public.can_see_company(company_id));

revoke all on public.suppliers, public.stock_items, public.purchases, public.purchase_lines from anon;
grant select on public.suppliers, public.stock_items, public.purchases, public.purchase_lines to authenticated;

-- ---------------------------------------------------------------- views (RLS applies via security_invoker)

-- One row per stock item with its latest purchase.
create view public.v_stock_items with (security_invoker = true) as
  select i.business_id, i.company_id, i.id as stock_item_id, i.name, i.aliases, i.stock_group, i.unit,
         i.closing_qty, i.closing_rate, i.closing_value, i.reorder_level, i.stock_status, i.synced_at,
         lp.purchase_date as last_purchase_date, lp.rate as last_purchase_rate, lp.supplier_name as last_supplier
  from public.stock_items i
  left join lateral (
    select p.purchase_date, l.rate, p.supplier_name
    from public.purchase_lines l
    join public.purchases p on p.id = l.purchase_id and p.deleted_at is null
    where l.stock_item_id = i.id
    order by p.purchase_date desc, p.tally_alter_id desc
    limit 1) lp on true
  where i.deleted_at is null;

-- Purchase totals per supplier and month.
create view public.v_purchases_by_supplier_month with (security_invoker = true) as
  select p.business_id, p.company_id, p.supplier_id, p.supplier_name,
         date_trunc('month', p.purchase_date)::date as month,
         count(*) as bills, sum(p.taxable_amount) as taxable_amount,
         sum(p.tax_and_other_amount) as tax_and_other_amount, sum(p.total_amount) as total_amount
  from public.purchases p
  where p.deleted_at is null
  group by p.business_id, p.company_id, p.supplier_id, p.supplier_name, date_trunc('month', p.purchase_date);

grant select on public.v_stock_items, public.v_purchases_by_supplier_month to authenticated;

commit;
