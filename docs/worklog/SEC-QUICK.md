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
- `make check` — PASS (scope and output recorded in the final verification
  section below).

## Unverified
- Everything claimed for item 1 was verified locally. Final report below.

## Follow-ups / out-of-lane findings
- none yet

## Open questions
- none
