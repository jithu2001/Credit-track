# WholeFlow server kit (Contabo)

Runs WholeFlow for many businesses on one Ubuntu server: one PostgreSQL with a
database per business, behind nginx at `https://api.<domain>/b/<slug>/`. See
[../../docs/MULTI_TENANT_PLAN.md](../../docs/MULTI_TENANT_PLAN.md) and
[../../docs/API_PLAN.md](../../docs/API_PLAN.md).

**Changing (branch `api-layer`, not deployed yet):** the WholeFlow app API
(`wholeflow-api`) serves every business's sign-in and data; the per-business
GoTrue and PostgREST containers are retired step by step
(`scripts/retire-containers.sh`), and the Deno staff service is gone (staff
management is `/b/<slug>/api/v1/staff`). New businesses get no containers.
Deploy order: API_PLAN.md section 5 plus **"Deploying the hardening"** below.

**New server from scratch (wipe and reinstall):** [../../docs/DEPLOY_FRESH_SERVER.md](../../docs/DEPLOY_FRESH_SERVER.md).

Live server: `75.119.130.27` (Contabo, Germany, 4 vCPU / 8 GB RAM, Ubuntu 24.04),
`api.jitsuji.xyz`, `admin.jitsuji.xyz`, `wholeflow.jitsuji.xyz`, files in `/opt/wholeflow`.
SSH: `ssh wholeflow` (key `~/.ssh/wholeflow_vps`; password login is off).

## Architecture

```
internet ─▶ nginx :443 ─┬─ api.<domain>
                        │    /b/<slug>/auth/v1/…, /b/<slug>/api/v1/… ─▶ wholeflow-api   127.0.0.1:8300 (user wholeflow-api)
                        │    /control/… (connect, activate, heartbeat, pc/login) ─▶ wholeflow-control 127.0.0.1:8100 (root)
                        │    /control/admin/…, /control/internal/… ─▶ 404
                        │    legacy /b/<slug>/rest/v1/ ─▶ PostgREST containers (until retired)
                        ├─ admin.<domain>  / , /assets/, /control/admin/… ─▶ wholeflow-control
                        └─ wholeflow.<domain>  static website; /api/contact ─▶ control /control/leads
PostgreSQL 15 (docker compose, 127.0.0.1:5432): control_db + biz_<slug> per business
```

## Layout on the server (`/opt/wholeflow`)

| Path | What | Owner / mode |
|---|---|---|
| `docker-compose.yml`, `.env` | Shared PostgreSQL 15 (localhost only). `.env`: `POSTGRES_PASSWORD`, `PUBLIC_URL` | root 600 |
| `control.env` | Control service: superuser URLs, `MASTER_KEY` | root 600 |
| `api.env` | App API: `CONTROL_DB_URL` as read-only `wholeflow_api_ro`, `MASTER_KEY` (systemd reads it as root) | root 600 |
| `backup/` | Nightly backups (download them yourself) | root 700, files 600 |
| `backup.env`, `backup.recipients` | Optional: off-site remote; age **public** key(s) to encrypt backups | root 600 / 644 |
| `businesses/<slug>/env` | That business's DB logins, JWT secret, keys | root:wholeflow 640 (dir 2750 + default ACL) |
| `db/` | `init/00-roles.sql` (server-wide roles), `api_ro_role.sql`, `lock-databases.sql` | |
| `migrations/`, `auth/` | Copies of `WholeFlow/db/migrations/*.sql`, `db/auth/auth_schema.sql` | |
| `templates/` | Legacy per-business compose/nginx (no longer used for new businesses); `admin-allowlist.conf.example` | |
| `nginx/wholeflow.conf` | Linked into `/etc/nginx/sites-enabled`; certbot added the HTTPS parts. Legacy routes in `/etc/nginx/wholeflow-businesses/<slug>.conf` | |
| `scripts/` | `new-business.sh`, `migrate.sh`, `backup.sh`, `restore.sh`, `delete-business.sh`, `retire-containers.sh`, `monitor.sh`, `setup-users.sh` | |
| `systemd/` | Units (copied to `/etc/systemd/system/`) and the journald drop-in | |
| `bin/` | `wholeflow-control` (admin app built in), `wholeflow-api` | root 755 |

## Everyday commands (on the server)

```bash
cd /opt/wholeflow
scripts/new-business.sh <slug> "<Business name>"   # database, roles, keys, migrations (the admin app runs this)
scripts/migrate.sh <slug>                          # apply new files in migrations/ to one business
scripts/migrate.sh --all                           # … to every business
systemctl start wholeflow-backup                   # backup now (the timer runs it at 02:30 IST)
journalctl -u wholeflow-api -u wholeflow-control --since today
tail /var/log/wholeflow/monitor-$(date +%F).log
```

A business's base URL is `https://api.<domain>/b/<slug>`; its anon key is in
`businesses/<slug>/env` (`ANON_KEY`). The service key in the same file must
never leave the server.

## Control service and admin app

The admin app is at `https://admin.<domain>` (sign in with a `control_db` admin;
the first one's password is in `/root/wholeflow-admin.txt`). Its pages are
built into the `wholeflow-control` binary, so updating either is one step.
From the repo root on your PC:

```bash
cd WholeFlow
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o wholeflow-control ./cmd/control
scp wholeflow-control wholeflow:/opt/wholeflow/bin/wholeflow-control.new
ssh wholeflow 'cd /opt/wholeflow/bin && cp wholeflow-control wholeflow-control.prev &&
  mv wholeflow-control.new wholeflow-control && systemctl restart wholeflow-control'
```

The app API (`./cmd/api` → `bin/wholeflow-api`, `systemctl restart wholeflow-api`) the same way.
Roll back with the `.prev` binary. Add or reset an admin on the server:
`/opt/wholeflow/bin/wholeflow-control create-admin EMAIL "Name"` (with
`control.env` loaded; the password is read from stdin).

Remove a business: admin app → business → *Danger zone*, or
`scripts/delete-business.sh <slug> --yes`. It first writes a final
backup to `/opt/wholeflow/backup/final/`; if that fails nothing
is deleted. The admin app's "also delete backups" removes only this server's
nightly copies; final backups stay 90 days here and off-site copies follow the
bucket's retention (for an erasure request, also delete them in the B2
console once Object Lock allows).

## Security

**Who runs what.** `wholeflow-api` runs as system user `wholeflow-api`
(group `wholeflow`, no shell) with a strict sandbox (read-only filesystem, no
capabilities, IPv4/IPv6/Unix sockets only, syscall filter). It reads only
`businesses/<slug>/env` and connects to `control_db` as `wholeflow_api_ro`
(SELECT on `businesses` and `settings`). `wholeflow-control` stays root: it
runs the provisioning scripts (docker, nginx, `/opt/wholeflow/businesses`);
it gets the hardening that does not break them (see the unit). `scripts/setup-users.sh`
creates the user and sets the permissions in the table above; run it again
if a business's env ever shows as unreadable in the monitor (`b/<slug> answered 500`).

**nginx (`nginx/wholeflow.conf`).**
- `api.<domain>` never forwards `/control/admin/` or `/control/internal/`
  (404; `^~` beats every other location). The admin API is only on `admin.<domain>`.
- Headers on both hosts: HSTS, `X-Content-Type-Options: nosniff`,
  `Referrer-Policy: no-referrer` (admin also `X-Frame-Options: DENY`).
- Rate limits per client IP (over → `429`):

  | Where | Rate | Burst |
  |---|---|---|
  | `…/auth/v1/token?grant_type=password`, admin login | 10/min | 20 |
  | `…/auth/v1/token` refresh grants | 60/min | 60 |
  | `/control/` (connect, activate, heartbeat, PC login), website contact form | 10/min | 20 (10) |
  | `/b/<slug>/api/v1/` and the rest of `auth/v1` (phones) | 10/s | 40 |
  | `/b/<slug>/api/v1/pc/` (Tally PC sync, body up to 16 MB) | 50/s | 500 |
  | `admin.<domain>` `/control/admin/` | 10/s | 40 |

  Mobile networks put many phones behind one IP (CGNAT); if the monitor or
  users report `429`s, raise the burst first.
- Timeouts: 60 s everywhere except creating a business, "update all",
  backup download and business delete on the admin host (15 min).
- **Admin IP allowlist (optional):** copy `templates/admin-allowlist.conf.example`
  to `/etc/nginx/wholeflow-admin-allow.conf`, list your IPs, uncomment the
  `include` line in the admin server block, `nginx -t && systemctl reload nginx`.
  Keep SSH access to edit it when your IP changes.
- **Legacy routes:** `/etc/nginx/wholeflow-businesses/<slug>.conf` (old
  GoTrue/PostgREST per business) accept the same service key as the API.
  Retire them after the switch: `scripts/retire-containers.sh stop postgrest`
  (disables the routes, reversible with `start postgrest`), later `remove --yes`.

**Secrets.** Never print or commit `.env`, `control.env`, `api.env`,
`backup.env`, `businesses/*/env`. `MASTER_KEY` and the backup key's
passphrase also belong in the password manager.

## PostgreSQL capacity

`docker-compose.yml` pins `postgres:15.19` and sets, for **8 GB RAM**:
`max_connections=300`, `shared_buffers=2GB` (25 % of RAM),
`effective_cache_size=5GB` (~RAM minus PostgreSQL's buffers, the services and
headroom), `work_mem=4MB`, `maintenance_work_mem=256MB`, `shm_size: 256mb`.
For another size: shared_buffers ≈ RAM/4, effective_cache_size ≈ RAM × 0.6,
and keep `max_connections × work_mem × 2` under about RAM/4. Changing
these restarts the database (`docker compose up -d db`, a few seconds).

Connections: the app API keeps a pool per business database it has served
(`API_TENANT_MAX_CONNS`, default 3) plus a sign-in pool (`API_AUTH_MAX_CONNS`,
default 2); idle connections close after 5 minutes. Worst case
`busy businesses × 5`, plus `wholeflow_api_ro` (≤ 20), the control service
(~5), backups/migrations (2) and PostgreSQL's 3 reserved. Legacy containers
add 5 (PostgREST) + ~10 (GoTrue) per business until retired.
`(300 − 30) / 5 ≈ 54` businesses busy at the same moment; past that, raise
`max_connections` (and RAM) or lower the pool sizes. Check with
`docker compose exec db psql -U postgres -c "select datname, count(*) from pg_stat_activity group by 1 order by 2 desc"`.

## Backups and restore

`scripts/backup.sh`, run by `wholeflow-backup.timer` at 02:30 IST, writes to
**`/opt/wholeflow/backup/`** (root only):

- every database (`control_db`, each `biz_<slug>`) with `pg_dump -Fc`, checked
  with `pg_restore --list`; the roles (`pg_dumpall --globals-only`); the
  configuration and secrets (env files, nginx, systemd units, rclone config,
  `/etc/letsencrypt`);
- written to `.tmp-<run>/`, renamed to `<YYYY-MM-DD_HHMM>/` when done, with an
  `OK` marker (counts) or `FAILED` (what failed; the other databases are still
  dumped) and `SHA256SUMS`. Kept 14 days on the server (`KEEP_DAYS`), by folder name;
- then `select public.purge_old_data()` in every business database (data
  retention), skipped with a note where the function does not exist yet.

**Download them yourself** (for now there is no automatic off-site copy).
From your laptop, e.g. weekly, the newest finished run (one with `OK`):

```bash
ssh wholeflow 'ls /opt/wholeflow/backup'                 # pick a run with OK inside
scp -r wholeflow:/opt/wholeflow/backup/2026-10-08_0230 ~/wholeflow-backups/
# or everything new since last time:
rsync -av --exclude '.tmp-*' --exclude '.lock' wholeflow:/opt/wholeflow/backup/ ~/wholeflow-backups/
```

The files are **not encrypted**: they hold every customer's ledgers and the
server's secrets (`MASTER_KEY`, database passwords, JWT secrets). Keep the
downloaded copies on an encrypted disk (or in an encrypted archive, e.g.
`7z a -p`), never in a shared or synced folder, and delete old ones you no
longer need.

**Optional later — encryption and an automatic off-site copy:** put an age
public key in `/opt/wholeflow/backup.recipients` (made on your laptop:
[../../docs/RUNBOOK_RESTORE.md](../../docs/RUNBOOK_RESTORE.md) "Backup key") and every file is
encrypted (`*.age`; the private key never comes to the server). Then
`BACKUP_REMOTE=<rclone remote:path>` in `backup.env` copies each finished run
off-site (Backblaze B2 with Object Lock, a key without `deleteFiles`); only
encrypted backups are ever sent off-site.

The monitor checks the newest finished run's `OK` marker and age, reports
`FAILED` runs, failed purges, and (when configured) the off-site copy
(`/opt/wholeflow/backup/offsite.status`, `offsite.last-ok`; without one it
notes `offsite=manual`). Log:
`/var/log/wholeflow/backup.log` and `journalctl -u wholeflow-backup`.

Restore (one business into a scratch database and swap, or a fresh VPS):
`scripts/restore.sh` and [../../docs/RUNBOOK_RESTORE.md](../../docs/RUNBOOK_RESTORE.md),
including the quarterly drill. **Never** `pg_restore --clean` into a live database.

**RPO / RTO:** RPO 24 h on the server (nightly dumps; no WAL archiving); if the
server itself is lost, everything since your last download. RTO ≈ 15 min for
one business, ≈ 2 h for a new VPS. Next step for a smaller RPO: continuous WAL
archiving with wal-g or pgBackRest to the same bucket (point-in-time recovery).

## Logs and personal data (DPDP)

Service logs (journal) contain e-mail addresses at sign-in and client IPs;
nginx access logs contain IPs and URLs. Retention:

- journald: 90 days, at most 1 GB (`/etc/systemd/journald.conf.d/wholeflow.conf`,
  installed by `setup-users.sh`);
- nginx: Ubuntu's logrotate (14 days by default, `/etc/logrotate.d/nginx`);
- `/var/log/wholeflow/` (monitor, daily summary, backup): 30 days (`monitor.sh`);
- PostgreSQL container log: Docker json-file, capped at 5 × 20 MB;
- backups: 14 days on the server, the bucket's lifecycle off-site; final
  backups of deleted businesses 90 days.

Keep these periods in the privacy policy; an erasure request must also cover
backups (they expire on their own within those periods).

## OS patching and updates

- **Ubuntu:** `unattended-upgrades` installs security updates daily. Reboots
  for kernel updates: `/etc/apt/apt.conf.d/52wholeflow` with
  `Unattended-Upgrade::Automatic-Reboot "true";` and
  `Unattended-Upgrade::Automatic-Reboot-Time "04:30";` (the quietest hour,
  well after the 02:30 backup; a reboot during a backup leaves that night
  without a finished run, which the monitor reports). All services restart on boot (systemd units
  enabled, Docker `restart: unless-stopped`).
- **Docker images:** PostgreSQL is pinned (`postgres:15.19`). Monthly: read
  the PostgreSQL minor release notes; if there is a new 15.x, back up, change
  the tag, `docker compose pull db && docker compose up -d db`. Keep the same
  Debian base (see the comment in `docker-compose.yml`). PostgreSQL 15 is
  supported until November 2027: plan the move to a newer major in 2027.
- **Go binaries:** rebuild with the current Go release when it has security
  fixes (`go version -m bin/wholeflow-api`).
- `apt list --upgradable` and `docker image ls` monthly; note it in STATUS.md.

## Deploying the hardening (order)

1. On the server: `apt-get install -y acl` (and `age rclone` only if you
   later turn on encryption / off-site copies, see "Backups and restore").
2. Copy the kit files (`scripts/`, `systemd/`, `templates/`, `nginx/`,
   `docker-compose.yml`, `db/`) to `/opt/wholeflow` (keep `.prev` copies of
   `nginx/wholeflow.conf` and `docker-compose.yml`).
3. Remove the old backup cron entry if there is one (`crontab -l`, `/etc/cron.d/`),
   then install and start the timer:
   `cp systemd/wholeflow-backup.{service,timer} /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now wholeflow-backup.timer`;
   run one now: `systemctl start wholeflow-backup` → the newest folder in
   `/opt/wholeflow/backup/` has `OK`; download it once to check (`scp`, above).
   The old backup folder `/var/backups/wholeflow/` is no longer used: delete
   it once the new run is OK (`rm -rf /var/backups/wholeflow`).
4. `scripts/setup-users.sh` (user, group, permissions, journald).
5. Read-only control_db role: `db/api_ro_role.sql` (see its header), put the
   new `CONTROL_DB_URL` in `api.env`.
6. Install `systemd/wholeflow-api.service` and `wholeflow-control.service`,
   `systemctl daemon-reload && systemctl restart wholeflow-api wholeflow-control`;
   `curl -s 127.0.0.1:8300/health`, sign in once, `journalctl -u wholeflow-api -n 20`.
   Then create and delete a test business in the admin app (checks the
   control service's sandbox and `delete-business.sh`).
7. PostgreSQL: check `docker compose exec db postgres --version` matches the
   pinned tag (see compose comment), then `docker compose up -d --remove-orphans db`
   (restarts the database: a few seconds; also removes the old Deno staff
   container, which is no longer in the file);
   `docker compose exec db psql -U postgres -c 'show max_connections'` → 300;
   `docker volume rm wholeflow_deno-cache`. Remove `INTERNAL_TOKEN` from
   `control.env` and `.env` (nothing uses it any more).
8. nginx: `nginx -t && systemctl reload nginx`; then
   `curl -s -o /dev/null -w '%{http_code}' https://api.jitsuji.xyz/control/admin/me` → 404,
   the admin app still signs in, a phone signs in, a Tally PC syncs.

## What was set up (phase 0)

- Ubuntu 24.04 updated; unattended security upgrades; 2 GB swap; time zone Asia/Kolkata.
- SSH keys only (`/etc/ssh/sshd_config.d/00-wholeflow.conf`), fail2ban on SSH.
- ufw: only 22, 80, 443. Container ports are bound to 127.0.0.1.
- Docker CE + compose; nginx; Let's Encrypt certificates for `api.` and `admin.` with auto-renewal (`certbot.timer`).
- Monitoring: `wholeflow-monitor.timer` (every 5 min) and `wholeflow-monitor-daily.timer`
  write `/var/log/wholeflow/` (no alerts by choice); admin app → Server health shows them.
