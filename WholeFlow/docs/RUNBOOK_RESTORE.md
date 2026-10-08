# Restore runbook

How to get WholeFlow back from its backups: one business (most common), or
the whole server (VPS lost). Tools: `deploy/server/scripts/backup.sh` (makes
them), `deploy/server/scripts/restore.sh` (uses them). Practise it every
quarter (checklist at the end).

**Recovery targets (today):** RPO 24 hours (one backup a night, 02:30 IST;
anything entered after the last backup is lost; Tally data comes back with the
next PC sync, phone-entered data does not). If the server itself is lost,
you lose everything since the last backup you **downloaded**. RTO about 2
hours for a fresh VPS, 15 minutes for one business. Shorter RPO needs continuous WAL archiving
(wal-g or pgBackRest to the same bucket): the next step, not set up yet.

## What a backup contains

`/opt/wholeflow/backup/<YYYY-MM-DD_HHMM>/` (14 days on the server), and the
copies you download (`deploy/server/README.md` "Backups and restore"):

| File | What |
|---|---|
| `globals.sql` | roles and password hashes (`pg_dumpall --globals-only`) |
| `control_db.dump` | businesses, subscriptions, devices, admins, sealed tenant secrets |
| `biz_<slug>.dump` | one business database (custom format) |
| `config.tar.gz` | `/opt/wholeflow/{.env,control.env,api.env,backup.env,backup.recipients}`, `businesses/*/env`, kit `nginx/`, `/etc/nginx/sites-*`, `/etc/nginx/wholeflow-*`, `wholeflow-*` systemd units, journald drop-in, rclone config, `/etc/letsencrypt` |
| `SHA256SUMS`, `OK` or `FAILED` | checksums; written last: counts, or what failed |

Final backups of deleted businesses: `/opt/wholeflow/backup/final/` (90 days).

Today the files are **plain** (not encrypted): `config.tar.gz` holds
`MASTER_KEY` and every database password, the dumps every customer's data.
Keep downloaded copies on an encrypted disk. When encryption is turned on
(below), every file name gets `.age` and the commands below need
`-i <key file>`; `restore.sh` handles both kinds.

## Backup key (optional: encryption and off-site copies)

Only if you turn on encryption. On the owner's laptop (not the server):

```bash
sudo apt install age            # or: brew install age / winget install FiloSottile.age
age-keygen | age -p -a > wholeflow-backup-key.age   # asks for a passphrase; prints "Public key: age1…"
```

- Store `wholeflow-backup-key.age` **and** its passphrase in the password
  manager (two separate entries), plus one offline copy (USB stick in a safe).
- Put the printed `age1…` public key on the server:
  `echo age1… > /opt/wholeflow/backup.recipients` (one key per line; add a
  second person's key for a second line if wanted).
- To print the public key again: `age -d wholeflow-backup-key.age | age-keygen -y`.

During a restore, copy the key file to the server (`scp wholeflow-backup-key.age
wholeflow:/root/`), pass it with `-i`, and delete it afterwards
(`shred -u /root/wholeflow-backup-key.age`). `restore.sh` asks for the
passphrase once and keeps the opened key only in `/dev/shm` while it runs.

## A. One business (data mistake, bad migration, corrupted database)

Never restore over the live database. Restore into a scratch database, check,
then swap.

```bash
ssh wholeflow
cd /opt/wholeflow
ls /opt/wholeflow/backup                           # pick the run, e.g. 2026-10-08_0230 (must contain OK)
scripts/restore.sh verify 2026-10-08_0230
scripts/restore.sh db 2026-10-08_0230 <slug> biz_<slug>_restore   # encrypted backups: add -i KEY
docker compose exec db psql -U postgres -d biz_<slug>_restore -c 'select count(*) from public.transactions'
```

If only some rows are needed, copy them from `biz_<slug>_restore` with SQL
and drop it. To replace the whole database:

```bash
scripts/restore.sh swap <slug> biz_<slug>_restore  # live one kept as biz_<slug>_old_<time>, closed to connections
scripts/migrate.sh <slug>                          # bring the restored copy to the current migration
```

Check: sign in to the Owner app for that business; open a shop statement;
let the Tally PC sync once (it re-sends what changed since the backup).
After a few days: `docker compose exec db psql -U postgres -c 'drop database biz_<slug>_old_<time>'`.

Older than 14 days: upload the run from your downloaded copies
(`scp -r ~/wholeflow-backups/<run> wholeflow:/opt/wholeflow/backup/`) and use
its name as above.

## B. Fresh VPS (server lost)

1. **Server.** New Ubuntu 24.04 VPS. Repeat "What was set up" in
   `deploy/server/README.md`: updates, unattended-upgrades, swap, time zone
   Asia/Kolkata, SSH keys only, fail2ban, ufw (22/80/443), Docker CE + compose,
   nginx, certbot, `apt install acl` (plus `age rclone` if backups are encrypted).
2. **Kit.** Copy `WholeFlow/deploy/server/` to `/opt/wholeflow`, plus
   `migrations/`, `auth/` and the built `bin/wholeflow-control`,
   `bin/wholeflow-api` (README "Deploy").
3. **Backups.** Upload your newest downloaded run (one with `OK`):
   `ssh root@<new-ip> mkdir -p -m 700 /opt/wholeflow/backup`, then
   `scp -r ~/wholeflow-backups/<run> root@<new-ip>:/opt/wholeflow/backup/`.
   (With off-site copies configured instead: `rclone config`, `BACKUP_REMOTE`
   in `backup.env`, `scripts/restore.sh fetch <run>`.)
4. **Config.** Unpack the config bundle for review:
   ```bash
   scripts/restore.sh config <run>             # -> /root/restore-config-<run>/  (encrypted: add -i KEY)
   R=/root/restore-config-<run>
   cp -a $R/opt/wholeflow/{.env,control.env,api.env} /opt/wholeflow/   # and backup.env / backup.recipients if present
   cp -a $R/opt/wholeflow/businesses /opt/wholeflow/
   cp -a $R/etc/nginx/wholeflow-* /etc/nginx/ 2>/dev/null || true
   cp -a $R/etc/letsencrypt /etc/              # or skip and issue new certificates in step 7
   ```
5. **Database.** `cd /opt/wholeflow && docker compose up -d db`, wait for
   `docker compose exec db pg_isready`, then
   `scripts/restore.sh all <run>` (encrypted: add `-i KEY`)
   (roles, then every database under its own name with its grants).
6. **Users and services.** `scripts/setup-users.sh`; install the systemd
   units (README "Deploy"); `systemctl enable --now wholeflow-control
   wholeflow-api wholeflow-monitor.timer wholeflow-monitor-daily.timer
   wholeflow-backup.timer`.
7. **nginx and HTTPS.** Link `nginx/wholeflow.conf` and the website's
   `nginx/wholeflow-site.conf` into `/etc/nginx/sites-enabled/`. Point DNS
   (GoDaddy A records `api`, `admin`, `wholeflow`) at the new IP. If
   `/etc/letsencrypt` was restored: `nginx -t && systemctl reload nginx`.
   Otherwise `certbot --nginx -d api.jitsuji.xyz -d admin.jitsuji.xyz` and
   `certbot --nginx -d wholeflow.jitsuji.xyz` (certbot re-adds its lines).
8. **Verify.**
   - `curl -s https://api.jitsuji.xyz/control/health` and
     `curl -s -o /dev/null -w '%{http_code}' https://api.jitsuji.xyz/b/<slug>/api/v1/me` → 401;
   - admin app signs in, lists every business;
   - Owner app and Staff app sign in for one business, numbers match;
   - one Tally PC syncs (it re-sends changes since the backup);
   - `scripts/backup.sh` runs with `OK`;
   - `tail /var/log/wholeflow/monitor-$(date +%F).log` shows `OK`.
9. `rm -rf /root/restore-config-*` once everything runs (and, for encrypted
   backups, `shred -u` the key file you copied over).

## Quarterly restore drill (about 30 minutes)

Do it on the live server (scratch database only) or a cheap throw-away VPS.

- [ ] Newest run has `OK`; `scripts/restore.sh verify <run>` passes.
- [ ] Your downloaded copies are recent (the newest is under a week old) and
      `sha256sum -c SHA256SUMS` passes inside one of them on your laptop.
- [ ] (Encrypted backups only) the key opens with the passphrase from the
      password manager.
- [ ] `restore.sh db <run> <slug> biz_<slug>_drill` restores; row counts of
      `transactions`, `shops` are plausible; `drop database biz_<slug>_drill`.
- [ ] `restore.sh config <run>` unpacks; `control.env` holds `MASTER_KEY`.
- [ ] Once a year: full fresh-VPS restore (section B) on a throw-away VPS,
      timed; update the RTO above.
- [ ] Note date, run used, time taken and problems in `WholeFlow/STATUS.md`.
