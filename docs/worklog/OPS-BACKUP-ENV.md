# Worklog: OPS-BACKUP-ENV — age-encrypted copy of the production .env in each backup

## Task and scope
- Task ID: OPS-BACKUP-ENV
- Item IDs covered: none
- Allowed paths (lane from the task prompt): `infrastructure/deploy/backup/**`,
  `docs/runbooks/BACKUP-RESTORE.md`, `docs/worklog/OPS-BACKUP-ENV.md`
- Agent branch: agent/OPS-BACKUP-ENV-env-copy, created from logic-exploitation @ 10dd01b3

## Decisions taken
- Before any code was written, the owner was asked whether production secrets may go off-host,
  even encrypted. Answer: **yes**, as specified (env-<stamp>.age, a required artifact,
  uploaded before SHA256SUMS). The owner also asked the runbook to say: if the age private key
  is ever suspected leaked, rotate every secret in .env (JWT_SECRET, OTP_AES_KEY,
  INTERNAL_SERVICE_TOKEN, ADMIN_API_TOKEN, Mongo/Redis passwords), re-encrypt the documents with
  a new DOCUMENT_ENCRYPTION_KEY, then generate a new age key pair. The password-manager advice
  stays.
- `ENV_FILE` (default `/home/deploybot/.env`) is a required input: preflight refuses a missing,
  unreadable or empty file, before any artifact is written. Only its path is ever logged.
- The file is streamed `cat -- "$ENV_FILE" | age -R "$RECIPIENT_FILE" -o env-<stamp>.age.partial`,
  then `mv`, the same as the other artifacts (with a shellcheck SC2002 disable for the deliberate
  `cat`). It is matched by the existing `*.age` upload loop, so it is uploaded before SHA256SUMS
  and listed in it.
- `quickdelivery-backup.service`: `ProtectHome=yes` → `ProtectHome=read-only`. With `yes`, /home
  is invisible to the unit and every production run would fail with "secrets file not
  readable". The service file is in the lane (`infrastructure/deploy/backup/**`). Read-only keeps
  /home and /root unwritable.
- restore.sh: `env-*.age` is decrypted (`age -d ... >"$out"`, under `umask 077`, into a `mktemp`
  file that is also explicitly chmod 600) into `RESTORE_TMP`. The script prints the count and the
  variable NAMES only (a sed that keeps only the identifier before `=`, optionally after
  `export`) and deletes the file at exit unless `-k` is given. The `*.tar.gz.age` case is matched
  before `env-*.age`, so a volume whose name starts with `env-` would still be treated as a
  volume.

## Changes per commit (message only — NO SHAs)
1. `OPS-BACKUP-ENV: back up an age-encrypted copy of the production .env`
2. `OPS-BACKUP-ENV: runbook for the env-<stamp>.age artifact`
3. `OPS-BACKUP-ENV: worklog`

## Verification
- `shellcheck backup.sh restore.sh install.sh test/e2e-local.sh` (in infrastructure/deploy/backup):
  no output, exit 0.
- `infrastructure/deploy/backup/test/e2e-local.sh`: `E2E RESULT: PASS`. New checks: 5 artifacts
  (env included) written and uploaded with 201; env-<stamp>.age is in SHA256SUMS and its upload
  log line comes before SHA256SUMS's; the backup log and the ps samples hold none of the three
  fake .env values; restore.sh lists exactly `DOCUMENT_ENCRYPTION_KEY JWT_SECRET
  MONGO_ROOT_PASSWORD`, prints no value, reports mode 600 and leaves RESTORE_TMP empty without
  `-k`; with `-k` exactly one file is kept, mode 600, byte-identical to the source; a missing
  ENV_FILE is refused with no secret in the output. The checks that existed before still pass.
- `make check` before each `make commit` (see the final report for its output).

## Unverified
- The `ProtectHome=read-only` change was not exercised under real systemd: the e2e test runs the
  script directly, not through the unit. It must be checked on the VM: re-run `sudo ./install.sh`,
  then `systemctl start quickdelivery-backup.service` and look for `[env] ok: env-<stamp>.age`
  in the journal.
- Not run against real Azure Blob Storage (fake endpoint only, as in OPS-BACKUP).

## Follow-ups / out-of-lane findings
- No document re-key tool exists: `services/auth-service/cmd/encrypt-documents` only encrypts
  plaintext files with a key. It cannot decrypt with an old key and re-encrypt with a new one. The
  leaked-key procedure in the runbook says re-encrypting with a new DOCUMENT_ENCRYPTION_KEY
  needs such a tool. Building one is out of lane (services/auth-service).
- The VM install must be refreshed (`sudo ./install.sh`) after merge. Until then the old unit
  (`ProtectHome=yes`) and the old script stay installed, so nothing changes. But a new script
  installed with the old unit would fail every run.

## Open questions
- none
