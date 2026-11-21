# Worklog: SEC-QUICK — three small security fixes

## Task and scope
- Task ID: SEC-QUICK
- Item IDs covered: #27, #30, #29
- Allowed paths (lane from the task prompt): `shared/infra/storage/**`,
  `services/auth-service/internal/config/**`,
  `services/auth-service/internal/handlers/internal_device_token.go`,
  `services/auth-service/internal/handlers/internal_device_token_test.go`,
  `docs/worklog/SEC-QUICK.md`
- Agent branch: `agent/SEC-QUICK-small-security-fixes`, created from
  `logic-exploitation` at `d3cf7f5d` (Merge ADDR-REQUIRED). The base had not
  moved when the worktree was created.

## Decisions taken
- Item 1: `key == ""` and `key == "."` are rejected by `Upload` and
  `OpenFile`. Both resolve to the base directory itself, which is not a file;
  `Delete` already rejected them. A single unexported `resolveInBase` helper
  now does the Abs/Join/Clean work plus the separator-aware prefix check in
  all three functions.
- Item 2: the body cap is 4 KiB (`maxDeviceTokenUnregisterBodyBytes = 4 << 10`),
  placed next to `maxDeviceTokenLength`. The body is at most
  `{"token": "<512 chars>"}`, so 4 KiB is ample. The cap is applied after the
  method and internal-token checks, so an unauthenticated caller still gets
  401 without the body being read. An oversized body answers 413 with the
  handler's existing `{"error": ...}` JSON shape and the stable message
  `request body too large`; a malformed body stays 400.
- Item 3: at the storage layer `appEnv == ""` is treated as **non-local**.
  Evidence: auth-service `config.Load` maps `""` to `"production"`
  (`services/auth-service/internal/config/config.go`); chat-service does the
  same (`services/chat-service/internal/config/config.go`); user-service
  defaults its storage `appEnv` to `"test"` when `cfg.AppEnv == ""`
  (`services/user-service/internal/handlers/handlers.go`). Every
  `NewLocalStorage` / `NewLocalStorageWithPath` call in tests passes `"test"`
  (the only other value is `"production"` in the production-refusal test).
  No caller passes `""`, so making `""` non-local does not break any caller.

## Changes per commit (message only — NO SHAs)
1. `SEC-QUICK: item 1 - storage traversal guard trailing separator (#27)`
2. `SEC-QUICK: item 2 - cap internal device-token unregister body (#30)`
3. `SEC-QUICK: item 3 - refuse empty document key outside local/test (#29)`

## Verification
- Item 1 test, before the change (failing):
  ```text
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/nested_key_inside_base
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/sibling_prefix_escape
      storage_test.go:182: Upload("../001-evil/x") = nil, want a directory traversal error
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/parent_escape
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/empty_key_equals_base
      storage_test.go:185: Upload("") error = storage: failed to open destination file: open /tmp/TestLocalStorage_RejectsSiblingPrefixEscape631815787/001: is a directory, want directory traversal detected
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/dot_key_equals_base
      storage_test.go:185: Upload(".") error = storage: failed to open destination file: open /tmp/TestLocalStorage_RejectsSiblingPrefixEscape631815787/001: is a directory, want directory traversal detected
  --- FAIL: TestLocalStorage_RejectsSiblingPrefixEscape (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/nested_key_inside_base (0.00s)
      --- FAIL: TestLocalStorage_RejectsSiblingPrefixEscape/sibling_prefix_escape (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/parent_escape (0.00s)
      --- FAIL: TestLocalStorage_RejectsSiblingPrefixEscape/empty_key_equals_base (0.00s)
      --- FAIL: TestLocalStorage_RejectsSiblingPrefixEscape/dot_key_equals_base (0.00s)
  FAIL
  FAIL	github.com/project/shared/infra/storage	0.002s
  FAIL
  ```
- Item 1 test, after the change (passing):
  ```text
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/nested_key_inside_base
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/sibling_prefix_escape
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/parent_escape
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/empty_key_equals_base
  === RUN   TestLocalStorage_RejectsSiblingPrefixEscape/dot_key_equals_base
  --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/nested_key_inside_base (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/sibling_prefix_escape (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/parent_escape (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/empty_key_equals_base (0.00s)
      --- PASS: TestLocalStorage_RejectsSiblingPrefixEscape/dot_key_equals_base (0.00s)
  PASS
  ok  	github.com/project/shared/infra/storage	0.003s
  ```
- Item 2 test, before the handler change (failing):
  ```text
  === RUN   TestUnregisterStaleDeviceToken_BodyCap
  === RUN   TestUnregisterStaleDeviceToken_BodyCap/body_just_over_the_cap
      internal_device_token_test.go:211: expected 413, got 400 (body: {"error":"token cannot exceed 512 characters"}
          )
  === RUN   TestUnregisterStaleDeviceToken_BodyCap/valid_body_under_the_cap
  2026/11/21 11:55:52 [AUTH] Unregistered stale device token stale-fcm- (user records changed: 0)
  === RUN   TestUnregisterStaleDeviceToken_BodyCap/too-long_token_under_the_cap
  --- FAIL: TestUnregisterStaleDeviceToken_BodyCap (0.00s)
      --- FAIL: TestUnregisterStaleDeviceToken_BodyCap/body_just_over_the_cap (0.00s)
      --- PASS: TestUnregisterStaleDeviceToken_BodyCap/valid_body_under_the_cap (0.00s)
      --- PASS: TestUnregisterStaleDeviceToken_BodyCap/too-long_token_under_the_cap (0.00s)
  FAIL
  FAIL	github.com/project/auth-service/internal/handlers	0.004s
  FAIL
  ```
- Item 2 test, after the handler change (passing):
  ```text
  === RUN   TestUnregisterStaleDeviceToken_BodyCap
  === RUN   TestUnregisterStaleDeviceToken_BodyCap/body_just_over_the_cap
  === RUN   TestUnregisterStaleDeviceToken_BodyCap/valid_body_under_the_cap
  2026/11/21 11:56:04 [AUTH] Unregistered stale device token stale-fcm- (user records changed: 0)
  === RUN   TestUnregisterStaleDeviceToken_BodyCap/too-long_token_under_the_cap
  --- PASS: TestUnregisterStaleDeviceToken_BodyCap (0.00s)
      --- PASS: TestUnregisterStaleDeviceToken_BodyCap/body_just_over_the_cap (0.00s)
      --- PASS: TestUnregisterStaleDeviceToken_BodyCap/valid_body_under_the_cap (0.00s)
      --- PASS: TestUnregisterStaleDeviceToken_BodyCap/too-long_token_under_the_cap (0.00s)
  PASS
  ok  	github.com/project/auth-service/internal/handlers	0.003s
  ```
- gosec on `services/auth-service` after the handler change — 0 issues, so the
  new `http.MaxBytesReader` line needs no `#nosec`/`//nolint` comment:
  ```text
  Summary:
    Gosec  : dev
    Files  : 17
    Lines  : 7721
    Nosec  : 35
    Issues : 0
  ```
- Item 3 storage test, before the change (failing):
  ```text
  === RUN   TestCreateDocAEAD_EnvironmentRules
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_staging
      storage_test.go:249: createDocAEAD("", "staging") = nil error, want an error
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_prod
      storage_test.go:249: createDocAEAD("", "prod") = nil error, want an error
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_Production
      storage_test.go:249: createDocAEAD("", "Production") = nil error, want an error
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_empty_environment
      storage_test.go:249: createDocAEAD("", "") = nil error, want an error
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_local
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_test
  === RUN   TestCreateDocAEAD_EnvironmentRules/invalid_hex_staging
      storage_test.go:249: createDocAEAD("not-a-hex-key", "staging") = nil error, want an error
  === RUN   TestCreateDocAEAD_EnvironmentRules/invalid_hex_local
  === RUN   TestCreateDocAEAD_EnvironmentRules/wrong_length_staging
      storage_test.go:249: createDocAEAD("abcd", "staging") = nil error, want an error
  === RUN   TestCreateDocAEAD_EnvironmentRules/wrong_length_test
  === RUN   TestCreateDocAEAD_EnvironmentRules/valid_key_staging
  --- FAIL: TestCreateDocAEAD_EnvironmentRules (0.00s)
      --- FAIL: TestCreateDocAEAD_EnvironmentRules/empty_key_staging (0.00s)
      --- FAIL: TestCreateDocAEAD_EnvironmentRules/empty_key_prod (0.00s)
      --- FAIL: TestCreateDocAEAD_EnvironmentRules/empty_key_Production (0.00s)
      --- FAIL: TestCreateDocAEAD_EnvironmentRules/empty_key_empty_environment (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_local (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_test (0.00s)
      --- FAIL: TestCreateDocAEAD_EnvironmentRules/invalid_hex_staging (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/invalid_hex_local (0.00s)
      --- FAIL: TestCreateDocAEAD_EnvironmentRules/wrong_length_staging (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/wrong_length_test (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/valid_key_staging (0.00s)
  FAIL
  FAIL	github.com/project/shared/infra/storage	0.002s
  FAIL
  ```
- Item 3 storage test, after the change (passing):
  ```text
  === RUN   TestCreateDocAEAD_EnvironmentRules
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_staging
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_prod
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_Production
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_empty_environment
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_local
  === RUN   TestCreateDocAEAD_EnvironmentRules/empty_key_test
  === RUN   TestCreateDocAEAD_EnvironmentRules/invalid_hex_staging
  === RUN   TestCreateDocAEAD_EnvironmentRules/invalid_hex_local
  === RUN   TestCreateDocAEAD_EnvironmentRules/wrong_length_staging
  === RUN   TestCreateDocAEAD_EnvironmentRules/wrong_length_test
  === RUN   TestCreateDocAEAD_EnvironmentRules/valid_key_staging
  --- PASS: TestCreateDocAEAD_EnvironmentRules (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_staging (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_prod (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_Production (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_empty_environment (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_local (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/empty_key_test (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/invalid_hex_staging (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/invalid_hex_local (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/wrong_length_staging (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/wrong_length_test (0.00s)
      --- PASS: TestCreateDocAEAD_EnvironmentRules/valid_key_staging (0.00s)
  PASS
  ok  	github.com/project/shared/infra/storage	0.002s
  ```
- Item 3 config test, before the change (failing):
  ```text
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_production
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_PRODUCTION
      config_test.go:280: APP_ENV="PRODUCTION": expected Load to refuse an empty DOCUMENT_ENCRYPTION_KEY, got nil
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses__production_
      config_test.go:280: APP_ENV=" production ": expected Load to refuse an empty DOCUMENT_ENCRYPTION_KEY, got nil
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_staging
      config_test.go:280: APP_ENV="staging": expected Load to refuse an empty DOCUMENT_ENCRYPTION_KEY, got nil
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_prod
      config_test.go:280: APP_ENV="prod": expected Load to refuse an empty DOCUMENT_ENCRYPTION_KEY, got nil
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_Production
      config_test.go:280: APP_ENV="Production": expected Load to refuse an empty DOCUMENT_ENCRYPTION_KEY, got nil
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_local
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_LOCAL
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows__local_
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_test
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_TEST
  === RUN   TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows__test_
  --- FAIL: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_ (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_production (0.00s)
      --- FAIL: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_PRODUCTION (0.00s)
      --- FAIL: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses__production_ (0.00s)
      --- FAIL: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_staging (0.00s)
      --- FAIL: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_prod (0.00s)
      --- FAIL: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_Production (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_local (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_LOCAL (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows__local_ (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_test (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_TEST (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows__test_ (0.00s)
  FAIL
  FAIL	github.com/project/auth-service/internal/config	0.002s
  FAIL
  ```
- Item 3 config test, after the change (passing):
  ```text
  --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_ (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_production (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_PRODUCTION (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses__production_ (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_staging (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_prod (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/refuses_Production (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_local (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_LOCAL (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows__local_ (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_test (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows_TEST (0.00s)
      --- PASS: TestLoad_RefusesEmptyDocumentEncryptionKeyOutsideLocalTest/allows__test_ (0.00s)
  PASS
  ok  	github.com/project/auth-service/internal/config	0.002s
  ```
- `make docs-check` — no diff. Literal output:
  ```text
  go run tools/docgen/main.go -check
  APPLICATION_MAP.md is fresh.
  go test -v -count=1 ./shared/infra/docgen ./shared/infra/handlerutil ./shared/infra/jwtutil ./shared/infra/ratelimit ./shared/infra/resilience ./shared/infra/tlsutil
  ```
  `git status --short` afterwards showed only the four item-3 source files, no
  `docs/APPLICATION_MAP.md`.
- `make check` — PASS (scope and output recorded in the final verification
  section below).

## Service key checks (item 3, out-of-lane services read only)
- auth-service: **now refuses** an empty `DOCUMENT_ENCRYPTION_KEY` outside
  local/test (`config.Load` uses `isDevOnlyAppEnv`). Before this item it
  refused only an exact `APP_ENV=production`.
- chat-service: **does not refuse**. Its config has no key validation; it
  reads `ATTACHMENT_ENCRYPTION_KEY` (falling back to
  `DOCUMENT_ENCRYPTION_KEY`) and passes it to
  `storage.NewLocalStorageWithPath`. With this item the storage call now
  returns an error outside local/test for an empty/invalid/wrong-length key;
  `services/chat-service/internal/handlers/chat.go` logs a warning, retries
  with a temp dir (same error), ignores that error, and leaves `chatStorage`
  nil. The service starts, but attachments are unavailable. Follow-up issue
  suggested below.
- user-service: **does not refuse outside an exact `APP_ENV=production`**.
  `ValidateDocumentEncryptionKey` rejects the key, but `config.Load` only
  returns that error when `appEnv == "production"` (exact, case-sensitive);
  for `staging`, `prod` or `Production` it appends a warning and starts.
  Storage init then fails under this item and photo storage stays nil
  (`503 photo_storage_unavailable`). Follow-up issue suggested below.

## Deploy notes (item 3)
- I could **not** inspect the real staging or production `.env` files: they
  live on the VMs, not in this repository. So I cannot say from here whether
  any environment currently runs with an empty `DOCUMENT_ENCRYPTION_KEY` and a
  non-local `APP_ENV`.
- What the repository says: `docs/DEPLOYMENT.md` requires
  `APP_ENV=production` plus a 64-hex `DOCUMENT_ENCRYPTION_KEY` for production;
  `infrastructure/staging/.env.staging.example` sets `APP_ENV=local`. If the
  real files match those examples, item 3 does not stop either environment
  from starting. Production with `APP_ENV=production` and an empty key was
  already refused by auth-service before this item.
- Owner action before release, on each VM (`/home/deploybot/.env` for prod,
  the staging `.env` for staging):
  ```bash
  sudo awk 'index($0,"DOCUMENT_ENCRYPTION_KEY=")==1 { v=substr($0,25); gsub(/^["\x27]|["\x27]$/,"",v); print length(v), (v ~ /^[0-9A-Fa-f]+$/ ? "hex" : "NOT hex") }' /home/deploybot/.env
  sudo grep '^APP_ENV=' /home/deploybot/.env
  ```
  Expect `64 hex` and, for production, `APP_ENV=production`. If any non-local
  `APP_ENV` has an empty key, auth-service will now refuse to start (by
  design). Restore the **existing** key from the password manager; do not
  generate a new one while encrypted data exists.

## Unverified
- Everything claimed for items 1–3 was verified locally. The real staging and
  production `.env` values were not available in this repository (see deploy
  notes); the owner must check them on the VMs.

## Follow-ups / out-of-lane findings
- Suggested issue title: `chat-service: refuse to start with an empty
  ATTACHMENT_ENCRYPTION_KEY/DOCUMENT_ENCRYPTION_KEY outside local/test`.
  Suggested body: `services/chat-service/internal/config/config.go` has no
  key validation and `internal/handlers/chat.go` swallows the storage init
  error and continues with nil storage. With SEC-QUICK item 3 the storage
  layer refuses an empty/invalid/wrong-length key outside local/test, so chat
  now starts with attachments unavailable instead of failing fast. Validate
  the key in config (reuse the isDevOnlyAppEnv rule) and stop on storage init
  failure outside local/test.
- Suggested issue title: `user-service: refuse to start with an invalid
  DOCUMENT_ENCRYPTION_KEY outside local/test`.
  Suggested body: `services/user-service/internal/config/config.go` returns
  the `ValidateDocumentEncryptionKey` error only for an exact
  `APP_ENV=production`; `staging`, `prod` and `Production` only record a
  warning. Storage init then fails and photo storage stays nil. Use the
  existing `isDevOnlyAppEnv` helper so every non-local/test environment
  refuses to start with an empty, invalid or wrong-length key.

## Open questions
- none
