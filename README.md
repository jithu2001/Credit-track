# WholeFlow (Credit-track)

WholeFlow gives a wholesale business its **shop outstanding balances, sales, stock and staff visits on the phone**, taken straight from **TallyPrime**, and lets you sell it to many businesses as a monthly subscription.

- A small Windows program on the business's **Tally PC** reads Tally (read-only, never writes) and syncs shops, balances, transactions, suppliers, purchases and stock to the cloud every few minutes.
- The **WholeFlow Owner** app shows the owner everything: dashboard, dues and overdue shops, payments, stock, staff, sites and visits.
- The **WholeFlow Staff** app shows staff only the companies and sites they are given, with optional GPS check-in at shops.
- **Your WholeFlow server** hosts every business, each in its own database. An **admin web app** is where you onboard businesses, record payments and block or unblock them.

```
                         ┌──────────────────────── WholeFlow server (Contabo, Ubuntu) ───────────────────────┐
 TallyPrime ─XML─▶ wholeflow.exe ──HTTPS──▶ nginx  api.<domain>/b/<slug>/  ─▶ per business: login (GoTrue)   │
 (customer PC)     (Tally PC app)     │                                         + data API (PostgREST)        │
                                      │                                         + database biz_<slug>         │
 Owner app ─┐                         ├─▶ api.<domain>/control/   ─▶ control service (Go) ─▶ control_db       │
 Staff app ─┴─ reference key ─────────┘   admin.<domain>          ─▶ admin web app (same Go service)         │
                         └────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Contents

1. [The parts](#1-the-parts)
2. [Repository layout](#2-repository-layout)
3. [Words used in this project](#3-words-used-in-this-project)
4. [Fresh setup, step by step](#4-fresh-setup-step-by-step)
   - [4.1 What you need](#41-what-you-need)
   - [4.2 Server](#42-server)
   - [4.3 First business](#43-first-business)
   - [4.4 Tally PC](#44-tally-pc)
   - [4.5 Phone apps](#45-phone-apps)
   - [4.6 Developer machine and tests](#46-developer-machine-and-tests)
5. [Running the service](#5-running-the-service)
6. [Releasing updates](#6-releasing-updates)
7. [Backups and restore](#7-backups-and-restore)
8. [Security](#8-security)
9. [Current status and open items](#9-current-status-and-open-items)
10. [More documentation](#10-more-documentation)

---

## 1. The parts

| Part | Where in the repo | Runs on | What it does |
|---|---|---|---|
| **Tally PC app** `wholeflow.exe` (Go) | [`WholeFlow/cmd/server`](WholeFlow/cmd/server), `WholeFlow/internal/*` | The business's Windows PC with TallyPrime, as a Windows service | Local web app at http://127.0.0.1:8080 (dashboards, shops, outstanding, suppliers, purchases, inventory, exports) and the background **Cloud Sync**. Sign-in uses your WholeFlow admin account. The PC connects to its business with a reference key and a one-time activation code. |
| **Owner app** and **Staff app** (Flutter) | [`wholeflow_app/`](wholeflow_app) (flavors `owner`, `staff`) | Android phones | The owner and staff apps. On first launch they ask for the business's reference key (typed or QR), then show the normal login. They show subscription banners and a "paused" screen when the subscription ends. |
| **Control service + admin app** (Go) | [`WholeFlow/cmd/control`](WholeFlow/cmd/control), [`WholeFlow/internal/control`](WholeFlow/internal/control) (pages in `internal/control/web`) | Server, systemd `wholeflow-control`, 127.0.0.1:8100 | Creates businesses, looks up reference keys for the apps, activates Tally PCs, records manual payments, enforces subscriptions. It also serves the admin web app at `https://admin.<domain>`. |
| **Business databases and APIs** | [`WholeFlow/deploy/server`](WholeFlow/deploy/server) (scripts and templates), [`WholeFlow/db/migrations`](WholeFlow/db/migrations) (schema) | Server, Docker | One PostgreSQL 15 with a database `biz_<slug>` per business. Each business has its own GoTrue (login) and PostgREST (data API) container. The apps reach them with the GoTrue/PostgREST client libraries. |
| **Server kit** | [`WholeFlow/deploy/server`](WholeFlow/deploy/server) | Copied to `/opt/wholeflow` | docker-compose, nginx config, systemd unit, scripts to create, migrate, back up and delete businesses. |

Rules that hold everywhere:

- **Nothing is ever written to Tally.** Only read-only export requests reach Tally, and this is checked in code (see [WholeFlow/README.md](WholeFlow/README.md)).
- **Each business's data is separate.** Each business has its own database, login service, signing secret and database roles, and row-level security separates the owner from staff within it.
- **Subscriptions are enforced on the server, not only in the apps.** Once a subscription has ended, every data request gets HTTP 402.

## 2. Repository layout

```
Credit-track/
├── README.md                     this file
├── IMPLEMENTATION.md             original brief for the mobile app
├── .env                          your VPS login details (git-ignored, chmod 600; never commit)
├── WholeFlow/                    Go module "wholeflow": Tally PC app, control service, server kit, database
│   ├── cmd/server/               wholeflow.exe (Tally PC app) – CLI, Windows service, web server
│   ├── cmd/control/              wholeflow-control (server) – `serve`, `create-admin`
│   ├── internal/
│   │   ├── tally/                the ONLY code that talks to Tally (XML/TDL, read-only allow-list)
│   │   ├── api/, export/         Tally PC web app API, CSV/xlsx
│   │   ├── syncer/               sync engine, scheduler, settings, heartbeat, company limit
│   │   ├── cloud/                cloud contract; cloud/rest = client for the business's API (PostgREST + GoTrue)
│   │   ├── controlclient/        Tally PC → control service (activate, heartbeat, PC login)
│   │   ├── admin/                Tally PC login + Cloud Sync API (/api/sync/*)
│   │   ├── auth/, secrets/       password hashing, sessions, lockout; Windows DPAPI
│   │   └── control/              control service: businesses, keys, PCs, subscriptions, admin API, admin web app (web/)
│   ├── web/static/               Tally PC web app pages (embedded in the exe)
│   ├── db/
│   │   ├── migrations/           0001–0009 business database schema (applied to every business)
│   │   └── tests/                SQL tests + run_local.sh (throwaway Postgres in Docker)
│   ├── deploy/                   Windows installer + release script (Install-WholeFlow.cmd, Build-Release.ps1)
│   ├── deploy/server/            server kit → /opt/wholeflow (compose, nginx, systemd, scripts, templates)
│   └── docs/                     MULTI_TENANT_PLAN, SYNC_SETUP, SYNC_ARCHITECTURE, DATABASE_SCHEMA
├── website/                      product website (wholeflow.jitsuji.xyz): static HTML/CSS/JS, deploy.sh
└── wholeflow_app/                Flutter app (Owner + Staff flavors)
    ├── lib/core/                 connection (reference key, connect screen), env, errors, router, theme, widgets
    ├── lib/features/             auth, dashboard, shops, shop_detail, outstanding, analytics, sites, visits,
    │                             staff, inventory, purchases, suppliers, stock, sync_health, subscription, settings
    ├── env/                      hosted.json (WholeFlow server address)
    └── test/                     unit and widget tests
```

## 3. Words used in this project

| Word | Meaning |
|---|---|
| **Business** | One customer (e.g. JMJ Marketing). It has its own database `biz_<slug>` and its own login and data API. |
| **Short name (slug)** | Lowercase id of a business, 2–20 letters/digits (e.g. `jmj`). It appears in its address `https://api.<domain>/b/jmj` and can't be changed. |
| **Company** | A Tally company synced by the business's PC. Plans limit how many (Basic 1, Standard 3, Pro 5). |
| **Reference key** | E.g. `JMJ-7KQ2-XW9P-4HTD`. The phone apps and the Tally PC use it to find their business. On its own it reads nothing; a login is still needed. You can replace it from the admin app. |
| **Activation code** | E.g. `H2AY-YKK3`. Single use, valid 48 hours. It turns a Tally PC into an authorised PC of one business. |
| **PC key** | The secret each activated Tally PC gets. It is stored encrypted on that PC and can be revoked on its own from the admin app. |
| **Admin account** | Your login for the admin app. The same account signs in on customers' Tally PCs. Stored in `control_db.admins`. |
| **Subscription states** | **Active**. **Renewal due**: 7 days before paid-until, and owners see a banner. **Grace**: up to 7 days after paid-until, with a red banner for everyone. **Ended**: after grace, or when you press Suspend. Both apps then show a "paused" screen, the PC's sync pauses, and the server refuses data with HTTP 402. Recording a payment clears it at the next refresh. |
| **Site** | An owner-made group of shops (replaces Tally areas). Staff can be given whole companies or chosen sites. Visits and GPS check-in are optional per staff member. |

---

## 4. Fresh setup, step by step

Follow these in order to rebuild everything from nothing. The live system was built exactly this way. Replace `example.in` with your domain and `203.0.113.10` with your server's IP throughout. The live values are `jitsuji.xyz` and `75.119.130.27`.

### 4.1 What you need

**Accounts**
- A VPS: Ubuntu 24.04, 4 vCPU / 8 GB RAM (Contabo Cloud VPS 20 or similar). Pick a region close to your customers; India or Singapore gives the lowest latency for Kerala.
- A domain (e.g. from GoDaddy).
- Optional: a Backblaze B2 bucket for off-site backups.

**On your PC (Linux, macOS or Windows)**
- Git, SSH and Docker (Docker is only needed for the SQL tests).
- **Go 1.26+**.
- **Flutter 3.47+** (Dart 3.13+) with the Android SDK, plus `adb` to install on phones.

### 4.2 Server

#### Step 1: DNS

At your domain registrar, make sure the domain uses the registrar's nameservers. Then add two **A records** pointing at the server's IP:

| Type | Name | Value |
|---|---|---|
| A | `api` | `203.0.113.10` |
| A | `admin` | `203.0.113.10` |

Check with `dig +short api.example.in`. Wait until both names answer before Step 6.

#### Step 2: SSH key login

On your PC:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/wholeflow_vps -C wholeflow
ssh-copy-id -i ~/.ssh/wholeflow_vps.pub root@203.0.113.10     # uses the VPS root password once
cat >> ~/.ssh/config <<'EOF'
Host wholeflow
    HostName 203.0.113.10
    User root
    IdentityFile ~/.ssh/wholeflow_vps
EOF
ssh wholeflow 'echo ok'
```

From here on, every server command runs inside `ssh wholeflow` as root.

#### Step 3: Harden the server

```bash
apt update && apt -y full-upgrade
apt -y install unattended-upgrades fail2ban ufw nginx certbot python3-certbot-nginx python3 curl rsync
dpkg-reconfigure -f noninteractive unattended-upgrades       # automatic security updates
timedatectl set-timezone Asia/Kolkata

# 2 GB swap
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# SSH: keys only (test a second `ssh wholeflow` in another terminal before closing this one)
cat > /etc/ssh/sshd_config.d/00-wholeflow.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
MaxAuthTries 4
EOF
systemctl reload ssh

# fail2ban on SSH
cat > /etc/fail2ban/jail.d/wholeflow.local <<'EOF'
[sshd]
enabled = true
maxretry = 5
EOF
systemctl restart fail2ban

# Firewall: only SSH, HTTP, HTTPS
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable
```

#### Step 4: Docker

```bash
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version
```

Every container port is bound to `127.0.0.1`, so nothing is reachable from outside except through nginx.

#### Step 5: Copy the server kit

On your PC, from the repo root:

```bash
rsync -a WholeFlow/deploy/server/ wholeflow:/opt/wholeflow/
ssh wholeflow 'mkdir -p /opt/wholeflow/{migrations,bin,businesses} /etc/nginx/wholeflow-businesses && chmod 700 /opt/wholeflow/businesses && chmod +x /opt/wholeflow/scripts/*.sh'
scp WholeFlow/db/migrations/*.sql wholeflow:/opt/wholeflow/migrations/
```

#### Step 6: Secrets and the database

On the server:

```bash
cd /opt/wholeflow
PG=$(openssl rand -hex 24); MASTER=$(openssl rand -hex 32)

cat > .env <<EOF
POSTGRES_PASSWORD=$PG
PUBLIC_URL=https://api.example.in
EOF

cat > control.env <<EOF
CONTROL_DB_URL=postgres://postgres:$PG@127.0.0.1:5432/control_db
PG_ADMIN_URL=postgres://postgres:$PG@127.0.0.1:5432/postgres
MASTER_KEY=$MASTER
PUBLIC_URL=https://api.example.in
KIT_DIR=/opt/wholeflow
LISTEN=127.0.0.1:8100
EOF
chmod 600 .env control.env

docker compose up -d db                                   # PostgreSQL 15 on 127.0.0.1:5432, creates the shared roles
sleep 5 && docker compose exec -T db createdb -U postgres control_db
```

> **Keep a safe copy of `MASTER_KEY`** (e.g. in your password manager). Each business's secrets in `control_db` are encrypted with it.

#### Step 7: HTTPS and nginx

The kit's [`nginx/wholeflow.conf`](WholeFlow/deploy/server/nginx/wholeflow.conf) already contains the HTTPS lines certbot wrote for the live server. So get the certificate first with a temporary site, then install the real config.

```bash
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-enabled/bootstrap.conf <<'EOF'
server { listen 80; server_name api.example.in admin.example.in; location / { return 404; } }
EOF
nginx -t && systemctl reload nginx
certbot --nginx -d api.example.in -d admin.example.in --agree-tos --register-unsafely-without-email   # or -m you@example.in
rm /etc/nginx/sites-enabled/bootstrap.conf

cd /opt/wholeflow
sed -i 's/jitsuji\.xyz/example.in/g' nginx/wholeflow.conf
ln -sf /opt/wholeflow/nginx/wholeflow.conf /etc/nginx/sites-enabled/wholeflow.conf
nginx -t && systemctl reload nginx
systemctl list-timers | grep certbot                      # auto-renewal is on
```

What it routes:
- `api.<domain>/control/` → control service
- `api.<domain>/b/<slug>/{auth,rest}/v1/` → that business's containers (one file per business in `/etc/nginx/wholeflow-businesses/`, written by `new-business.sh`)
- `admin.<domain>` → admin app (pages and admin API only)

The bare IP and unknown names are dropped.

#### Step 8: Control service and admin app

On your PC, build the server binary and copy it up:

```bash
cd WholeFlow
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o wholeflow-control ./cmd/control
scp wholeflow-control wholeflow:/opt/wholeflow/bin/wholeflow-control
```

On the server:

```bash
cp /opt/wholeflow/systemd/wholeflow-control.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now wholeflow-control
systemctl status wholeflow-control --no-pager | head -5   # "active (running)"; it creates the control_db tables itself

# Your admin account (password typed on stdin, at least 10 characters)
set -a; . /opt/wholeflow/control.env; set +a
/opt/wholeflow/bin/wholeflow-control create-admin you@example.in "Your Name"
```

#### Step 9: Nightly backups

```bash
cp /opt/wholeflow/systemd/wholeflow-backup.{service,timer} /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now wholeflow-backup.timer   # 02:30 IST
systemctl start wholeflow-backup && ls /opt/wholeflow/backup/              # run once now: newest folder has OK
```

#### Step 10: Check the server

```bash
curl -s https://api.example.in/control/health            # {"ok":true}
```

Open **https://admin.example.in** and sign in with the admin account from Step 8. In **Plans**, check the prices: Basic ₹500 for 1 company, Standard ₹800 for 3, Pro ₹1000 for 5. In **Settings**, fill in the **renewal message** and your **contact number** (UPI / phone). Owners see these on their banners and on the paused screen.

### 4.3 First business

In the admin app click **New business**:

1. Fill in the business name; the short name fills itself.
2. Choose the plan, and the paid-until date (leave it empty for a 14-day trial).
3. Add the contact details, and the **owner's email** (their login).
4. Click **Create business**. It takes about 20 seconds: it creates the database, login, data API, route, owner account, reference key and first activation code.
5. On the result screen, note the **temporary password** and the **activation code**; they are not shown again. Then use **Copy message for the owner** and send it (WhatsApp etc.).

Later, from the same business page you can record payments, change plan or grace days, suspend or resume, make a new reference key, **Add a Tally PC** (a new activation code), revoke a PC, download a backup, and see the history. The business page also shows the **QR code** of the reference key for the phone apps.

### 4.4 Tally PC

Full details are in [WholeFlow/README.md](WholeFlow/README.md#deploying-on-a-client-pc). Short version:

1. **Build the release** on a Windows PC: `powershell -ExecutionPolicy Bypass -File WholeFlow\deploy\Build-Release.ps1`, which produces `dist\WholeFlow-<version>.zip`. You can also build only the exe from any OS with `cd WholeFlow && GOOS=windows GOARCH=amd64 go build -o bin/wholeflow.exe ./cmd/server`.
2. **Set up TallyPrime**: F1 Help → Settings → Connectivity → Client/Server → *TallyPrime acts as* **Server** (or Both). The company must be open.
3. **Install**: on the customer PC, extract the zip and double-click `Install-WholeFlow.cmd` (accept UAC). It installs the Windows service **WholeFlow** and opens http://127.0.0.1:8080.
4. **Sign in** with your **admin account**. The server checks every sign-in, and there is no local or offline login, so the PC can't be opened without the server.
5. **Cloud Sync**:
   1. Enter the **reference key** and **activation code**, then click **Connect**. It should say "Connected to <business>".
   2. Click **Test cloud connection**, then **Test Tally & discover companies**.
   3. Tick the companies (up to the plan's limit) and click **Save**, then **Sync now**.
   4. Tick **Background synchronisation enabled** and click **Save**.
6. **Check**: the admin app's business page should show the PC with its version and "last seen". Run `"C:\Program Files\WholeFlow\wholeflow.exe" status` (as Administrator) to see each company's last sync.

The PC on a domain other than `jitsuji.xyz`: set `CONTROL_URL=https://api.example.in` in the `.env` next to the exe before installing.

### 4.5 Phone apps

Build the **hosted** apps, which ask for a reference key instead of having a server built in:

```bash
cd wholeflow_app
flutter pub get
# env/hosted.json holds only {"CONTROL_URL": "https://api.jitsuji.xyz"}; change it for another domain
flutter build apk --release --flavor owner -t lib/main_owner.dart --dart-define-from-file=env/hosted.json
flutter build apk --release --flavor staff -t lib/main_staff.dart --dart-define-from-file=env/hosted.json
# → build/app/outputs/flutter-apk/app-owner-release.apk and app-staff-release.apk
adb install -r build/app/outputs/flutter-apk/app-owner-release.apk   # or share the APK
```

On the phone:

1. Open the app. Enter the **reference key**, or tap **Scan QR code** and scan the QR from the admin app.
2. It shows "Connect to <business>?". Tap **Connect**.
3. Sign in. The owner uses the email and temporary password from Step 4.3 and is asked to choose a new password.
4. The owner adds staff in **Settings → Staff**: email, temporary password, companies or sites, and optional check-in. Staff install the **Staff** app, connect with the **same reference key** and sign in.

Settings → **Switch business** connects to another business. Owner and Staff can be installed side by side (`com.wholeflow.wholeflow_app`, `com.wholeflow.staff`).

> Release APKs are currently signed with the debug key ([android/app/build.gradle.kts](wholeflow_app/android/app/build.gradle.kts)). Create a real upload key before publishing on the Play Store.

### 4.6 Developer machine and tests

```bash
# Go: Tally PC app + control service
cd WholeFlow
go build ./... && GOOS=windows go build ./cmd/server
go vet ./... && gofmt -l . && go test ./...

# Database: every migration + SQL test on a throwaway Postgres in Docker (never touches a real server)
db/tests/run_local.sh

# Flutter
cd ../wholeflow_app
flutter pub get
dart run build_runner build -d       # after changing @riverpod / freezed code
flutter analyze && flutter test
flutter run --flavor owner -t lib/main_owner.dart --dart-define-from-file=env/hosted.json
```

**Running the Tally PC app locally (Linux/macOS, no Tally)**:

```bash
APP_ADDR=127.0.0.1:18080 go run ./cmd/server run -data /tmp/wf-data
```

Then open http://127.0.0.1:18080.

---

## 5. Running the service

| Task | Where |
|---|---|
| Customer paid | Admin app → business → **Record a payment** (months, amount, UPI/cash/bank, reference). Paid-until moves forward and blocked apps unblock at their next refresh. |
| Unpaid | Nothing to do. Renewal-due and grace banners appear by themselves, and the apps and sync stop after the grace days. |
| Block for another reason | Business → **Suspend**; **Resume** undoes it. **Close** is final for that reference key; the data stays until you delete it. |
| New or replacement Tally PC | Business → **Add a Tally PC**, which gives a new activation code. Revoke the old PC in **Tally PCs**. |
| Reference key leaked | Business → **New reference key**. Phones already connected keep working. |
| Change prices or limits | **Plans** (applies to every business on the plan). |
| Renewal text or contact | **Settings → Message to owners**. |
| Another admin | **Settings → Admins**. That account also works on Tally PCs. |
| Website enquiries | Admin app → **Enquiries**: contact-form submissions from wholeflow.jitsuji.xyz, with call/WhatsApp/email links, a status and your note. |
| Customer wants their data | Business → **Download backup** (a `pg_dump` file). |
| Logs | `journalctl -u wholeflow-control` · `docker compose -p biz-<slug> -f businesses/<slug>/compose.yml --env-file businesses/<slug>/env logs` · on a Tally PC `C:\ProgramData\WholeFlow\logs\app.log` |
| Delete one Tally company's data | Business → **Tally companies** → **Delete**. You type the company name and your own admin password, then confirm once more. It removes the company's shops, transactions, suppliers, purchases, stock, sites, visits and staff access. Untick it on the Tally PC first, or the next sync uploads it again. The card warns when more companies are stored than the plan allows. |
| Delete a whole business | Business → **Danger zone** → **Delete business**. You type its short name and your admin password, then confirm once more. It removes the database, containers, route, logins, keys, PCs and payment records. A tick box (on by default) also deletes its nightly backup files. Use **Download backup** first if the customer wants their data. On the server, `scripts/delete-business.sh <slug> --yes` does the same apart from the backups. |

## 6. Releasing updates

| What changed | How to roll it out |
|---|---|
| **Control service or admin pages** (`WholeFlow/internal/control`, `cmd/control`) | Build as in Step 8, `scp` to `/opt/wholeflow/bin/wholeflow-control.new`, then `cp wholeflow-control wholeflow-control.prev && mv wholeflow-control.new wholeflow-control && systemctl restart wholeflow-control`. Roll back with `.prev`. |
| **Database** (new file in `WholeFlow/db/migrations/`) | Keep migrations additive. Run `db/tests/run_local.sh`, copy the file to `/opt/wholeflow/migrations/`, then admin app → **Settings → Update all businesses** (or `scripts/migrate.sh --all`). New businesses get every migration automatically. |
| **Tally PC app** | Raise `Version` in `WholeFlow/internal/syncer/settings.go`, run `Build-Release.ps1`, and run `Install-WholeFlow.cmd` on each PC (it upgrades in place and keeps settings). The admin app shows each PC's version. |
| **Phone apps** | Raise `version:` in `wholeflow_app/pubspec.yaml`, build the APKs (4.5) and share them. Saved connections and logins survive updates. |

## 7. Backups and restore

- **Nightly** at 02:30 IST (`wholeflow-backup.timer` → `scripts/backup.sh`): every database (`control_db`, each `biz_*`), the roles and the server's configuration and secrets (env files, `businesses/*/env`, nginx, certificates) go to **`/opt/wholeflow/backup/<date>_<time>/`**, each dump checked, with an `OK` or `FAILED` marker and checksums. Kept 14 days on the server. Log: `/var/log/wholeflow/backup.log`; the admin app's Server health shows the newest backup's age.
- **Download them yourself** (no automatic off-site copy yet), e.g. weekly from your laptop:

  ```bash
  rsync -av --exclude '.tmp-*' --exclude '.lock' wholeflow:/opt/wholeflow/backup/ ~/wholeflow-backups/
  ```

  They are **not encrypted** and contain every customer's data and the server's `MASTER_KEY`: keep them on an encrypted disk only.
- **Restore** (one business into a scratch database, then swap; or a whole new server from a downloaded copy): `scripts/restore.sh` and [WholeFlow/docs/RUNBOOK_RESTORE.md](WholeFlow/docs/RUNBOOK_RESTORE.md). Never `pg_restore --clean` into the live database.
- **Later, optional:** encryption (an age public key in `/opt/wholeflow/backup.recipients`) and an automatic off-site copy (`BACKUP_REMOTE`), see `WholeFlow/deploy/server/README.md` "Backups and restore".

## 8. Security

- **Server**: SSH keys only, root login only with a key, fail2ban, and ufw allowing only 22/80/443. PostgreSQL and every container listen on localhost only. Security updates install automatically.
- **HTTPS**: Let's Encrypt everywhere, with auto-renewal.
- **Secrets**:
  - Each business has its own signing secret and keys. Its service key never leaves the server.
  - Secrets in `control_db` are encrypted with `MASTER_KEY`.
  - `.env`, `control.env` and `businesses/` are root-only and git-ignored.
  - Your local [.env](.env) (VPS login) is git-ignored and `chmod 600`.
- **Apps and PCs**:
  - A reference key alone reads nothing.
  - Key lookups are rate-limited per IP.
  - Activation codes are single-use and expire in 48 hours.
  - Each PC has its own revocable key, stored with Windows DPAPI.
- **Admin app**:
  - Strong passwords with lockout after repeated failures.
  - 12-hour sessions kept only in the browser tab.
  - A strict content-security policy; the page cannot be framed.
  - On the admin host, only the admin pages and API are reachable.
- **Tally**: read-only, enforced by an allow-list in `WholeFlow/internal/tally/readonly.go`.

## 9. Current status and open items

Built, deployed and tested (October 2026):
- server
- control service
- admin app
- business databases (staff management later moved into the app API)
- Owner and Staff apps (hosted mode, tested on a phone)
- Tally PC app 0.4.0 (tested live against the server)

The `demo` business on the server is for testing.

Open items:
- **Set up JMJ fresh** (nothing is moved from the old Supabase project; Supabase support is removed everywhere):
  1. Create `jmj` in the admin app.
  2. Install the current Tally PC release on JMJ's PC and connect it with the reference key and activation code.
  3. Install the apps and connect them with the reference key. The owner adds staff, sites, shop pins and visit plans again.
  4. Cancel the old Supabase project.
- **Off-site backups** (Backblaze B2) are not set up; today the backups exist only on the server.
- **Play Store signing key** (see 4.5).
- **Server region**: the server is in Germany, which means about 200 ms per request from Kerala. Consider Contabo India or Singapore before many customers join.
- **Uptime monitoring** (e.g. UptimeRobot on `/control/health`) is not set up.
- **App/schema version check** ("please update the app") is not built.

## 10. More documentation

| Document | What's in it |
|---|---|
| [WholeFlow/docs/MULTI_TENANT_PLAN.md](WholeFlow/docs/MULTI_TENANT_PLAN.md) | Design of the hosting: databases, control service, keys, subscriptions, phases |
| [WholeFlow/deploy/server/README.md](WholeFlow/deploy/server/README.md) | Server kit: layout on the server, everyday commands |
| [WholeFlow/README.md](WholeFlow/README.md) | Tally PC app: build, run, install on a client PC, updates, how Tally data is read, local API |
| [WholeFlow/docs/SYNC_SETUP.md](WholeFlow/docs/SYNC_SETUP.md) · [SYNC_ARCHITECTURE.md](WholeFlow/docs/SYNC_ARCHITECTURE.md) | Sync setup runbook; how a sync run works, retries, offline rules |
| [WholeFlow/docs/DATABASE_SCHEMA.md](WholeFlow/docs/DATABASE_SCHEMA.md) | Business database tables, row-level security, example queries |
| [WholeFlow/STATUS.md](WholeFlow/STATUS.md) | Tally PC app status and history |
| [wholeflow_app/README.md](wholeflow_app/README.md) | Flutter app: builds, structure, backend pieces |
