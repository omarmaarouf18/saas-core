# Worklog: OBS-MIN — minimal monitoring (uptime, backup dead-man, host health)

## Task and scope
- Task ID: OBS-MIN
- Item IDs covered: 1 (backup dead-man ping), 2 (host health check + timer), 3 (monitoring runbook)
- Allowed paths (lane from the task prompt): `infrastructure/deploy/backup/**` (only the ping hook), `infrastructure/deploy/monitor/**` (new), `docs/runbooks/MONITORING.md` (new), `docs/runbooks/BACKUP-RESTORE.md` (dead-man section only), `docs/worklog/OBS-MIN.md`
- Agent branch: agent/OBS-MIN-uptime-deadman, created from logic-exploitation (31f20aa1)

## Decisions taken
- One shared fake ping server (`infrastructure/deploy/monitor/test/fake_ping_server.py`) serves both test suites: the backup e2e references it via `../../monitor/test/…`. It logs one `PING <path> <truncated body>` line per ping and, like the fake blob server, never logs a query string (ping URLs have none anyway).
- backup.sh ping semantics: `<url>/start` right after the run gets going, bare `<url>` at the end of a successful run, `<url>/fail` on failure. `/fail` is sent from cleanup() with the freshly written marker text as the body; the `--post-stop` ExecStopPost hook sends it too **only when it writes a fresh marker** (i.e. the script died before its own cleanup: SIGKILL, OOM, timeout) so a failed run produces exactly one `/fail`. Lock refusals send nothing: the run holding the lock owns the ping. Deaths before the ping URL is read (early refusal) also send `/fail`, because ping_fail re-reads the file itself.
- Ping URL handling: first line of a root-only file, default `/etc/quickdelivery-backup/ping` / `/etc/quickdelivery-monitor/ping`; handed to curl through a stdin config (`-K -`, `url = "…"`), everywhere like the SAS; never logged (only the suffix is logged), never on a command line. Only `https://` is accepted in production; `http://127.0.0.1:<port>` is allowed under `BACKUP_ALLOW_HTTP=1` (the local tests). A scheme violation is a WARN that disables the ping; a loose-mode ping file (backup.sh only) is a WARN that does not disable it. A missing/empty file logs one `ping: dead-man ping disabled` line. Ping curl calls are capped at `--connect-timeout 5 --max-time 10`.
- hostcheck.sh: single `docker inspect` over all containers, filtered client-side by the compose project label (`com.docker.compose.project`), fields pipe-joined so the column count is stable (the health column renders `none` for containers without a healthcheck). A project container that is not `running` fails the check, even without a healthcheck (caddy and the reviewer console have none but must stay up). Restart-in-a-loop detection compares `RestartCount` with the previous run's snapshot under `/var/lib/quickdelivery-monitor/restart-counts` (first run is a baseline). The backup `FAILED` marker check makes a failed backup visible within 5 minutes even before the backup's own daily-expiry alert.
- hostcheck.sh always exits 0 and logs one outcome line (`hostcheck: ok: …` / `hostcheck: FAIL: <reasons>`); a non-zero exit on a timer job would add noise without informing anyone. All findings are collected and sent as ONE `/fail` body.
- The monitor unit deliberately does **not** create an empty ping file (unlike the SAS): absent file = feature off, which is not a failure state.
- install flows mirror the backup's: `--set-ping` (masked input, no shell history, mode 600, https-validated), then a plain idempotent install that enables the timer and runs one check immediately.
- The e2e's "placeholder recipient" refusal was reworked inside item 1's commit (see Changes note): the repo's `backup-recipient.pub` holds the owner's real age key since a later OPS-BACKUP commit, so pointing `RECIPIENT_FILE` at it can no longer demonstrate the not-yet-configured refusal. The test now writes a throwaway placeholder file instead of touching the repo copy.
- Systemd unit fields: `Nice=15`, `IOSchedulingClass=idle`, `CPUSchedulingPolicy=idle` (below the backup's Nice=19 — the host check is the least important recurring job), `MemoryHigh=48M`/`MemoryMax=64M`, `TimeoutStartSec=2min`, `ProtectSystem=full`, `ProtectHome=yes`, `DOCKER_CONFIG` pointed at the monitor's state dir (same pattern as the backup unit), timer `OnCalendar=*-*-* *:0/5` + `RandomizedDelaySec=30`, not Persistent (a run missed during a planned reboot must not alarm through the grace).

## Changes per commit (message only — NO SHAs)
1. `OBS-MIN: backup dead-man ping (start/success/fail)` — backup.sh ping hooks (start/success/fail; cleanup + post-stop), install.sh `--set-ping`, e2e-local.sh extensions (fake ping server, ping order/secret assertions, disabled-ping and dead-endpoint runs), the joint fail on the stale placeholder-recipient check fixed with a throwaway file, and the short "Dead-man ping (OBS-MIN)" section in BACKUP-RESTORE.md replacing the stale "backup.sh could send that ping on success" outlook.
2. `OBS-MIN: 5-minute host health check (disk, memory, containers, restarts, backup marker)` — hostcheck.sh, quickdelivery-monitor.service/.timer, monitor install.sh with `--set-ping`, and the local test hostcheck-local.sh.
3. `OBS-MIN: monitoring runbook (uptime, backup dead-man, host health)` — docs/runbooks/MONITORING.md.
4. this worklog commit.

Note for the owner on commit 1's message: its last paragraph contains a stray leading " Ukra follows" typo before the sentence about the BACKUP-RESTORE.md note style (a make commit MSG quoting slip). The commit content is unaffected; the task forbids amending published commits, so it stays as-is and is disclosed here and in the task report.

## Verification (per the task's verification section)
- `shellcheck -x` on all six shell scripts (backup.sh, backup/install.sh, backup/test/e2e-local.sh, monitor/hostcheck.sh, monitor/install.sh, monitor/test/hostcheck-local.sh) — clean; literal closing output:

```
SHELLCHECK: all 6 scripts clean
PY COMPILE OK
```

  (the py_compile line covers fake_ping_server.py, not a shell script).
- `systemd-analyze verify` on the monitor units. A bare verify on this dev machine cannot resolve `docker.service`/`sysinit.target`, so it ran against a synthetic root containing only the units, the script and stub dependencies — literal output:

```
--- systemd-analyze --root verify quickdelivery-monitor.service quickdelivery-monitor.timer ---
verify RC=0
--- systemd-analyze calendar parse checks (as install.sh does) ---
hostcheck calendar RC=0
backup calendar RC=0
```

- Local e2e for backup.sh with the fake ping server (also re-verified all pre-existing behavior after the ping edits). Literal filtered output:

```
PASS: 5 artifacts (mongo, 2 volumes, env, SHA256SUMS) written locally and uploaded with 201
PASS: backup log contains neither the SAS sig, the Mongo password nor an .env value
PASS: ps sampled every 50 ms during the run (37112 lines): no SAS sig, no Mongo password, no ping URL on any command line
PASS: run 1 pinged /start then success to the fake endpoint in order, no /fail, and every ping body is secret-free
PASS: overlapping run refused by flock (exit 1), no FAILED marker, no /fail ping
PASS: failed run pinged /fail once, body mentions the failed step, no secret in the body
PASS: recovery run pinged success again (last of 13 pings so far)
PASS: missing ping file: run succeeds, one 'ping disabled' log line, no ping sent
PASS: unreachable ping endpoint: backup still succeeds, WARN logged, URL and path not in the log, no ping logged
PASS: bash -x: refused (exit 2), no secret in the output
PASS: placeholder recipient: refused (exit 1), no secret in the output
E2E RESULT: PASS
```

  (After the ping edits the first full e2e pass ended in the stale
  placeholder-recipient refusal being missed (no refusal possible anymore);
  once the check was switched to a throwaway placeholder file, a full
  e2e re-run passed. The pre-existing segments were green in both runs.)
- Local test of hostcheck.sh with the fake ping server. Literal filtered output:

```
PASS: ok line logged, one plain success ping
PASS: missing ping file: one 'ping disabled' line, ok line still logged, no ping sent
PASS: RestartCount increase detected, /fail ping carries the container name and counts
PASS: MemAvailable breach detected, /fail reason in the ping body
PASS: disk breach detected, /fail reason in the ping body
PASS: unhealthy (but running) container detected, /fail reason in the ping body
PASS: stopped container detected, /fail reason in the ping body
PASS: backup FAILED marker detected, /fail reason in the ping body, marker removed
PASS: all clear: ok line and recovery success ping
PASS: no ping URL in any hostcheck log line or in ps during a run
PASS: bash -x refused (exit 2), no URL printed
HOSTCHECK RESULT: PASS
```

  Three consecutive hostcheck-local runs passed (the mid-development failures
  are recorded in the decision notes; the disk threshold breach is
  simulated with `DISK_MAX_PCT=0` (env override as the task allows), the
  unhealthy container is a real tiny busybox container with a failing
  healthcheck, and the restart-trigger container is a busybox
  `sleep 20; exit 1` under `--restart on-failure:1` seeded long enough that
  both hostcheck runs happen between its first crash (count 0→1) and its
  second.
- `make check` before every commit (`make commit` refuses otherwise), three
  gate stamps, as captured: item 1 `scope: docs infra-tests compose=prod`,
  item 2 `scope: docs compose=prod`, item 3 `scope: docs infra-tests`. No Go
  or frontend scope is affected by any OBS-MIN file.
- Ping URL secrecy: asserted in both suites across run logs, ps samples
  (50 ms sampling during the runs), the ping bodies themselves and the
  xtrace refusal output. The "ping log" belongs to the fake endpoint itself
  and does contain the ping path by design (the tests check that the
  hostcheck/backup logs do NOT contain the path or URL).

## Unverified
- The healthchecks.io / UptimeRobot / Better Stack portal steps in MONITORING.md have not been clicked through by this task (no third-party account access); they follow the services' documented menus and the CHECK parameters (1 day/2 h, 5 min/10 min) mirror the timer's real schedule.
- Timer/install behaviour on the real VM (`systemctl enable --now`, first-run, journald output labels) is untested on actual Ubuntu 22.04+ systemd: verified only by `systemd-analyze verify` on a synthetic root plus the pre-push gate's compose validation.
- hostcheck.sh has not run against the full production container set (9
  containers, 2 without healthchecks); the local test used 3 throwaway
  containers, including the two patterns that differ (with/without
  healthcheck). The inspect format and the project-label filter are the only
  production-specific assumptions.
- The `RestartCount` snapshot file grows with one line per project container
  and is rewritten fully each run; behavior at compose scale changes
  (containers appearing/disappearing) is a benign prune by design but was
  not verified with a live scale change. The mid-development flake seen in
  the local test (an `--rm` container being auto-removed on docker stop
  instead of showing as exited) is fixed in the final test and does not
  exist in production code paths.

## Follow-ups / out-of-lane findings
- The backup runbook's "Failure alerts (later, not installed)" section still describes the OnFailure=/Discord-webhook idea as uninstalled; OBS-MIN delivers the dead-man pings requested there but leaves the optional Discord/email alert path as the runbook's own future option (intentionally out of this task's lane). The stale outlook sentence ("backup.sh could send that ping on success, which needs a small change") was folded into the new dead-man section as part of the allowed dead-man lane.
- If the owner ever wants a second healthchecks.io check (e.g. per-container alerts), hostcheck.sh would need a second ping URL or a split env file; not built — one check covers the whole host.
- The `backup.env`/`hostcheck.env` override files now carry the ping-related knobs (PING_FILE) too; the header comments of both scripts list all knobs for the owner.

## Open questions
- none
