# ADR-0001: Owner-Authenticated Employee Provisioning

- **Status**: Accepted
- **Date**: 2026-07-13
- **Related Commit SHA**: ``current``
- **Related audit finding**: Unauthenticated employee account creation / tenant privilege escalation

## Context
When registering an employee account via `POST /auth/signup` (with `role=employee`), the signup handler only verified that the supplied `owner_id` belonged to an existing user with `role=owner`. It did not verify that the caller was that owner or acting on that owner's behalf. No Authorization header or internal-service token was required on this route.
This allowed anyone who knew or could guess a valid `owner_id` to register a fully active and confirmed employee account bound to that owner's tenant, bypassing OTP/2FA checks (employees bypass 2FA at login per existing design). This rogue employee identity could then pass downstream authorization checks trustingly (e.g. `resolvedRequester == job.EmployeeID`).

## Decision
We decided to require proof that the caller is the owner identified by `owner_id` during employee signup.
Specifically:
1. When `role=employee`, the caller must supply a valid signed JSON Web Token (JWT) in the `Authorization` header.
2. The JWT token is validated using the existing `shared/infra/jwtutil` validator.
3. We verify that the token's subject/user ID (`claims.UserID`) matches the requested `req.OwnerID`.
4. We verify that the token's role (`claims.Role`) is `owner`.
5. We reject any unauthorized attempts with a `401 Unauthorized` or `403 Forbidden` response.
6. We preserve the existing public, OTP-gated signups for `owner` and `user` roles (which remain unauthenticated at the signup stage).
7. We ship a security audit event `UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED` via `handlerutil.ShipSecurityEvent` for all failed authorization attempts.
8. We protect the signup endpoint from abuse/brute force by applying Redis-backed rate limiting lockouts (using `a.limiter`) on the client IP for employee provisioning attempts.

Reusing the existing cryptographically signed JWT infrastructure (`jwtutil.ValidateToken`) is chosen to avoid inventing a new authentication or verification mechanism.

## Consequences
- **UX Impact**: The tenant owner's client must now send its valid JWT token when provisioning new employees.
- **Client Changes**: Updated `index.html` to automatically save the JWT token returned on login/verification and pass it in the `Authorization` header for subsequent requests. The Flutter frontend already manages and attaches the token via the `ApiClient`.
- **Security Posture**: Closes the unauthenticated privilege escalation vulnerability. Attackers can no longer provision employee accounts under a tenant owner without a valid, signed JWT for that owner.

## Alternatives Considered
- **Inventing a separate OTP/onboarding token flow**: A temporary, signed link or onboarding token could have been generated for employee invitations. This was rejected for the initial phase as it adds unnecessary complexity (storing invitation state, generating/mailing tokens) compared to direct, owner-authenticated provisioning.
- **Using internal service token**: An internal token (mTLS or service-to-service) was considered but rejected because employee creation is initiated by the owner directly from the client application rather than background internal processes.
