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

## Unverified
- Real staging and production `.env` values are not in this repository; the
  deploy notes below are based on the checked-in compose files and examples.
- Everything else claimed for item 1 was verified locally.

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
