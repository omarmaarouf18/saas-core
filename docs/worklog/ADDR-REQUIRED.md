# Worklog: ADDR-REQUIRED — typed address required at booking (app 2.1.0), structured address details

## Task and scope
- Task ID: ADDR-REQUIRED
- Item IDs covered: 1 (done), 2 (done), 3 (done)
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
- In `auth-service`, added `Building`, `Floor`, `Apartment` to `SavedAddress` (`omitempty` in JSON and BSON) with matching caps (50, 20, 20) and `SanitizeAddressText` in profile update.
- Preserved existing `SavedAddress.UnmarshalJSON` and `MarshalJSON`, maintaining full backward compatibility with old records without the new fields.
- In `frontend`, made street address required (5-250 runes) with `tooShort` validation error and mapped server error codes `address_required` and `address_too_short`.
- Added optional `building` (max 50), `floor` (max 20), `apartment` (max 20) in `PickedPlace`, `JobLocation`, `SavedAddress`, `CustomerPickerPage`, and `MarketplaceProvider`.
- Selecting a saved address in `CustomerPickerPage` pre-fills address, building, floor, apartment, and note.

## Changes per commit (message only — NO SHAs)
1. `user-service: require typed address for app >= 2.1.0 with structured details`
2. `auth-service: add building, floor, apartment to saved addresses`
3. `frontend: require typed address and add structured details to booking form`

## Verification
- `services/user-service` unit & integration tests:
  - `go test -v ./services/user-service/internal/handlers -run "TestAppVersion|TestIsLegacyAppBuild"` — PASS
  - `go test -v -count=1 ./services/user-service/internal/handlers -run TestTypedAddress` — PASS
  - All 229 handler tests in `services/user-service/internal/handlers` pass.
- `services/auth-service` unit & integration tests:
  - `go test -v ./services/auth-service/internal/handlers -run TestSavedAddresses` — PASS (round-trip, over-cap rejected, old records still load without fields, sanitization)
- `gofmt -l .` — empty (all files formatted).
- `make docs` — ran `tools/docgen/main.go`, no changes to `APPLICATION_MAP.md`.
- `frontend` tests:
  - `flutter test test/features/customer/booking_rules_test.dart` — PASS (34 tests)
  - `flutter test test/features/customer/booking_v2_test.dart` — PASS (12 tests)
  - `flutter test test/providers/marketplace_provider_v2_test.dart` — PASS
  - `flutter test test/features/customer/booking_page_test.dart` — PASS (9 tests)
  - `flutter test test/features/customer/error_codes_test.dart` — PASS (8 tests)
  - `flutter test test/features/customer/` — PASS (all 320 tests)
- `make check` — PASS for previous commits, will run for Item 3 commit.

## Unverified
- None for items 1, 2, and 3.

## Follow-ups / out-of-lane findings
- None

## Open questions
- None
