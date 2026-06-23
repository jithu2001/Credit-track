# WholesaleTrack

A single-file React wholesale creditor (accounts-receivable) manager backed by
Supabase. No build tools — it runs straight from `index.html` and deploys to
Vercel as a static site for free.

## Files

| File | Purpose |
|------|---------|
| `index.html` | Loads React, ReactDOM and Babel from CDN, then mounts the app. |
| `app.jsx` | The entire application — custom Supabase REST client, auth, dashboard, statement view, and inline styling. Exports a default `App` component. |
| `vercel.json` | Serves `app.jsx` with the right content type. |

## 1. Create the database (free Supabase)

1. Sign up at [supabase.com](https://supabase.com) and create a **New Project**.
2. Open the **SQL Editor** and run the schema below (also shown in the in-app
   setup wizard with a copy button):

```sql
create table if not exists wt_creditors (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  contact text,
  address text,
  username text not null unique,
  password text not null,
  created_at timestamptz default now()
);

create table if not exists wt_transactions (
  id uuid primary key default gen_random_uuid(),
  creditor_id uuid references wt_creditors(id) on delete cascade,
  date date not null,
  type text not null check (type in ('invoice','payment')),
  description text not null,
  amount numeric(12,2) not null,
  created_at timestamptz default now()
);

create table if not exists wt_settings (
  key text primary key,
  value text not null
);
insert into wt_settings (key, value) values ('admin_password', '0000')
  on conflict (key) do nothing;
insert into wt_settings (key, value) values ('staff_password', '9999')
  on conflict (key) do nothing;

alter table wt_creditors    enable row level security;
alter table wt_transactions enable row level security;
alter table wt_settings     enable row level security;
create policy "allow_all_creditors"    on wt_creditors    for all using (true) with check (true);
create policy "allow_all_transactions" on wt_transactions for all using (true) with check (true);
create policy "allow_all_settings"     on wt_settings     for all using (true) with check (true);
```

> **Already deployed before the password feature?** Run just the
> `wt_settings` block above in the SQL Editor to add it. Until you do, login
> still works with the default `admin`/`0000` and `staff`/`9999`, but admin/staff
> password changes won't persist.

3. In **Project Settings → API**, copy your **Project URL** and **anon public key**.

## 2. Run locally

Because the app loads ES modules, open it through a tiny static server rather
than `file://`:

```bash
npx serve .
# or
python -m http.server 8000
```

Then visit the URL, complete the 3-step setup wizard (URL + anon key are stored
in `localStorage`), and you're in.

## 3. Deploy to Vercel (free)

- Push this folder to a Git repo and **Import** it on [vercel.com](https://vercel.com),
  selecting the **Other** framework preset (it's a static site), **or**
- Run `npx vercel` from this folder.

No environment variables are needed — each browser stores its own Supabase
connection. To re-enter credentials, use **Reconnect to Supabase** on the login
screen.

## Logins

| Role | Username | Password | Access |
|------|----------|----------|--------|
| Admin | `admin` | `0000` | Full read/write, sees shop credentials |
| Staff | `staff` | `9999` | Read-only across everything, no credentials |
| Shop | *(per shop)* | *(per shop)* | Read-only statement for that shop only |

Shop credentials are created by the admin via **+ Shop**.

`0000` and `9999` are only the **initial** admin/staff passwords. Every role can
change its own password via the **Password** button (top bar for admin/staff and
shop). Admin/staff changes are stored in `wt_settings`; shop changes update the
shop's `wt_creditors` row — both persist across devices.

## Notes

- Amounts are formatted as Indian Rupees with Indian digit grouping
  (`₹ 12,34,567.89`).
- Balance = sum of invoices − sum of payments per shop.
- Passwords are stored in plain text in the database to match the brief's
  "admin can see shop credentials" requirement. This is fine for an internal
  tool, but do **not** reuse real/sensitive passwords here.


