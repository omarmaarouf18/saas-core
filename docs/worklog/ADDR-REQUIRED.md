# Worklog: ADDR-REQUIRED — typed address required at booking (app 2.1.0), structured address details

## Task and scope
- Task ID: ADDR-REQUIRED
- Item IDs covered: Item 1 implemented and verified; Item 2 planned; blocked at gate.
- Allowed paths (lane from the task prompt):
  - `services/user-service/internal/models/**`
  - `services/user-service/internal/handlers/jobs_handlers.go`
  - new files under `services/user-service/internal/handlers/` (+ tests)
  - `services/auth-service/internal/models/models.go`
  - `services/auth-service/internal/handlers/auth.go`: only the saved-address validation
  - new files under `services/auth-service/internal/handlers/` (+ tests)
  - `tests/contracts/**`, `tests/e2e/**`
  - `docs/APPLICATION_MAP.md` (via make docs only), `docs/api/**`
  - `frontend/lib/**`, `frontend/test/**`, `frontend/docs/**`
  - Hot path granted: `frontend/pubspec.yaml` (only version line 2.0.0+1 -> 2.1.0+1)
  - `docs/worklog/ADDR-REQUIRED.md`
- Agent branch: `agent/ADDR-REQUIRED-typed-address-required`, rebased onto `logic-exploitation` at `ac8a79a3` (originally `a9e8e53b`)

## Decisions taken
- Reused version parser logic between `isLegacyAppBuild` and the new helper `isAppVersionAtLeast` in `services/user-service/internal/handlers/app_version.go`.
- Added `parseAppMajor` in `app_version.go` to retain `isLegacyAppBuild`'s original lenient major-only parsing semantics ("1", "1.9", "v1", "1.9.3+4" remain legacy).
- Required strict 3-part semver in `parseAppVersion` (`len(parts) == 3`), ensuring versions like `2.1.0.0` or non-standard formats return false.
- Structured address fields `building` (max 50 runes), `floor` (max 20 runes), `apartment` (max 20 runes) added to `models.Location` with `omitempty` in JSON and BSON.
- Sanitized with `models.SanitizeAddressText` and length-capped for all versions.
- Required address check (`address_required` and `address_too_short`) gated strictly to `X-App-Version >= 2.1.0`.
- Owner decision on GO-2026-6865 blocker: Option 2 selected (no go.mod grant). Task DEPS-COMPRESS will bump klauspost/compress across all modules and be merged into logic-exploitation. Item 1 stays uncommitted in working tree; task pauses now until rebase instruction.

## Changes per commit (message only — NO SHAs)
- (Uncommitted pending gate pass) `user-service: require typed address for app >= 2.1.0 with structured details`

## Verification
- `services/user-service` unit & integration tests:
  - `go test -v ./services/user-service/internal/handlers -run "TestAppVersion|TestIsLegacyAppBuild"` — PASS
  - `go test -v -count=1 ./services/user-service/internal/handlers -run TestTypedAddress` — PASS
  - All 229 handler tests in `services/user-service/internal/handlers` pass.
- `gofmt -l .` — empty (all files formatted).
- `make check` — BLOCKED at `govulncheck:services/user-service` step (`GO-2026-6865`).
- `make commit` — Refused (`ERROR: no passing gate stamp for the tree being committed: run make check first`).

## Unverified
- Commits cannot be created because `scripts/commit.sh` requires a passing `make check` stamp, which fails due to the `govulncheck` blocker.

## Follow-ups / out-of-lane findings
- `govulncheck` in `scripts/govulncheck-module.sh` fails on newly reported third-party vulnerability `GO-2026-6865` against `github.com/klauspost/compress` `v1.18.7` (required indirectly via `go.mongodb.org/mongo-driver/v2` `v2.8.0`).
- This failure is not introduced by this task: running `scripts/govulncheck-module.sh services/user-service` on the clean base branch `logic-exploitation` (`a9e8e53b`) yields the exact same failure.

## Open questions
- None (resolved by owner decision: wait for DEPS-COMPRESS to land on logic-exploitation, rebase per WORKFLOW §4, run make check, commit item 1, and continue with item 2).

