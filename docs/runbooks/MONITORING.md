# Runbook: monitoring — uptime, backup dead-man, host health (OBS-MIN)

Owner-only procedures for the three monitoring layers of the production VM.
The scripts and units live in
[infrastructure/deploy/backup/](../../infrastructure/deploy/backup/) and
[infrastructure/deploy/monitor/](../../infrastructure/deploy/monitor/). The
backup's own dead-man section is in
[BACKUP-RESTORE.md](BACKUP-RESTORE.md#dead-man-ping-obs-min).

> [!NOTE]
> The agent that wrote this had no access to the VM, to Azure or to the
> third-party dashboards (healthchecks.io, UptimeRobot/Better Stack). The
> commands follow the behaviour verified in the local tests
> (`infrastructure/deploy/backup/test/e2e-local.sh`,
> `infrastructure/deploy/monitor/test/hostcheck-local.sh`); the portal steps
> follow the services' documented menus but nobody has clicked through each
> screen for this runbook yet. If a label differs, look for the nearest
> equivalent; when unsure, stop and ask before continuing.

## The three layers

| Layer | Watches | Where it lives | Catches |
| :--- | :--- | :--- | :--- |
| 1. External uptime | public endpoints from outside the VM | UptimeRobot or Better Stack (free tier), poll every 5 min | VM/network down, TLS broken, Caddy dead — the whole site unreachable even while the inside "looks fine" |
| 2. Backup dead-man | the daily backup run | healthchecks.io check, pinged by `backup.sh` on /start, success and /fail | backup that never runs, hangs or dies: VM fine but backups silently broken |
| 3. Host health | the VM from the inside every 5 min | healthchecks.io check, pinged by `hostcheck.sh` on success /fail | disk filling up, memory starvation, containers unhealthy/stopped/restarting in a loop, a failed backup while it happens |

Layer 1 sees what a customer sees. Layers 2 and 3 see what dashboards of
layer 1 cannot: a backup job that dies overnight, or a crash-looping
container behind a Caddy that still answers.

## Accounts and checks to create

Two free accounts are enough. Create them with a password manager entry and a
dedicated email alias if possible. **Ping URLs and monitor URLs are secrets:
never paste them into the repository, a chat or a ticket. They are stored on
the VM only, root-only, by the install scripts.**

### healthchecks.io (free: 20 checks)

Create two checks:

1. **Check `qd-backup`** — *Settings* → Period **1 day**, Grace period
   **2 h**. The backup runs daily at 03:30 Africa/Cairo with up to 20 min
   random delay, so any day without a success ping (and without a /fail)
   alerts you within grace after ~26 h. Alternative: set the schedule as cron
   `30 3 * * *`, timezone Africa/Cairo; keep grace 1-2 h.
2. **Check `qd-hostcheck`** — Period **5 min**, Grace **10 min**. hostcheck
   runs every 5 minutes (+30 s jitter) and pings the bare URL on success and
   `/fail` when a check fails, so most host problems alert within minutes;
   the grace covers missed runs while the VM reboots.

For both checks open the check's **ping URL** page (the plain `https://hc-ping.com/<uuid>`
line, no suffix and no trailing slash — the scripts append `/start` and
`/fail` themselves). Note the URLs in the password manager as "backup ping"
and "hostcheck ping".

Alert delivery: *How it works → Notifications* — email is configured on
signup; to get it on the phone, add a **Pushover**, **Telegram** or **ntfy**
integration and select it for both checks (free tier allows the
integrations; their accounts and tokens live in the password manager too).
There is no SMTP on the VM, which is exactly why the delivery is external.

### UptimeRobot or Better Stack (free tier)

Two HTTPS monitors, each with a 5-minute interval:

| Monitor | URL | Expected |
| :--- | :--- | :--- |
| `qd-api-health` | `https://api.logiclinkeg.tech/health` | HTTP 200 |
| `qd-kyc` | `https://kyc.logiclinkeg.tech/` | HTTP 200 |

Add the same alert channels (email + phone app integration) as for
healthchecks.io.

## Install on the VM

From a checkout of this repo on your machine (`<you>@<vm>` is the SSH login):

```bash
rsync -a infrastructure/deploy/backup/ <you>@<vm>:quickdelivery-backup/
rsync -a infrastructure/deploy/monitor/ <you>@<vm>:quickdelivery-monitor/
```

(If `rsync` is unavailable and the target directory already exists from an
earlier install, remove it first: `ssh <you>@<vm> 'rm -r
quickdelivery-monitor'`, then `scp -r` it again — never `scp -r` into an
existing directory, it nests.)

On the VM (whole copy; everything as root):

```bash
sudo ~/quickdelivery-backup/install.sh --set-ping    # paste the backup ping URL
sudo ~/quickdelivery-backup/install.sh              # installs/updates and runs one backup now
sudo ~/quickdelivery-monitor/install.sh --set-ping  # paste the hostcheck ping URL
sudo ~/quickdelivery-monitor/install.sh             # installs/updates, enables the timer, runs one check
```

Both `install.sh` scripts store the URL root-only (mode 600) in
`/etc/quickdelivery-backup/ping` and `/etc/quickdelivery-monitor/ping` and
are idempotent: re-run them after every repo update. The ping files are
never touched by a plain install: an existing one stays.

Confirm each one worked — each journal shows one outcome line:

```bash
journalctl -n 5 -o cat _SYSTEMD_UNIT=quickdelivery-backup.service    # BACKUP OK ... and ok: ping ... lines
journalctl -n 5 -o cat _SYSTEMD_UNIT=quickdelivery-monitor.service   # hostcheck: ok: ... line
systemctl list-timers quickdelivery-backup.timer quickdelivery-monitor.timer
```

The healthchecks.io pages of both checks now show pings. In the backup
check a successful run appears as a *latest ping* of the plain URL
preceded by a `/start` line; in the hostcheck check the bare URL is the
ping of every passing 5-min run.

To switch the dead-man feature off on either side, delete the ping file:
`sudo rm /etc/quickdelivery-backup/ping` (or the monitor's). One "ping
disabled" line appears in the journal; nothing fails.

## Test each alert on purpose

Do each of these once after the install, then whenever you feel a layer got
rusty.

1. **Backup /fail (the exact alert path).** Break the SAS the way a real
   expiry would — on the VM, in the root-only config dir only:

   ```bash
   sudo cp /etc/quickdelivery-backup/sas /etc/quickdelivery-backup/sas.good
   sudo sed -i 's/.\{8\}$/0deadbeef/' /etc/quickdelivery-backup/sas   # breaks on purpose
   sudo systemctl start quickdelivery-backup.service                 # this run fails on the upload
   ```

   Expected: the upload fails with `HTTP 403 <Code>AuthenticationFailed</Code>`
   in `journalctl -u quickdelivery-backup.service`, backup.sh pings
   `<backup-url>/fail`, the healthchecks.io check page turns **red
   immediately** (a /fail does not wait for grace) and the alert (email +
   push) arrives. Then restore:

   ```bash
   sudo mv /etc/quickdelivery-backup/sas.good /etc/quickdelivery-backup/sas
   sudo systemctl start quickdelivery-backup.service
   ```

   The run succeeds, pings the plain URL and the check turns green. In this
   whole test the broken SAS never travels beyond the VM.

2. **Hostcheck fails (a real container problem, not staged).** Stop one
   service container for one grace window:

   ```bash
   docker stop saas-user-service
   ```

   Expected: the next hostcheck (within 5 min) pings `<hostcheck-url>/fail`
   with body `host not healthy: container saas-user-service is exited`, the
   check page shows the body on the *ping details* view and the alert
   arrives. Then:

   ```bash
   docker start saas-user-service
   ```

   The next hostcheck pings the success URL and everything returns to green.

   A threshold stage without touching real disk/memory: add a one-line
   override in `/etc/quickdelivery-monitor/hostcheck.env` (root, mode 600,
   e.g. `DISK_MAX_PCT=71`), `sudo systemctl start
   quickdelivery-monitor.service`, confirm the alert, then delete the line
   and run the check again.

3. **Backup dead-man (the silence detector).** In healthchecks.io UI,
   temporarily set the `qd-backup` check's Period to **1 min** with grace
   **1 min**: after ~2 min it turns red and emits the same alert pipeline
   without touching the VM. Restore Period 1 day / grace 2 h afterwards.

4. **External monitors.** The realistic test is the same one layer 2 uses —
   briefly stop the edge: `docker stop saas-caddy`, wait for a ping cycle (≤
   5 min), confirm both UptimeRobot monitors alert, then `docker start
   saas-caddy`. Do this at a low-traffic hour; until Caddy returns, every
   public request sees TLS/refused errors. Alternatively confirm delivery
   from the monitor dashboards' test/confirm buttons.

## What to do when each alert fires

### External uptime monitor is down (`qd-api-health` / `qd-kyc`)

1. `ssh <you>@<vm>`; `docker ps --format '{{.Names}} {{.Status}}'`.
2. Caddy is the public edge: `docker logs --tail 50 saas-caddy`. If Caddy is
   dead/restarting, `docker restart saas-caddy` and watch TLS renewal logs —
   if the ACL/KYC monitor still fails, follow the renewal troubleshooting in
   the deployment docs.
3. `systemctl status docker` for a Docker daemon problem.
4. If a service container is unhealthy follow the hostcheck section below.
5. Once all is green, note the downtime in your log; a >10 min outage that
   involved data should be followed by a successful backup run and, if data
   may have been lost, the restore procedure of BACKUP-RESTORE.md.

### `qd-backup` check is red

The daily backup did not ping success (or sent no ping at all after grace).
Work from the top of [BACKUP-RESTORE.md](BACKUP-RESTORE.md) → *When a backup
fails*; short version:

1. `systemctl status quickdelivery-backup.service` and `journalctl -u
   quickdelivery-backup.service --since -2d` — find the first ERROR line.
2. Match it against the failure table in BACKUP-RESTORE.md (SAS expired
   → renew; Disk full → free space; mongodump OOM → raise DUMP_MEMORY; …).
3. A `ping: dead-man ping disabled` line here means the ping file was
   deleted: re-add it with `install.sh --set-ping`.
4. After the fix, `sudo systemctl start quickdelivery-backup.service` must
   end with `BACKUP OK: run…` and ping the plain URL.
5. If the VM was rebooted and backups were missed for more than a day and
   the last local run is older than it should be, run the restore procedure
   (step 7) on the newest local/off-host run as soon as possible to be sure
   the last good backup is REALLY good.

### `qd-hostcheck` check is red

Read the failure reason on the check's *ping details* page (the `/fail` body
is one line, `host not healthy: <reasons joined with "; ">`), then:

| Reason (in the body) | First reactions |
| :--- | :--- |
| `disk / usage N% >= 85%` | `docker system df`; `docker system prune -f` (orphan layers/images), `docker system prune` (Attention: deletes stopped containers too), `journalctl --vacuum-size=200M`. `/var/backups/quickdelivery` is already pruned by the backup's KEEP_LOCAL=3; if it still grew, look for a volume-fill loop |
| `MemAvailable NMB <= 80MB` | `docker stats --no-stream`, `free -h`. The usual suspects: the dump/tar sidecars during a backup (capped at 192 MB / 64 MB) and mongod. Consider reviewing the backup time or a bigger VM |
| `container <name> health=unhealthy` | `docker inspect <name> --format '{{json .State.Health.Log}}'` (the last entries show what failed), `docker logs --tail 100 <name>`. Often a dependency (Mongo/Redis) just restarted — wait one run; otherwise restart the container: `docker restart <name>` |
| `container <name> is exited` | `docker logs --tail 100 <name>`; if the logs look stale rather than crashing, `docker start <name>`; if the compose service is broken: `docker compose -p saas-core-deploy up -d <service>` from the deploy dir |
| `container <name> RestartCount a -> b (restart loop?)` | `docker events --since -10m --filter container=<name>`, `docker logs` between those times; a crash loop usually needs an app-level fix (env/config/dependency). If the loop has been building for minutes, restart once and watch |
| `no containers found for compose project saas-core-deploy` | Docker daemon gone or the whole stack being removed: `systemctl status docker`, then `docker compose -p saas-core-deploy up -d` from `infrastructure/deploy/` (the deploy flow) |
| `backup FAILED marker present: …` | The last backup run failed: see *When a backup fails* in BACKUP-RESTORE.md; the marker disappears on the next success |

The threshold names and defaults (`DISK_MAX_PCT`, `MEM_MIN_MB`) are
documented at the top of
[hostcheck.sh](../../infrastructure/deploy/monitor/hostcheck.sh); tune them
in `/etc/quickdelivery-monitor/hostcheck.env` only after confirming with
`df -h /; free -m` that the VM has real headroom above the new values.

## Cost

All three layers are on free tiers: healthchecks.io free = 20 checks (2
used), UptimeRobot free = 50 monitors (2 used), Better Stack free = 10
monitors. Keep it that way for now; if you ever outgrow them, self-hosting
healthchecks.io on the tiny VM costs more RAM than it is worth — the free
tier is fine at this scale.
