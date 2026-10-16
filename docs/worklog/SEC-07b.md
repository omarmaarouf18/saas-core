# Worklog: SEC-07b — token revocation failures must fail closed

## Task and scope
- Task ID: SEC-07b
- Item IDs covered: 1 (password reset), 2 (account suspension incl. owner cascade), 3 (tests)
- Allowed paths (lane from the task prompt): `services/auth-service/**`, `docs/worklog/SEC-07b.md`; `shared/infra/jwtutil` read-only
- Agent branch: agent/SEC-07b-revoke-fail-closed, created from logic-exploitation (79117981)

## RevokeAllUserTokens callers (`grep -rn RevokeAllUserTokens services shared`, non-test)

| Location (base) | Handler / action | State changed | Behaviour on revoke failure (before) | After SEC-07b |
|---|---|---|---|---|
| `auth.go:906` | `ToggleEmployee` freeze (`POST /auth/employee/toggle`, `set_active=false`) | employee `is_active=false` | already fail closed by SEC-07: revoke first, 500 `internal_error`, not persisted | unchanged |
| `auth.go:2428` | `SuspendAccount` (`POST /auth/accounts/{id}/suspend`, reviewer-only) | `account_status=suspended`, `is_active=false`, reason, `suspended_at` (CAS) | suspension persisted first, error discarded (`_ =`) → suspended-but-unrevoked | revoke first; 503 `service_unavailable` + `ACCOUNT_SUSPEND_REVOKE_FAILED`; nothing persisted |
| `auth.go:2435` | same, F-04 owner cascade over `GetEmployeesByOwner` | (none of its own; part of the owner suspension) | each employee error discarded (`_ =`) | any failure aborts the whole suspension (owner included) |
| `auth.go:3156` | `ResetPassword` phase 2 (`POST /auth/reset-password`) | `password`, clears OTP + `reset_token_*` fields | password changed first, failure only logged `[SECURITY WARNING]` → new password with old sessions alive | revoke first; 503 `service_unavailable` + `PASSWORD_RESET_REVOKE_FAILED`; password and reset token unchanged |

`shared/infra/jwtutil/jwt.go:291` is the definition; all other hits are tests/comments.

## Decisions taken
- Password reset: option (a), revoke first. On failure: 503 `service_unavailable` via `handlerutil.WriteSafeError`, security event, password NOT changed and reset token NOT consumed (holder retries). Reason, as SEC-07: option (b)'s rollback can itself fail and leave exactly the state being prevented. If revoke succeeds but `UpdateUser` fails, the user is only logged out with the old password intact.
- Suspension: revoke first (target, then every employee if the target is an owner), then the CAS `SuspendUser`. Any single failure aborts everything with 503; revocations that already landed stay (those users are only logged out). A partially revoked tenant is never reported as suspended.
- Status/code: 503 + `ErrCodeUnavailable` per the task prompt. Note this differs from SEC-07's ToggleEmployee (500 `internal_error`); I left ToggleEmployee unchanged.
- Already-suspended target with Redis down now gets 503 instead of 409 (revocation runs before the CAS). Revoking an already-suspended account is harmless.
- Security event seam: added `var shipSecurityEvent = handlerutil.ShipSecurityEvent` in `auth.go` (handlerutil's stdout writer is unexported, and `shared/infra` is out of lane). Only the two new events use it; existing calls are untouched.
- Failure injection: a go-redis `ProcessHook` on a test-owned miniredis client fails only the `SET jwt:invalidated_before:<id>` for selected IDs, so the owner-succeeds/employee-fails partial case is exact. No jwtutil change needed.

## Changes per commit (message only — NO SHAs)
1. `SEC-07b: password reset revokes sessions first and fails closed`
2. `SEC-07b: account suspension revokes sessions first and fails closed`
3. `SEC-07b: tests for fail-closed revocation on reset and suspension`
4. `SEC-07b: worklog` (this file)

## Verification
- `make ci` before commits 1, 2, 3: each ended `== pre-push gate: all checks passed ==` (exit 0).
- `gofmt -l .` and `go vet ./...` in `services/auth-service`: empty / clean.
- New tests (`go test ./internal/handlers/ -run 'TestResetPassword_RevokeFailure_FailsClosed|TestSuspendAccount_' -count=1 -v`): all 4 PASS on the branch.
- Regression proof: same command against the base `auth.go` plus only the `shipSecurityEvent` var (needed to compile):

  | Test | Fails on base? |
  |---|---|
  | `TestResetPassword_RevokeFailure_FailsClosed` | yes (`expected 503, got 200`) |
  | `TestSuspendAccount_RevokeFailure_FailsClosed` | yes (`expected 503, got 200`) |
  | `TestSuspendAccount_OwnerCascadePartialFailure_AbortsAll` | yes (`expected 503, got 200`) |
  | `TestSuspendAccount_RevokesSessions` (happy path) | no (passes on base: base already revoked on success; it guards the new ordering against regressions) |

- Happy path for reset: existing `TestResetPassword_SessionInvalidation` still passes; the new reset failure test also asserts the old token is rejected after a successful retry.

## Unverified
- Behaviour against a real Redis outage (tests inject failure with a hook on miniredis, not by stopping Redis).
- Other services' reaction to suspension (`account:events` pubsub) was not exercised.

## Follow-ups / out-of-lane findings
- Revoke-first race (applies to SEC-07 ToggleEmployee too): a token minted between the revoke and the persist, in a later wall-clock second, survives (e.g. a login with the old password during a reset, or a login just before the suspension lands). The window is milliseconds and the `<=` same-second rule covers most of it. Possible fix: a second best-effort revoke after the persist. Not done here to stay consistent with SEC-07; owner to decide.
- `store.GetEmployeesByOwner` swallows Mongo errors and returns nil, so on a DB error an owner suspension would skip the employee cascade silently. Changing its signature is out of this task's scope; worth a small follow-up.
- ToggleEmployee uses 500 `internal_error` for the same failure; consider aligning on 503 `service_unavailable`.

## Open questions
- Product decision flagged by the task: should an admin suspension still go through when Redis is down? Implemented as the prompt prescribes (abort with 503, nothing persisted). Trade-off: until the admin retries, the account stays active (but while Redis is unreachable, `ValidateToken` already rejects every token). The alternative (persist and warn) blocks new logins at once but leaves old tokens valid after Redis recovers, with no signal. Please confirm.
