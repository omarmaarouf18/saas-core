# Worklog: USER-AUTH-BE — Backend gaps found while building redesign A

## Task and scope
- Task ID: USER-AUTH-BE
- Item IDs covered: 1–12 (complete)
- Allowed paths: Worktree `../saas-core-wt/USER-AUTH-BE`, branch `agent/USER-AUTH-BE-backend-gaps-for-redesign` from `logic-exploitation`. Parallel with FE-CLEANUP (`frontend/**`, `docs/frontend/**`, `docs/design/**`), which were not touched. No `go.mod` `go`/`toolchain` changes.
- Agent branch: `agent/USER-AUTH-BE-backend-gaps-for-redesign`, created from `logic-exploitation` (`758f01b4`).

## Decisions taken
1. **Item 1 (Service photo)**: Service photo upload handler enforces ≤5 MB payload bounding, image decoding (PNG/JPEG) and re-encoding to strip EXIF/metadata, magic-byte inspection (JPEG `FF D8 FF`, PNG `89 50 4E 47 0D 0A 1A 0A`), and writes encrypted blobs using `shared/infra/storage`. Authenticated read endpoint validates JWT (`user`, `customer`, `owner`, `employee`, `admin`) before serving decrypted stream. Old local-file path strings (e.g., `file://`, `/`, `\`, `./`, `../`) in `photo_url` are ignored and cleared to empty on read. Added `/photo` to `MaxBytesMiddleware` 10MB upload path exception so photos up to 5MB are not prematurely truncated by default 1MB global middleware. Added temp dir fallback and logging in user-service storage initialization to gracefully handle environments without pre-mounted storage volumes.
2. **Item 2 (Service create persists every field)**: `POST /users/services` accepts and persists `address`, `working_hours`, `coverage_radius_km` (with `coverage_radius` alias), `photo_url` (with `photo` alias), structured schedule fields (`schedule_mode`, `open_time`, `close_time`, `per_day_schedule`, `timezone`), matching `PUT /users/services`.
3. **Item 3 (Customer name for owners)**: Added `customer_name` snapshot field to `Job` and `OwnerJobResponse` (omitted if empty for legacy jobs). Handlers snapshot `User.Name` at booking time (`POST /users/jobs/track` and `POST /users/jobs/request-price`); legacy jobs without snapshot fall back to memoized S2S auth lookup (`GET /auth/user?id=...`), then to empty if lookup fails.
4. **Item 4 (Courier KYE status)**: Added `kye_status` to `EmployeeResponse` projection in auth-service, populated from `Employee.KYEStatus` (or derived from `User.KYCStatus` / fallback "none" if unset) in `GET /auth/employees`.
5. **Item 5 (Saved addresses with coordinates - ADR-0028 §2.8)**: Added `SavedAddresses []SavedAddress` (max 10, validated coordinates [-90,90]/[-180,180], non-empty label and address, rune length bounds) to `User` and `UpdateUserRequest`. In `PUT`/`PATCH /auth/user`, updating `saved_addresses` automatically re-derives legacy `frequent_addresses []string` (labels/addresses), maintaining bidirectional backwards-compatibility. `GET /auth/user` returns both.
6. **Item 6 (2FA login code resend)**: `POST /auth/resend-otp` inspects both pending signup OTP (`otp:pending:<email>`) and pending 2FA login challenge OTP (`otp:login:challenge:<email>`). For pending login challenges, generates a new cryptographic OTP using the existing crypto/AES storage and rate limiter rules, and re-sends via Resend/mock email.
7. **Item 7 (Notification payloads carry job_id & stable event types)**: All job lifecycle notifications (`job_booked`, `job_accepted`, `job_picked_up`, `job_in_transit`, `job_delivered`, `job_cancelled`) explicitly include `job_id` and stable `event_type` in the notification data payload and SSE stream. Updated notification history projection to include `job_id`.
8. **Item 8 (POST /users/jobs/pickup returns EmployeeJobResponse)**: Changed `PickupJob` handler response from raw `*models.Job` to `models.NewEmployeeJobResponse(refreshed, courierID)`, preventing leakage of owner-only fields such as `actual_cash_amount` and internal payment settlement structures.
9. **Item 9 (Text limits in runes, not bytes)**: Updated length validation across `address_note` (500 runes), v2 `address` (250 runes), `recipient_notes` (200 runes), `package_notes` (200 runes), and `name` (100 runes) using `len([]rune(str))` so Arabic and multi-byte UTF-8 text is not truncated prematurely.
10. **Item 10 (Stable error codes)**: Standardized validation and pickup errors to include both user message and stable code: `{"error": "<msg>", "message": "<msg>", "code": "<code>"}`. Added stable codes `address_required`, `address_too_long`, `recipient_name_required`, `recipient_name_too_long`, `recipient_phone_required`, `recipient_phone_invalid`, `recipient_notes_too_long`, `package_details_required`, `package_notes_too_long`, `job_not_found`, `access_denied`, `already_picked_up`, `job_state_changed`.
11. **Item 11 (Documentation updates)**: Added ADR-0007 addendum for COD reconciliation exception (FIX-COD-RECON), updated ADR-0028 status to Accepted with Task 3 implementation notes covering backend gap completions, and regenerated API documentation via `make docs`.
12. **Item 12 (E2E tests)**: Added new isolated test file `tests/e2e/user_auth_be_gaps_test.go` covering service create+photo upload/read, saved addresses with coordinates and legacy sync, pickup endpoint `EmployeeJobResponse` projection (asserting absence of `actual_cash_amount`) + stable error codes, and 2FA login OTP resend against live staging stack.

## Changes per commit (message only — NO SHAs)
1. `USER-AUTH-BE: item 1 - service photo upload and authenticated read`
2. `USER-AUTH-BE: item 2 - service create persists all fields matching PUT`
3. `USER-AUTH-BE: item 3 - snapshot customer name at booking and expose in owner job responses`
4. `USER-AUTH-BE: item 4 - expose courier kye_status in /auth/employees`
5. `USER-AUTH-BE: item 5 - saved addresses with coordinates (ADR-0028 2.8)`
6. `USER-AUTH-BE: item 6 - resend 2FA login challenge code`
7. `USER-AUTH-BE: item 7 - job_id and stable event types in notification payloads`
8. `USER-AUTH-BE: item 8 - return EmployeeJobResponse projection from POST /users/jobs/pickup`
9. `USER-AUTH-BE: item 9 - count address note text limits in Unicode runes`
10. `USER-AUTH-BE: item 10 - stable error codes for booking validation and pickup`
11. `USER-AUTH-BE: item 11 - ADR-0007 COD exception, ADR-0028 implementation notes, API docs`
12. `USER-AUTH-BE: item 12 - E2E tests for redesign backend gaps`

## Tests added and which tests failed before
- **Item 1 (`services/user-service/internal/handlers/service_photo_test.go`)**:
  - `TestUploadServicePhoto_Success_JPEG`, `TestUploadServicePhoto_Success_PNG`, `TestUploadServicePhoto_OversizedRejected`, `TestUploadServicePhoto_InvalidMagicBytes`, `TestGetServicePhoto_Authenticated`, `TestGetServicePhoto_UnauthenticatedRejection`, `TestGetServicePhoto_LocalPathIgnored`.
  - *Failed before*: Endpoints did not exist (`404 Not Found`).
- **Item 2 (`services/user-service/internal/handlers/service_create_fields_test.go`)**:
  - `TestCreateService_PersistsAllFieldsMatchingPUT`.
  - *Failed before*: `address`, `working_hours`, `coverage_radius_km` were omitted on `CreateService` response and DB document.
- **Item 3 (`services/user-service/internal/handlers/customer_name_owner_test.go`)**:
  - `TestCustomerName_SnapshotOnBooking`, `TestCustomerName_LegacyFallbackS2S`, `TestCustomerName_LegacyFallbackFailureEmpty`.
  - *Failed before*: `customer_name` field was not present in `Job` model or `OwnerJobResponse`.
- **Item 4 (`services/auth-service/internal/handlers/auth_test.go`)**:
  - `TestGetEmployees_IncludesKYEStatus`.
  - *Failed before*: `kye_status` was omitted from `EmployeeResponse`.
- **Item 5 (`services/auth-service/internal/handlers/saved_addresses_test.go`)**:
  - `TestSavedAddresses_CRUD_And_LegacySync`, `TestSavedAddresses_ValidationMax10`, `TestSavedAddresses_CoordinateBounds`.
  - *Failed before*: `saved_addresses` field was unrecognized on user update and missing from user response.
- **Item 6 (`services/auth-service/internal/handlers/resend_login_otp_test.go`)**:
  - `TestResendOTP_PendingLoginChallenge`, `TestResendOTP_PendingSignup_Unchanged`.
  - *Failed before*: Resending OTP for a login challenge returned `400` ("no pending registration for this email").
- **Item 7 (`services/notification-service/internal/handlers/job_notification_payload_test.go`)**:
  - `TestJobNotification_PayloadCarriesJobIDAndEventType`, `TestNotificationHistory_IncludesJobID`.
  - *Failed before*: Notification payloads lacked structured `job_id` and stable event types.
- **Item 8 (`services/user-service/internal/handlers/job_pickup_dto_test.go`)**:
  - `TestPickupJob_ReturnsEmployeeJobResponseProjection_RedactsOwnerFields`.
  - *Failed before*: Response returned full internal Job model with `actual_cash_amount` exposed.
- **Item 9 (`services/user-service/internal/handlers/address_note_test.go`)**:
  - `TestAddressNote_RuneLimitsArabic`.
  - *Failed before*: 300-character Arabic string was rejected because byte length (600 bytes) exceeded byte limit (500).
- **Item 10 (`services/user-service/internal/handlers/job_v2_booking_test.go`, `job_pickup_dto_test.go`)**:
  - Assertions on stable error codes in booking validation and pickup errors.
  - *Failed before*: JSON errors did not contain `"code"` field.
- **Item 12 (`tests/e2e/user_auth_be_gaps_test.go`)**:
  - `TestE2E_UserAuthBEGaps/ServiceCreate_PersistsAllFields_AndPhoto`
  - `TestE2E_UserAuthBEGaps/SavedAddresses_WithCoordinates_AndLegacySync`
  - `TestE2E_UserAuthBEGaps/Pickup_EmployeeJobResponseDTO_AndStableErrorCodes`
  - `TestE2E_UserAuthBEGaps/ResendLoginCode_PendingChallenge`
  - *Failed before*: New E2E test suite written from scratch to validate end-to-end integration against the staging stack.

## Verification
- `services/auth-service` tests:
```text
ok  	github.com/project/auth-service/cmd	0.003s
ok  	github.com/project/auth-service/cmd/approve-kyc	0.013s
?   	github.com/project/auth-service/cmd/encrypt-documents	[no test files]
ok  	github.com/project/auth-service/cmd/onboard-reviewer	0.012s
ok  	github.com/project/auth-service/internal/config	0.001s
ok  	github.com/project/auth-service/internal/handlers	50.220s
ok  	github.com/project/auth-service/internal/models	0.001s
ok  	github.com/project/auth-service/internal/otp	0.004s
ok  	github.com/project/auth-service/internal/otpcrypto	0.001s
ok  	github.com/project/auth-service/internal/storage	0.002s
ok  	github.com/project/auth-service/internal/store	1.020s
```

- `services/notification-service` tests:
```text
?   	github.com/project/notification-service/cmd	[no test files]
ok  	github.com/project/notification-service/internal/config	0.002s
ok  	github.com/project/notification-service/internal/fcm	0.004s
ok  	github.com/project/notification-service/internal/handlers	0.910s
ok  	github.com/project/notification-service/internal/hub	0.516s
ok  	github.com/project/notification-service/internal/store	1.954s
```

- `shared/infra` tests:
```text
ok  	github.com/project/shared/infra	0.710s
ok  	github.com/project/shared/infra/docgen	0.036s
ok  	github.com/project/shared/infra/handlerutil	0.056s
ok  	github.com/project/shared/infra/jwtutil	1.579s
ok  	github.com/project/shared/infra/passwordpolicy	0.002s
ok  	github.com/project/shared/infra/ratelimit	14.682s
ok  	github.com/project/shared/infra/redact	0.002s
ok  	github.com/project/shared/infra/resilience	1.386s
ok  	github.com/project/shared/infra/storage	0.003s
ok  	github.com/project/shared/infra/testutil	0.003s
ok  	github.com/project/shared/infra/tlsutil	0.029s
```

- `services/user-service` tests:
```text
?   	github.com/project/user-service/cmd	[no test files]
ok  	github.com/project/user-service/internal/config	0.002s
ok  	github.com/project/user-service/internal/handlers	204.762s
ok  	github.com/project/user-service/internal/models	0.008s
ok  	github.com/project/user-service/internal/store	11.005s
```

- `make check` last lines:
```text
01:10 +1830: /home/omarmaarouf/CS ... builds every section [en, dark: true]    01:10 +1831: /home/omarmaarouf/CS ... builds every section [en, dark: true]    01:10 +1831: ... (tearDownAll)                                                 01:10 +1831: All tests passed!                                                 
[timing] flutter-analyze-test 74.9s
[timing] total 425.9s
== pre-push gate: all checks passed (scope: full) ==
gate stamp written: /home/omarmaarouf/CS tools/Antigravity/SaaS prototype/.git/gate-stamps/<hash> (scope: full)
```

- `tests/e2e` new test against local staging:
```text
=== RUN   TestE2E_UserAuthBEGaps
=== RUN   TestE2E_UserAuthBEGaps/ServiceCreate_PersistsAllFields_AndPhoto
=== RUN   TestE2E_UserAuthBEGaps/SavedAddresses_WithCoordinates_AndLegacySync
=== RUN   TestE2E_UserAuthBEGaps/Pickup_EmployeeJobResponseDTO_AndStableErrorCodes
=== RUN   TestE2E_UserAuthBEGaps/ResendLoginCode_PendingChallenge
--- PASS: TestE2E_UserAuthBEGaps (0.38s)
    --- PASS: TestE2E_UserAuthBEGaps/ServiceCreate_PersistsAllFields_AndPhoto (0.02s)
    --- PASS: TestE2E_UserAuthBEGaps/SavedAddresses_WithCoordinates_AndLegacySync (0.01s)
    --- PASS: TestE2E_UserAuthBEGaps/Pickup_EmployeeJobResponseDTO_AndStableErrorCodes (0.00s)
    --- PASS: TestE2E_UserAuthBEGaps/ResendLoginCode_PendingChallenge (0.34s)
PASS
ok  	github.com/project/tests/e2e	0.385s
```

## Regression Table
| Scope | Target | Result | Notes |
|-------|--------|--------|-------|
| auth-service | unit / handlers / store | PASS | All 11 package suites passed cleanly |
| notification-service | unit / hub / store / handlers | PASS | All 6 package suites passed cleanly |
| shared/infra | handlerutil / docgen / storage / ratelimit | PASS | All 11 package suites passed cleanly |
| user-service | config / handlers / models / store | PASS | All 5 package suites passed cleanly |
| e2e (all suites) | `go test -count=1 ./tests/e2e` | PASS | All CUJ, RBAC, Security, and Contract suites passed |
| full gate (`make check`) | go vet, gosec, staticcheck, flutter | PASS | Scope full passed |

## Unverified
- None. All 12 items have dedicated automated unit/integration tests and are covered in the new E2E suite against the running local staging stack.

## Follow-ups / out-of-lane findings
- None. All backend changes are strictly additive and backward compatible.

## Open questions
- None.
