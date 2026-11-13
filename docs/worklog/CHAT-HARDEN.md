# Worklog: CHAT-HARDEN — chat-service hardening sweep

## Task and scope
- Task ID: CHAT-HARDEN
- Item IDs covered: #22, #26, #32, #38, #10 (chat-service part), #31 (chat part)
- Allowed paths (lane from the task prompt):
  - `services/chat-service/**`, except `go.mod` / `go.sum`
  - `tests/contracts/**`, only the chat contracts (for example `user_chat_contract_test.go`)
  - `tests/e2e/**`, only chat fakes and assertions
  - `README.md`: only the lines that mention `onboard-agent`
  - `docs/APPLICATION_MAP.md` (only via make docs) and `docs/api/**` if they document these error bodies
  - `docs/worklog/CHAT-HARDEN.md`
- Agent branch: agent/CHAT-HARDEN-chat-service-hardening, rebased onto logic-exploitation (ac8a79a3)

## Decisions taken
- Item 1 (#22, #31): Set `defaultTokenCacheCap = 10000` entries. Justification: with ~64 bytes per entry, 10,000 entries require < 1 MB memory while comfortably holding active WebSocket user tokens across reconnection bursts and guarding against memory exhaustion / token spam DoS. Eviction drops expired entries on lookup and evicts the entry closest to expiry when the cap is reached. Mutex is released before calling auth-service, and query parameter `id` is escaped via `url.QueryEscape`. The doc comment on `verifyToken` was corrected to 5 seconds.
  - Owner review update:
    1. Reverted response-decoding rewrite back to original `json.NewDecoder(resp.Body).Decode(&user)`. Avoided unbounded `io.ReadAll` and extra struct tag fallbacks since `encoding/json` already matches case-insensitively.
    2. Updated `setCachedToken` to avoid scanning the entire map under the mutex on every insert below capacity: sweep only executes when `len(tokenCache) >= capLimit`. Added `TestTokenCache_BelowCapDoesNotSweep` proving entries below cap are not swept.
- Item 2 (#26) ID Format Audit: Inspected `user-service/internal/handlers/jobs_handlers.go:1732-1734` (`job:` + `job.ID`, `fleet:` + `job.OwnerID`), `jobs_handlers.go:2008` (`fleet:` + `tenantID`), `handlers.go:670` (`generateID()` returning 16-hex characters or `fallback-<timestamp>`), `auth-service/internal/handlers/auth.go:1702` (16-hex characters), and contract/unit tests (`user_chat_contract_test.go`, `chat_test.go`, `adr0008_e2e_integration_test.go` using IDs like `job-contract-999`, `valid-job-123`, `1`, `owner-fleet-123`). Real ID charset is `^[a-zA-Z0-9_-]+$`, length 1 to 128 characters. Valid channels are strictly `job:<id>` and `fleet:<id>`. Coordinates must be finite and within [-90.0, 90.0] latitude and [-180.0, 180.0] longitude.

## Changes per commit (message only — NO SHAs)
1. `fix(chat): bound tokenCache with cap and eviction, escape lookup URL`

## Verification
- `go test -v -race -run TestTokenCache ./services/chat-service/internal/handlers` — PASS (6/6 tests: cap holds, expired eviction, below cap does not sweep, cached hit avoids HTTP, URL escaping, race concurrency)
- `gofmt -l .` — empty
- `go vet ./...` (chat-service) — PASS
- `make check` — PASS (scope: `go=services/chat-service contracts docs infra-tests docgen`) after rebase onto logic-exploitation (ac8a79a3) with DEPS-COMPRESS and GO-1-26-11 toolchain bump.

## Unverified
- None for Item 1.

## Follow-ups / out-of-lane findings
- `AI_CONTEXT.md` line 144 mentions orphan `services/chat-service/cmd/onboard-agent`. Per task instructions, `AI_CONTEXT.md` was not edited; line 144 is recorded here for the owner to update during merge fold.
- `services/user-service` and other services using `go.mongodb.org/mongo-driver/v2@v2.8.0` also fail `govulncheck` on GO-2026-6865 due to the same dependency on `klauspost/compress` v1.18.7.

## Open questions
- **RESOLVED**: `go.mod` grant question: Owner confirmed no `go.mod` grant for CHAT-HARDEN. The bump is done once for all six modules by task DEPS-COMPRESS. When DEPS-COMPRESS is merged, rebase branch onto the new `logic-exploitation`, run `make check`, then commit.
