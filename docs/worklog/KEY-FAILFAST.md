# Worklog: KEY-FAILFAST — chat and user services refuse a bad document key outside local/test

## Task and scope
- Task ID: KEY-FAILFAST
- Item IDs covered: 1 (chat-service), 2 (user-service)
- Allowed paths (lane from the task prompt):
  `services/chat-service/internal/config/**`,
  `services/chat-service/internal/handlers/chat.go` plus new/changed
  `*_test.go` in `services/chat-service/internal/handlers/`,
  `services/chat-service/cmd/main.go` (only if item 1 needed it),
  `services/user-service/internal/config/**`,
  `docs/worklog/KEY-FAILFAST.md`
- Agent branch: `agent/KEY-FAILFAST-document-key-fail-fast`, created from
  `logic-exploitation` at `c3cbd7f0` (Merge SEC-QUICK). The base had not moved
  when the worktree was created.

## Decisions taken
- Item 1 config: validation runs after the existing `APP_ENV` default
  (`""` → `"production"`) and after the attachment key resolution. The key
  variable name is captured during resolution (`ATTACHMENT_ENCRYPTION_KEY`
  when set, otherwise `DOCUMENT_ENCRYPTION_KEY`), so an empty
  `ATTACHMENT_ENCRYPTION_KEY` that falls back to `DOCUMENT_ENCRYPTION_KEY`
  names the variable that was actually used.
- Item 1 config: the published dev key is rejected before the hex/length
  checks (it is valid hex), with its own message. No error path includes the
  key value.
- Item 1 handler: `NewChat` now assigns the result to a concrete
  `*storage.LocalStorage` first and only assigns it to the `storage.Storage`
  interface when `err == nil`. On failure it logs once (no key value) and
  leaves `chatStorage` as a true nil interface.
- Item 1 handler: the temp-dir fallback is kept **only for local/test**. In
  local/test the storage layer accepts any key, so the remaining failure mode
  is a missing/unwritable configured directory; a temp dir keeps development
  working. Outside local/test an ephemeral temp dir would silently lose
  attachments, and `config.Load` already refuses an unusable key, so no
  fallback is used there. The failure is logged once and attachment handlers
  answer 503.
- Item 1 handler: both attachment handlers that use `c.storage`
  (`UploadTicketAttachment`, `ViewAttachment`) check `c.storage == nil` right
  after the method check and answer `503 attachment_storage_unavailable`
  through `handlerutil.WriteSafeError`, following the user-service
  `photo_storage_unavailable` pattern. The response never carries storage
  paths or key material.
- Item 1 tests: `TestLoad` previously relied on an empty key with the default
  production environment; it now sets a valid attachment key so it still
  tests defaults without weakening the new rule.
- Item 1 tests: `TestSafeError_NoInternalsLeak_Chat` used `NewChat` without a
  storage, so its unauthorized-upload case would now stop at the 503 guard
  instead of the 401 auth check. It now passes a working storage so it still
  exercises the sanitized 401 path; the new 503 guard is covered by
  `TestAttachmentHandlers_StorageUnavailable_503`.
- Item 2: the `ValidateDocumentEncryptionKey` failure is fatal for every
  `!isDevOnlyAppEnv(appEnv)`; local/test keep the warning and the 503
  behaviour. `ALLOW_TEST_PAYMENT_BYPASS` was left unchanged (see follow-up).
- Startup failure belongs in config: checked that
  `services/chat-service/cmd/main.go` already does
  `log.Fatalf("[CHAT] Failed to load configuration: %v", err)` and its
  `--check-env` path exits non-zero on `config.Load` errors. No change was
  needed there, so `cmd/main.go` is untouched.

## Changes per commit (message only — NO SHAs)
1. `KEY-FAILFAST: item 1 - chat fail fast on invalid attachment key`
2. `KEY-FAILFAST: item 2 - user fail fast on invalid document key`

## Verification

### Item 1 — chat-service config, before the change (failing)
Command: `go test ./internal/config -run TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest -count=1`
```text
--- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest (0.00s)
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_staging_not_hex (0.00s)
        config_test.go:153: APP_ENV="staging" ATTACHMENT_ENCRYPTION_KEY=not hex: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_staging_wrong_length (0.00s)
        config_test.go:153: APP_ENV="staging" ATTACHMENT_ENCRYPTION_KEY=wrong length: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_staging_published_dev_key (0.00s)
        config_test.go:153: APP_ENV="staging" ATTACHMENT_ENCRYPTION_KEY=published dev key: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_staging_empty (0.00s)
        config_test.go:153: APP_ENV="staging" ATTACHMENT_ENCRYPTION_KEY=empty: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_prod_published_dev_key (0.00s)
        config_test.go:153: APP_ENV="prod" ATTACHMENT_ENCRYPTION_KEY=published dev key: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_prod_empty (0.00s)
        config_test.go:153: APP_ENV="prod" ATTACHMENT_ENCRYPTION_KEY=empty: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_prod_not_hex (0.00s)
        config_test.go:153: APP_ENV="prod" ATTACHMENT_ENCRYPTION_KEY=not hex: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_prod_wrong_length (0.00s)
        config_test.go:153: APP_ENV="prod" ATTACHMENT_ENCRYPTION_KEY=wrong length: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_empty (0.00s)
        config_test.go:153: APP_ENV="Production" ATTACHMENT_ENCRYPTION_KEY=empty: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_not_hex (0.00s)
        config_test.go:153: APP_ENV="Production" ATTACHMENT_ENCRYPTION_KEY=not hex: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_wrong_length (0.00s)
        config_test.go:153: APP_ENV="Production" ATTACHMENT_ENCRYPTION_KEY=wrong length: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_published_dev_key (0.00s)
        config_test.go:153: APP_ENV="Production" ATTACHMENT_ENCRYPTION_KEY=published dev key: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_empty (0.00s)
        config_test.go:153: APP_ENV="production" ATTACHMENT_ENCRYPTION_KEY=empty: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_not_hex (0.00s)
        config_test.go:153: APP_ENV="production" ATTACHMENT_ENCRYPTION_KEY=not hex: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_wrong_length (0.00s)
        config_test.go:153: APP_ENV="production" ATTACHMENT_ENCRYPTION_KEY=wrong length: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_published_dev_key (0.00s)
        config_test.go:153: APP_ENV="production" ATTACHMENT_ENCRYPTION_KEY=published dev key: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__empty (0.00s)
        config_test.go:153: APP_ENV="" ATTACHMENT_ENCRYPTION_KEY=empty: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__not_hex (0.00s)
        config_test.go:153: APP_ENV="" ATTACHMENT_ENCRYPTION_KEY=not hex: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__wrong_length (0.00s)
        config_test.go:153: APP_ENV="" ATTACHMENT_ENCRYPTION_KEY=wrong length: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__published_dev_key (0.00s)
        config_test.go:153: APP_ENV="" ATTACHMENT_ENCRYPTION_KEY=published dev key: expected Load to refuse the key, got nil
    --- FAIL: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/document_fallback_names_DOCUMENT_ENCRYPTION_KEY (0.00s)
        config_test.go:172: expected Load to refuse the fallback DOCUMENT_ENCRYPTION_KEY, got nil
FAIL
FAIL	github.com/project/chat-service/internal/config	0.003s
FAIL
```

### Item 1 — chat-service config, after the change (passing)
Command: `go test ./internal/config -run TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest -count=1 -v`
```text
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_Production_wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses_production_published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/refuses__not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/document_fallback_names_DOCUMENT_ENCRYPTION_KEY (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/valid_key_outside_local/test (0.00s)
        --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/valid_key_outside_local/test/staging (0.00s)
        --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/valid_key_outside_local/test/prod (0.00s)
        --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/valid_key_outside_local/test/Production (0.00s)
        --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/valid_key_outside_local/test/production (0.00s)
        --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/valid_key_outside_local/test/#00 (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_local_empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_local_not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_local_wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_local_published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_LOCAL_empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_LOCAL_not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_LOCAL_wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_LOCAL_published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__local__empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__local__not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__local__wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__local__published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_test_empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_test_not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_test_wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_test_published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_TEST_published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_TEST_empty (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_TEST_not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows_TEST_wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__test__not_hex (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__test__wrong_length (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__test__published_dev_key (0.00s)
    --- PASS: TestLoad_RefusesInvalidAttachmentKeyOutsideLocalTest/allows__test__empty (0.00s)
PASS
ok  	github.com/project/chat-service/internal/config	0.002s
```

### Item 1 — chat-service handler, before the change (failing)
Command: `go test ./internal/handlers -run TestNewChat_StorageInitFailureLeavesNilInterface -count=1`
```text
2026/11/23 07:55:55 security event shipping disabled — CloudWatch log group not set
2026/11/23 07:55:55 [CHAT] Warning: failed to initialize storage with base dir /tmp/TestNewChat_StorageInitFailureLeavesNilInterface994098235/001 (storage: failed to create encryption cipher: storage: DOCUMENT_ENCRYPTION_KEY must be a valid hex string) - falling back to temp dir
--- FAIL: TestNewChat_StorageInitFailureLeavesNilInterface (0.00s)
    storage_unavailable_test.go:35: storage = (*storage.LocalStorage)(nil), want a nil interface after storage init failure
FAIL
FAIL	github.com/project/chat-service/internal/handlers	0.003s
FAIL
```
Command: `go test ./internal/handlers -run TestAttachmentHandlers_StorageUnavailable_503 -count=1`
```text
2026/11/23 07:55:56 security event shipping disabled — CloudWatch log group not set
2026/11/23 07:55:56 [CHAT] Warning: failed to initialize storage with base dir /tmp/TestAttachmentHandlers_StorageUnavailable_503973567797/001 (storage: failed to create encryption cipher: storage: DOCUMENT_ENCRYPTION_KEY must be a valid hex string) - falling back to temp dir
2026/11/23 07:55:56 [ERROR] 6701e1d343d745d1 unauthorized POST /chat/tickets/t1/attachment: missing authentication token
--- FAIL: TestAttachmentHandlers_StorageUnavailable_503 (0.00s)
    storage_unavailable_test.go:65: upload: expected 503, got 401: {"error":"unauthorized","code":"unauthorized","request_id":"6701e1d343d745d1"}
FAIL
FAIL	github.com/project/chat-service/internal/handlers	0.004s
FAIL
```

### Item 1 — chat-service handler, after the change (passing)
Command: `go test ./internal/handlers -run 'TestNewChat_StorageInitFailureLeavesNilInterface|TestAttachmentHandlers_StorageUnavailable_503' -count=1 -v`
```text
=== RUN   TestNewChat_StorageInitFailureLeavesNilInterface
2026/11/23 07:56:53 security event shipping disabled — CloudWatch log group not set
2026/11/23 07:56:53 [CHAT] Attachment storage unavailable; upload and view will answer 503 attachment_storage_unavailable: storage: failed to create encryption cipher: storage: DOCUMENT_ENCRYPTION_KEY must be a valid hex string
--- PASS: TestNewChat_StorageInitFailureLeavesNilInterface (0.00s)
=== RUN   TestAttachmentHandlers_StorageUnavailable_503
2026/11/23 07:56:53 [CHAT] Attachment storage unavailable; upload and view will answer 503 attachment_storage_unavailable: storage: failed to create encryption cipher: storage: DOCUMENT_ENCRYPTION_KEY must be a valid hex string
2026/11/23 07:56:53 [ERROR] f7141dd3e8a1799e attachment_storage_unavailable POST /chat/tickets/t1/attachment: storage not initialized
2026/11/23 07:56:53 [ERROR] 46907f0e84a6d803 attachment_storage_unavailable GET /chat/attachments/view: storage not initialized
--- PASS: TestAttachmentHandlers_StorageUnavailable_503 (0.00s)
PASS
ok  	github.com/project/chat-service/internal/handlers	0.004s
```

### Item 2 — user-service config, before the change (failing)
Command: `go test ./internal/config -run TestLoad_DocumentEncryptionKey -count=1`
```text
--- FAIL: TestLoad_DocumentEncryptionKey (0.00s)
    --- FAIL: TestLoad_DocumentEncryptionKey/empty (0.00s)
        config_test.go:160: APP_ENV="Production": expected an error, got cfg with warnings [DOCUMENT_ENCRYPTION_KEY is empty; service photo upload and read will answer 503 photo_storage_unavailable]
    --- FAIL: TestLoad_DocumentEncryptionKey/not_hex (0.00s)
        config_test.go:160: APP_ENV="Production": expected an error, got cfg with warnings [DOCUMENT_ENCRYPTION_KEY is not a valid hex string; service photo upload and read will answer 503 photo_storage_unavailable]
    --- FAIL: TestLoad_DocumentEncryptionKey/too_short (0.00s)
        config_test.go:160: APP_ENV="Production": expected an error, got cfg with warnings [DOCUMENT_ENCRYPTION_KEY must be 32 bytes (64 hex characters), got 16 bytes; service photo upload and read will answer 503 photo_storage_unavailable]
    --- FAIL: TestLoad_DocumentEncryptionKey/too_long (0.00s)
        config_test.go:160: APP_ENV="Production": expected an error, got cfg with warnings [DOCUMENT_ENCRYPTION_KEY must be 32 bytes (64 hex characters), got 33 bytes; service photo upload and read will answer 503 photo_storage_unavailable]
    --- FAIL: TestLoad_DocumentEncryptionKey/odd_hex_length (0.00s)
        config_test.go:160: APP_ENV="Production": expected an error, got cfg with warnings [DOCUMENT_ENCRYPTION_KEY is not a valid hex string; service photo upload and read will answer 503 photo_storage_unavailable]
FAIL
FAIL	github.com/project/user-service/internal/config	0.003s
FAIL
```

### Item 2 — user-service config, after the change (passing)
Command: `go test ./internal/config -run TestLoad_DocumentEncryptionKey -count=1 -v`
```text
=== RUN   TestLoad_DocumentEncryptionKey
=== RUN   TestLoad_DocumentEncryptionKey/empty
=== RUN   TestLoad_DocumentEncryptionKey/not_hex
=== RUN   TestLoad_DocumentEncryptionKey/too_short
=== RUN   TestLoad_DocumentEncryptionKey/too_long
=== RUN   TestLoad_DocumentEncryptionKey/odd_hex_length
=== RUN   TestLoad_DocumentEncryptionKey/valid_key
--- PASS: TestLoad_DocumentEncryptionKey (0.00s)
    --- PASS: TestLoad_DocumentEncryptionKey/empty (0.00s)
    --- PASS: TestLoad_DocumentEncryptionKey/not_hex (0.00s)
    --- PASS: TestLoad_DocumentEncryptionKey/too_short (0.00s)
    --- PASS: TestLoad_DocumentEncryptionKey/too_long (0.00s)
    --- PASS: TestLoad_DocumentEncryptionKey/odd_hex_length (0.00s)
    --- PASS: TestLoad_DocumentEncryptionKey/valid_key (0.00s)
PASS
ok  	github.com/project/user-service/internal/config	0.002s
```

### Final gate (after both item commits)
Command: `make check` — exit 0. Literal scope block and result lines:
```text
scope: changed paths = committed since merge-base with logic-exploitation (c3cbd7f0) + staged + unstaged + untracked
scope: SCOPED gate (8 changed path(s)): go=services/chat-service,services/user-service contracts docs infra-tests docgen
scope:   docs/worklog/KEY-FAILFAST.md
scope:   services/chat-service/internal/config/config.go
scope:   services/chat-service/internal/config/config_test.go
scope:   services/chat-service/internal/handlers/chat.go
scope:   services/chat-service/internal/handlers/safe_error_regression_test.go
scope:   services/chat-service/internal/handlers/storage_unavailable_test.go
scope:   services/user-service/internal/config/config.go
scope:   services/user-service/internal/config/config_test.go
TEST_DB_SUFFIX=KEY-FAILFAST-77961
== pre-push gate: running checks (scope: go=services/chat-service,services/user-service contracts docs infra-tests docgen) ==
-- checking services/chat-service --
ok  	github.com/project/chat-service/internal/config	(cached)
ok  	github.com/project/chat-service/internal/chat	0.450s
ok  	github.com/project/chat-service/internal/handlers	31.793s
ok  	github.com/project/chat-service/internal/store	6.142s
  Issues : 0
-- checking services/user-service --
ok  	github.com/project/user-service/internal/config	(cached)
ok  	github.com/project/user-service/internal/models	(cached)
ok  	github.com/project/user-service/internal/handlers	251.725s
ok  	github.com/project/user-service/internal/store	31.502s
  Issues : 0
ok  	github.com/project/tests/contracts	0.039s
[timing] total 311.1s
== pre-push gate: all checks passed (scope: go=services/chat-service,services/user-service contracts docs infra-tests docgen) ==
gate stamp written: /home/omarmaarouf/CS tools/Antigravity/SaaS prototype/.git/gate-stamps/5e8040cb... (scope: go=services/chat-service,services/user-service contracts docs infra-tests docgen)
```
- `gofmt -l .` — empty (no output).
- `go vet ./...` in `services/chat-service` — exit 0, no output.
- `go vet ./...` in `services/user-service` — exit 0, no output.
- `gosec -fmt=text ./...` unfiltered (dev build, default rules):
  `services/chat-service` `Files: 8`, `Lines: 3572`, `Nosec: 15`, `Issues: 0`;
  `services/user-service` `Files: 24`, `Lines: 15516`, `Nosec: 61`, `Issues: 0`.
- `make docs-check` — PASS, no `docs/APPLICATION_MAP.md` change. Literal first lines:
  ```text
  go run tools/docgen/main.go -check
  APPLICATION_MAP.md is fresh.
  go test -v -count=1 ./shared/infra/docgen ./shared/infra/handlerutil ./shared/infra/jwtutil ./shared/infra/ratelimit ./shared/infra/resilience ./shared/infra/tlsutil
  ```

## Deploy notes
- Chat now refuses to start outside local/test without a valid
  `ATTACHMENT_ENCRYPTION_KEY` or `DOCUMENT_ENCRYPTION_KEY` (the same rule
  auth-service already applied). User now refuses to start without a valid
  `DOCUMENT_ENCRYPTION_KEY` outside local/test, not only on an exact
  `APP_ENV=production`.
- Checked read-only compose stacks:
  - `infrastructure/deploy/docker-compose.prod.yml`: chat gets
    `APP_ENV: ${APP_ENV}` and
    `ATTACHMENT_ENCRYPTION_KEY: ${DOCUMENT_ENCRYPTION_KEY}`; user gets
    `APP_ENV: ${APP_ENV}` and `DOCUMENT_ENCRYPTION_KEY:
    ${DOCUMENT_ENCRYPTION_KEY}`. `docs/DEPLOYMENT.md` requires
    `APP_ENV=production` and a 64-hex `DOCUMENT_ENCRYPTION_KEY`. If the VM
    `.env` matches that (auth-service already refused anything else), **no
    production stack stops starting**.
  - `infrastructure/staging/docker-compose.staging.yml`: same key wiring for
    chat and user. `infrastructure/staging/.env.staging.example` sets
    `APP_ENV=local` and `DOCUMENT_ENCRYPTION_KEY=CHANGE_ME_64_HEX`. Because
    `APP_ENV=local`, both services accept the placeholder and start. If the
    real staging `.env` sets a non-local/test `APP_ENV` (e.g. `staging`), the
    placeholder is not a valid key and **both services would now refuse to
    start**; a real 64-hex key is required there.
  - `infrastructure/docker-compose.yml` (local): `APP_ENV` comes from
    `.env.example`, which sets `APP_ENV=local`; chat is not given an
    attachment/document key, which local/test accept (the storage layer
    generates one). If a local run sets a non-local/test `APP_ENV`, chat now
    refuses to start instead of panicking on attachment requests.
- Exact check the owner should run on the production VM before release:
  ```bash
  sudo awk 'index($0,"DOCUMENT_ENCRYPTION_KEY=")==1 { v=substr($0,25); gsub(/^["\x27]|["\x27]$/,"",v); print "DOCUMENT_ENCRYPTION_KEY length=" length(v) (v ~ /^[0-9A-Fa-f]+$/ ? " hex" : " NOT hex") }' /home/deploybot/.env
  sudo grep '^APP_ENV=' /home/deploybot/.env
  ```
  Expect `DOCUMENT_ENCRYPTION_KEY length=64 hex` and `APP_ENV=production`.
  Run the same `DOCUMENT_ENCRYPTION_KEY` check against the staging `.env`
  (and confirm its `APP_ENV`). If a non-local/test environment has an empty,
  invalid or placeholder key, restore the **existing** key from the password
  manager; do not generate a new one while encrypted data exists.

## Unverified
- Real staging and production `.env` values are not in this repository; the
  deploy notes above are based on the checked-in compose files and examples.
- Everything else claimed for items 1 and 2 was verified locally.

## Follow-ups / out-of-lane findings
- Item 2 follow-up: `ALLOW_TEST_PAYMENT_BYPASS` still uses the exact
  `appEnv == "production"` comparison, so `staging`, `prod` and `Production`
  accept the flag. Suggested issue title:
  `user-service: apply isDevOnlyAppEnv to ALLOW_TEST_PAYMENT_BYPASS`.
  Suggested body: `services/user-service/internal/config/config.go` refuses
  `ALLOW_TEST_PAYMENT_BYPASS=true` only for an exact `APP_ENV=production`.
  Every other non-local/test environment (`staging`, `prod`, `Production`)
  accepts it, which contradicts the flag's "local/test only" intent. Use the
  existing `isDevOnlyAppEnv` helper so the flag is refused outside local/test,
  and extend `TestLoad_AllowTestPaymentBypass` to cover those environments.
  Left unchanged in KEY-FAILFAST because the task prompt scopes item 2 to the
  document key.

## Open questions
- none
