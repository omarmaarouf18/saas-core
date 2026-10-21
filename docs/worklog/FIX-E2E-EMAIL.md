# Worklog: FIX-E2E-EMAIL — contract test keeps using a revoked token

## Task and scope
- **Task ID**: `FIX-E2E-EMAIL`
- **Goal**: Fix `TestContract_AuthService` in `tests/e2e/contract_auth_test.go` where `customerToken` was used after email change confirmation despite SEC-07c revoking all previous tokens; add verification assertion that the old token gets 401 and the new token gets 200 on `GET /auth/user`; add `logic-exploitation` to `.github/workflows/release-gate-e2e.yml` push triggers.
- **Lane**:
  - `tests/e2e/contract_auth_test.go`
  - `.github/workflows/release-gate-e2e.yml`
  - `docs/worklog/FIX-E2E-EMAIL.md` (committed last, alone)
- **Branch**: `agent/FIX-E2E-EMAIL-contract-token-after-email-change`, branched from `logic-exploitation` @ `28326739`.
- **Parallel Tasks**: `FE-CUST-2` (`frontend/**`), `FIX-COD-RECON` (`services/user-service/**` + new e2e test), `FE-LINUX-BUILD` (`frontend/linux/**`) — all untouched.

## Status per item
1. **Contract Test Token Refresh & Revocation Assertion** — Done (committed in `a804d667`).
   - Parsed fresh token from confirm response (`json:"token"` from `ConfirmEmailChange` in `services/auth-service/internal/handlers/auth.go:3752`).
   - Updated `customerToken` in `TestContract_AuthService` scope so all subsequent subtests (`GET_Auth_Employees`, `GET_Auth_Audit_Log`, `POST_Auth_KYB_Upload`, `POST_Auth_KYE_Upload`) receive the valid fresh token.
   - Added explicit assertion: `GET /api/v1/auth/user` with `oldCustomerToken` returns 401 Unauthorized (documenting SEC-07c revocation behavior), while `GET /api/v1/auth/user` with `customerToken` returns 200 OK.
   - Grepped `tests/e2e/` for other occurrences: no other tests reuse a customer token after email change, password reset, or freeze (`logout` tests intentionally use distinct per-test tokens, and `suspend`/`reactivate` tests operate via reviewer token).
2. **Workflow Push Trigger Update** — Done (committed in `4f35df5c`).
   - Updated `.github/workflows/release-gate-e2e.yml` to trigger on push to both `[ main, logic-exploitation ]` in addition to `workflow_dispatch`.
   - **Recommendation on Required Checks**: The owner should consider adding `e2e-release-gate` as a required status check on `logic-exploitation` branch protection ruleset if staging runtime (~1–2 minutes) is acceptable for PR merges. If fast PR feedback is preferred, leaving it as a push gate on `logic-exploitation` ensures any integration breakage is caught immediately post-merge before reaching `main`.
3. **Worklog** — Done (committed in this step, alone).

## Verification Results

### 1. Reproduction of Original Failure (Prior to Fix)
```text
=== RUN   TestContract_AuthService/GET_Auth_Employees
    contract_auth_test.go:846: Expected 403 Forbidden for customer, got 401
=== RUN   TestContract_AuthService/GET_Auth_Audit_Log
    contract_auth_test.go:962: Expected 403 for non-owner audit read, got 401
=== RUN   TestContract_AuthService/POST_Auth_KYB_Upload
    contract_auth_test.go:995: Expected 403 for customer KYB upload, got 401
=== RUN   TestContract_AuthService/POST_Auth_KYE_Upload
    contract_auth_test.go:1027: Expected 403 for customer KYE upload, got 401
--- FAIL: TestContract_AuthService (2.05s)
```

### 2. Full Staging Release Gate E2E Run (Post Fix)
Staging stack provisioned via `bash scripts/staging_up.sh` and full E2E test suite executed with `go test -v -count=1 ./tests/e2e/...`:
```text
--- PASS: TestContract_AuthService (1.28s)
    --- PASS: TestContract_AuthService/POST_Auth_Signup (0.19s)
    --- PASS: TestContract_AuthService/POST_Auth_Resend_OTP (0.15s)
    --- PASS: TestContract_AuthService/POST_Auth_Verify_OTP (0.01s)
    --- PASS: TestContract_AuthService/POST_Auth_Login (0.23s)
    --- PASS: TestContract_AuthService/POST_Auth_Refresh (0.00s)
    --- PASS: TestContract_AuthService/POST_Auth_Forgot_Password (0.14s)
    --- PASS: TestContract_AuthService/POST_Auth_Reset_Password (0.06s)
    --- PASS: TestContract_AuthService/POST_Auth_Logout (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_User (0.00s)
    --- PASS: TestContract_AuthService/PATCH_Auth_User (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_User_Public_Profile (0.00s)
    --- PASS: TestContract_AuthService/DELETE_Auth_Device_Token (0.00s)
    --- PASS: TestContract_AuthService/POST_Auth_Email_Change_Request (0.14s)
    --- PASS: TestContract_AuthService/POST_Auth_Email_Change_Confirm (0.19s)
    --- PASS: TestContract_AuthService/GET_Auth_Employees (0.00s)
    --- PASS: TestContract_AuthService/POST_Auth_Employee_Toggle (0.11s)
    --- PASS: TestContract_AuthService/POST_Auth_Employee_Action (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_Audit_Log (0.00s)
    --- PASS: TestContract_AuthService/POST_Auth_KYB_Upload (0.01s)
    --- PASS: TestContract_AuthService/POST_Auth_KYE_Upload (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_Reviewer_Verify (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_KYB_KYE_Pending (0.00s)
    --- PASS: TestContract_AuthService/POST_Auth_KYB_KYE_Review (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_Documents_View (0.00s)
    --- PASS: TestContract_AuthService/GET_Auth_Accounts (0.00s)
    --- PASS: TestContract_AuthService/POST_Auth_Accounts_Suspend (0.01s)
    --- PASS: TestContract_AuthService/POST_Auth_Accounts_Reactivate (0.01s)
PASS
ok  	github.com/project/tests/e2e	8.860s
```
Staging stack torn down and isolated volumes cleared via `bash scripts/staging_down.sh`.

## Git Verification

### `git log --oneline logic-exploitation..HEAD`
```text
4f35df5c FIX-E2E-EMAIL: add logic-exploitation to release-gate-e2e push branches
a804d667 FIX-E2E-EMAIL: update customer token after email change confirm in contract test
```

### `git diff --stat logic-exploitation..HEAD`
```text
 .github/workflows/release-gate-e2e.yml |  2 +-
 tests/e2e/contract_auth_test.go        | 30 ++++++++++++++++++++++++++++++
 2 files changed, 31 insertions(+), 1 deletion(-)
```
