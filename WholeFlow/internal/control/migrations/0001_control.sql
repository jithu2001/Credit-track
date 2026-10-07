-- control_db: the businesses WholeFlow hosts, their keys, PCs, plans,
-- subscriptions, manual payments, admin accounts and an audit log.
-- Applied by the control service at start-up (schema_migrations).

create extension if not exists pgcrypto;

create table admins (
  id             uuid primary key default gen_random_uuid(),
  email          text not null unique check (email = lower(btrim(email)) and email <> ''),
  name           text not null default '',
  password_hash  text not null,
  disabled       boolean not null default false,
  created_at     timestamptz not null default now(),
  last_login_at  timestamptz
);

create table plans (
  code           text primary key check (code ~ '^[a-z0-9_-]{2,20}$'),
  name           text not null,
  max_companies  integer not null check (max_companies between 1 and 100),
  price_month    numeric(10, 2) not null check (price_month >= 0),
  active         boolean not null default true
);
insert into plans (code, name, max_companies, price_month) values
  ('basic', 'Basic', 1, 500),
  ('standard', 'Standard', 3, 800),
  ('pro', 'Pro', 5, 1000);

create table businesses (
  id                  uuid primary key default gen_random_uuid(),
  slug                text not null unique check (slug ~ '^[a-z][a-z0-9]{1,19}$'),
  name                text not null check (btrim(name) <> ''),
  contact_name        text,
  phone               text,
  email               text,
  status              text not null default 'active' check (status in ('active', 'suspended', 'closed')),
  base_url            text not null,
  anon_key            text not null,
  service_key_sealed  text not null,   -- AES-GCM with the server's master key
  jwt_secret_sealed   text not null,
  auth_port           integer not null,
  tenant_business_id  uuid,            -- businesses.id inside the business database
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  closed_at           timestamptz
);

create table subscriptions (
  business_id  uuid primary key references businesses (id) on delete cascade,
  plan_code    text not null references plans (code),
  paid_until   date not null,
  grace_days   integer not null default 7 check (grace_days between 0 and 60),
  remind_days  integer not null default 7 check (remind_days between 0 and 60),
  updated_at   timestamptz not null default now()
);

create table payments (
  id           uuid primary key default gen_random_uuid(),
  business_id  uuid not null references businesses (id) on delete cascade,
  amount       numeric(10, 2) not null check (amount > 0),
  paid_on      date not null,
  mode         text not null check (mode in ('cash', 'upi', 'bank', 'other')),
  reference    text,
  months       integer not null check (months between 1 and 36),
  period_from  date not null,
  period_to    date not null,
  note         text,
  recorded_by  uuid references admins (id) on delete set null,
  created_at   timestamptz not null default now()
);
create index payments_business_idx on payments (business_id, paid_on desc);

-- Phones find a business by this key; it reads nothing without a login.
create table reference_keys (
  key          text primary key,
  business_id  uuid not null references businesses (id) on delete cascade,
  created_at   timestamptz not null default now(),
  revoked_at   timestamptz
);
create unique index reference_keys_one_active on reference_keys (business_id) where revoked_at is null;

-- Single-use codes for activating a Tally PC; only a hash is stored.
create table activation_codes (
  code_hash    text primary key,
  business_id  uuid not null references businesses (id) on delete cascade,
  expires_at   timestamptz not null,
  used_at      timestamptz,
  used_by      uuid,
  created_by   uuid references admins (id) on delete set null,
  created_at   timestamptz not null default now()
);

create table devices (
  id            uuid primary key default gen_random_uuid(),
  business_id   uuid not null references businesses (id) on delete cascade,
  machine       text not null default '',
  windows_user  text not null default '',
  app_version   text not null default '',
  activated_at  timestamptz not null default now(),
  last_seen_at  timestamptz,
  revoked_at    timestamptz
);
create index devices_business_idx on devices (business_id);

-- Owner-facing text and your contact details for the subscription banners.
create table settings (
  key    text primary key,
  value  text not null
);
insert into settings (key, value) values
  ('renew_message', 'To keep using WholeFlow, pay ₹{price} per month for the {plan} plan.'),
  ('contact', '');

create table audit_log (
  id           bigserial primary key,
  at           timestamptz not null default now(),
  admin_id     uuid references admins (id) on delete set null,
  business_id  uuid references businesses (id) on delete set null,
  action       text not null,
  details      jsonb not null default '{}'::jsonb
);
create index audit_log_business_idx on audit_log (business_id, at desc);

-- Reference-key lookups, for rate limiting and spotting guessing.
create table key_lookups (
  id   bigserial primary key,
  at   timestamptz not null default now(),
  ip   text not null,
  ok   boolean not null
);
create index key_lookups_ip_idx on key_lookups (ip, at desc);
