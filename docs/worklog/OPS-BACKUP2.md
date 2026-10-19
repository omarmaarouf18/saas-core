# Worklog: OPS-BACKUP2 — age-encrypted copy of the production .env in each backup

## Task and scope
- Task ID: OPS-BACKUP2 (owner's spec). **ID mismatch**: the first brief named the task
  OPS-BACKUP-ENV, so the worktree, the branch and the commit subjects use `OPS-BACKUP-ENV`. The
  owner's spec, which came later, names it OPS-BACKUP2. I kept the branch as it was, as
  instructed, and renamed this worklog from `OPS-BACKUP-ENV.md` to `OPS-BACKUP2.md`.
- Item IDs covered: none
- Allowed paths (lane from the task prompt): `infrastructure/deploy/backup/**`,
  `docs/runbooks/BACKUP-RESTORE.md`, `docs/worklog/OPS-BACKUP2.md`
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
  file that is also explicitly chmod 600) into `RESTORE_TMP`. The first version printed the
  variable names. The owner's spec says the file is "never printed", so restore.sh now prints only
  the path, mode, size and line count. Nothing from the contents is printed, not even a name. The
  file is deleted at exit unless `-k` is given. The `*.tar.gz.age` case is matched before
  `env-*.age`, so a volume whose name starts with `env-` would still be treated as a volume.
- Runbook: the leaked-key procedure is its own section, "If the age private key may have leaked",
  under "Renewing the SAS, rotating the key". It replaces the old leaked-key text of the age-key
  bullet. I read `services/auth-service/cmd/encrypt-documents/main.go` before writing the
  re-encryption step. It takes one key (`-key` or `DOCUMENT_ENCRYPTION_KEY`), skips files that
  decrypt with that key and encrypts every other file. It does NOT re-key, and running it with a
  new key over old-key files would double-encrypt them. The runbook says exactly that, and tells
  the owner to pass the new key in the environment rather than as `-key`, which would show in ps.
- Approval: before any code was written, I asked the owner whether secrets may go off-host (yes).
  The parent session later relayed the owner's spec, which confirms that approval.

## Changes per commit (message only — NO SHAs)
1. `OPS-BACKUP-ENV: back up an age-encrypted copy of the production .env`
2. `OPS-BACKUP-ENV: runbook for the env-<stamp>.age artifact`
3. `OPS-BACKUP-ENV: worklog`
4. `OPS-BACKUP-ENV: restore.sh never prints anything from the .env`
5. `OPS-BACKUP-ENV: runbook leaked-age-key rotation section`
6. `OPS-BACKUP-ENV: worklog renamed to OPS-BACKUP2.md and updated`

## Verification
- `shellcheck backup.sh restore.sh install.sh test/e2e-local.sh` (in infrastructure/deploy/backup):
  no output, exit 0.
- `infrastructure/deploy/backup/test/e2e-local.sh`: `E2E RESULT: PASS`. New checks: 5 artifacts
  (env included) written and uploaded with 201; env-<stamp>.age is in SHA256SUMS and its upload
  log line comes before SHA256SUMS's; the backup log and the ps samples hold none of the three
  fake .env values. restore.sh prints no value and no variable name, reports mode 600 plus the
  source's byte size and line count, and leaves RESTORE_TMP empty without `-k`. With `-k`, exactly
  one file is kept, mode 600, byte-identical to the source. A missing ENV_FILE is refused with no
  secret in the output. The checks that existed before still pass. Re-run after the
  metadata-only change: `E2E RESULT: PASS`.
- `make check` before each `make commit` (see the final report for its output).

## Unverified
- The `ProtectHome=read-only` change was not exercised under real systemd: the e2e test runs the
  script directly, not through the unit. It must be checked on the VM: re-run `sudo ./install.sh`,
  then `systemctl start quickdelivery-backup.service` and look for `[env] ok: env-<stamp>.age`
  in the journal.
- Not run against real Azure Blob Storage (fake endpoint only, as in OPS-BACKUP).

## Follow-ups / out-of-lane findings
- No document re-key tool exists (see Decisions). The leaked-key procedure needs a decrypt-with-
  old-key step first. Building one (or a `-old-key` mode for encrypt-documents) is out of lane
  (services/auth-service).
- The VM install must be refreshed (`sudo ./install.sh`) after merge. Until then the old unit
  (`ProtectHome=yes`) and the old script stay installed, so nothing changes. But a new script
  installed with the old unit would fail every run.

## Open questions
- none
