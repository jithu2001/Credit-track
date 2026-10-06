-- WholeFlow Tally Sync — initial schema for Supabase (PostgreSQL 15+).
--
-- Multi-tenant: every business-owned row carries business_id. Row Level
-- Security lets owners/staff (Supabase Auth users mapped through public.users)
-- read only their own business. Nothing here grants write access to
-- authenticated users: only the sync service, using the service-role key
-- (which bypasses RLS), writes business data. The service-role key must never
-- be embedded in the mobile app.
--
-- Apply with the Supabase SQL editor or `supabase db push`.

begin;

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------- helpers

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ---------------------------------------------------------------- tenants & users

create table public.businesses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- One row per Supabase Auth user. Owners are created by the developer (or an
-- onboarding flow); staff are created by their owner. permissions is reserved
-- for per-staff restrictions (e.g. {"areas": ["Pala"], "transactions": false}).
create table public.users (
  id           uuid primary key references auth.users (id) on delete cascade,
  business_id  uuid not null references public.businesses (id) on delete cascade,
  role         text not null check (role in ('OWNER', 'STAFF')),
  name         text not null default '',
  email        text,
  is_active    boolean not null default true,
  permissions  jsonb not null default '{}'::jsonb,
  created_by   uuid references public.users (id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index users_business_idx on public.users (business_id);

-- ---------------------------------------------------------------- Tally side

create table public.tally_connections (
  id                  uuid primary key default gen_random_uuid(),
  business_id         uuid not null references public.businesses (id) on delete cascade,
  machine_identifier  text not null,
  hostname            text,
  tally_host          text,
  tally_port          integer,
  status              text not null default 'unknown',
  app_version         text,
  last_seen_at        timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (business_id, machine_identifier)
);

create table public.tally_companies (
  id                   uuid primary key default gen_random_uuid(),
  business_id          uuid not null references public.businesses (id) on delete cascade,
  connection_id        uuid references public.tally_connections (id) on delete set null,
  tally_company_id     text not null,                 -- Tally company GUID (stable across renames)
  company_name         text not null,
  company_number       text,
  financial_year_from  date,
  books_from           date,
  ending_at            date,
  period_from          date,
  period_to            date,
  last_voucher_date    date,
  enabled              boolean not null default true,
  sync_enabled         boolean not null default true,
  last_sync_at         timestamptz,
  sync_status          text not null default 'PENDING',
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (business_id, tally_company_id)
);
create index tally_companies_business_idx on public.tally_companies (business_id);

-- ---------------------------------------------------------------- current state: shops

create table public.shops (
  id                      uuid primary key default gen_random_uuid(),
  business_id             uuid not null references public.businesses (id) on delete cascade,
  company_id              uuid not null references public.tally_companies (id) on delete cascade,
  tally_ledger_id         text not null,              -- Tally ledger GUID
  tally_master_id         integer,
  tally_alter_id          bigint,
  name                    text not null,
  aliases                 text[] not null default '{}',
  ledger_group            text,
  phone                   text,                       -- primary phone
  phones                  text[] not null default '{}',
  phone_source            text,                       -- 'ledger' | 'address'
  contact_person          text,
  email                   text,
  gstin                   text,
  gst_registration_type   text,
  address                 text,                       -- lines joined with newlines
  address_lines           text[] not null default '{}',
  state                   text,
  pincode                 text,
  country                 text,
  area                    text,                       -- derived from the ledger name, not a Tally field
  opening_balance_amount  numeric(14,2) not null default 0,
  opening_balance_type    text not null default '' check (opening_balance_type in ('DR', 'CR', '')),
  balance_amount          numeric(14,2) not null default 0,
  balance_type            text not null default '' check (balance_type in ('DR', 'CR', '')),
  receivable              numeric(14,2) not null default 0, -- signed: > 0 means the shop owes the business
  tally_updated_at        timestamptz,                -- reserved: Tally exposes no reliable modification time
  synced_at               timestamptz not null,
  deleted_at              timestamptz,                -- soft delete: set when Tally no longer lists the ledger
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (company_id, tally_ledger_id)
);
create index shops_business_idx on public.shops (business_id);
create index shops_company_active_idx on public.shops (company_id) where deleted_at is null;
create index shops_receivable_idx on public.shops (company_id, receivable desc) where deleted_at is null;
create index shops_area_idx on public.shops (company_id, area) where deleted_at is null;

-- ---------------------------------------------------------------- history: transactions

create table public.transactions (
  id                 uuid primary key default gen_random_uuid(),
  business_id        uuid not null references public.businesses (id) on delete cascade,
  company_id         uuid not null references public.tally_companies (id) on delete cascade,
  shop_id            uuid not null references public.shops (id) on delete cascade,
  tally_voucher_id   text not null,                   -- Tally voucher GUID
  tally_ledger_id    text not null,                   -- shop ledger GUID (a voucher can touch several shops)
  tally_master_id    bigint,
  tally_alter_id     bigint,                          -- Tally's change counter: the incremental sync cursor
  transaction_date   date not null,
  voucher_number     text,
  voucher_type       text,                            -- as named in Tally, e.g. "JK RECEIPT"
  base_voucher_type  text,                            -- predefined type it derives from, e.g. "Receipt"
  category           text not null check (category in ('sales', 'receipts', 'returns', 'adjustments')),
  narration          text,
  debit              numeric(14,2) not null default 0, -- raises what the shop owes
  credit             numeric(14,2) not null default 0, -- lowers it
  amount             numeric(14,2) not null default 0, -- signed effect on receivable = debit - credit
  synced_at          timestamptz not null,
  deleted_at         timestamptz,                     -- soft delete: voucher deleted/cancelled/no longer touches the shop
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  unique (company_id, tally_voucher_id, tally_ledger_id)
);
create index transactions_business_idx on public.transactions (business_id);
create index transactions_shop_date_idx on public.transactions (shop_id, transaction_date desc) where deleted_at is null;
create index transactions_company_date_idx on public.transactions (company_id, transaction_date desc) where deleted_at is null;
create index transactions_voucher_idx on public.transactions (company_id, tally_voucher_id);

-- ---------------------------------------------------------------- sync bookkeeping

create table public.sync_state (
  id                       uuid primary key default gen_random_uuid(),
  business_id              uuid not null references public.businesses (id) on delete cascade,
  company_id               uuid not null references public.tally_companies (id) on delete cascade,
  entity_type              text not null check (entity_type in ('company', 'shops', 'transactions')),
  last_successful_sync_at  timestamptz,
  last_attempt_at          timestamptz,
  last_cursor              text,                      -- transactions: highest Tally AlterID synced
  records_processed        integer not null default 0,
  status                   text not null default 'ok' check (status in ('ok', 'error')),
  error_code               text,
  error_message            text,
  updated_at               timestamptz not null default now(),
  unique (company_id, entity_type)
);

create table public.sync_logs (
  id                    uuid primary key default gen_random_uuid(),
  business_id           uuid not null references public.businesses (id) on delete cascade,
  company_id            uuid references public.tally_companies (id) on delete cascade,
  started_at            timestamptz not null,
  completed_at          timestamptz,
  status                text not null check (status in ('success', 'partial', 'failed', 'skipped')),
  mode                  text,                         -- full | incremental | reconcile
  records_processed     integer not null default 0,
  records_created       integer not null default 0,
  records_updated       integer not null default 0,
  records_deleted       integer not null default 0,
  records_failed        integer not null default 0,
  shops_processed       integer not null default 0,
  transactions_fetched  integer not null default 0,
  error_code            text,
  error_message         text,
  created_at            timestamptz not null default now()
);
create index sync_logs_company_idx on public.sync_logs (company_id, started_at desc);
create index sync_logs_business_idx on public.sync_logs (business_id, started_at desc);

-- ---------------------------------------------------------------- updated_at triggers

do $$
declare t text;
begin
  foreach t in array array['businesses','users','tally_connections','tally_companies','shops','transactions','sync_state']
  loop
    execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ---------------------------------------------------------------- Row Level Security

create or replace function public.current_business_id()
returns uuid language sql stable security definer set search_path = public as $$
  select business_id from public.users where id = auth.uid() and is_active
$$;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.users where id = auth.uid() and role = 'OWNER' and is_active)
$$;

grant execute on function public.current_business_id() to authenticated;
grant execute on function public.is_owner() to authenticated;

alter table public.businesses         enable row level security;
alter table public.users              enable row level security;
alter table public.tally_connections  enable row level security;
alter table public.tally_companies    enable row level security;
alter table public.shops              enable row level security;
alter table public.transactions       enable row level security;
alter table public.sync_state         enable row level security;
alter table public.sync_logs          enable row level security;

-- Tenant read access (owner and staff). Staff-level restrictions on top of
-- this (e.g. by area) are a future policy driven by users.permissions.
create policy businesses_read on public.businesses for select to authenticated
  using (id = public.current_business_id());

create policy users_read on public.users for select to authenticated
  using (business_id = public.current_business_id());

-- Owners manage staff of their own business; nobody can change their own role.
create policy users_owner_insert on public.users for insert to authenticated
  with check (business_id = public.current_business_id() and public.is_owner() and role = 'STAFF');
create policy users_owner_update on public.users for update to authenticated
  using (business_id = public.current_business_id() and public.is_owner() and role = 'STAFF')
  with check (business_id = public.current_business_id() and role = 'STAFF');

-- Machine details of the Tally PC are for the owner only.
create policy connections_owner_read on public.tally_connections for select to authenticated
  using (business_id = public.current_business_id() and public.is_owner());

create policy companies_read    on public.tally_companies for select to authenticated using (business_id = public.current_business_id());
create policy shops_read        on public.shops           for select to authenticated using (business_id = public.current_business_id());
create policy transactions_read on public.transactions    for select to authenticated using (business_id = public.current_business_id());
create policy sync_state_read   on public.sync_state      for select to authenticated using (business_id = public.current_business_id());
create policy sync_logs_read    on public.sync_logs       for select to authenticated using (business_id = public.current_business_id());

-- No policies for anon: anonymous requests see nothing.
revoke all on all tables in schema public from anon;

-- ---------------------------------------------------------------- convenience views (RLS applies via security_invoker)

create view public.v_shop_outstanding with (security_invoker = true) as
  select s.business_id, s.company_id, c.company_name, s.id as shop_id, s.name, s.area, s.phone, s.gstin,
         s.balance_amount, s.balance_type, s.receivable, s.synced_at
  from public.shops s
  join public.tally_companies c on c.id = s.company_id
  where s.deleted_at is null;

create view public.v_company_summary with (security_invoker = true) as
  select c.business_id, c.id as company_id, c.company_name, c.sync_status, c.last_sync_at,
         count(s.id) filter (where s.deleted_at is null)                          as shops,
         count(s.id) filter (where s.deleted_at is null and s.receivable > 0)     as shops_with_dues,
         coalesce(sum(s.receivable) filter (where s.deleted_at is null and s.receivable > 0), 0) as total_outstanding,
         coalesce(-sum(s.receivable) filter (where s.deleted_at is null and s.receivable < 0), 0) as total_credit
  from public.tally_companies c
  left join public.shops s on s.company_id = c.id
  group by c.business_id, c.id, c.company_name, c.sync_status, c.last_sync_at;

grant select on public.v_shop_outstanding, public.v_company_summary to authenticated;

commit;
