# ADR-0022: Reviewer Account Directory, Search, and Account Suspension / Reactivation

- **Status**: Accepted
- **Date**: 2026-09-01
- **Related ADRs**: [ADR-0013](0013-support-agent-console-as-separate-client-application.md) (Support Agent Console as a Separate Client Application), [ADR-0021](0021-kyc-kyb-kye-reviewer-console.md) (Standalone KYC/KYB/KYE Reviewer Console)
- **Deployment Gate**: **Hold merge to `main` / production until explicit product-owner confirmation** (affects live user access control).

## Context

[ADR-0021](0021-kyc-kyb-kye-reviewer-console.md) delivered the standalone KYC/KYB/KYE reviewer console (`omarmaarouf18/kyc-reviewer-console`), providing an internal-network tool for identity verification during user onboarding. However, verification was designed as a one-way gate: once approved, an account had no ongoing operational management capabilities within the reviewer console.

In practice, operational teams need ongoing account governance:
1. **Account Directory & Search**: Reviewers must be able to list and find any registered account by username, email, or user ID, inspecting their verification standing and current account status across all roles (`owner`, `employee`, `user`).
2. **Post-Onboarding Suspension**: If an account violates platform policies, commits fraud, or presents safety risks, reviewers must be able to deactivate/suspend the account immediately through the console rather than requiring manual database queries by backend engineers.
3. **Reactivation**: If an account suspension is resolved or appealed successfully, reviewers need a first-class console action to restore the account to active standing.
4. **Separation of Verification vs. Ongoing Standing**: KYC/KYB/KYE verification (`KYCStatus`) represents the outcome of document identity verification, whereas account status (`AccountStatus`) represents operational standing. A suspended account must retain its KYC verification record (not conflate "never verified" with "was verified, now suspended").

## Decision

### 1. Data Model (`auth-service`)

Extend `models.User` with explicit account status tracking:

```go
type AccountStatus string

const (
	AccountStatusActive    AccountStatus = "active"
	AccountStatusSuspended AccountStatus = "suspended"
)

type User struct {
	// ... existing fields ...
	AccountStatus    AccountStatus `json:"account_status" bson:"account_status,omitempty"`
	SuspensionReason string        `json:"suspension_reason,omitempty" bson:"suspension_reason,omitempty"`
	SuspendedAt      time.Time     `json:"suspended_at,omitempty" bson:"suspended_at,omitempty"`
	ReactivatedAt    time.Time     `json:"reactivated_at,omitempty" bson:"reactivated_at,omitempty"`
}
```

- **Backward Compatibility & Synchronization**: `IsActive bool` is retained and synchronized with `AccountStatus` (`AccountStatusActive <=> IsActive == true`, `AccountStatusSuspended <=> IsActive == false`). A helper `user.EffectiveAccountStatus()` gracefully treats historical unmigrated documents with `AccountStatus == ""` as active if `IsActive == true` or suspended if `IsActive == false`.
- **Identity Isolation**: KYC documents, verification statuses (`KYCStatus`, `KYEStatus`), and reviewer audit histories are preserved intact when an account is suspended.

### 2. Access Enforcement & Token Revocation

When an account transitions to `suspended`:
1. **Login Prevention**: `POST /auth/login` and `POST /auth/verify-otp` fail-closed with `403 Forbidden` (`{"error": "account is suspended"}`) for all roles (`owner`, `employee`, `user`) if `user.EffectiveAccountStatus() == models.AccountStatusSuspended` or `!user.IsActive`.
2. **Session Invalidation**: Suspension immediately calls `jwtutil.RevokeAllUserTokens(userID)` which records `jwt:invalidated_before:<user_id>` in Redis with an 8-day TTL (24h token life + 7d refresh window). All existing issued JWTs for that user are immediately rejected by `jwtutil.ValidateToken` across all services (`api-gateway`, `user-service`, `chat-service`, `notification-service`).
3. **Token Refresh Blocking**: `POST /auth/refresh` checks `user.EffectiveAccountStatus()` and returns `403 Forbidden`.
4. **Employee Assignment Blocking**: `POST /auth/employee/verify` fails if either the employee account or the employee's owner account is suspended.

### 3. Reviewer-Facing Endpoints (`auth-service`)

Protected by the established `authenticateReviewer` pattern (requiring both `X-Internal-Token` and `X-Reviewer-Token`):

| Endpoint | Method | Purpose |
|---|---|---|
| `/auth/accounts` | `GET` | Paginated search & list accounts (query params: `search`, `role`, `status`, `page`, `limit`) |
| `/auth/accounts/{id}/suspend` | `POST` | Suspend account with mandatory `reason` (1-1000 chars) |
| `/auth/accounts/suspend` | `POST` | Body-addressed variant (`user_id` + `reason`) |
| `/auth/accounts/{id}/reactivate` | `POST` | Reactivate suspended account with optional `reason` |
| `/auth/accounts/reactivate` | `POST` | Body-addressed variant (`user_id` + optional `reason`) |

- **Atomic CAS Updates**:
  - `SuspendUser`: `UpdateOne` where `_id == userID` and `account_status != "suspended"` (or `is_active == true`). Returns `409 Conflict` if the account is already suspended.
  - `ReactivateUser`: `UpdateOne` where `_id == userID` and `account_status == "suspended"` (or `is_active == false`). Returns `409 Conflict` if the account is already active.
- **Audit Logging & Security Events**:
  - Writes to `audit_log` collection with `Action: "ACCOUNT_SUSPENDED"` or `"ACCOUNT_REACTIVATED"`, `EmployeeID: reviewer.ID`, `TenantID: targetUser.ID`.
  - Dispatches `handlerutil.ShipSecurityEvent` with client IP and sanitized reason.
- **Fire-and-Forget Notification Dispatch**:
  - Dispatches `POST /notifications/send` via `notification-service` (`type: "account_suspended"` / `"account_reactivated"`, target `user_id` and `tenant_id`) informing the user of the action and explanation. Dispatch failure is logged under `[ACCOUNT-NOTIFY]` and does not roll back the database transaction.

### 4. Reviewer Console Architecture (`kyc-reviewer-console`)

The console UI and proxy are updated to support the new capability:
- **Proxy Layer (`internal/proxy/proxy.go`)**:
  - `Accounts`: proxies `GET /auth/accounts` preserving query parameters (`search`, `role`, `status`, `page`, `limit`).
  - `SuspendAccount`: validates payload shape locally (`user_id` required, `reason` required and trimmed <= 1000 chars), proxies `POST /auth/accounts/suspend`.
  - `ReactivateAccount`: validates payload shape locally (`user_id` required), proxies `POST /auth/accounts/reactivate`.
- **Web UI (`web/index.html`, `web/app.js`, `web/style.css`)**:
  - Tabbed interface switching between **Pending Queue** and **Accounts Directory**.
  - Accounts Directory table with search bar (search on Enter or Search button), role/status filters, pagination controls, status badges (`Active` / `Suspended`), and contextual Action buttons (Suspend / Reactivate).
  - Modal dialog for Suspend enforcing mandatory reason input.
  - Modal dialog for Reactivate with optional reason.

## Consequences

### Positive
- Reviewers gain end-to-end account management without direct database access.
- Suspensions take effect instantaneously across all microservices via Redis JWT invalidation.
- Full auditability: every suspension and reactivation records reviewer ID, timestamp, IP, and reason.
- Clean separation between identity verification state (`KYCStatus`) and account standing (`AccountStatus`).

### Negative / Tradeoffs
- Additional reviewer endpoints to maintain and test.
- User lockout is high-impact; UI and API enforce mandatory reasons and confirmation dialogs to prevent accidental deactivations.

## Alternatives Considered

- **Conflating `KYCStatus = "rejected"` with Suspension**: Rejected. Overwriting `KYCStatus` destroys the audit trail of approved verification documents and forces the user to re-upload documents upon reactivation.
- **Direct Database Mutation by Operators**: Rejected. Unaudited, error-prone, leaves outstanding JWT sessions active, and bypasses user notifications.
