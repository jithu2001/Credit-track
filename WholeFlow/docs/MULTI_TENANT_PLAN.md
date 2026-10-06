# WholeFlow multi-business hosting plan (Contabo, one database per business)

Status (2026-10-06): phases 0–4 built, deployed and tested (server, control service, admin app, phone apps, Tally PC app). Phase 5: restore drill passed; Supabase support removed from all parts (the owner starts fresh, no data is moved); JMJ is set up as a new business in the admin app. Off-site backups (B2) not set up yet.

## 1. Goal

Sell WholeFlow to many businesses from one server you run:

- each business's data lives in **its own PostgreSQL database**;
- the WholeFlow desktop app (Tally PC) and the Owner/Staff phone apps connect
  with a **reference key** instead of built-in server details;
- you create businesses, keys and subscriptions in an **admin web app**;
  payments are collected **manually** (cash/UPI/bank) for now;
- the apps, screens, SQL migrations and database rules stay as they are.

Out of scope for now: payment gateway (Razorpay), self-service sign-up,
several servers (designed for, not built).

## 2. Architecture

```
Phones (Owner/Staff)          Tally PC (WholeFlow desktop)          You (browser)
   │ 1. reference key → business address + public key                │
   │ 2. login, data: https://api.<domain>/b/<slug>/...                │ https://admin.<domain>
   ▼                                                                  ▼
┌──────────────────────── Contabo VPS (Ubuntu, 8 GB / 4 vCPU) ────────────────────────┐
│ nginx + Let's Encrypt HTTPS                                                          │
│   api.<domain>/control/*            → Control service (Go)                           │
│   api.<domain>/b/<slug>/auth/v1/*   → GoTrue  (one container per business)           │
│   api.<domain>/b/<slug>/rest/v1/*   → PostgREST (one container per business)         │
│   api.<domain>/b/<slug>/functions/v1/manage-staff → Staff service (one, multi-biz)   │
│   admin.<domain>                    → Admin web app (served by the control service)  │
│                                                                                      │
│ PostgreSQL 15 (Docker, not exposed to the internet)                                  │
│   control_db           businesses, keys, plans, payments, admins, audit              │
│   biz_<slug> (one per business) migrations 0001…, auth schema, all business data    │
│   biz_template         an empty, fully migrated database new businesses are copied from │
└──────────────────────────────────────────────────────────────────────────────────────┘
          │ nightly encrypted backups → off-site storage (Backblaze B2 / S3)
```

Why the apps barely change: the GoTrue/PostgREST client libraries
(supabase_flutter, supabase-js) only need a base URL and a public ("anon")
key. For a business with slug `jmj` the base URL is
`https://api.<domain>/b/jmj`; its GoTrue and PostgREST answer at
`/auth/v1` and `/rest/v1`, so every query, RPC and RLS policy works unchanged.

## 3. Per-business stack

| Piece | Detail |
|---|---|
| Database `biz_<slug>` | Copied from `biz_template`; `CONNECT` only for this business's roles |
| Login roles | `<slug>_auth` (owns schema `auth`, used by GoTrue), `<slug>_api` (PostgREST, switches into `anon` / `authenticated` / `service_role`). Shared non-login roles `anon`, `authenticated`, `service_role` exist once on the server |
| Signing secret | Random per business. Its anon key and service key are signed with it, so a token from one business is useless on another. The business service key never leaves the server |
| PC keys | Each Tally PC gets its own key (role `service_role`, claim `device_id`), signed with the business secret. PostgREST's pre-request check refuses keys listed in `revoked_devices`, so one PC can be cut off without touching the others |
| Service status | A one-row table `service_status` (paid_until, grace_until, status, message, contact) in each business database, written only by the control service. The pre-request check refuses every API request once access has ended (section 5.4) |
| GoTrue | Own container; sign-up disabled (accounts are made by the owner/desktop/admin); email + password logins |
| PostgREST | Own container; schema `public`; OpenAPI listing off |
| Memory | ~60–100 MB per business (two containers) → about 50–60 businesses per 8 GB server |

## 4. Control database (`control_db`)

| Table | Columns (main) |
|---|---|
| `businesses` | id, slug, name, phone, email, status (`active` / `suspended` / `closed`), server, db_name, base_url, anon_key, service_key (encrypted), jwt_secret (encrypted), schema_version, created_at |
| `reference_keys` | key (e.g. `JMJ-7K4Q-92XD`), business_id, active, created_at, revoked_at |
| `desktop_activations` | business_id, one-time code, expires_at, used_at, used_by_device |
| `devices` | id, business_id, machine name, Windows user, app version, activated_at, last_seen_at, revoked_at |
| `plans` | code, name, max_companies, price_month (₹) |
| `subscriptions` | business_id, plan_code, paid_until, grace_days, notes |
| `payments` | business_id, amount, paid_on, mode (cash / UPI / bank / other), reference, period_from, period_to, recorded_by, note |
| `admins` | id, email, password_hash, totp_secret (later), last_login. Also the login for every Tally PC's page (section 5.3) |
| `audit_log` | at, admin_id, business_id, action, details |
| `lookups` | reference-key lookups (key, ip, at, ok) for rate limiting and abuse checks |

Secrets (service keys, JWT secrets) are encrypted with a master key kept in the
server's `.env`, never in the database dump in clear text.

## 5. Flows

### 5.1 Create a business (admin app, one click)
1. Enter name, slug, plan, contact, number of Tally companies.
2. Control service: create roles → `CREATE DATABASE biz_<slug> TEMPLATE biz_template`
   → generate secret and keys → write container config → start GoTrue and
   PostgREST → add nginx route and reload → health-check.
3. Create the owner account (email + temporary password, must change at
   first login) and the `businesses` / `users` rows in the business database.
4. Show: **reference key**, **desktop activation code** (valid 48 h), owner login.

### 5.2 Phone apps connect
1. First launch: "Connect to your business" → enter (or scan QR of) reference key.
2. `GET /control/connect?key=…` → `{name, base_url, anon_key, status}`.
3. App shows "Connect to **JMJ Marketing**?" → saves the connection → normal login.
4. Settings → "Switch business" clears it. Staff of several businesses can switch.
5. A reference key alone reads nothing: a login is still required.

### 5.3 Desktop app (Tally PC) connects

**Login to the PC's page** (`http://127.0.0.1:8080`, used only by you): the
first-run "create an admin account" step is removed. The page asks for an
account from `control_db.admins` (email + password), checked by
`POST /control/login`. One set of accounts for every customer PC, managed in
the admin app. Every sign-in is checked by the server; there is no local
account and no offline login (both removed in 0.4.1 so the PC can't be opened
without the server). The background sync needs no login.

The cloud connection then changes as follows:

1. Admin app: create business → shows reference key + **activation code**
   (single use, valid 48 h). "Add PC" issues a new code for a second or
   replacement PC.
2. Cloud Sync page: enter reference key + activation code →
   `POST /control/activate`.
3. Control service checks the code (unused, not expired, same business,
   business not closed), records the PC in `devices`, and returns business id,
   base URL and a **PC key** made for this PC only. The code is used up.
4. The PC stores them encrypted with Windows DPAPI (as the service key is today),
   then: test connection → tick Tally companies → sync as today, in the background.
5. Each sync reports app version and "last seen" to the control service.
6. Admin app → PCs → **Revoke**: the PC's key is refused from the next request;
   other PCs of the business keep working.

The PC is not where subscriptions are shown (nobody looks at it). It obeys the
same server-side stop as the apps (section 5.4): when access ends its sync
requests are refused, it pauses and logs "Subscription ended", and it resumes
by itself once you record a payment. The plan's company limit is checked when
companies are ticked and before each sync.

### 5.4 Subscription (manual collection) — shown and enforced in the phone apps

The business sees its subscription **in the Owner and Staff apps**, because the
Tally PC runs unattended.

- Record a payment in the admin app → extends `paid_until`; the control service
  writes the new dates into that business's `service_status` immediately.
- States and what each person sees:

| State | When | Owner app | Staff app | Tally PC sync |
|---|---|---|---|---|
| Active | paid_until ≥ today | Normal | Normal | Runs |
| Renewal due | 7 days before paid_until | Banner: "Subscription ends on 12 Nov. Pay ₹800 to <your UPI / phone>" | Normal | Runs |
| Grace | paid_until passed, up to `grace_days` (default 7) | Red banner on every screen: "Subscription ended on 12 Nov. The app stops on 19 Nov." | Banner: "Ask your owner to renew WholeFlow" | Runs |
| Ended | after grace, or you press **Suspend** | Full-screen block: "Subscription ended", your contact and payment details, Refresh button. No data shown | Full-screen block: "WholeFlow is paused for this business. Ask your owner." | Refused, pauses |
| Closed | you close the business | Same block; data kept 90 days | Same block | Refused |

- **Enforced on the server, not only in the apps.** Every API request goes
  through a PostgREST pre-request check that reads `service_status`; once access
  has ended it fails with HTTP 402 and a `subscription_ended` code. Old app
  versions, a phone with the wrong date, or a direct API call are blocked the
  same way. Login still works, so the app can show the right message.
- The apps read `service_status` at login, on resume and with each refresh, and
  turn a 402 into the block screen at once. When you record a payment, the
  next refresh (or Refresh button) unblocks everyone; nothing to reinstall.
- Banner texts, your UPI id and phone come from `service_status.message` /
  `contact`, so you can change them in the admin app.
- Closed businesses: data kept 90 days, then exported for the customer and dropped.

### 5.5 Database updates
- Business databases record applied migrations in `schema_migrations`.
- Release a new migration → admin app "Update all" → applied to `biz_template`
  and every business database in turn, stops and reports on the first failure.
- Apps read the schema version; if the app is too old/new → "Please update".

### 5.6 Staff management (`manage-staff`)
One staff service for all businesses: it reads the slug from the URL, loads that
business's base URL and service key from `control_db`, then runs the existing
handler logic unchanged (it already isolates storage behind an interface).

## 6. Changes per part

| Part | Change | Size |
|---|---|---|
| Phone apps | Connect screen (key/QR), saved connection, switch business; subscription banners (owner: renewal due / grace; staff: grace) and full-screen block for both on HTTP 402; schema-version check. No server address or key built in | M |
| Desktop app | Login against `control_db.admins` instead of the first-run local account (checked by the server at every sign-in; no offline or local login); Cloud Sync: reference key + activation code only; stores its PC key encrypted; pauses on 402 and resumes by itself; company-limit check; reports version / last seen | M |
| Business database | `service_status`, `revoked_devices`, pre-request check function (new migration) | S |
| SQL migrations | None (0001–0006 as they are) + `schema_migrations` tracking | S |
| manage-staff | Wrapped in a multi-business service (Deno) | S |
| New: control service (Go) | Provisioning, connect/activate/status API, migration runner, admin web app | L |
| New: server kit | Compose files, nginx, scripts, backups, monitoring | M |

## 7. Security

- HTTPS only (Let's Encrypt via nginx, auto-renew). PostgreSQL bound to localhost.
- Firewall: 22 (SSH keys only), 80, 443. Fail2ban. Automatic security updates.
- Admin app on its own subdomain, strong password, login rate limit; optional
  IP allow-list; 2FA later.
- Reference-key lookups rate-limited per IP; keys are long and random; can be revoked.
- Activation codes single-use, short-lived. Each PC has its own key, revocable on its own; the business service key never leaves the server.
- Per-business database roles and signing secrets; Postgres `CONNECT` revoked from `PUBLIC`.
- Secrets encrypted at rest with a master key; `.env` readable by root only.

## 8. Backups and monitoring

- Nightly `pg_dump` of every business database and `control_db`, encrypted (age/GPG),
  uploaded to Backblaze B2 / S3; keep 14 daily + 8 weekly.
- Monthly restore test into a scratch database (scripted).
- Per-business "Download backup" in the admin app (customer data export).
- Uptime monitor (UptimeRobot, free) on `/control/health` and one business API.
- Disk / memory alerts; log rotation.

## 9. JMJ on the new server

Decided: start fresh, nothing is moved from the old Supabase project, and
Supabase support is removed from every part (Tally PC app 0.5.0, phone apps,
staff service).

1. Create business `jmj` in the admin app.
2. Install the current Tally PC release on JMJ's PC and connect it with the
   reference key + activation code; the first sync uploads everything from Tally.
3. Owner and staff install the apps and connect with the reference key; the
   owner adds staff, sites, shop pins and visit plans again in the Owner app.
4. Cancel the old Supabase project.

## 10. Phases

| # | Phase | Deliverables | Done when | Time |
|---|---|---|---|---|
| 0 | Server | Domain DNS, Contabo VPS, Docker, Postgres, nginx + HTTPS, firewall, backups to B2 | `https://api.<domain>` answers; a backup lands in B2 and restores | 1–2 d |
| 1 | One business by hand | Script that makes `biz_<slug>` + GoTrue + PostgREST; migrations 0001–0006; existing SQL tests pass on it; apps built with that URL work on the phone | Owner and Staff apps work against `/b/jmj` | 2–3 d |
| 2 | Control service | `control_db`, provisioning API, connect / activate / status, migration runner, multi-business manage-staff | A new business is created by one API call | 4–6 d |
| 3 | Admin web app | Businesses, reference keys, activation codes, PCs (list, revoke), plans, payments, status, suspend, update-all, download backup | You can onboard a business and record a payment in the browser | 3–4 d |
| 4 | App changes | Phone connect screen, subscription banners and block screen; desktop activation, PC key, pause/resume on 402, company limit | Fresh phone + fresh PC connect with only a reference key; ending a subscription blocks both apps and the sync, recording a payment unblocks them | 3–4 d |
| 5 | Cut-over | JMJ set up fresh, phone tests with both logins, restore drill, docs, Supabase removed | JMJ runs on Contabo | 1–2 d |

Total ≈ 3 weeks of work. Each phase is usable and tested before the next.

## 11. Costs (approximate)

| Item | ₹/month |
|---|---|
| Contabo VPS 8 GB / 4 vCPU | ~600–900 |
| Domain (₹200–900 / year) | ~20–75 |
| Off-site backups (B2, few GB) | ~50–200 |
| Uptime monitoring | 0 |
| **Total** | **~700–1,200** for up to ~50 businesses |

## 12. Decisions needed

1. Domain name (and `api.` / `admin.` subdomains).
2. Contabo location (nearest to Kerala; test latency first).
3. Plans: price and company limit per plan (e.g. ₹500 / 1 company, ₹800 / 3, ₹1,000 / 5).
4. Grace period (default 7 days), reminder lead time (default 7 days), and the payment details shown to owners (UPI id, phone).
5. Reference-key format and whether the owner can see/regenerate it in the Owner app.
6. ~~Keep or drop the old Supabase project~~ Decided: drop it; start fresh.
