# ADR-0013: Support Agent Console as a Separate Client Application

- **Status**: Proposed (Forward-Looking Scope Boundary)
- **Date**: 2026-08-03
- **Related Commit SHA**: 856bba37c92dc605e53559c4d6465848c2bff1a8
- **Related Audit / Scope Finding**: Scope Boundary & Agent Authentication Isolation for `POST /chat/tickets/resolve`

## Context

The `chat-service` Go microservice (`services/chat-service/internal/handlers/chat.go`) exposes support ticket handling endpoints. While ticket creation (`POST /chat/tickets`) uses standard user JWT authentication (`Authorization: Bearer <user_token>`), administrative resolution endpoints such as `POST /chat/tickets/resolve` enforce agent token authentication via `GetAgentByToken` (`token` query parameter or `Bearer <agent_token>` header).

During the 11-endpoint frontend integration effort in `frontend/`, we evaluated whether `POST /chat/tickets/resolve` and agent token management should be wired into the consumer mobile app (`frontend/`).

### Key Architectural Factors
1. **Security & Role Boundary**: End-user customers and driver employees use the consumer mobile app (`quick-delivery-mobile`). Support agents are administrative staff who operate with elevated privileges to view and resolve customer dispute tickets across all tenants.
2. **Authentication Mechanism Mismatch**: Consumer app workflows exclusively rely on JWT tokens issued to users, employees, and tenant owners upon login. Agent resolution endpoints rely on `agent` record tokens stored in `chat-service`'s MongoDB `agents` collection.
3. **Multi-Frontend Ecosystem Precedent**: Per [ADR-0010](0010-separate-repos-for-deployment-artifacts.md), the Quick Delivery SaaS platform serves multiple decoupled client applications (`quick-delivery-mobile`, `logiclinc`) from a single unified Go microservices backend (`saas-core`).

## Decision

We formally decide that agent-authenticated ticket resolution endpoints (such as `POST /chat/tickets/resolve`) are **intentionally OUT OF SCOPE** for the Flutter consumer mobile app (`frontend/`).

1. **Consumer Mobile Scope Floor**: The consumer mobile app (`frontend/` / `quick-delivery-mobile`) will ONLY integrate user-facing ticket creation (`POST /chat/tickets`) and ticket status viewing using standard user JWT authentication.
2. **Support Agent Console**: A future, separate client application—provisionally designated `omarmaarouf18/support-agent-console`—will be built to consume agent-token-authenticated endpoints (`POST /chat/tickets/resolve`, agent status toggles, and cross-tenant ticket management queues).
3. **No Code or Repo Invention Yet**: As of this ADR, no Support Agent Console repository or codebase exists. This ADR establishes an architectural scope boundary to prevent embedding agent resolution logic or agent secret token handling into the consumer mobile app.

## Consequences

### Positive
- **Strict Least-Privilege Isolation**: Prevents embedding support agent resolution logic, agent API tokens, or administrative controls into the consumer mobile application binary.
- **Clean API Scope Floor**: Clarifies that only user-facing endpoints (e.g. `POST /chat/tickets`) belong in the consumer app integration effort, excluding `POST /chat/tickets/resolve`.
- **Alignment with Multi-Repo Strategy**: Preserves the multi-frontend architecture defined in ADR-0010.

### Negative / Tradeoffs
- **Deferred Support Resolution UI**: Ticket resolution cannot be performed directly within the consumer app and will require support agents to use backend administrative scripts, HTTP clients, or the future Support Agent Console.

## Alternatives Considered
- **Embedding Support Agent Mode into Consumer Mobile App**: Rejected due to security risks associated with bundling administrative agent capabilities and agent token authentication flows in end-user binaries.

---

## Addendum: Enforcement & KYB/KYE Reviewer UI Cleanup (2026-08-13)

- **Date**: 2026-08-13
- **Action**: Enforced ADR-0013 scope boundary by completely removing all KYB/KYE administrative reviewer UI (`kyb_kye_review_screen.dart`), document viewer dialogs (`document_viewer_dialog.dart`), AppBar actions (`reviewer_queue_button`), dead provider methods (`fetchPendingSubmissions`, `fetchDocumentBytes`, `reviewSubmission`), and reviewer widget tests from the consumer Flutter app (`frontend/`).
- **Rationale**: Bundling reviewer/admin review screens and administrative API endpoints (`POST /auth/kyb-kye/review`, `GET /auth/kyb-kye/pending`, `GET /auth/documents/view`) inside the public consumer binary leaks administrative review workflows, endpoint structures, and approval/rejection logic via reverse engineering / APK decompilation.
- **Scope Floor Enforced**: All administrative review tools are strictly reserved for separate administrative client applications per ADR-0013 and ADR-0010.

---

## Addendum: Reaffirmation of Boundary & Re-Reversion of Mistaken Restoration (2026-08-16)

- **Date**: 2026-08-16
- **Action**: Re-reverted commit `ab9073ab497d26a30b67c4bcf53ae045eec5cab0` which had mistakenly reintroduced `KybKyeReviewScreen`, `DocumentViewerDialog`, provider review methods, and `home_screen.dart` reviewer buttons back into the consumer app based on an incorrect premise that the 2026-08-13 removal was in error. Removed all reviewer screens, widgets, provider methods, and test files from `frontend/`.
- **Project Owner Reconfirmation**: The project owner explicitly reconfirmed that ADR-0013's architectural scope boundary is authoritative, correct, and intentional: KYC/KYB reviewer tools, cross-tenant review workflows, and administrative token semantics MUST NOT be bundled in the consumer mobile app binary (`quick-delivery-mobile`).
- **Policy on Future Modifications**: Any future attempt to re-introduce administrative reviewer interfaces into the consumer app binary is strictly prohibited without explicit, direct written authorization from the project owner. Agents and contributors must not infer or override this scope boundary based solely on code comments or prior commit messages.
