# Worklog: ADDR-REQUIRED — typed address required at booking (app 2.1.0), structured address details

## Task and scope
- Task ID: ADDR-REQUIRED
- Item IDs covered: 1 (done), 2 (done), 3 (done), 4 (done), 5 (done), 6 (done)
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
- Added shared formatter `formatAddressDetails` in `customer_format.dart` and exported it via `courier_format.dart`, `job_v2_sections.dart`, and `owner_format.dart`.
- Formats non-empty parts with localized strings (`addrDetailsBuilding`, `addrDetailsFloor`, `addrDetailsApartment`) separated by comma (Arabic comma `'، '` in AR, `', '` in EN), omitting empty/null parts.
- Updated `jobPlaceLabel` and `placeOf` to display structured details next to the address (`'$address · $details'`), rendering across Courier (`CourierStops`, `active_job_page.dart`), Owner (`OwnerOrderDetailPage`), and Customer (`OrderRouteCard`).
- In `saved_address_rules.dart`, added `buildingTooLong` (cap 50), `floorTooLong` (cap 20), `apartmentTooLong` (cap 20) validation rules.
- In `saved_addresses_page.dart`, added `_building`, `_floor`, `_apartment` input fields in `SavedAddressEditorPage`, updated `_SavedRow` to format structured details next to address via `formatAddressDetails`, and updated golden images for the editor.
- In `frontend/pubspec.yaml`, bumped `version: 2.0.0+1` to `version: 2.1.0+1`. Bumped `kAppVersion` default in `frontend/lib/core/app_version.dart` to `'2.1.0'`, and updated `frontend/test/core/app_version_test.dart` to verify consistency.
- Verified `frontend/.github/workflows/build-apk.yml`: the release build derives the semver version from `pubspec.yaml` using `VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)`, combines it with `${{ github.run_number }}`, and passes `--dart-define=APP_VERSION="${{ steps.vars.outputs.full_version }}"`.

## Changes per commit (message only — NO SHAs)
1. `user-service: require typed address for app >= 2.1.0 with structured details`
2. `auth-service: add building, floor, apartment to saved addresses`
3. `frontend: require typed address and add structured details to booking form`
4. `frontend: format and display structured address details across roles`
5. `frontend: add building, floor, apartment to saved addresses management`
6. `app: bump version to 2.1.0+1`

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
  - `flutter test test/features/customer/customer_format_test.dart` — PASS (15 tests)
  - `flutter test test/features/courier/courier_v2_places_test.dart` — PASS (6 tests)
  - `flutter test test/features/owner/order_detail_page_test.dart` — PASS (9 tests)
  - `flutter test test/features/customer/order/order_v2_test.dart` — PASS (11 tests)
  - `flutter test test/features/account/saved_addresses_test.dart` — PASS (15 tests)
  - `flutter test test/features/account/` — PASS (all 188 tests)
  - `flutter test test/core/app_version_test.dart` — PASS (2 tests)
  - `flutter test` — PASS (all 1445 tests)
  - `flutter analyze` — PASS (0 issues found)
- `make check` — PASS

## Deploy notes
- Backend: no VM change. The rule only applies to apps >= 2.1.0, so the backend can release before the app.
- App 2.1.0: goes out through the normal mobile pipeline.
- The owner raises minimum_version to 2.1.0 in the console only after the 2.1.0 APK is published.

## Unverified
- None for items 1-6.

## Follow-ups / out-of-lane findings
- None

## Open questions
- None


