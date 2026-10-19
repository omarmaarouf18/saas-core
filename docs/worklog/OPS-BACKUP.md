# Worklog: OPS-BACKUP — daily encrypted off-host backups with a tested restore

## Task and scope
- Task ID: OPS-BACKUP
- Item IDs covered: design requirements 1–5 of the task prompt (backup script,
  systemd units + install.sh, failure signal, off-host retention docs, restore)
- Allowed paths (lane): `infrastructure/deploy/backup/**` (new),
  `docs/runbooks/BACKUP-RESTORE.md` (new), `docs/worklog/OPS-BACKUP.md`
- Agent branch: agent/OPS-BACKUP-daily-backups, created from logic-exploitation
  (75367b57). The worktree did not exist when the task started; it was created
  with `make worktree-new TASK=OPS-BACKUP SLUG=daily-backups`.
- No access to the VM or to Azure: everything here is installed once by the owner
  (runbook `docs/runbooks/BACKUP-RESTORE.md`).

## Design summary
- **What**: every Mongo database (`mongodump --archive --gzip`), the volumes
  `saas_platform_documents_data` and `saas_platform_attachments_data` (names
  checked against `docker-compose.prod.yml`: they match), and `caddy_data`
  when present (optional: a missing one is a WARN, not a failure). Redis is out
  of scope (prompt).
- **Where**: locally under `/var/backups/quickdelivery/<UTC stamp>/` (last 3
  runs), off-host in Azure Blob `<container>/<hostname>/<stamp>/<file>`.
- **How encrypted**: each artifact is streamed `producer | age -R backup-recipient.pub -o file.partial`
  (no full dump in RAM or on disk in plaintext). `backup-recipient.pub` is a
  placeholder; backup.sh and install.sh refuse to run until it holds an `age1…` key.
- **Upload**: `curl` Put Blob (`x-ms-blob-type: BlockBlob`), URL from the
  root-only `/etc/quickdelivery-backup/sas`, passed to curl as a config on stdin
  (`-K -`), never as an argument. `SHA256SUMS` is uploaded last as the
  "run complete" marker.
- **Retention**: local 3 runs (pruned only after a fully successful run);
  off-host via a Portal lifecycle rule (Cool at 7 days, delete at 30) plus an
  optional 14-day time-based immutability policy.
- **Schedule**: `OnCalendar=*-*-* 03:30:00 Africa/Cairo`, `RandomizedDelaySec=20min`,
  `Persistent=true`.

## Decisions taken
- **mongodump runs in a sidecar container, not `docker exec saas-mongo`
  (owner decision, asked in chat after the stop-condition measurement below).**
  The sidecar is `docker run --network container:saas-mongo --memory 192m --memory-swap 192m`
  with the image of the running saas-mongo (`mongo:7`, already on the VM),
  `--numParallelCollections=1`. Reason: a process started with `docker exec` runs
  inside the 400m mongo cgroup, and a cgroup OOM there kills mongod (the biggest
  process), not mongodump. In the sidecar, the worst case is that the dump is
  OOM-killed (exit 137, logged with a hint to raise `DUMP_MEMORY`) while mongod
  stays untouched.
- Mongo credentials are read with `docker exec saas-mongo printenv MONGO_INITDB_ROOT_USERNAME/PASSWORD`,
  the same variables the compose healthcheck uses (checked in
  `docker-compose.prod.yml`), instead of parsing `/home/deploybot/.env`.
  The password reaches mongodump as a YAML `--config` file written from stdin
  onto a tmpfs inside the sidecar. It is never on a command line or in the
  sidecar's environment. (`--config /dev/stdin` failed with `permission denied`,
  hence the tmpfs file.)
- Volumes are read through a read-only mount (`-v vol:/src:ro`) into a
  short-lived container instead of the host mountpoints: there is no dependency
  on Docker's data-root layout or volume driver, and `:ro` guarantees no
  writes. The image is the same `mongo:7` (GNU tar, already on the VM, so
  nothing new is pulled) rather than alpine. GNU tar exit 1 ("file changed
  while reading", i.e. an upload in progress) is a WARN; anything else fails
  the run.
- The SAS file holds the whole **Blob SAS URL**. backup.sh validates that the
  host is `*.blob.core.windows.net`, that it is https, and that `sp=` contains
  only `c`/`w`. It accepts `si=` (stored access policy) and logs that the
  permissions are then in the policy. It fails when the SAS has expired and
  warns 30 days before expiry. The runbook recommends a stored access policy
  (revocable) and notes that Create alone blocks overwrites.
- Failure signal: the script's EXIT trap writes `/var/lib/quickdelivery-backup/FAILED`
  (step + exit code); `ExecStopPost=backup.sh --post-stop` covers kills
  (SIGKILL, MemoryMax, timeout) and prints the marker, so it shows in
  `systemctl status`. A successful run removes it and writes `last-success`.
  A lock refusal does not write the marker.
- backup.sh refuses to run under `bash -x` (it would print secrets), refuses a
  group/other-readable SAS file, and refuses to start below `MIN_FREE_MB=2048`.
- Unit: `Nice=19`, `IOSchedulingClass=idle`, `CPUSchedulingPolicy=idle`,
  `MemoryHigh=96M`, `MemoryMax=128M` (measured below: 33 MiB anon peak),
  `ProtectSystem=full`, `ProtectHome=yes` (with `DOCKER_CONFIG` pointed under
  `/var/lib`, so the docker CLI does not need `/root`), `PrivateTmp`,
  `NoNewPrivileges`, `UMask=0077`, `TimeoutStartSec=2h`.
- install.sh `--set-sas` reads the SAS URL with `read -s` (no echo, no shell
  history). install.sh installs `age` with apt-get only when it is missing.
- The runbook adds "What is NOT in the backup": documents and attachments are
  AES-256-GCM encrypted at rest with `DOCUMENT_ENCRYPTION_KEY`
  (`shared/infra/storage/storage.go`), so **the volume backups cannot be read
  without the `.env` secrets**. The owner must keep `.env` offline.

## Changes per commit (message only — NO SHAs)
1. `OPS-BACKUP: backup.sh (sidecar mongodump, age, create/write SAS upload)`
2. `OPS-BACKUP: make backup.sh executable` (`core.fileMode=false` dropped the
   mode in commit 1; amending is not allowed, so it is a separate commit)
3. `OPS-BACKUP: systemd service + timer and install.sh`
4. `OPS-BACKUP: restore.sh for test restores on the owner's machine`
5. `OPS-BACKUP: local end-to-end test with a fake Blob endpoint`
6. `OPS-BACKUP: backup and restore runbook`
7. `OPS-BACKUP: worklog` (this file)

## Verification

`make check` ran before every commit; each run ended with
`== pre-push gate: all checks passed (scope: docs infra-tests compose=prod) ==`
and wrote a gate stamp.

### Stop condition: memory of mongodump in the 400m mongo container

Disposable `mongo:7` with `--memory 400m --wiredTigerCacheSizeGB 0.25` (as in
production), seeded with about 300k documents (on-disk sizes printed by the
seed: auth_db 1957888, chat_db 9281536, notification_db 8245248, user_db
11366400 bytes). The peak `anon` of the container's cgroup was sampled every
50 ms. Literal output:

```text
A exec: before=68
max=391 after=127 size=3501785
B sidecar: before=70
mongod-cgroup max=296 after=296 size=3502352
oom_kill 0
```

(A = `docker exec … mongodump`, B = the same dump from a sidecar container: the
mongod cgroup alone peaks at 296 MiB, so the exec'd mongodump added about 95 MiB
to the same cgroup and brought it to 391/400.) Sidecar memory need, literal:

```text
limit=64m exit=137 oom=true size=10
limit=128m exit=137 oom=true size=111850
limit=192m flags='' exit=137 oom=true size=111850
limit=256m flags='' exit=137 oom=true size=1384330
limit=64m flags='--numParallelCollections=1' exit=137 oom=true size=111850
limit=96m flags='--numParallelCollections=1' exit=137 oom=true size=621130
limit=128m flags='--numParallelCollections=1' exit=0 oom=false size=3498357
```

The first two lines had no extra flags (the first loop did not print a
`flags=` field). Hence `--numParallelCollections=1` and `--memory 192m`
(1.5× the passing 128m). The production data size is unknown to me; the cap is
an env setting (`DUMP_MEMORY`).

### shellcheck

```text
$ shellcheck --version | sed -n 2p
version: 0.10.0
$ shellcheck -x backup.sh install.sh restore.sh test/e2e-local.sh; echo "exit=$?"
exit=0
```

(run in `infrastructure/deploy/backup/`. `test/e2e-local.sh` has a file-level
`# shellcheck disable=SC2015` with a comment: its `A && B || fail` lines are
intended. `python3 -m py_compile test/fake_blob_server.py` printed nothing and
exited 0.)

### SAS is only read from the file and never echoed (grep proof)

```text
$ grep -n -E "set -x|xtrace|SAS_URL|SAS_TOKEN|curl" backup.sh
13:# with curl to Azure Blob Storage using a create/write-only SAS URL read from
48:# Refuse xtrace: it would print the SAS URL and the Mongo password.
50:	echo "backup.sh: refusing to run with xtrace (set -x) enabled: it would print secrets" >&2
161:for tool in docker age curl flock sha256sum numfmt; do
175:SAS_URL="$(head -n 1 "$SAS_FILE" | tr -d '\r\n\t ')"
176:[ -n "$SAS_URL" ] || die "$SAS_FILE is empty: paste the container SAS URL (runbook step 3)"
177:SAS_BASE="${SAS_URL%%\?*}"
178:SAS_TOKEN="${SAS_URL#*\?}"
179:if [ "$SAS_TOKEN" = "$SAS_URL" ] || [ -z "$SAS_TOKEN" ]; then
195:	for kv in $SAS_TOKEN; do
319:# The URL (with the SAS signature) goes to curl through a config on stdin
327:	code="$(printf 'url = "%s/%s/%s/%s?%s"\n' "$SAS_BASE" "$BLOB_PREFIX" "$STAMP" "$name" "$SAS_TOKEN" |
328:		curl -K - --silent --show-error --retry 3 --connect-timeout 20 --max-time 3600 \
333:		die "curl failed: ${err%%\?*}"
$ grep -n -E '^[[:space:]]*set -[a-z]*x|set -o xtrace' backup.sh install.sh || echo '(no match)'
(no match)
```

`SAS_TOKEN` is only ever passed to `printf` (a bash builtin) piped into
`curl -K -`. Logged lines use `SAS_BASE` (account + container, not secret)
only. Upload errors log the HTTP status and Azure `<Code>`, never the URL or
the body. The e2e test also checks this at runtime: no log line and no `ps`
sample (every 50 ms during a full run, 16384 lines) contained the SAS `sig` or
the Mongo password.

### systemd-analyze

```text
$ systemd-analyze calendar --iterations=3 '*-*-* 03:30:00 Africa/Cairo'
  Normalized form: *-*-* 03:30:00 Africa/Cairo
    Next elapse: Tue 2026-10-20 03:30:00 EEST
       (in UTC): Tue 2026-10-20 00:30:00 UTC
       From now: 17h left
   Iteration #2: Wed 2026-10-21 03:30:00 EEST
       (in UTC): Wed 2026-10-21 00:30:00 UTC
       From now: 1 day 17h left
   Iteration #3: Thu 2026-10-22 03:30:00 EEST
       (in UTC): Thu 2026-10-22 00:30:00 UTC
       From now: 2 days left
--- verify as committed:
quickdelivery-backup.service: Command /usr/local/lib/quickdelivery-backup/backup.sh is not executable: No such file or directory
quickdelivery-backup.service: Command /usr/local/lib/quickdelivery-backup/backup.sh is not executable: No such file or directory
exit=1
--- verify with ExecStart pointing at an existing copy of backup.sh:
exit=0
```

The only complaint about the committed units is the install path, which does
not exist on this machine. With `ExecStart`/`ExecStopPost` rewritten (sed) to a
copy of backup.sh, `systemd-analyze verify` passes on both units. The
`$ systemd-analyze calendar …` line was added here to name the command; the
lines under it are its literal output. The `--- verify …` lines are labels
echoed by the command I ran.

### Unit memory (MemoryMax sizing)

The whole e2e test ran inside a user scope, sampling the scope's `anon`. The
test harness itself (python fake server, ps sampler) is included, so this is
an upper bound for bash + docker CLI + age + curl:

```text
e2e exit=0
peak cgroup memory.peak=66764800
peak anon of whole e2e scope: 33 MiB
```

### install.sh (as root, in a throwaway mongo:7 container)

Stub `systemctl`/`systemd-analyze`/`docker`/`journalctl`/`curl` print their
arguments, the real `age` binary is copied in, and `--network none` is used.
Runs: A placeholder key, B install with empty SAS, C `--set-sas` with junk,
D `--set-sas` with a valid-looking URL (the fake sig masked by sed), E re-run.
`age1…` keys masked by sed. Literal:

```text
### A: placeholder key
== 1/6 checks
install.sh: ERROR: /work/backup-recipient.pub holds no age public key yet (placeholder): do runbook step 1 first
exit=1
### B: install with empty SAS
== 1/6 checks
== 2/6 tools (age, curl, flock)
== age v1.2.1
== 3/6 files under /usr/local/lib/quickdelivery-backup
== 4/6 directories and the SAS file
== created an empty /etc/quickdelivery-backup/sas (fill it with: sudo ./install.sh --set-sas)
== 5/6 systemd units
[stub] systemctl daemon-reload
[stub] systemctl enable --now quickdelivery-backup.timer
[stub] systemctl list-timers --no-pager quickdelivery-backup.timer
== 6/6 first backup
== SKIPPED: /etc/quickdelivery-backup/sas is empty. Run: sudo ./install.sh --set-sas, then: sudo ./install.sh
exit=0
### C: --set-sas with junk
Paste the Blob SAS URL (https://<account>.blob.core.windows.net/<container>?sp=...), then Enter.
Input is not shown.
> 
install.sh: ERROR: that does not look like a container SAS URL (https://<account>.blob.core.windows.net/<container>?<token>); nothing written
exit=1
### D: --set-sas valid
Paste the Blob SAS URL (https://<account>.blob.core.windows.net/<container>?sp=...), then Enter.
Input is not shown.
> 
== SAS URL written to /etc/quickdelivery-backup/sas (mode 600). Now run: sudo ./install.sh
exit=0
### E: re-run (idempotent, starts first backup)
== 1/6 checks
== 2/6 tools (age, curl, flock)
== age v1.2.1
== 3/6 files under /usr/local/lib/quickdelivery-backup
== 4/6 directories and the SAS file
== 5/6 systemd units
[stub] systemctl daemon-reload
[stub] systemctl enable --now quickdelivery-backup.timer
[stub] systemctl list-timers --no-pager quickdelivery-backup.timer
== 6/6 first backup
[stub] systemctl start quickdelivery-backup.service
[stub] systemctl --no-pager status quickdelivery-backup.service
== first backup OK; daily runs are scheduled (systemctl list-timers quickdelivery-backup.timer)
exit=0
### modes
755 root:root /usr/local/lib/quickdelivery-backup
644 root:root /usr/local/lib/quickdelivery-backup/backup-recipient.pub
755 root:root /usr/local/lib/quickdelivery-backup/backup.sh
700 root:root /etc/quickdelivery-backup
600 root:root /etc/quickdelivery-backup/sas
700 root:root /var/backups/quickdelivery
700 root:root /var/lib/quickdelivery-backup
644 root:root /etc/systemd/system/quickdelivery-backup.service
644 root:root /etc/systemd/system/quickdelivery-backup.timer
```

### End-to-end test: backup.sh → fake Blob endpoint → restore.sh

`TMPDIR=$SCRATCH infrastructure/deploy/backup/test/e2e-local.sh`: a disposable
mongo:7 (400m, cache 0.25 GB, root password with `'`, `"`, `$`, `&` and a space),
two seeded volumes, a throwaway age key pair, and `test/fake_blob_server.py`
(Put Blob stand-in: 403 on a wrong sig, 409 when a blob exists). Literal output
of the final run, in which the scratchpad path prefix is replaced by `$SCRATCH`
and nothing else is changed:

```text

### fixtures
throwaway age key pair generated (public key in $SCRATCH/tmp.nMweSugOVA/recipient.pub)
seeded mongo container qdbt-285275-mongo
seeded volumes qdbt-285275-documents, qdbt-285275-attachments
fake blob endpoint on 127.0.0.1:36561

### 1. backup.sh
[preflight] WARN: BACKUP_ALLOW_HTTP=1: uploading to a local test endpoint
[preflight] start run 20261019T070605Z: dir=$SCRATCH/tmp.nMweSugOVA/backups/20261019T070605Z target=http://127.0.0.1:36561/backups/e2e-host/20261019T070605Z/ image=mongo:7 free=7670MB
[mongodump] ok: mongo-20261019T070605Z.archive.gz.age 964KB in 0.7s
[volume:qdbt-285275-documents] ok: qdbt-285275-documents-20261019T070605Z.tar.gz.age 413KB in 0.5s
[volume:qdbt-285275-attachments] ok: qdbt-285275-attachments-20261019T070605Z.tar.gz.age 89KB in 0.5s
[volume:qdbt-285275-caddy-missing] WARN: optional volume qdbt-285275-caddy-missing not found; skipped
[checksums] ok: SHA256SUMS (3 files)
[upload:mongo-20261019T070605Z.archive.gz.age] ok: uploaded mongo-20261019T070605Z.archive.gz.age 964KB in 0.0s
[upload:qdbt-285275-attachments-20261019T070605Z.tar.gz.age] ok: uploaded qdbt-285275-attachments-20261019T070605Z.tar.gz.age 89KB in 0.0s
[upload:qdbt-285275-documents-20261019T070605Z.tar.gz.age] ok: uploaded qdbt-285275-documents-20261019T070605Z.tar.gz.age 413KB in 0.0s
[upload:SHA256SUMS] ok: uploaded SHA256SUMS 338B in 0.0s
[retention] ok: kept 1 local runs, removed 0 (KEEP_LOCAL=3)
[done] BACKUP OK: run 20261019T070605Z, 1.5MB encrypted, uploaded to http://127.0.0.1:36561/backups/e2e-host/20261019T070605Z/ in 1.8s
PASS: backup.sh exit 0
fake endpoint log:
PUT /backups/e2e-host/20261019T070605Z/mongo-20261019T070605Z.archive.gz.age -> 201
PUT /backups/e2e-host/20261019T070605Z/qdbt-285275-attachments-20261019T070605Z.tar.gz.age -> 201
PUT /backups/e2e-host/20261019T070605Z/qdbt-285275-documents-20261019T070605Z.tar.gz.age -> 201
PUT /backups/e2e-host/20261019T070605Z/SHA256SUMS -> 201
PASS: 4 artifacts (mongo, 2 volumes, SHA256SUMS) written locally and uploaded with 201
PASS: uploaded bytes identical to the local copies
PASS: every artifact starts with the age header (encrypted)
PASS: backup log contains neither the SAS sig nor the Mongo password
PASS: ps sampled every 50 ms during the run (16384 lines): no SAS sig, no Mongo password on any command line
PASS: ps sampling caught the mongodump sidecar running (the sampler saw the run)
PASS: no FAILED marker, last-success written

### 2. restore.sh from the uploaded copies
source counts (restore.sh --counts on the source container):
auth_db.kyc_documents 700
auth_db.refresh_tokens 0
auth_db.users 1500
chat_db.messages 12000
chat_db.tickets 333
notification_db.notifications 7777
user_db.jobs 4000
user_db.ledger 9000
user_db.services 120
user_db.wallets 1500
== checksum ok: mongo-20261019T070605Z.archive.gz.age
== mongo: starting throwaway container qd-restore-287459-0 (mongo:7, --network none, no auth)
== mongo: decrypt | mongorestore mongo-20261019T070605Z.archive.gz.age
== mongo: document counts (<db>.<collection> <count>)
auth_db.kyc_documents 700
auth_db.refresh_tokens 0
auth_db.users 1500
chat_db.messages 12000
chat_db.tickets 333
notification_db.notifications 7777
user_db.jobs 4000
user_db.ledger 9000
user_db.services 120
user_db.wallets 1500
== restore test finished: 1 file(s)
PASS: document counts match exactly: 10 collections, 36930 documents
== checksum ok: qdbt-285275-documents-20261019T070605Z.tar.gz.age
== volume: decrypt | tar -x qdbt-285275-documents-20261019T070605Z.tar.gz.age -> $SCRATCH/tmp.nMweSugOVA/restore-tmp/qd-restore-HjPdo5
== volume: 13 files, 4 dirs, 420006 bytes (411KB) in total
  space dir/ 1 files 6 bytes
  user-1/ 4 files 70000 bytes
  user-2/ 4 files 140000 bytes
  user-3/ 4 files 210000 bytes
== checksum ok: qdbt-285275-attachments-20261019T070605Z.tar.gz.age
== volume: decrypt | tar -x qdbt-285275-attachments-20261019T070605Z.tar.gz.age -> $SCRATCH/tmp.nMweSugOVA/restore-tmp/qd-restore-7ZVMGb
== volume: 6 files, 2 dirs, 90000 bytes (88KB) in total
  ticket-1/ 3 files 30000 bytes
  ticket-2/ 3 files 60000 bytes
== restore test finished: 2 file(s)
== kept dirs (personal data, delete when done): $SCRATCH/tmp.nMweSugOVA/restore-tmp/qd-restore-HjPdo5 $SCRATCH/tmp.nMweSugOVA/restore-tmp/qd-restore-7ZVMGb
PASS: qdbt-285275-documents: 13 files restored, every sha256 equal to the source
PASS: qdbt-285275-attachments: 6 files restored, every sha256 equal to the source

### 3. retention (KEEP_LOCAL=3) and lock
[retention] ok: kept 2 local runs, removed 0 (KEEP_LOCAL=3)
[retention] ok: kept 3 local runs, removed 0 (KEEP_LOCAL=3)
[retention] ok: kept 3 local runs, removed 1 (KEEP_LOCAL=3)
PASS: after 4 runs: 3 local runs kept, the oldest (20261019T070605Z) removed; off-host copies untouched: 4 runs
[lock] ERROR: another backup run holds $SCRATCH/tmp.nMweSugOVA/backups/.lock; not starting a second one
PASS: overlapping run refused by flock (exit 1), no FAILED marker

### 4. failure marker, rejected upload
[preflight] WARN: BACKUP_ALLOW_HTTP=1: uploading to a local test endpoint
[preflight] ERROR: container qdbt-285275-nonexistent is not running
[preflight] BACKUP FAILED (exit 1); marker written: $SCRATCH/tmp.nMweSugOVA/state/FAILED
marker: 2026-10-19T07:06:25Z backup failed at step "preflight" (exit 1); see: journalctl -u quickdelivery-backup.service
PASS: failed run: exit 1, FAILED marker written
[post-stop] BACKUP FAILED: 2026-10-19T07:06:25Z backup failed at step "preflight" (exit 1); see: journalctl -u quickdelivery-backup.service
[post-stop] marker: $SCRATCH/tmp.nMweSugOVA/state/FAILED (removed by the next successful run)
PASS: --post-stop (systemd ExecStopPost) prints the marker into the unit's log / systemctl status
[preflight] WARN: BACKUP_ALLOW_HTTP=1: uploading to a local test endpoint
[preflight] start run 20261019T070626Z: dir=$SCRATCH/tmp.nMweSugOVA/backups/20261019T070626Z target=http://127.0.0.1:36561/backups/e2e-host/20261019T070626Z/ image=mongo:7 free=7658MB
[mongodump] ok: mongo-20261019T070626Z.archive.gz.age 964KB in 0.7s
[volume:qdbt-285275-documents] ok: qdbt-285275-documents-20261019T070626Z.tar.gz.age 413KB in 0.5s
[volume:qdbt-285275-attachments] ok: qdbt-285275-attachments-20261019T070626Z.tar.gz.age 89KB in 0.5s
[volume:qdbt-285275-caddy-missing] WARN: optional volume qdbt-285275-caddy-missing not found; skipped
[checksums] ok: SHA256SUMS (3 files)
[upload:mongo-20261019T070626Z.archive.gz.age] ERROR: upload rejected: HTTP 403 <Code>AuthenticationFailed</Code>
[upload:mongo-20261019T070626Z.archive.gz.age] BACKUP FAILED (exit 1); marker written: $SCRATCH/tmp.nMweSugOVA/state/FAILED
PASS: rejected upload: exit 1, HTTP status + Azure code logged, SAS sig not logged
[done] BACKUP OK: run 20261019T070629Z, 1.5MB encrypted, uploaded to http://127.0.0.1:36561/backups/e2e-host/20261019T070629Z/ in 1.7s
PASS: next successful run cleared the FAILED marker

### 5. refusals
backup.sh: refusing to run with xtrace (set -x) enabled: it would print secrets
+ exit 2
PASS: bash -x: refused (exit 2), no secret in the output
[preflight] ERROR: no age public key (age1...) in /home/omarmaarouf/CS tools/Antigravity/saas-core-wt/OPS-BACKUP/infrastructure/deploy/backup/test/../backup-recipient.pub: generate the key pair offline (runbook step 1)
[preflight] BACKUP FAILED (exit 1); marker written: $SCRATCH/tmp.nMweSugOVA/state/FAILED
PASS: placeholder recipient: refused (exit 1), no secret in the output
[preflight] ERROR: SAS permissions are sp=rcwl; only c (create) and w (write) are allowed (runbook step 3)
[preflight] BACKUP FAILED (exit 1); marker written: $SCRATCH/tmp.nMweSugOVA/state/FAILED
PASS: SAS with read/list: refused (exit 1), no secret in the output
[preflight] ERROR: $SCRATCH/tmp.nMweSugOVA/sas has mode 644; it must be 600 or 400
[preflight] BACKUP FAILED (exit 1); marker written: $SCRATCH/tmp.nMweSugOVA/state/FAILED
PASS: SAS file mode 644: refused (exit 1), no secret in the output
E2E RESULT: PASS
```

Document counts before (source) and after (restored from the uploaded copy)
are identical: 10 collections, 36930 documents. Every restored volume file has
the source's sha256.

### Runbook "restore into production" steps 4 and 5, run locally

The code blocks were extracted verbatim from the runbook with awk, then names
were substituted by sed (`saas-mongo` → a disposable 400m `mongo:7` with root
password `a'b"c $d`, paths → scratch). Source counts `auth_db.users 500`,
`chat_db.messages 300`; damaged by dropping `auth_db.users` and adding a
message (`chat_db.messages 301`); step 4 (sidecar `mongorestore --drop`) then
printed `800 document(s) restored successfully. 0 document(s) failed to restore.`
and `restore.sh --counts` gave `auth_db.users 500` / `chat_db.messages 300`
again. The last line of the extracted step 4 failed only in the test
(`/home/omarmaarouf/CS: No such file or directory`: my substituted path
contains a space). It was re-run by hand with the output above. Step 5 put
back a deleted file and reverted a changed one, keeping owner `999:999` and
mode `600`. The runbook's Discord `alert.sh`, pointed at a local POST
receiver, sent
`{'content': 'Backup FAILED on fedora: 2026-10-19T00:31:02Z backup failed at step upload:x (exit 1); quote  and backslash  here'}`
with `Content-Type: application/json` (valid JSON although the marker held `"`
and `\`).

## Unverified
- **Nothing ran on the VM or against real Azure.** In particular:
  - Real Put Blob with a Portal-generated SAS: header set, `201`, the error
    codes in the runbook's failure table, and whether a **Create-only**
    policy is enough for Put Blob of new blobs (Azure docs say so; untested).
  - The Portal click paths and labels (storage account, stored access policy,
    Shared access tokens, lifecycle management, immutability). They are written
    from Azure's documented menus, not clicked.
  - Lifecycle Cool tiering on blobs under an immutability policy, and the cost
    figures (estimates; the runbook says to check the pricing calculator).
- The production data size, and therefore whether `DUMP_MEMORY=192m` is enough
  there: measured only on a 300k-document synthetic set (128m passed, 96m
  failed).
- The units were not run under a real systemd as root (`systemd-analyze verify`
  only): `ProtectSystem=full`, `ProtectHome=yes` + `DOCKER_CONFIG`,
  `ExecStopPost` environment (`SERVICE_RESULT`, `EXIT_CODE`, `EXIT_STATUS`) and
  journald output are untested here. `--post-stop` was exercised by setting
  those variables by hand. install.sh's last step runs a real backup, so a
  problem shows up at install time.
- install.sh's `apt-get install age` path did not run (the test container had
  no network; `age` was provided). Ubuntu's release on the VM, and hence the
  availability of the `age` package (in Ubuntu since 22.04), are not known to me.
- `age` locally is v1.2.1, installed with `go install filippo.io/age/cmd/...@v1.2.1`.

## Follow-ups / out-of-lane findings
- **Keep `/home/deploybot/.env` offline** (owner action, in the runbook). Without
  `DOCUMENT_ENCRYPTION_KEY` the documents/attachments backups are unreadable.
  Option for a later task: an extra age-encrypted copy of `.env` in the same
  run (it is root-readable on the VM; encrypted to the same offline key).
- No compose or deploy.yml wiring is needed: the backup is host-level (systemd)
  and uses only the container/volume names from `docker-compose.prod.yml`. If
  a later change renames `saas-mongo` or the volumes, `backup.sh` defaults (or
  `/etc/quickdelivery-backup/backup.env`) must follow. A drift check could live
  in `deploy.yml` (proposal only, out of lane).
- CI does not shellcheck `infrastructure/deploy/backup/*.sh` (no shellcheck
  stage in the gate). Proposal: add one (hot paths `scripts/**`/`.github/**`,
  out of lane).
- `docs/README.md` (docs index) does not link the new runbook: out of lane, and
  CLN-02 is editing `docs/**`. The owner may add the link when folding.
- Dead-man check (alert when backups stop, not only when one fails): described
  in the runbook, not implemented.

## Open questions
- none (the one stop condition hit, exec vs sidecar mongodump, was answered by
  the owner in chat: sidecar).
