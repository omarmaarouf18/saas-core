# ADR-0021: Standalone KYC/KYB/KYE Reviewer Console

- **Status**: Accepted (authorized by project owner, 2026-08-26)
- **Date**: 2026-08-26
- **Related ADR**: [ADR-0013](0013-support-agent-console-as-separate-client-application.md) (Support Agent Console as a Separate Client Application), [ADR-0010](0010-separate-repos-for-deployment-artifacts.md) (Separate Repos for Deployment Artifacts)
- **Authorization Note**: This ADR executes the Support Agent Console deferred by ADR-0013 under the explicit written authorization of the project owner issued 2026-08-26. Per ADR-0013's enforcement policy, this authorization covers ONLY a separate standalone application. Nothing in this ADR authorizes reintroducing any reviewer interface into the consumer app binary (`frontend/`); the sole permitted consumer-app touch is notification *consumption* (receiving and displaying review outcome notifications), which is an end-user-facing concern, not a reviewer capability.

## Context

KYB (owner business verification) and KYE (employee identity verification) reviews are performed via three agent-authenticated endpoints in `auth-service`, all gated by `authenticateReviewer` (which requires BOTH `X-Internal-Token` — internal network context — AND `X-Reviewer-Token` — an individual reviewer credential stored hashed in the `reviewers` collection):

| Endpoint | Purpose |
|---|---|
| `GET /auth/kyb-kye/pending` | Queue of pending submissions with 15-minute signed document URLs |
| `POST /auth/kyb-kye/review` | Approve/reject decision (`{user_id, action, reason}`) |
| `GET /auth/documents/view?token=...` | Streams an encrypted-at-rest document via signed view token |

Today, reviewers operate these endpoints through raw HTTP clients. Two prior attempts to build reviewer UI inside the consumer app were reverted (2026-08-13 and 2026-08-16, see ADR-0013 addenda), leaving reviewers without any purpose-built tooling. Additionally:

1. **No user-facing outcome notification exists.** On approve/reject, `ReviewKYBKYESubmissions` updates the database and writes audit/security events only. Users learn their KYC outcome either by polling-driven refresh of `KycDocumentUploadScreen` (which already renders a rejection-reason banner when `rejection_reason` is present on the profile) or not at all if they never revisit.
2. **Rejection reason is optional server-side** (`reason,omitempty`). A rejection can currently be recorded with no explanation, which directly undermines the consumer screen's rejection-reason banner and any notification built on it.
3. **notification-service exposes unused internal dispatch plumbing**: `POST /notifications/send` (`X-Internal-Token` authenticated, empty-secret guarded, rate-limited) supports single-user targeting (`user_id`) with `type`/`title`/`body` and fans out over Redis Pub/Sub → SSE to connected consumer clients. No service currently calls `/notifications/send` (user-service calls only the separate `/notifications/broadcast/job-alert` endpoint).
4. **The public gateway cannot carry reviewer traffic, by design.** The api-gateway strips `X-Internal-Token` from every inbound client request (`api-gateway/internal/proxy/proxy.go`, Director function), and `authenticateReviewer` requires that header. Consequently no external application — web or mobile — can reach reviewer endpoints through the public edge. This is intentional defense-in-depth and MUST NOT be weakened (e.g., by adding a gateway route that injects the internal token).

### Scope Call: Ticket Resolution Remains Deferred

ADR-0013 provisionally named the future console `support-agent-console` for cross-tenant *ticket resolution* (`POST /chat/tickets/resolve`). This ADR makes an explicit scoping decision: **the console delivered here covers KYC/KYB/KYE review only. Full support-ticket resolution remains deferred** to a future ADR.

Justification: ticket resolution lives in a different service (`chat-service`), a different data model (disputes vs. identity documents), and different operational workflows (customer communication vs. compliance decisions). Folding it in would delay shipping a working review tool behind unrelated design work. The repo name reflects the narrower scope; a follow-up ADR may extend this same console with ticket queues rather than spawning another app.

## Decision

### 1. A Separate Standalone Reviewer Console Repository

A new repository, **`omarmaarouf18/kyc-reviewer-console`**, implements the review tooling as a **thin internal-network web service** with a lightweight browser UI.

**Tech choice: Go HTTP service serving a minimal HTML/JS UI.** Reasoning:

- **Deployment topology is forced by security, not preference.** Because the gateway strips `X-Internal-Token` (Constraint 4 above), something inside the internal network must hold the internal secret and inject it server-side. A browser-only SPA calling the gateway directly is therefore impossible without leaking `INTERNAL_SERVICE_TOKEN` into reviewer devices or weakening the gateway boundary — both rejected. A small server-side component colocated with the services (same compose network) is the simplest shape that satisfies the existing two-token model.
- **Go over Node/Python for the thin service**: matches monorepo conventions exactly — `gofmt`/`go vet`/`go test`/gosec gates, Dockerfile patterns, config fail-fast conventions, empty-secret-guard discipline, and mTLS/TLS utility patterns are all directly reusable. One language across saas-core and the console lowers maintenance cost for an internal tool.
- **Web UI over Flutter mobile/desktop**: the reviewer workflow is desk-bound administrative work; a browser tab needs no APK signing, store distribution, or device provisioning — updates are a server redeploy. Code reuse from the Flutter app (`api_client.dart`, theme) is marginal because the console UI is tiny (login, queue list, detail/action view, document images), so Flutter's distribution friction buys nothing here. This mirrors the ADR-0013-era reasoning but lands on the opposite conclusion precisely because the deployment constraint rules out a pure static SPA.
- **Auth flow through the console (stateless pass-through)**: the reviewer enters their `X-Reviewer-Token` in the console UI; the browser sends it to the console on each request; the console proxies to `auth-service` over the internal network, adding `X-Internal-Token` from its own environment. The console performs no local authorization decisions — `auth-service` remains the single authentication authority for every proxied call. The internal token never reaches any browser. Reviewer tokens live in browser memory only (no persistence beyond the tab session).
- **Document viewing**: because `GET /auth/documents/view` also requires both headers (and browsers cannot attach headers to `<img>` requests), the console streams document bytes through itself: it fetches from auth-service with both tokens server-side and relays the response to the reviewer's browser. Signed view URLs from the pending queue are consumed server-side by the proxy, never handed to the client.

### 2. Server-Side Mandatory Rejection Reason

In `ReviewKYBKYESubmissions`, a `reject` action with an empty (or whitespace-only, after `strings.TrimSpace`) `reason` returns `400 {"error": "reason is required for rejection"}`. A reason length cap of 1000 characters is enforced, mirroring the existing `RateJob` comment bound. This is enforced at the API layer as defense-in-depth — the console UI enforces it too, but the endpoint must protect itself since it is callable by other means. Approvals do not require a reason (not meaningful there).

Regression tests: reject-without-reason → 400; reject-with-reason → 200; approve-without-reason → 200.

### 3. Review Outcome Notifications via Existing Internal Dispatch

After a successful, persisted approve or reject, `ReviewKYBKYESubmissions` dispatches a notification via notification-service's existing `POST /notifications/send` (the outbound inter-service call pattern matches `broadcastJobAlert` in user-service: fire-and-forget goroutine, `X-Internal-Token` header, structured failure logging):

- `type`: `kyc_approved` or `kyc_rejected`
- `user_id`: the reviewed user's ID; `tenant_id`: the target user's `TenantID`
- `title`/`body`: approval confirmation, or rejection with the reason text

PII and log discipline: the rejection reason is already recorded in the existing `KYC_REVIEWED` security event (pre-existing behavior, unchanged). New log lines never interpolate the raw reason without stripping CR/LF control characters first (G706 log-injection discipline, consistent with AI_CONTEXT gosec policy). The reason travels only to the reviewed user themself — it is their rejection rationale and is already displayed to them by the existing profile-polling banner — and is not added to any new log or audit surface beyond current practice.

Failure handling: notification dispatch failure is logged distinctly (`[KYC-NOTIFY]`) but NEVER fails the review. Persistence and notification are deliberately decoupled; a failed dispatch leaves the review correctly recorded, auditable, and visible via the existing status screens. No retry queue in this iteration (deferred: at-least-once redelivery).

Empty-secret guard: the new outbound caller follows the established Q23 discipline — the console and any new sending code treat an unset internal token as hard-fail-at-startup (config validation), never authenticating or emitting with an empty secret.

Consumer app behavior (notification-consumption only — the sole authorized `frontend/` touch):

- `NotificationsProvider`'s SSE pipeline already parses every `notification` event generically into the notifications list; new types appear in the list/badge without structural change. The alert-type filters in `notifications_screen.dart` gain the two new types.
- On receiving `kyc_rejected` while the app is active, the app shows an informational in-app dialog presenting the rejection reason (reusing/extending the shared dialog pattern — `ConfirmActionDialog` family — per shared-pattern-first principle), in addition to normal list/badge delivery. The user should not have to hunt for why they were rejected.
- On `kyc_approved`, no new UI: the existing `KycDocumentUploadScreen` status display already reflects `approved` via profile data; the notification itself provides the immediacy.
- New strings get EN+AR ARB keys per the standing l10n discipline. Widget tests cover the dialog trigger path.

### 4. Console Scope and Views

Minimal internal tool: reviewer token login; pending queue view (`GET /auth/kyb-kye/pending`); review action view (approve / reject with reason field required-and-validated in the UI when rejecting, mirroring the now-mandatory server rule); document viewing (queue-provided signed URLs streamed via the console proxy).

### 5. CI/CD Connection to saas-core

Modeled on the hot-swap sync/build pattern in `frontend/docs/CI_CD.md`, adapted for an original-code repo rather than a subtree mirror (the console is developed in its own repo; unlike `quick-delivery-mobile`, it is not a push mirror of a monorepo directory, so `git subtree split` does not apply):

- **Console repo CI** (on every push/PR): `gofmt`, `go vet`, `go test`, `gosec`, and a UI build/lint step — same gate philosophy as saas-core's `ci.yml`.
- **Cross-repo trigger**: saas-core gains a workflow that fires a `repository_dispatch` to `omarmaarouf18/kyc-reviewer-console` when pushes to `main` touch the reviewer API contract surface (`services/auth-service/**`, notification-service send-path, or the shared contracts the console compiles against). The console repo responds by running its contract/integration test suite against the updated API expectations, so a breaking change to e.g. `ReviewKYBKYESubmissions`'s request/response shape surfaces immediately instead of at review time.
- Secrets handling mirrors the `MOBILE_REPO_PAT` lessons already documented: fine-grained PAT with `Contents: Read/write` limited to the console repo, `persist-credentials: false` on checkout, `x-access-token:` URL prefix form.

## Consequences

### Positive
- Reviewers finally get purpose-built tooling without ever embedding admin capabilities in the consumer binary — executing ADR-0013 rather than eroding it.
- Rejections become explainable by construction (API-enforced reason), improving both user experience and audit quality.
- Users get timely outcome awareness through infrastructure that already exists (SSE hub, notifications screen), with zero new user-facing backend surface.
- The two-token reviewer model is preserved end-to-end; the internal secret stays server-side.

### Negative / Tradeoffs
- One more deployable unit in the stack (small Go service + static assets).
- Document bytes transit the console process (memory-bounded streaming; acceptable for internal review volume).
- Fire-and-forget notifications can be lost on transient dispatch failure until a retry/redelivery pass is added (logged distinctly; status screens remain the source of truth).

## Alternatives Considered

- **Reviewer UI in the consumer app**: prohibited twice over by ADR-0013 enforcement history; not reconsidered.
- **Pure static SPA hitting the gateway**: impossible without weakening the internal-token boundary (gateway strips `X-Internal-Token`; injecting it at the edge would let any internet caller impersonate the internal network).
- **Flutter desktop/mobile console**: strongest code reuse story but adds build/sign/distribute friction for an internal desk tool whose UI is trivially small; revisitable if reviewers demand mobile workflows.
- **Folding support-ticket resolution into this console now**: rejected for scope focus (see Scope Call above); extension later is cheaper than shipping late.
