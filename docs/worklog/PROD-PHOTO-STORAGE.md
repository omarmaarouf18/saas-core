# Worklog: PROD-PHOTO-STORAGE — service photos survive deploys, are encrypted and backed up; FCM credentials

## Task and scope
- Task ID: PROD-PHOTO-STORAGE
- Item IDs covered: 1, 2, 3, 4, 5 (no code of its own, met by item 1), 6, 7, 8 (added mid-task by the owner)
- Allowed paths (lane from the task prompt): user-service photo config/handlers and tests,
  `infrastructure/deploy/docker-compose.prod.yml`, `infrastructure/deploy/backup/**`,
  `docs/runbooks/BACKUP-RESTORE.md`, `docs/DEPLOYMENT.md`; item 8 adds
  `services/notification-service/internal/config/**` and its tests, prod + staging compose
  (notification-service FCM env) and the `.env` examples. Not `frontend/**`.
- Agent branch: agent/PROD-PHOTO-STORAGE-service-photos-volume-backup, created from logic-exploitation (144d945d)

## Decisions taken
- Item 1: a key is usable only when it is exactly 64 hex characters (32 bytes), the same rule
  `shared/infra/storage` enforces in production. With an unusable key user-service does not build
  photo storage at all (no random throwaway key outside production any more), so upload and read
  answer the existing BE-GAPS-FIX `503 photo_storage_unavailable` (item 5: no new code).
  `config.Load` fails in `APP_ENV=production` (startup and `--check-env` exit 1) and adds a
  `Config.Warnings` entry elsewhere; `--check-env` prints `PREFLIGHT WARNING: ...` and exits 0.
  Staging runs `APP_ENV=local` (`.env.staging.example`), so staging gets the warning, not the error.
- Item 2: reuses `DOCUMENT_ENCRYPTION_KEY`, the variable auth-service (documents) and chat-service
  (attachments, as `ATTACHMENT_ENCRYPTION_KEY`) already read from `/home/deploybot/.env`. No new
  secret. `STORAGE_BASE_DIR` is set in the compose file, not in `.env`. Volume ownership relies on
  Docker's copy-up: the prod image pre-creates `/app/data/service_photos` owned by `appuser`
  (uid 100, gid 101), and a fresh named volume mounted there inherits it (checked locally).
- Item 3: the photos volume is a **required** backup volume, like documents and attachments, so a
  missing volume fails the run loudly. Consequence: deploy the release (which creates the volume)
  before updating backup.sh on the VM; the runbook documents the order and a temporary
  `VOLUMES=` override. restore.sh already restored any `*.tar.gz.age`; it now prints a volume
  count report and warns, per run directory, about any expected volume missing from it
  (`EXPECTED_VOLUMES`, warning not error: runs taken before this release have no photos volume).
- Item 6: accepted `photo_url` = empty, the stored value resent unchanged (legacy values), or
  `services/<scope>/photo[_<alnum>].(jpg|png)` with scope = owner ID on create, service ID or
  tenant ID on update (the delete path's prefix rule, plus a file-name shape so traversal and
  nested paths are refused). Stable code `invalid_photo_url` (400), plus an `INVALID_PHOTO_URL`
  security event. The guard checks shape and prefix; it does not check that the object exists.
- Item 7: key = `services/<service id|owner id>/photo_<generateID()>.<ext>` (16 random hex). The
  old object is now always deleted on replace via the BE-GAPS-FIX delete path.
- Item 8: precedence `FCM_SERVICE_ACCOUNT_JSON` > `FCM_CREDENTIALS_JSON` > `FCM_SERVICE_ACCOUNT_JSON_B64`
  (existing deployments unchanged). Base64 decoding tolerates line wrapping and missing padding.
  The key must look like a service account (`type`, `client_email`, `private_key`).
  `FCM_PROJECT_ID` defaults to the key's `project_id`. When the key is missing or unusable,
  config clears both the key and the project ID, because `fcm.NewClient` treats a project ID
  alone as "enabled". That keeps the log line truthful without touching `internal/fcm` (out of
  lane). The status line is logged from `config.Load`, so it shows both in `--check-env` and at
  startup without editing `cmd/main.go` (out of lane).

## Changes per commit (message only — NO SHAs)
1. `PROD-PHOTO-STORAGE: item 1 - fail closed on an unusable DOCUMENT_ENCRYPTION_KEY`
2. `PROD-PHOTO-STORAGE: item 2 - prod compose: service photos volume and key`
3. `PROD-PHOTO-STORAGE: item 3 - back up and test-restore the service photos volume`
4. `PROD-PHOTO-STORAGE: item 4 - runbook and deployment steps for service photos`
5. `PROD-PHOTO-STORAGE: item 6 - photo_url write guard on POST/PUT /users/services`
6. `PROD-PHOTO-STORAGE: item 7 - new storage key on every photo upload`
7. `PROD-PHOTO-STORAGE: item 8 - FCM credentials reach notification-service`
8. `PROD-PHOTO-STORAGE: worklog`

## Verification
- `make check` passed before every commit (it stamps the tree; `make commit` refused otherwise).
- go test, user-service (from the `make check` run before the item 7 commit; the run is not verbose):

  ```text
  -- go test services/user-service: 3 unit (cached), 0 repo-reader (-count=1), 2 integration (-count=1) package(s) --
  ok  	github.com/project/user-service/internal/config	(cached)
  ok  	github.com/project/user-service/internal/models	(cached)
  ok  	github.com/project/user-service/internal/handlers	215.985s
  ok  	github.com/project/user-service/internal/store	25.571s
  ```

- go test, notification-service (from the `make check` run before the item 8 commit):

  ```text
  ok  	github.com/project/notification-service/internal/config	0.002s
  ok  	github.com/project/notification-service/internal/fcm	0.005s
  ok  	github.com/project/notification-service/internal/handlers	0.816s
  ok  	github.com/project/notification-service/internal/hub	0.525s
  ok  	github.com/project/notification-service/internal/store	1.956s
  ```

- user-service `--check-env` on a locally built prod image (`docker build --target prod`), with
  dummy JWT/TLS/Redis values. The key used was the all-zero test key; in this file it is written
  `<64 zeros>` because the repo's SHA check rejects long hex runs. Everything else is literal:

  ```text
  ## APP_ENV=production key=<empty>
  PREFLIGHT FAILED: config: DOCUMENT_ENCRYPTION_KEY is empty; service photos cannot be stored encrypted
  exit=1
  ## APP_ENV=production key=<2 chars>zz
  PREFLIGHT FAILED: config: DOCUMENT_ENCRYPTION_KEY is not a valid hex string; service photos cannot be stored encrypted
  exit=1
  ## APP_ENV=production key=<64 chars><64 zeros>
  PREFLIGHT OK: user-service config validated
  exit=0
  ## APP_ENV=local key=<empty>
  PREFLIGHT WARNING: DOCUMENT_ENCRYPTION_KEY is empty; service photo upload and read will answer 503 photo_storage_unavailable
  PREFLIGHT OK: user-service config validated
  exit=0
  ## APP_ENV=local key=<2 chars>zz
  PREFLIGHT OK: user-service config validated
  PREFLIGHT WARNING: DOCUMENT_ENCRYPTION_KEY is not a valid hex string; service photo upload and read will answer 503 photo_storage_unavailable
  exit=0
  ## APP_ENV=local key=<64 chars><64 zeros>
  PREFLIGHT OK: user-service config validated
  exit=0
  ```

- Volume ownership, same image, fresh named volume mounted at `/app/data/service_photos`:

  ```text
  uid=100(appuser) gid=101(appgroup) groups=101(appgroup),101(appgroup)
  drwxr-xr-x    1 100      101              0 Oct 26 07:01 /app/data/service_photos
  write-ok
  ```

- `docker compose -f infrastructure/deploy/docker-compose.prod.yml config`: run with an env file
  in which every variable is `REDACTED` (ports set to 3003, `DOCUMENT_ENCRYPTION_KEY` set to the
  all-zero test key, written `<64 zeros>` below for the same reason, `FCM_PROJECT_ID=qd-example`).
  Exit code and the relevant lines, after item 8:

  ```text
  79:      DOCUMENT_ENCRYPTION_KEY: "<64 zeros>"
  93:      STORAGE_BASE_DIR: /app/data/documents
  205:      STORAGE_BASE_DIR: /app/data/attachments
  347:      FCM_PROJECT_ID: qd-example
  348:      FCM_SERVICE_ACCOUNT_JSON_B64: REDACTED
  449:      DOCUMENT_ENCRYPTION_KEY: "<64 zeros>"
  458:      STORAGE_BASE_DIR: /app/data/service_photos
  489:        source: service_photos_data
  490:        target: /app/data/service_photos
  524:  service_photos_data:
  525:    name: saas_platform_service_photos_data
  exit=0
  ```

  `make check` also ran `compose config OK: prod (infrastructure/deploy/docker-compose.prod.yml)`
  and the same for local and staging.

- Backup e2e, `infrastructure/deploy/backup/test/e2e-local.sh` (PASS/volume/WARNING lines, the
  rest of the log omitted):

  ```text
  PASS: backup.sh exit 0
  PASS: 6 artifacts (mongo, 3 volumes incl. service photos, env, SHA256SUMS) written locally and uploaded with 201
  PASS: env-20261027T124329Z.age is in SHA256SUMS and uploaded before SHA256SUMS
  PASS: uploaded bytes identical to the local copies
  PASS: every artifact starts with the age header (encrypted)
  PASS: backup log contains neither the SAS sig, the Mongo password nor an .env value
  PASS: ps sampled every 50 ms during the run (30043 lines): no SAS sig, no Mongo password, no ping URL on any command line
  PASS: ps sampling caught the mongodump sidecar running (the sampler saw the run)
  PASS: no FAILED marker, last-success written
  PASS: run 1 pinged /start then success to the fake endpoint in order, no /fail, and every ping body is secret-free
  PASS: document counts match exactly: 10 collections, 36930 documents
  volume qdbt-2481497-documents 13 files 420006 bytes
  volume qdbt-2481497-attachments 6 files 90000 bytes
  volume qdbt-2481497-service_photos 6 files 54000 bytes
  PASS: qdbt-2481497-documents: 13 files restored, every sha256 equal to the source
  PASS: qdbt-2481497-documents: volume count report line matches the source file count
  PASS: qdbt-2481497-attachments: 6 files restored, every sha256 equal to the source
  PASS: qdbt-2481497-attachments: volume count report line matches the source file count
  PASS: qdbt-2481497-service_photos: 6 files restored, every sha256 equal to the source
  PASS: qdbt-2481497-service_photos: volume count report line matches the source file count
  volume qdbt-2481497-attachments 6 files 90000 bytes
  volume qdbt-2481497-documents 13 files 420006 bytes
  volume qdbt-2481497-service_photos 6 files 54000 bytes
  == WARNING: vols-only has no backup of volume qdbt-2481497-missing
  PASS: run dir restore: 3 volume report lines; a missing expected volume is flagged with one WARNING
  PASS: env: mode 600, size and line count of the source, no value and no variable name printed, deleted without -k
  PASS: env with -k: decrypted file kept, mode 600, byte-identical to the source .env
  PASS: after 4 runs: 3 local runs kept, the oldest (20261027T124329Z) removed; off-host copies untouched: 4 runs
  PASS: overlapping run refused by flock (exit 1), no FAILED marker, no /fail ping
  PASS: failed run: exit 1, FAILED marker written
  PASS: --post-stop (systemd ExecStopPost) prints the marker into the unit's log / systemctl status
  PASS: failed run pinged /fail once, body mentions the failed step, no secret in the body
  PASS: rejected upload: exit 1, HTTP status + Azure code logged, SAS sig not logged
  PASS: next successful run cleared the FAILED marker
  PASS: recovery run pinged success again (last of 13 pings so far)
  PASS: missing ping file: run succeeds, one 'ping disabled' log line, no ping sent
  PASS: unreachable ping endpoint: backup still succeeds, WARN logged, URL and path not in the log, no ping logged
  PASS: bash -x: refused (exit 2), no secret in the output
  PASS: placeholder recipient: refused (exit 1), no secret in the output
  PASS: SAS with read/list: refused (exit 1), no secret in the output
  PASS: SAS file mode 644: refused (exit 1), no secret in the output
  PASS: missing secrets file: refused (exit 1), no secret in the output
  E2E RESULT: PASS
  ```

- `shellcheck backup.sh restore.sh test/e2e-local.sh`: no findings.
- notification-service `--check-env` on a locally built prod image. The "valid" case uses a fake
  service-account file appended to a scratch env file with the exact `{ printf ...; base64 -w0 ...; echo; } | tee -a`
  pipeline from DEPLOYMENT.md step 9.4 (that step printed `key length: 248`):

  ```text
  ## valid key via env-file
  PREFLIGHT OK: notification-service config validated
  2026/10/27 13:06:02 [CONFIG] push enabled (project qd-test)
  exit=0
  ## invalid base64
  2026/10/27 13:06:03 [CONFIG] push disabled: FCM_SERVICE_ACCOUNT_JSON_B64 is not valid base64
  PREFLIGHT OK: notification-service config validated
  exit=0
  ## nothing set
  PREFLIGHT OK: notification-service config validated
  2026/10/27 13:06:04 [CONFIG] push disabled: no FCM service-account key (set FCM_SERVICE_ACCOUNT_JSON_B64)
  exit=0
  ```

- `make check`, last lines of the run before the item 8 commit:

  ```text
  [timing] total 243.5s
  == pre-push gate: all checks passed (scope: go=services/notification-service,services/user-service contracts docs infra-tests docgen compose=local,staging,prod) ==
  ```

## Unverified
- Anything on the production VM (no server access): the real `.env` key, volume creation by the CD
  deploy, the backup on the VM, the after-deploy photo check. The owner steps are in
  docs/DEPLOYMENT.md steps 9.3 and 9.4 and docs/runbooks/BACKUP-RESTORE.md.
- That the go-test runs exercised the new Mongo-backed handler tests rather than skipping them:
  `make check` is not verbose. The handlers package took about 200 s and local Mongo was up, and
  the photo tests skip only when Mongo is unreachable, but no `--- PASS` line was captured for
  `TestServicePhotoURL_WriteGuard` or `TestServicePhoto_ReplaceSameTypeGetsNewKey`. An early raw
  `go test -run TestServicePhoto -v` (run before I noticed the rule against raw tests on shared
  services) showed `TestServicePhoto_InvalidEncryptionKey_FailsClosed` and the existing photo
  tests passing.
- The restore-into-production commands for the photos volume (`tar --numeric-owner`) were not run.
- Real FCM push delivery (see the open question).

## Follow-ups / out-of-lane findings
- **FCM client has no OAuth**: `services/notification-service/internal/fcm/fcm.go` posts to
  `https://fcm.googleapis.com/v1/projects/<id>/messages:send` with no `Authorization: Bearer`
  header. It stores the service-account JSON but never uses it to get an access token. Google
  rejects such requests (401), so push cannot work even after item 8. The fix (mint and cache an
  OAuth2 token from the key, JWT-bearer grant to `oauth2.googleapis.com/token`, scope
  `firebase.messaging`) is in `internal/fcm`, outside this task's lane. It may be possible
  without a go.mod change (`golang-jwt/jwt/v5` is already a dependency).
- `infrastructure/docker-compose.yml` (local dev) passes no `DOCUMENT_ENCRYPTION_KEY` to
  user-service. After item 1, local photo upload answers 503 until it does (`--check-env` warns).
  Not changed: out of lane.
- user-service still falls back to a temp dir when `STORAGE_BASE_DIR` cannot be created
  (`handlers.go`). With the volume in place this should not happen, but photos written there
  would be lost on restart. Not changed: not asked.
- `GET /users/services/{id}/photo` keeps a fixed URL and answers `Cache-Control: private, max-age=86400`.
  Item 7's cache busting only helps clients that address the photo by its key (`photo_url`).
- Photos uploaded before a service exists (`services/<owner>/photo_<id>.*`) that are never attached
  to a service are never deleted (orphans). Unchanged by this task.
- Item 6 now answers 400 for any `photo_url` that is not an upload key. An old app build that sends a
  device path or URL on create/update gets 400 instead of a silently stored value. The current
  frontend sends the key returned by the upload (`service_photo_store.dart`); older builds not checked.

## Open questions
- Item 8: may a follow-up task (lane `services/notification-service/internal/fcm/**`) add OAuth2
  access-token minting to the FCM client? Until then "push enabled" means the key is loaded, not
  that sends succeed. DEPLOYMENT.md step 9.4 says so in a warning.
