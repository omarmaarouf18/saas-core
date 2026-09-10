# Architecture & Tier Matrix: Broad Paid-Tier Gating

## Overview & Product Decision

In accordance with the zero-commission, subscription-only revenue model ([ADR-0017](../adr/0017-zero-commission-subscription-only-revenue-model.md)) and Product Decision Part A (#3):
- **Free-Tier Owner Accounts**: A Free-tier business owner account can register, log in, view the services catalog (read-only), inspect their own profile, and view ratings. **No functional or mutating operations are permitted on the Free tier.**
- **Paid-Tier Owner Accounts (`models.PlanPaid`)**: Full operational access across the SaaS platform (service creation and editing, driver location updates, wallet deposits and payouts, escrow dispute resolutions, job tracking/dispatching, rating submissions, and staff member management).
- **HTTP 402 Payment Required**: Any attempt by a Free-tier owner to invoke a mutating or operational endpoint returns HTTP 402 with structured body `{"error": "upgrade_required", "message": "<Feature> requires a paid subscription."}` and triggers an `UPGRADE_REQUIRED` security event audit log.
- **Frontend Mapping**: The client-side error handling layer (`frontend/lib/core/error_messages.dart`) maps HTTP 402 directly to `ErrorMessages.paymentRequired` ("A paid subscription is required to perform this action. Please upgrade to continue."), driving an immediate upgrade prompt rather than a generic fallback error.

---

## Reference Catalog Table

The following matrix documents every owner-facing endpoint, its operational role, previous access tier, updated access tier, and corresponding automated verification test.

| Endpoint | HTTP Method | Description | Previous Tier | New Tier | Rejection Code | Test Covering Gating |
|---|---|---|---|---|---|---|
| `/users/services` | `POST` | Owner creates new service catalog entry | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `paid_tier_gating_matrix_test.go` |
| `/users/services` | `PUT`, `PATCH` | Owner updates service catalog details, pricing, and coordinates | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `paid_tier_gating_matrix_test.go` |
| `/users/services/update` | `POST`, `PUT`, `PATCH` | Owner updates service catalog details, pricing, and coordinates | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `paid_tier_gating_matrix_test.go` |
| `/users/wallet/deposit` | `POST` | Owner deposits funds into e-wallet | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `paid_tier_gating_matrix_test.go` |
| `/users/wallet/payout/request` | `POST` | Owner requests payout withdrawal from withdrawable balance | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `paid_tier_gating_matrix_test.go` |
| `/users/jobs/reconciliation-resolve` | `POST` | Owner manually resolves escrow reconciliation dispute | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `paid_tier_gating_matrix_test.go` |
| `/users/jobs/location/update` | `POST` | Courier/Owner updates live driver GPS coordinates | Paid | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `handlers_test.go` |
| `/auth/employee/toggle` | `POST` | Owner activates or freezes employee account | Free | **Paid** (`models.PlanPaid`) | `402 upgrade_required` | `auth_paid_tier_gating_test.go` |

---

## Permitted Read-Only Endpoints on Free Tier

Free-tier owner accounts retain read-only access to browse the platform, inspect public state, and review their account standing:

| Endpoint | HTTP Method | Purpose | Free Tier Status | Test Covering Read Access |
|---|---|---|---|---|
| `/users/services` | `GET` | List catalog services / categories | **Allowed** (`200 OK`) | `paid_tier_gating_matrix_test.go` |
| `/users/profile` | `GET` | Retrieve owner profile details | **Allowed** (`200 OK`) | `paid_tier_gating_matrix_test.go` |
| `/users/ratings` | `GET` | View user / employee ratings | **Allowed** (`200 OK`) | `paid_tier_gating_matrix_test.go` |
| `/users/ledger` | `GET` | View transaction history | **Allowed** (`200 OK`) | `paid_tier_gating_matrix_test.go` |
| `/users/subscription` | `GET` | Inspect current tier and expiration | **Allowed** (`200 OK`) | `paid_tier_gating_matrix_test.go` |
| `/users/platform/config` | `GET` | Read platform fees and operational config | **Allowed** (`200 OK`) | `paid_tier_gating_matrix_test.go` |

---

## Inter-Service Subscription Verification

For services that do not directly manage subscriptions (such as `auth-service`), an internal endpoint is exposed by `user-service`:
- **Path**: `GET /users/subscription/internal?tenant_id=<tenant_id>`
- **Security**: Protected by `X-Internal-Token` constant-time header verification.
- **Responses**:
  - `200 OK`: Tenant holds an active `models.PlanPaid` subscription.
  - `402 Payment Required`: Tenant holds `models.PlanFree` or has expired paid subscription.
  - `401 Unauthorized`: Missing or invalid internal token.

When `auth-service` receives an owner request to toggle employee active standing (`POST /auth/employee/toggle`), it queries `/users/subscription/internal`. If a 402 status is returned, `auth-service` rejects the toggle immediately with HTTP 402 and logs an `UPGRADE_REQUIRED` security event.
