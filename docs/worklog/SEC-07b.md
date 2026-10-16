# Worklog: SEC-07b — token revocation failures must fail closed

## Task and scope
- Task ID: SEC-07b
- Item IDs covered: 1 (password reset), 2 (account suspension incl. owner cascade), 3 (tests)
- Allowed paths (lane from the task prompt): `services/auth-service/**`, `docs/worklog/SEC-07b.md`; `shared/infra/jwtutil` read-only
- Agent branch: agent/SEC-07b-revoke-fail-closed, created from logic-exploitation (79117981)

## RevokeAllUserTokens callers (`grep -rn RevokeAllUserTokens services shared`, non-test)

| Location (base) | Handler / action | State changed | Behaviour on revoke failure (before) | After SEC-07b |
|---|---|---|---|---|
| `auth.go:906` | `ToggleEmployee` freeze (`POST /auth/employee/toggle`, `set_active=false`) | employee `is_active=false` | already fail closed by SEC-07: revoke first, 500 `internal_error`, not persisted | now 503 `service_unavailable`; best-effort re-revoke after the save |
| `auth.go:2428` | `SuspendAccount` (`POST /auth/accounts/{id}/suspend`, reviewer-only) | `account_status=suspended`, `is_active=false`, reason, `suspended_at` (CAS) | suspension persisted first, error discarded (`_ =`) → suspended-but-unrevoked | revoke first; 503 `service_unavailable` + `ACCOUNT_SUSPEND_REVOKE_FAILED`; nothing persisted; best-effort re-revoke after the save |
| `auth.go:2435` | same, F-04 owner cascade over `GetEmployeesByOwner` | (none of its own; part of the owner suspension) | each employee error discarded (`_ =`); a Mongo lookup error silently meant "no employees" | any revocation failure or employee lookup error aborts the whole suspension (owner included) |
| `auth.go:3156` | `ResetPassword` phase 2 (`POST /auth/reset-password`) | `password`, clears OTP + `reset_token_*` fields | password changed first, failure only logged `[SECURITY WARNING]` → new password with old sessions alive | revoke first; 503 `service_unavailable` + `PASSWORD_RESET_REVOKE_FAILED`; password and reset token unchanged; best-effort re-revoke after the save |

`shared/infra/jwtutil/jwt.go:291` is the definition; all other hits are tests/comments.

## Decisions taken
- Password reset: option (a), revoke first. On failure: 503 `service_unavailable` via `handlerutil.WriteSafeError`, security event, password NOT changed and reset token NOT consumed (holder retries). Reason, as SEC-07: option (b)'s rollback can itself fail and leave exactly the state being prevented. If revoke succeeds but `UpdateUser` fails, the user is only logged out with the old password intact.
- Suspension: revoke first (target, then every employee if the target is an owner), then the CAS `SuspendUser`. Any single failure aborts everything with 503; revocations that already landed stay (those users are only logged out). A partially revoked tenant is never reported as suspended.
- **Owner decision (round 2): keep the 503 when revocation fails during a suspension; do not save the suspension.** Rationale from the owner: while Redis is down every token is already rejected by `ValidateToken`; saving the suspension without revoking would silently re-enable the old tokens once Redis returns.
- Already-suspended target with Redis down gets 503 instead of 409 (revocation runs before the CAS). Revoking an already-suspended account is harmless.
- `store.GetEmployeesByOwner` now returns `([]*models.User, error)`.
  - `SuspendAccount`: a lookup error fails closed: 503 `service_unavailable`, `ACCOUNT_SUSPEND_REVOKE_FAILED`, nothing saved. Reading the error as "no employees" would leave every employee session alive under a suspended owner.
  - `GetEmployees` (`GET /auth/employees`, the owner's read-only staff list): **fail closed**, 500 `internal_error`. It changes no state, so failing open cannot leak anything, but the old behaviour (200 with `[]`) told the owner "you have no employees", which is false and hides the staff they may need to freeze. An error lets the client show "could not load, retry". 500 rather than 503 because that matches the handler's other store-error paths.
- Revoke-then-save gap: after the state is saved, all three paths (freeze, reset, suspension incl. every cascaded employee) call `RevokeAllUserTokens` a second time through `reRevokeAfterPersist`. It is best effort: on failure it emits `EMPLOYEE_FREEZE_REREVOKE_FAILED` / `PASSWORD_RESET_REREVOKE_FAILED` / `ACCOUNT_SUSPEND_REREVOKE_FAILED` but the request still succeeds (state saved, first revocation landed). There is no separate `log.Printf` (gosec G706 flags request-derived IDs in log lines; `RevokeAllUserTokens` already logs the Redis error).
  - Side effect: each successful revocation also publishes `ACCOUNT_SUSPENDED` on `account:events` (jwtutil behaviour), so subscribers now see it twice per action. I assumed subscribers are idempotent (they disconnect a user's connections); not verified.
  - Accepted trade-off: the second revocation also rejects a token minted in the same second as it, e.g. a login with the new password immediately after a reset; the user just logs in again (same `<=` rule as SEC-07).
- Status/code: 503 + `ErrCodeUnavailable` on every revoke-failure path, now including ToggleEmployee (was 500 `internal_error`).
- Security event seam: `var shipSecurityEvent = handlerutil.ShipSecurityEvent` in `auth.go` (handlerutil's stdout writer is unexported, and `shared/infra` is out of lane). Only the new SEC-07b events use it; existing calls are untouched.
- Failure injection: go-redis `ProcessHook`s on a test-owned miniredis client. `revokeFailHook` fails `SET jwt:invalidated_before:<id>` for selected IDs; `revokeCountHook` counts those SETs for one user, can fail the Nth one, and runs a callback right after the first, which is how a token is minted between the two revocations. Employee lookup failure is staged with a real undecodable employee document (`is_active: "corrupt"`), not a mock. No jwtutil change needed.

## Changes per commit (message only — NO SHAs)
1. `SEC-07b: password reset revokes sessions first and fails closed`
2. `SEC-07b: account suspension revokes sessions first and fails closed`
3. `SEC-07b: tests for fail-closed revocation on reset and suspension`
4. `SEC-07b: worklog`
5. `SEC-07b: GetEmployeesByOwner returns lookup errors; callers fail closed`
6. `SEC-07b: re-revoke sessions after saving freeze, reset and suspension`: **committed with a failing `make ci`** (gosec G706 on a new `log.Printf`). My command chain did not stop on the gate's exit code. Not amended (task rule); fixed by commit 7. The owner may want to squash 6+7 at merge.
7. `SEC-07b: drop log line in re-revocation helper flagged by gosec G706`
8. `SEC-07b: ToggleEmployee revoke failure returns 503 service_unavailable`
9. `SEC-07b: worklog: round 2 decisions and verification` (this update)

## Verification
- `make ci` before commits 1, 2, 3, 4, 5, 7, 8, 9: each ended `== pre-push gate: all checks passed ==` (exit 0). Before commit 6 it FAILED (`BLOCKED: services/auth-service failed gosec security scan`, G706 at `auth.go:59`); see above.
- `gofmt -l .` and `go vet ./...` in `services/auth-service`: empty / clean.
- Regression proof. Each new test was run against the code before the matching fix (the previous commit's `auth.go`/`mongodb.go`; for round 1, the base `auth.go` plus only the `shipSecurityEvent` var so it compiles):

  | Test | Fails before the fix? |
  |---|---|
  | `TestResetPassword_RevokeFailure_FailsClosed` | yes (`expected 503, got 200`) |
  | `TestSuspendAccount_RevokeFailure_FailsClosed` | yes (`expected 503, got 200`) |
  | `TestSuspendAccount_OwnerCascadePartialFailure_AbortsAll` | yes (`expected 503, got 200`) |
  | `TestSuspendAccount_RevokesSessions` (happy path) | no (base already revoked on success; guards the new ordering) |
  | `TestSuspendAccount_EmployeeLookupFailure_FailsClosed` | yes (`expected 503, got 200`) |
  | `TestGetEmployees_LookupFailure_ReturnsError` | yes (`expected 500, got 200. Body: []`) |
  | `TestMongoDB_GetEmployeesByOwner_ReturnsErrors` | n/a (needs the new signature to compile) |
  | `TestRevokeFirst_TokenMintedBeforeSave_IsRejected` (freeze / reset / suspend-owner) | yes, all 3 (`expected token minted between revoke and save to be rejected, got: <nil>`) |
  | `TestRevokeFirst_ReRevokeFailure_IsBestEffort` (freeze / reset / suspend-owner) | yes, all 3 (no `*_REREVOKE_FAILED` event) |
  | `TestToggleEmployee_FreezeRevokeFailure_FailsClosed` (updated) | n/a (expectation changed from 500 to 503) |

- The token race is staged for real, not assumed: the hook waits past the wall-clock second of the first revocation, then mints the token, so its `iat` is strictly after the first revocation timestamp. Before the fix it validated (`got: <nil>`); after the fix it is rejected.
- Happy path for reset: existing `TestResetPassword_SessionInvalidation` still passes; the reset failure test also asserts the old token is rejected after a successful retry.

## Unverified
- Behaviour against a real Redis outage (tests inject failure with hooks on miniredis, not by stopping Redis).
- Other services' reaction to suspension and to the doubled `account:events` publish was not exercised.
- `TestMongoDB_GetEmployeesByOwner_ReturnsErrors` and `TestMongoDB_EmployeesAndAudit` SKIP under a plain `go test` with the default `MONGO_URI` (`setupTestStore` has no credential fallback, unlike `setupTestAuth`). I ran them with `MONGO_URI='mongodb://root:devpassword123@localhost:27017/?authSource=admin'`: both PASS. `make ci` runs the pre-push gate, which exports a credentialed `MONGO_URI` (`.githooks/pre-push:98`), so they should run there too; its log prints no per-test lines, so that is inferred, not observed.
- The frontend's handling of 503 (instead of 500) from the employee toggle was not checked (out of lane).

## Follow-ups / out-of-lane findings
- `setupTestStore` in `internal/store/mongodb_test.go` skips without credentials, while `setupTestAuth` falls back to the local dev URI. Aligning them would stop store tests silently skipping under a plain local `go test` (the gate itself sets `MONGO_URI`).

## Open questions
- none (the suspension-with-Redis-down question is answered above)
