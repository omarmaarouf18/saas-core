# Runbook: daily encrypted backups and restore (OPS-BACKUP)

Owner-only procedures for the production backup. The scripts and units live in
[infrastructure/deploy/backup/](../../infrastructure/deploy/backup/).

> [!NOTE]
> The agent that wrote this had no access to the VM or to Azure. Commands that
> run on the VM were tested locally (see `docs/worklog/OPS-BACKUP.md`), and the
> Azure Portal steps follow the Portal's documented menus, but nobody has
> clicked through them for this runbook yet. If a label differs, look for the
> nearest equivalent. If you are unsure, stop and ask before going on.

## What is backed up, where, how

| | |
| :--- | :--- |
| Schedule | daily at 03:30 Africa/Cairo, plus up to 20 min random delay (`quickdelivery-backup.timer`); a run missed while the VM was off happens at next boot |
| Mongo | `mongodump --archive --gzip` of every database, run in a short-lived `mongo:7` sidecar container that shares `saas-mongo`'s network (own 192 MiB memory cap; `--numParallelCollections=1`) |
| Volumes | `tar.gz` of `saas_platform_documents_data` (KYC/KYB/KYE documents: **personal data**) and `saas_platform_attachments_data` (ticket attachments), plus `caddy_data` (TLS certs, nice-to-have) when present, read through a read-only mount |
| Secrets | `/home/deploybot/.env` (holds `DOCUMENT_ENCRYPTION_KEY`, without which the volume backups are unreadable), copied byte for byte into `env-<stamp>.age`; its contents are never logged. A required artifact: a run without it fails (see "The secrets file in the backup" below) |
| Encryption | every artifact streamed into [`age`](https://age-encryption.org) to the public key in `backup-recipient.pub`. The private key is only on the owner's machine/offline media, **never on the VM** |
| Off-host | Azure Blob Storage, container in `quickdelivery-rg`, blob names `<vm hostname>/<UTC stamp>/<file>`, uploaded with plain `curl` (Put Blob) and a SAS that can only **create/write**: a compromised VM cannot read, list or delete old backups |
| Local | last 3 runs under `/var/backups/quickdelivery/<stamp>/` (encrypted files only) |
| Off-host retention | lifecycle rule: Cool after 7 days, delete after 30 days (step 4), optional immutability (step 5) |
| Integrity | `SHA256SUMS` per run (uploaded last: a run folder without it is incomplete) |
| Logs | journald, one line per step with size and duration: `journalctl -u quickdelivery-backup.service` |
| Failure signal | `/var/lib/quickdelivery-backup/FAILED` plus a `BACKUP FAILED: …` line that `systemctl status quickdelivery-backup.service` shows |

Files of one run (`<stamp>` = `YYYYMMDDTHHMMSSZ`, UTC):

```text
mongo-<stamp>.archive.gz.age
saas_platform_documents_data-<stamp>.tar.gz.age
saas_platform_attachments_data-<stamp>.tar.gz.age
caddy_data-<stamp>.tar.gz.age
env-<stamp>.age
SHA256SUMS
```

### The secrets file in the backup (`env-<stamp>.age`)

Documents and attachments are stored AES-256-GCM encrypted with
`DOCUMENT_ENCRYPTION_KEY` (`shared/infra/storage`), which lives only in
`/home/deploybot/.env`. **Without that key the volume backups cannot be
read.** Since OPS-BACKUP-ENV every run therefore also stores the whole `.env`
(`DOCUMENT_ENCRYPTION_KEY`, `OTP_AES_KEY`, `JWT_SECRET`,
`INTERNAL_SERVICE_TOKEN`, `ADMIN_API_TOKEN`, the Mongo and Redis passwords, …),
encrypted to the same age recipient as the data. After losing the VM you then
need only the age private key to get everything back.

The trade-off, accepted by the owner: whoever holds the age private key can
now read **every production secret** as well as the data, and old versions of
the secrets stay in Blob Storage until the lifecycle rule deletes them (30
days, or later under immutability).

- **Still keep a copy of the whole `.env` in your password manager**, and
  update it whenever a secret changes. It is your fallback if the age key or
  the Blob account is lost.
- `restore.sh` decrypts `env-*.age` to a temp file with mode 600, prints only
  the variable **names**, and deletes the file unless you pass `-k` (step 7).
- The systemd unit runs with `ProtectHome=read-only` (it was `yes`) so the
  script can read `/home/deploybot/.env`. On a VM installed before this
  change, re-run `sudo ./install.sh` (step 6) to install the new unit and
  script; until then every run fails with `secrets file not readable`.
- To back up a different file, set `ENV_FILE=` in
  `/etc/quickdelivery-backup/backup.env`.

> [!WARNING]
> **If the age private key is ever suspected leaked**, treat every secret in
> `.env` as leaked too:
>
> 1. Rotate every secret in `/home/deploybot/.env`: `JWT_SECRET`,
>    `OTP_AES_KEY`, `INTERNAL_SERVICE_TOKEN`, `ADMIN_API_TOKEN`, the Mongo root
>    password and the Redis password (plus any other credential in the file),
>    then redeploy.
> 2. Re-encrypt the documents and attachments with a new
>    `DOCUMENT_ENCRYPTION_KEY`. There is no re-key tool in the repo yet
>    (`services/auth-service/cmd/encrypt-documents` only encrypts plaintext
>    files), so this needs one: decrypt every file with the old key and
>    encrypt it with the new one, with the services stopped.
> 3. Generate a new age key pair and replace the public key ("Renewing the
>    SAS, rotating the key" below). Delete the old blobs if possible.
> 4. Update the password-manager copy of `.env`.

### What is NOT in the backup

- The age private key itself (by design: keep it offline, step 1).
- Redis (cache-like data with TTLs, by decision).
- The mTLS certs in the deploy dir's `certs/` (regenerable) and `caddy_config`.
- Point-in-time consistency: a standalone mongod has no oplog, so writes made
  during the few seconds of the dump can land in some collections and not
  others. At 03:30 traffic is lowest, and this is acceptable at this scale.

### Cost (estimate, check the Azure pricing calculator)

Storage is per GB per month, about 2 US cents for Hot LRS and less for Cool.
30 daily runs of 50 MB come to 1.5 GB, i.e. a few cents per month. About 150
PUTs per month cost a fraction of a cent. Moving blobs to Cool at day 7 and
deleting them at day 30 triggers Cool's pro-rated 30-day early-deletion charge
for the remaining 7 days. At these sizes that is a fraction of a cent. If you
prefer, drop the Cool action and only delete.

## One-time setup

Do steps 1–6 once, in order. Step 7 verifies the whole chain.

### Step 1: age key pair, OFFLINE on your machine

```bash
age-keygen -o quickdelivery-backup-key.txt
```

(`age` is in the Fedora/Ubuntu/Homebrew repos as `age`; Windows: the release
binaries from the age GitHub project.) The command prints
`Public key: age1…`.

- Store `quickdelivery-backup-key.txt` (the line `AGE-SECRET-KEY-1…`) in **two**
  offline places, e.g. your password manager and an encrypted USB stick. If it is
  lost, every backup is unreadable. Optional: protect the file with a passphrase
  (`age -p -o quickdelivery-backup-key.txt.age quickdelivery-backup-key.txt`, then
  delete the plain file). `age -d -i quickdelivery-backup-key.txt.age` asks for
  the passphrase, and `restore.sh -i` accepts the same file.
- Replace the comment block in
  `infrastructure/deploy/backup/backup-recipient.pub` with the single public-key
  line `age1…` (you may keep `#` comment lines above it), and commit and push it
  the normal way. A second recipient line (a second key kept elsewhere) is
  allowed: either private key can then decrypt.
- Never copy the private key to the VM, into the repo, or into CI.

### Step 2: storage account and container (Azure Portal)

1. Portal → **Storage accounts** → **Create**.
   - Resource group: `quickdelivery-rg`. Name: e.g. `qdbackups<something>` (3–24
     lowercase letters/digits, globally unique). Region: the VM's region.
   - Performance **Standard**. Redundancy **LRS** (cheapest; GRS if you want a
     second region).
   - **Advanced**: *Require secure transfer* **on**; *Allow enabling anonymous
     access on individual containers* **off**; *Enable storage account key
     access* **on** (the SAS in step 3 is signed with the account key); *Minimum
     TLS version* **1.2**; *Default access tier* **Hot**.
   - **Data protection**: leave the defaults.
   - **Review + create** → **Create**.
2. The new account → **Data storage → Containers** → **+ Container**: name
   `backups`, *Anonymous access level* **Private** → **Create**.

### Step 3: the create/write-only SAS

Use a stored access policy: you can revoke or extend the SAS later without
rotating the account keys.

1. Container `backups` → **Settings → Access policy** → *Stored access
   policies* → **+ Add policy**: Identifier `backup-writer`, Permissions
   **Create** and **Write** only (NOT Read, List, Delete, Add, …), Start time:
   now, Expiry time: 1 year from now (write the date in your calendar a month
   before it) → **OK** → **Save**.
2. Container `backups` → **Settings → Shared access tokens**:
   - *Signing method*: **Account key**.
   - *Stored access policy*: **backup-writer**. The permissions and expiry then
     come from the policy and are greyed out. Without a policy, tick only
     **Create** and **Write** and set an expiry of at most 1 year.
   - *Allowed IP addresses*: optional, the VM's public IP (a stolen SAS then
     works nowhere else).
   - *Allowed protocols*: **HTTPS only**.
   - **Generate SAS token and URL** → copy the **Blob SAS URL**. It looks like
     `https://<account>.blob.core.windows.net/backups?sv=…&si=backup-writer&sr=c&sig=…`.
     It is a secret: paste it only into the VM (step 6), never into chat, a
     ticket or the repo.

backup.sh refuses a SAS whose `sp=` contains anything other than `c` and `w`.
With a stored access policy (`si=`), the permissions are in the policy, so
check them there.

> [!TIP]
> Stricter: **Create** alone is enough to upload new blobs, and unlike **Write**
> it cannot overwrite an existing one. If the first backup works with a
> Create-only policy, keep it that way. The immutability policy in step 5 closes
> the same gap.

### Step 4: off-host retention (lifecycle management)

Storage account → **Data management → Lifecycle management** → **Add a rule**:

1. *Details*: Rule name `backups-retention`; *Rule scope* **Limit blobs with
   filters**; *Blob type* **Block blobs**; *Blob subtype* **Base blobs** → Next.
2. *Base blobs*: If **Last modified** more than **7** days ago → **Move to cool
   storage**. **+ Add conditions**: If **Last modified** more than **30** days
   ago → **Delete the blob**.
3. *Filter set*: Blob prefix `backups/` → **Add**.

The same rule in the **Code view** tab:

```json
{
  "rules": [
    {
      "enabled": true,
      "name": "backups-retention",
      "type": "Lifecycle",
      "definition": {
        "actions": {
          "baseBlob": {
            "tierToCool": { "daysAfterModificationGreaterThan": 7 },
            "delete": { "daysAfterModificationGreaterThan": 30 }
          }
        },
        "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["backups/"] }
      }
    }
  ]
}
```

Lifecycle rules run about once a day, so a blob can outlive day 30 by a day or two.

### Step 5 (optional, recommended): immutability

With a time-based retention policy, nobody can delete or overwrite a backup
before it expires, not even someone holding the account key.

Container `backups` → **Settings → Access policy** → *Immutable blob storage* →
**+ Add policy**: Policy type **Time-based retention**, Retention period **14**
days → **Save**.

- Keep it **unlocked** at first: an unlocked policy can still be changed or
  removed. **Locking it is irreversible**: it cannot be removed or shortened
  afterwards, and the container cannot be deleted while blobs are retained.
  Lock it only once the backups have run well for a few weeks.
- The retention period (14) must stay at or below the lifecycle delete age
  (30), otherwise the delete action keeps failing until retention ends.

### Step 6: install on the VM

From a checkout of this repo on your machine. `<you>@<vm>` is your SSH login to
the VM:

```bash
scp -r infrastructure/deploy/backup <you>@<vm>:quickdelivery-backup
```

On the VM:

```bash
sudo ~/quickdelivery-backup/install.sh --set-sas
```

Paste the Blob SAS URL from step 3. It is not echoed and not stored in your
shell history. Then:

```bash
sudo ~/quickdelivery-backup/install.sh
```

install.sh installs `age` with apt if it is missing, copies `backup.sh`, the
public key and the units, creates the directories with root-only modes,
enables the timer and runs one backup immediately, then prints its status. It
refuses to run while `backup-recipient.pub` is still the placeholder. Re-run it
after any change to the files (pull, then `scp` again): it is idempotent.

Optional overrides go in `/etc/quickdelivery-backup/backup.env` (root, mode
600), one `KEY=value` per line, e.g. `DUMP_MEMORY=256m`. The keys are listed at
the top of `backup.sh`.

### Step 7: test-restore the first backup on your machine

1. Portal → container `backups` → **Browse** → `<vm hostname>/` → the newest
   `<stamp>/` → download every file into one folder, e.g. `~/qd-restore/<stamp>/`.
2. From the repo checkout:

   ```bash
   infrastructure/deploy/backup/restore.sh -i quickdelivery-backup-key.txt ~/qd-restore/<stamp>
   ```

   It verifies `SHA256SUMS` and restores Mongo into a throwaway `mongo:7`
   container (no published ports, removed at the end). It prints one
   `<db>.<collection> <count>` line per collection, then extracts each volume
   into a temp dir, prints file counts and sizes, and deletes the temp dir. For
   `env-<stamp>.age` it decrypts to a mode-600 temp file, lists the variable
   names (check that `DOCUMENT_ENCRYPTION_KEY` is among them), and deletes the
   file. `-k` keeps the container, the dirs and the secrets file; they contain
   personal data and production secrets, so delete them when done.
3. Compare with production. On the VM (read-only, prints the same format):

   ```bash
   sudo ~/quickdelivery-backup/restore.sh --counts saas-mongo
   ```

   The counts match exactly if nothing was written since the backup. Otherwise,
   collections that only grow (ledger, messages, notifications) are equal or
   slightly higher in production.
4. Delete the downloaded files when done (`rm -r ~/qd-restore`).

Repeat step 7 once a month: a backup that has never been restored is not a
backup.

## Daily operation

```bash
systemctl list-timers quickdelivery-backup.timer        # next / last run
systemctl status quickdelivery-backup.service           # last result
journalctl -u quickdelivery-backup.service --since -2d   # step log
sudo cat /var/lib/quickdelivery-backup/last-success      # UTC time of the last good run
sudo ls -l /var/backups/quickdelivery/                   # last 3 local runs
sudo systemctl start quickdelivery-backup.service        # run one now (blocks)
```

A healthy run logs `start run …`, one `ok:` line per artifact and upload,
`ok: kept …` and finally `BACKUP OK: run <stamp>, <size> encrypted, …`.

If `last-success` is older than about 26 hours, a run was missed or failed,
even if there is no FAILED marker (for example, the timer is disabled).

## When a backup fails

`systemctl status quickdelivery-backup.service` shows `failed` and a
`BACKUP FAILED: …` line. `/var/lib/quickdelivery-backup/FAILED` says which step
failed, and the next successful run removes it. The local copies of a failed
run stay in place: if only the upload failed, they are still good.

| Log line | Cause | Fix |
| :--- | :--- | :--- |
| `upload rejected: HTTP 403 <Code>AuthenticationFailed</Code>` | SAS expired, revoked, or mistyped | new SAS (step 3), `sudo install.sh --set-sas` |
| `upload rejected: HTTP 403 <Code>AuthorizationPermissionMismatch</Code>` | the policy lacks Create/Write | fix the stored access policy |
| `upload rejected: HTTP 403 <Code>AuthorizationSourceIPMismatch</Code>` | the VM's public IP changed | update *Allowed IP addresses*, new SAS |
| `upload rejected: HTTP 409 …` | a blob with that name already exists (should not happen: names carry the run's second-resolution stamp and runs never overlap) | rerun; if it repeats, look at the container in the Portal |
| `SAS expired at …` / `WARN: SAS expires in N days` | expiry near or past | extend the policy's expiry (step 3, same SAS keeps working) or make a new SAS |
| `mongodump sidecar exited 137` | the dump hit its memory cap | `DUMP_MEMORY=256m` in `backup.env` (the host has about 380 MB free) |
| `container saas-mongo is not running` | Mongo down | fix Mongo first; nothing to back up |
| `only N MB free under /var/backups/quickdelivery` | disk below 2 GB free | free disk (Docker images, logs); `MIN_FREE_MB` overrides |
| `another backup run holds …/.lock` | a manual run overlapped the timer | wait for it |
| `run killed or failed outside the script: result=oom-kill` | the unit hit `MemoryMax=128M` | look at the journal, raise `MemoryMax` in the unit |

### Failure alerts (later, not installed)

When you want a push notification, add an `OnFailure=` unit. Do not paste the
webhook URL into the repo. Example for a Discord webhook:

1. Put the webhook URL in a root-only file:

   ```bash
   sudo install -m 600 /dev/null /etc/quickdelivery-backup/discord-webhook
   sudo nano /etc/quickdelivery-backup/discord-webhook
   ```

2. `/usr/local/lib/quickdelivery-backup/alert.sh` (mode 755). The URL reaches
   curl through stdin, never through the command line:

   ```sh
   #!/bin/sh
   set -eu
   marker="$(head -c 300 /var/lib/quickdelivery-backup/FAILED 2>/dev/null || echo 'no marker; see journalctl -u quickdelivery-backup')"
   msg="$(printf 'Backup FAILED on %s: %s' "$(hostname -s)" "$marker" | tr -d '"\\\n')"
   printf 'url = "%s"\n' "$(cat /etc/quickdelivery-backup/discord-webhook)" |
     curl -sS --fail -K - -H 'Content-Type: application/json' -d "{\"content\": \"$msg\"}"
   ```

3. `/etc/systemd/system/quickdelivery-backup-alert.service`:

   ```ini
   [Unit]
   Description=Alert: QuickDelivery backup failed

   [Service]
   Type=oneshot
   ExecStart=/usr/local/lib/quickdelivery-backup/alert.sh
   ```

4. In `/etc/systemd/system/quickdelivery-backup.service`, uncomment
   `OnFailure=quickdelivery-backup-alert.service`, then
   `sudo systemctl daemon-reload`. Test it with
   `sudo systemctl start quickdelivery-backup-alert.service`.

For email, use the same pattern with an SMTP relay CLI (e.g. `msmtp`). Also
consider a dead-man check: an external uptime service that alerts when it
stops receiving a ping. backup.sh could send that ping on success, which needs
a small change to `backup.sh`.

## Renewing the SAS, rotating the key

- **SAS**: backup.sh warns 30 days before expiry. With a stored access policy,
  extend the policy's *Expiry time* (step 3.1): the existing SAS keeps working.
  To revoke a leaked SAS, delete the policy (it stops working at once), then
  create a new policy and SAS and run `sudo install.sh --set-sas`.
- **age key**: generate a new pair (step 1) and put the new public key in
  `backup-recipient.pub`, then re-run `install.sh`. Keep the OLD private key
  until the last backup encrypted to it has aged out (30 days). If the old key
  leaked, also delete the old blobs (this is impossible during an immutability
  period), and follow the leaked-key steps in "The secrets file in the backup":
  the backups contain every production secret.

## Restore into production (DANGEROUS)

> [!CAUTION]
> This overwrites live data. Do it only after a test restore (step 7) of the
> same files succeeded, during announced downtime, and step by step. The
> private key stays on your machine: you decrypt locally and copy plaintext to
> the VM only for the duration of the restore.

`<stamp>` is the run to restore, `<you>@<vm>` your SSH login. Run the VM
commands in a root shell (`sudo -i`).

1. **Pre-restore dump (mandatory).** Take a backup of the current state first,
   even if it is broken. You may need it to undo the restore:

   ```bash
   systemctl start quickdelivery-backup.service && systemctl status quickdelivery-backup.service
   ```

   Note the new `<stamp>` it prints. If it cannot run (e.g. Mongo does not
   start), stop Mongo and take a raw copy of its volume instead:

   ```bash
   docker stop saas-mongo
   docker run --rm -v saas_platform_mongo_data:/src:ro --entrypoint tar mongo:7 -C /src -czf - . > /var/backups/quickdelivery/pre-restore-mongo_data-$(date -u +%Y%m%dT%H%M%SZ).tar.gz
   docker start saas-mongo
   ```

2. **Decrypt on your machine** and copy the plaintext to the VM:

   ```bash
   age -d -i quickdelivery-backup-key.txt -o mongo.archive.gz ~/qd-restore/<stamp>/mongo-<stamp>.archive.gz.age
   scp mongo.archive.gz <you>@<vm>:/tmp/
   ```

   (Same for a volume: `…-<stamp>.tar.gz.age` → `<volume>.tar.gz`. If the
   VM was rebuilt and `.env` is lost: `age -d -i quickdelivery-backup-key.txt
   -o env ~/qd-restore/<stamp>/env-<stamp>.age`, copy it to
   `/home/deploybot/.env` with owner `deploybot` and mode 600, and delete the
   local plaintext.)

3. **Stop the app containers** (Mongo keeps running; Caddy stays up and returns
   errors meanwhile):

   ```bash
   docker stop saas-api-gateway saas-auth-service saas-chat-service saas-user-service saas-notification-service saas-kyc-reviewer-console
   ```

4. **Mongo.** `--drop` replaces each collection contained in the archive. It
   leaves collections that are not in the archive untouched. To restore just
   one database, add `--nsInclude 'auth_db.*'`. This uses the same
   memory-capped sidecar as the backup, and the password goes in through stdin:

   ```bash
   install -d -m 700 /var/backups/quickdelivery/restore
   mv /tmp/mongo.archive.gz /var/backups/quickdelivery/restore/
   u="$(docker exec saas-mongo printenv MONGO_INITDB_ROOT_USERNAME)"
   p="$(docker exec saas-mongo printenv MONGO_INITDB_ROOT_PASSWORD)"
   printf "password: '%s'\n" "${p//\'/\'\'}" | docker run -i --rm --network container:saas-mongo --memory 256m \
     --tmpfs /run/qdb:size=64k,mode=0700 -v /var/backups/quickdelivery/restore/mongo.archive.gz:/in.archive.gz:ro \
     --entrypoint sh mongo:7 -c 'umask 077; cat >/run/qdb/cfg && exec mongorestore --config /run/qdb/cfg --username "$1" --authenticationDatabase admin --host 127.0.0.1 --port 27017 --archive=/in.archive.gz --gzip --drop --numParallelCollections=1' sh "$u"
   unset p
   ~/quickdelivery-backup/restore.sh --counts saas-mongo
   ```

   Compare the counts with the ones restore.sh printed in the test restore.
   The archive also holds the admin users and roles from backup time, and
   mongorestore restores them (its log says `restoring users from archive`).
   If you changed the Mongo root password after that backup, check in step 6
   that the services can still log in.

5. **Volumes** (only if they are lost or damaged). Extraction adds and
   overwrites files and keeps files that are not in the archive. It keeps the
   archived owners and modes:

   ```bash
   mv /tmp/saas_platform_documents_data.tar.gz /var/backups/quickdelivery/restore/
   docker run --rm --network none -v saas_platform_documents_data:/dst \
     -v /var/backups/quickdelivery/restore/saas_platform_documents_data.tar.gz:/in.tar.gz:ro \
     --entrypoint tar mongo:7 -C /dst -xzf /in.tar.gz
   ```

   Same for `saas_platform_attachments_data`. The files are only readable with
   the production `DOCUMENT_ENCRYPTION_KEY` from the time they were written.

6. **Start the app** and check it:

   ```bash
   docker start saas-auth-service saas-user-service saas-chat-service saas-notification-service saas-api-gateway saas-kyc-reviewer-console
   docker ps --format '{{.Names}} {{.Status}}'
   ```

7. **Delete the plaintext** on both sides:

   ```bash
   rm -rf /var/backups/quickdelivery/restore         # on the VM
   rm -f mongo.archive.gz *.tar.gz                   # on your machine, in the folder you used
   ```

To undo, restore the pre-restore dump from step 1 the same way.
