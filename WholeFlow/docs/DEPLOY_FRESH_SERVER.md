# Fresh production install (wipe the Contabo server and start again)

This sets up the whole WholeFlow system from nothing on the existing Contabo VPS
(`75.119.130.27`, domain `jitsuji.xyz`):

| Address | What |
|---|---|
| `https://api.jitsuji.xyz` | App API (phones, Tally PCs) and the public control endpoints |
| `https://admin.jitsuji.xyz` | Admin app (you) |
| `https://wholeflow.jitsuji.xyz` | Product website with the contact form |

**Everything on the server is deleted** (all businesses, logins, backups,
settings). The result has no old containers and no test data: one PostgreSQL,
the control service, the app API, nginx with HTTPS, nightly backups and the
monitor.

Time: about 1.5–2 hours. Commands marked **laptop** run in the repo on your
computer; everything else runs on the server as root (`ssh wholeflow`).

Contents: [0 Before you wipe](#0-before-you-wipe) · [1 Reinstall](#1-reinstall-the-server-wipes-everything) ·
[2 SSH](#2-ssh-from-the-laptop) · [3 Harden](#3-harden-the-os) · [4 Docker](#4-docker) ·
[5 Build](#5-build-on-the-laptop) · [6 Copy the kit](#6-copy-the-kit) · [7 Secrets and database](#7-secrets-and-the-database) ·
[8 HTTPS](#8-https-certificates-and-nginx) · [9 Control](#9-control-service-and-your-admin-account) ·
[10 API](#10-app-api) · [11 Backups and monitor](#11-backups-and-monitor) · [12 Website](#12-website) ·
[13 Checks](#13-production-checks) · [14 First business](#14-first-business-tally-pc-and-phones) ·
[15 Afterwards](#15-afterwards)

---

## 0. Before you wipe

1. **Code ready (laptop).** Work from the branch you want live (today `api-layer`;
   after merging, `main`). All tests must pass:
   ```bash
   cd WholeFlow && go vet ./... && go test ./... && db/tests/run_local.sh
   cd ../wholeflow_app && flutter analyze && flutter test
   ```
2. **Save anything you want to keep (laptop).** Optional; the data is test data:
   ```bash
   rsync -av wholeflow:/opt/wholeflow/backup/ ~/wholeflow-old-backups/
   ```
3. **Password manager ready.** You will create and must keep: the server root
   password, `MASTER_KEY`, the PostgreSQL password, your admin password and its
   two-step backup codes.
4. **Authenticator app** on your phone (Google Authenticator, Microsoft
   Authenticator…) for the admin app's two-step sign-in.
5. **DNS stays as it is** (GoDaddy A records `api`, `admin`, `wholeflow` →
   `75.119.130.27`). A reinstall keeps the IP. Check:
   `dig +short api.jitsuji.xyz admin.jitsuji.xyz wholeflow.jitsuji.xyz`.

## 1. Reinstall the server (wipes everything)

Contabo customer panel → **VPS** → your server → **Reinstall** (or *Manage →
Reinstall*):

- Image: **Ubuntu 24.04** (plain, no panel / no apps).
- Set a **new, long root password** (save it in the password manager).
- If the form offers "SSH key", paste the contents of `~/.ssh/wholeflow_vps.pub`.

Wait until the panel shows it running (5–15 minutes).

## 2. SSH from the laptop

The reinstall gives the server a new host key, so forget the old one first:

```bash
# laptop
ssh-keygen -R 75.119.130.27 && ssh-keygen -R api.jitsuji.xyz && ssh-keygen -R admin.jitsuji.xyz
ssh-copy-id -i ~/.ssh/wholeflow_vps.pub root@75.119.130.27   # only if the key was not added in the panel (asks the root password once)
ssh wholeflow 'hostname && lsb_release -ds'                   # Ubuntu 24.04…
```

`~/.ssh/config` already has the `wholeflow` entry (key `~/.ssh/wholeflow_vps`).
If not:

```
Host wholeflow 75.119.130.27 api.jitsuji.xyz admin.jitsuji.xyz
    HostName 75.119.130.27
    User root
    IdentityFile ~/.ssh/wholeflow_vps
    IdentitiesOnly yes
```

Give the key a passphrase if it has none: `ssh-keygen -p -f ~/.ssh/wholeflow_vps`.

## 3. Harden the OS

```bash
ssh wholeflow
apt update && apt -y full-upgrade
apt -y install unattended-upgrades fail2ban ufw nginx certbot python3-certbot-nginx \
  curl rsync acl dnsutils
timedatectl set-timezone Asia/Kolkata

# Automatic security updates, with a reboot at 04:30 when a kernel update needs one
dpkg-reconfigure -f noninteractive unattended-upgrades
cat > /etc/apt/apt.conf.d/52wholeflow <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
EOF

# 2 GB swap
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# SSH: keys only. Files in sshd_config.d are read in name order and the first
# value wins, so 00- overrides Ubuntu's own 50-cloud-init.conf.
cat > /etc/ssh/sshd_config.d/00-wholeflow.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
MaxAuthTries 4
EOF
sshd -t && systemctl reload ssh
```

**Test before closing this session:** in a second laptop terminal,
`ssh wholeflow 'echo ok'` must work. (Keys only is the safe choice for a
public server. If you insist on password login, set `PasswordAuthentication yes`
in this file, keep fail2ban on, and use a long random root password.)

```bash
# fail2ban for SSH
cat > /etc/fail2ban/jail.d/wholeflow.local <<'EOF'
[sshd]
enabled = true
maxretry = 5
bantime = 1h
EOF
systemctl enable --now fail2ban && systemctl restart fail2ban

# Firewall: only SSH, HTTP, HTTPS
ufw allow OpenSSH && ufw allow 80/tcp && ufw allow 443/tcp && ufw --force enable
ufw status
```

## 4. Docker

```bash
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version
```

Note: Docker's own published ports bypass ufw. The kit publishes only
`127.0.0.1:5432` (PostgreSQL), so nothing is reachable from outside except
through nginx. Checked again in step 13.

## 5. Build on the laptop

```bash
# laptop, repo root
cd WholeFlow
mkdir -p /tmp/wf-build
for c in api control; do
  CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /tmp/wf-build/wholeflow-$c ./cmd/$c
done
ls -la /tmp/wf-build
```

`go.mod` pins the Go toolchain (`toolchain go1.27.0`), so the binaries contain
the current Go security fixes.

## 6. Copy the kit

```bash
# laptop, in WholeFlow/
ssh wholeflow 'mkdir -p /opt/wholeflow/{migrations,auth,bin,businesses,backup} /etc/nginx/wholeflow-businesses /var/www/wholeflow-site'
rsync -a --exclude '*.example' --exclude '.env.example' \
  deploy/server/scripts deploy/server/systemd deploy/server/nginx deploy/server/db \
  deploy/server/templates deploy/server/docker-compose.yml wholeflow:/opt/wholeflow/
rsync -a deploy/server/api.env.example deploy/server/backup.env.example wholeflow:/opt/wholeflow/
scp db/migrations/*.sql wholeflow:/opt/wholeflow/migrations/
scp db/auth/auth_schema.sql wholeflow:/opt/wholeflow/auth/
scp /tmp/wf-build/wholeflow-api /tmp/wf-build/wholeflow-control wholeflow:/opt/wholeflow/bin/
ssh wholeflow 'chmod +x /opt/wholeflow/scripts/*.sh /opt/wholeflow/bin/*; chmod 700 /opt/wholeflow/backup; ls /opt/wholeflow /opt/wholeflow/migrations'
```

All migrations go up, including `0009_lockdown.sql`: on a fresh server there is
no old PostgREST to keep working, so every business gets the locked-down
permissions from the start.

## 7. Secrets and the database

```bash
cd /opt/wholeflow
umask 077
PG=$(openssl rand -hex 24); MASTER=$(openssl rand -hex 32)

cat > .env <<EOF
POSTGRES_PASSWORD=$PG
PUBLIC_URL=https://api.jitsuji.xyz
EOF

cat > control.env <<EOF
CONTROL_DB_URL=postgres://postgres:$PG@127.0.0.1:5432/control_db
PG_ADMIN_URL=postgres://postgres:$PG@127.0.0.1:5432/postgres
MASTER_KEY=$MASTER
PUBLIC_URL=https://api.jitsuji.xyz
KIT_DIR=/opt/wholeflow
LISTEN=127.0.0.1:8100
EOF
chmod 600 .env control.env
```

**Save `MASTER_KEY` and the PostgreSQL password in the password manager now**
(`grep -E '^(MASTER_KEY|POSTGRES_PASSWORD)=' control.env .env`). Each
business's secrets in `control_db` are encrypted with `MASTER_KEY`; without it
a restore on another server cannot open them. Clear the terminal afterwards.

```bash
docker compose up -d db          # PostgreSQL 15.19 on 127.0.0.1:5432; db/init creates the shared roles
until docker compose exec -T db pg_isready -U postgres -q; do sleep 1; done
docker compose exec -T db createdb -U postgres control_db
docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -q < db/lock-databases.sql   # no PUBLIC access to any database
docker compose exec -T db psql -U postgres -tAc 'show max_connections'                      # 300
```

Users and file permissions for the app API (it runs as its own user, not root):

```bash
scripts/setup-users.sh           # ends with "setup-users: ok (...)"
```

## 8. HTTPS certificates and nginx

The kit's nginx files already contain the certbot lines for
`api.jitsuji.xyz` (one certificate for api + admin) and
`wholeflow.jitsuji.xyz`. So: get the certificates with a temporary site, then
switch to the kit's files.

```bash
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-enabled/bootstrap.conf <<'EOF'
server { listen 80; server_name api.jitsuji.xyz admin.jitsuji.xyz wholeflow.jitsuji.xyz; location / { return 404; } }
EOF
nginx -t && systemctl reload nginx

certbot --nginx -d api.jitsuji.xyz -d admin.jitsuji.xyz -m you@example.com --agree-tos --no-eff-email
certbot --nginx -d wholeflow.jitsuji.xyz -m you@example.com --agree-tos --no-eff-email
rm /etc/nginx/sites-enabled/bootstrap.conf

ln -sf /opt/wholeflow/nginx/wholeflow.conf      /etc/nginx/sites-enabled/wholeflow.conf
ln -sf /opt/wholeflow/nginx/wholeflow-site.conf /etc/nginx/sites-enabled/wholeflow-site.conf
nginx -t && systemctl reload nginx
certbot renew --dry-run          # automatic renewal works
```

(Use your real email with `-m`: Let's Encrypt warns there before a certificate
would expire.)

Optional, stronger: limit the admin site to your own IP addresses. See
`templates/admin-allowlist.conf.example` and the commented `include` in
`nginx/wholeflow.conf`.

## 9. Control service and your admin account

```bash
cp /opt/wholeflow/systemd/wholeflow-control.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now wholeflow-control
sleep 2 && journalctl -u wholeflow-control -n 5 --no-pager -o cat   # "control_db migrations applied", "listening"
curl -s 127.0.0.1:8100/control/health                                # {"ok":true}

# Your admin account (password typed, at least 10 characters; not shown)
set -a; . /opt/wholeflow/control.env; set +a
/opt/wholeflow/bin/wholeflow-control create-admin you@example.com "Your Name"
```

Open **https://admin.jitsuji.xyz**, sign in, and set up **two-step sign-in**
with the authenticator app on your phone (scan the QR code, enter the 6-digit
code). **Save the backup codes** in the password manager. Lost phone later:
`wholeflow-control reset-2fa you@example.com` on the server.

In the admin app:
- **Admins → add an installer** (for signing in on customers' Tally PCs; it
  cannot open the admin app). Save its password.
- **Settings:** your contact details for the subscription banners; leave
  *Minimum phone app build* at 0 for now; set *Latest Tally PC version* to
  `0.6.0`.

## 10. App API

Read-only database login for the API, generated and written straight into
`api.env` (never printed):

```bash
cd /opt/wholeflow
umask 077
PW=$(openssl rand -hex 24)
docker compose exec -T db psql -U postgres -d control_db -v ON_ERROR_STOP=1 -q -v pw="$PW" < db/api_ro_role.sql
cat > api.env <<EOF
CONTROL_DB_URL=postgres://wholeflow_api_ro:$PW@127.0.0.1:5432/control_db
$(grep '^MASTER_KEY=' control.env)
KIT_DIR=/opt/wholeflow
PG_HOST=127.0.0.1:5432
LISTEN=127.0.0.1:8300
API_EXPECTED_MIGRATION=0009_lockdown.sql
EOF
chmod 600 api.env; unset PW

cp systemd/wholeflow-api.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now wholeflow-api
sleep 2 && curl -s 127.0.0.1:8300/health          # {"ok":true}
```

## 11. Backups and monitor

```bash
cp /opt/wholeflow/systemd/wholeflow-backup.{service,timer} \
   /opt/wholeflow/systemd/wholeflow-monitor{,-daily}.{service,timer} /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now wholeflow-backup.timer wholeflow-monitor.timer wholeflow-monitor-daily.timer
systemctl start wholeflow-backup && ls /opt/wholeflow/backup/        # a dated folder with an OK file
systemctl start wholeflow-monitor && tail -1 /var/log/wholeflow/monitor-$(date +%F).log
systemctl list-timers 'wholeflow-*' --no-pager
```

Backups are nightly at 02:30 IST in `/opt/wholeflow/backup/` (kept 14 days),
**not encrypted** and not copied off the server: download them yourself
(step 15). The admin app's **Server health** page shows the monitor's log.

## 12. Website

```bash
# laptop, repo root
website/deploy.sh
curl -sI https://wholeflow.jitsuji.xyz/ | head -1        # HTTP/2 200
```

Send a test enquiry from the contact form: it appears in the admin app under
**Enquiries** (delete it afterwards).

## 13. Production checks

On the server:

```bash
ss -ltnp | grep -vE '127\.0\.0\.1|\[::1\]'     # listening publicly: only sshd (22) and nginx (80, 443)
ufw status                                      # 22, 80, 443
systemctl is-active fail2ban unattended-upgrades docker nginx wholeflow-control wholeflow-api
grep -E '^(PasswordAuthentication|PermitRootLogin)' /etc/ssh/sshd_config.d/00-wholeflow.conf
ls -l /opt/wholeflow/{.env,control.env,api.env}            # -rw------- root root
runuser -u wholeflow-api -- cat /opt/wholeflow/control.env  # must fail: Permission denied
```

From the laptop:

```bash
for u in https://api.jitsuji.xyz/control/admin/me https://api.jitsuji.xyz/control/internal/x \
         https://api.jitsuji.xyz/control/health https://admin.jitsuji.xyz/ https://wholeflow.jitsuji.xyz/; do
  printf '%-50s %s\n' $u "$(curl -s -o /dev/null -w '%{http_code}' $u)"; done
# expected: 404, 404, 200, 200, 200
curl -sI https://api.jitsuji.xyz/control/health | grep -i strict-transport   # HSTS present
curl -s -o /dev/null -w '%{http_code}\n' http://75.119.130.27/              # no answer / 000 (the bare IP is refused)
```

Then, in the Contabo panel, take a **snapshot** of the finished server (a fast
way back if a later change goes wrong).

## 14. First business, Tally PC and phones

**Business** — admin app → **New business**: name, short name (e.g. `jmj`),
owner's name and email, plan. The result screen shows the **reference key**, a
first **activation code** (48 hours, one use), and the owner's **temporary
password**. "Copy message for the owner" gives a ready text.
(`scripts/new-business.sh` runs for you: database, login roles, keys, all
migrations including the lockdown.)

**Tally PC** (laptop, then the customer's PC):

```bash
WholeFlow/deploy/build-release.sh          # → WholeFlow/dist/WholeFlow-0.6.0.zip
```

On the Tally PC: extract the zip, double-click `Install-WholeFlow.cmd`
(accept the UAC prompt), open http://127.0.0.1:8080, sign in with the
**installer** account, Cloud Sync → enter the reference key and activation
code → tick the Tally companies → turn sync on → **Sync now**. The admin app's
business page and Server health then show the PC as online, version 0.6.0.

**Phone apps** — release builds need the upload key once (laptop):

```bash
keytool -genkey -v -keystore ~/keys/wholeflow-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp wholeflow_app/android/key.properties.example wholeflow_app/android/key.properties   # fill in path and passwords
cd wholeflow_app && tool/build_release.sh   # Play Store bundles (.aab) for Owner and Staff
```

Keep the `.jks` file and its passwords in the password manager **and** a
second safe place: Play only accepts updates signed with it (with Play App
Signing, a lost upload key can be reset through Google support).
For installing on your own phone before Play, build APKs instead:
`flutter build apk --release --flavor owner -t lib/main_owner.dart --dart-define-from-file=env/hosted.json`
(and `staff`, `lib/main_staff.dart`), then `adb install -r …`. If an older
build with a different signature is on the phone, uninstall it first.

In the Owner app: enter the reference key → sign in with the owner email and
temporary password → set a new password → the dashboard shows the Tally data
after the first sync. Settings → Staff → **Add staff**, then sign in once in
the Staff app.

## 15. Afterwards

- **Backups:** download weekly (laptop), keep on an encrypted disk:
  `rsync -av --exclude '.tmp-*' --exclude '.lock' wholeflow:/opt/wholeflow/backup/ ~/wholeflow-backups/`
  Practise a restore every quarter (`docs/RUNBOOK_RESTORE.md`).
- **Check Server health** in the admin app a few times a week (there are no
  alert messages; problems are only logged).
- **After every phone has the new app:** admin app → Settings → *Minimum
  phone app build* = that build number.
- **Updating later:** build the changed binary, `scp` it to
  `/opt/wholeflow/bin/<name>.new`, then `cp <name> <name>.prev && mv <name>.new <name>
  && systemctl restart <service>`. New migrations: copy to `migrations/`, then
  admin app → Settings → *Update all businesses* (it backs each business up
  first). Website: `website/deploy.sh`. Details: `deploy/server/README.md`.
- **Monthly:** `apt list --upgradable`, PostgreSQL minor release notes
  (`docker-compose.yml` comment), Go security releases.
