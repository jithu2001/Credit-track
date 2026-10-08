-- Admin sign-in security: installer accounts, two-step sign-in (TOTP) with
-- one-time backup codes, sessions kept in the database (a restart of the
-- control service no longer signs everyone out), and the app/PC version
-- settings.

-- 'admin': the admin app. 'installer': only signs in on customers' Tally PCs
-- (/control/pc/login), never the admin app.
alter table admins add column role text not null default 'admin' check (role in ('admin', 'installer'));

-- The authenticator secret, sealed with the server's master key (as the
-- business secrets). totp_pending_sealed: made by "set up" and not yet
-- confirmed with a code. totp_last_step: the last 30-second step whose code
-- was used (a code works once).
alter table admins add column totp_secret_sealed text;
alter table admins add column totp_pending_sealed text;
alter table admins add column totp_enabled_at timestamptz;
alter table admins add column totp_last_step bigint not null default 0;

-- One-time codes for a lost phone: SHA-256 of the normalised code.
create table admin_backup_codes (
  admin_id   uuid not null references admins (id) on delete cascade,
  code_hash  text not null,
  used_at    timestamptz,
  created_at timestamptz not null default now(),
  primary key (admin_id, code_hash)
);

-- Admin app sessions: only the SHA-256 of the token is stored. stage 'enrol':
-- signed in with the password but two-step sign-in is not set up yet; such a
-- session may only set it up.
create table admin_sessions (
  token_hash   text primary key,
  admin_id     uuid not null references admins (id) on delete cascade,
  stage        text not null default 'full' check (stage in ('full', 'enrol')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  ip           text not null default ''
);
create index admin_sessions_admin_idx on admin_sessions (admin_id);

-- min_app_build: phones whose app build number (X-App-Version: 1.0.0+<build>)
-- is lower are told to update (0 = off). latest_pc_version: the newest
-- WholeFlow Tally PC release; older PCs are flagged in the admin app.
insert into settings (key, value) values ('min_app_build', '0'), ('latest_pc_version', '')
  on conflict (key) do nothing;
