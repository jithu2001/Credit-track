-- Enquiries from the product website's contact form (wholeflow.jitsuji.xyz),
-- shown in the admin app under Enquiries.
create table leads (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  business    text not null default '',
  phone       text not null,
  email       text not null,
  companies   text not null default '',   -- "1", "2-3", "4-5", "6+"
  city        text not null default '',
  message     text not null default '',
  source      text not null default 'website',
  ip          text not null default '',
  status      text not null default 'new' check (status in ('new', 'contacted', 'won', 'lost')),
  note        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index leads_created_idx on leads (created_at desc);
create index leads_ip_idx on leads (ip, created_at);
