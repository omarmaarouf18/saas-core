# Worklog: BE-HARDEN — backend hardening follow-ups

## Task and scope
- Task ID: BE-HARDEN
- Item IDs covered: 1, 2, 3, 4, 5, 6, 7
- Allowed paths (lane from the task prompt):
  - `services/api-gateway/**`
  - `services/notification-service/**`
  - `services/user-service/**`
  - `services/auth-service/**` (only what items 3, 5 and 7 need)
  - `shared/infra/resilience/**` and `shared/infra/ratelimit/**` (hot paths owned by this task)
  - `scripts/staging_up.sh`
  - `tests/contracts/**`, `tests/e2e/**`
  - `docs/api/**`, `docs/APPLICATION_MAP.md` (regenerated with `make docs` only),
    `docs/worklog/BE-HARDEN.md`
- Agent branch: `agent/BE-HARDEN-backend-hardening`, created from `logic-exploitation`
  (base commit `2263a516`, short SHA only — no full SHAs on agent branches).
- Out of lane and untouched: `frontend/**`, `infrastructure/**`, `.github/**`,
  `Makefile`, every `go.mod`/`go.sum`, `go.work`, `.githooks/**`, the other repos,
  and everything under `shared/infra/` except `resilience/` and `ratelimit/`.

## Decisions taken
- **Item 1**: the passthrough is an opt-in `resilience.Option`
  (`resilience.WithUpstream5xxPassthrough()`) on `NewClient` and
  `NewRoundTripper`; only the api-gateway proxy transport
  (`services/api-gateway/cmd/main.go`) enables it. The upstream 5xx still
  travels through the circuit breaker as a failure (the breaker closure
  returns a typed `*upstream5xxError`), the retry policy is untouched, and
  only the response of the *last* attempt is handed to the caller with a nil
  error. The error message stays exactly `HTTP status N`, because
  chat-service parses it with `upstreamStatusPattern`
  (`services/chat-service/internal/handlers/admin_tickets.go:244`) and
  chat-service is outside this task's lane.
- **Item 1**: the proxy `ErrorHandler` now only sees real transport errors
  (dial, timeout, open breaker) and keeps its existing 502 answer and body.
  The `Sscanf` branch and the `/photo` special case are gone.

## Changes per commit (message only — NO SHAs)
1. `BE-HARDEN: item 1 - gateway passes upstream 5xx through unchanged`
2. `BE-HARDEN: item 2 - notification-service survives missing Redis and Mongo`
3. `BE-HARDEN: item 3 - internal device-token unregister endpoint`
4. `BE-HARDEN: item 4 - mask phones in the admin job list`
5. `BE-HARDEN: item 5 - admin 500s no longer leak store errors`
6. `BE-HARDEN: item 6 - mask CI secrets in staging_up.sh`
7. `BE-HARDEN: item 7 - refuse the dev DOCUMENT_ENCRYPTION_KEY outside local/test`

## Verification
- (filled in as the task progresses)

## Unverified
- (filled in as the task progresses)

## Follow-ups / out-of-lane findings
- (filled in as the task progresses)

## Open questions
- (filled in as the task progresses)
