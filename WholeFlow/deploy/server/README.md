# WholeFlow server kit (Contabo)

Runs WholeFlow for many businesses on one Ubuntu server: one PostgreSQL with a
database per business, behind nginx at `https://api.<domain>/b/<slug>/`. See
[../../docs/MULTI_TENANT_PLAN.md](../../docs/MULTI_TENANT_PLAN.md).

**Changing (branch `api-layer`, not deployed yet):** the WholeFlow app API
(`wholeflow-api`) serves every business's sign-in and data, and the per-business
GoTrue and PostgREST containers (and the Deno staff service) are retired. New
businesses get no containers. The deploy order is in
[../../docs/API_PLAN.md](../../docs/API_PLAN.md) section 5. Until then, the
setup below describes the server as it runs today.

Live server: `75.119.130.27`, `api.jitsuji.xyz`, `admin.jitsuji.xyz`, files in `/opt/wholeflow`.
SSH: `ssh wholeflow` (key `~/.ssh/wholeflow_vps`; password login is off).

## Layout on the server (`/opt/wholeflow`)

| Path | What |
|---|---|
| `docker-compose.yml`, `.env` | Shared PostgreSQL 15 (localhost only). `.env` holds `POSTGRES_PASSWORD`, `PUBLIC_URL` (mode 600) |
| `db/init/00-roles.sql` | Server-wide roles `anon`, `authenticated`, `service_role` |
| `migrations/` | Copy of `WholeFlow/db/migrations/*.sql` |
| `templates/` | Per-business compose file and nginx block |
| `businesses/<slug>/` | That business's `env` (secrets, keys, ports) and `compose.yml` (mode 700) |
| `nginx/wholeflow.conf` | Linked into `/etc/nginx/sites-enabled`; certbot added the HTTPS parts. Business routes are in `/etc/nginx/wholeflow-businesses/<slug>.conf` |
| `scripts/` | `new-business.sh`, `migrate.sh`, `backup.sh`, `delete-business.sh` |
| `bin/wholeflow-control` | Control service + admin app (systemd `wholeflow-control`, 127.0.0.1:8100; config `control.env`) |
| `staff/` | Staff-management service for every business (container `staff`, 127.0.0.1:8200) |

## Everyday commands (on the server)

```bash
cd /opt/wholeflow
scripts/new-business.sh <slug> "<Business name>"   # database, roles, keys, containers, route, migrations
scripts/migrate.sh <slug>                          # apply new files in migrations/ to one business
scripts/migrate.sh --all                           # … to every business
scripts/backup.sh                                  # what cron runs at 02:30 IST
docker compose -p biz-<slug> -f businesses/<slug>/compose.yml --env-file businesses/<slug>/env logs
```

A business's base URL is `https://api.<domain>/b/<slug>`; its anon key is in
`businesses/<slug>/env` (`ANON_KEY`). The apps use these with the
PostgREST/GoTrue client libraries. The service key in the same file must never leave the server
(phase 2 gives each Tally PC its own key instead).

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

Roll back with `wholeflow-control.prev`. Logs: `journalctl -u wholeflow-control`.
Add or reset an admin on the server:
`/opt/wholeflow/bin/wholeflow-control create-admin EMAIL "Name"` (with
`control.env` loaded; the password is read from stdin).

Remove a business: admin app → business → *Danger zone* (asks for the short name and your password), or `scripts/delete-business.sh <slug> --yes` (containers,
database, route and its control_db records; take a backup first).

## What was set up (phase 0)

- Ubuntu 24.04 updated; unattended security upgrades; 2 GB swap; time zone Asia/Kolkata.
- SSH keys only (`/etc/ssh/sshd_config.d/00-wholeflow.conf`), fail2ban on SSH.
- ufw: only 22, 80, 443. Container ports are bound to 127.0.0.1.
- Docker CE + compose; nginx; Let's Encrypt certificates for `api.` and `admin.` with auto-renewal (`certbot.timer`).
- Nightly backups: `/var/backups/wholeflow/<date>/` (each database as a custom-format dump,
  plus roles), checked with `pg_restore --list`, kept 14 days. Log: `/var/log/wholeflow-backup.log`.
  Off-site copy (Backblaze B2): not set up yet.

## Restore one business (outline)

```bash
docker compose exec -T db pg_restore -U postgres -d biz_<slug> --clean --if-exists < /var/backups/wholeflow/<date>/biz_<slug>.dump
```
