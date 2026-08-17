# New Features Changelog

This file tracks historical entries for the primary category: **New Features Changelog**.

## Google Stitch Visual Redesign Implementation (Batches A–E)

- **Implementation Detail**:
  - **Design Tokens & Primary CTA Evolution (`frontend/lib/widgets/primary_button.dart`, `frontend/lib/core/theme.dart`, `docs/frontend/BRAND_IDENTITY.md`, `docs/frontend/DESIGN_SYSTEM.md`)**:
    - Updated `PrimaryButton` default fill to `AppColors.secondary` (Amber Gold `#FFC107`) with `AppColors.onSecondary` (Deep Navy `#0D1321`) text for primary conversion CTAs, while preserving crimson red `AppColors.error` for destructive confirmation actions and active-state tap scaling.
    - Deep Navy (`AppColors.primary`) remains the structural header, dark background, and dark surface anchor.
    - Extended typography scale with `headlineMd` (20pt) and `labelSm` (10pt).
  - **Modern Reusable Shared UI Components (`frontend/lib/widgets/`)**:
    - `OtpPinInput` (`otp_pin_input.dart`): 6 discrete square digit input boxes with auto-advance, backspace focus retreat, clipboard paste, error border highlighting, and external controller sync.
    - `PillFilterBar` (`pill_filter_bar.dart`): Reusable horizontal scrollable category chip bar with active/inactive states, badge counts, tap debounce, and full `InkWell` touch targets.
    - `RouteTimeline` (`route_timeline.dart`): 2-point vertical route connector (dark pickup dot, vertical line, red dropoff dot, dock/bay notes, distance/time/cargo metrics row).
    - `ThemedCard` (`themed_card.dart`): Added optional `onTap` parameter with `Material` and `InkWell` ripple integration.
  - **Batch A (Authentication & Onboarding — 5 screens)**: Upgraded `login_screen.dart`, `signup_screen.dart`, `otp_screen.dart`, `forgot_password_screen.dart`, and `update_required_screen.dart` with external centered headlines, inline password/resend links, 2-card role selection, and discrete PIN boxes.
  - **Batch B (Customer Marketplace & Tracking — 5 screens)**: Upgraded `customer_home_screen.dart`, `customer_jobs_screen.dart`, `job_status_screen.dart`, `customer_marketplace_screen.dart`, and `customer_job_map_screen.dart` with top "Where to deliver?" Quick Booking module, pill filter chips, live shipment tracking cards, map preview header, and driver contact cards.
  - **Batch C (Tenant Owner Operations & Services — 5 screens)**: Upgraded `home_screen.dart` (Bento metrics grid, 48pt balance display, dark subscription tier card), `employee_screen.dart` (search bar, worker status filter chips, roster cards), `owner_configuration_screen.dart` (2:1 aspect ratio dashed photo uploader, 2-column pricing grid), `service_screen.dart`, and `kyc_document_upload_screen.dart` (2x2 document grid).
  - **Batch D (Financial Management & Fleet Oversight — 5 screens)**: Upgraded `wallet_screen.dart` (Deep Navy Balance Hero card, side-by-side withdraw/deposit actions), `subscription_screen.dart` (highlighted Professional tier card with Best Value styling), `owner_fleet_map_screen.dart`, `owner_history_screen.dart` (added `ThemedTextField` search + `PillFilterBar` across completed/cancelled jobs), and `owner_reconciliation_queue_screen.dart` (added search + `PillFilterBar` category chips across distance/time/other disputes).
  - **Batch E (Employee Shell, Support & Communication — 8 screens)**: Upgraded `employee_jobs_screen.dart` and `employee_history_screen.dart` (integrated `RouteTimeline` 2-point route connectors with dock/bay notes and metrics), `employee_home_screen.dart` (3-tab persistent navigation container hosting jobs and history sub-views), `settings_screen.dart` (top Profile Summary card, grouped preference containers), `my_account_screen.dart`, `notifications_screen.dart`, `chat_screen.dart`, and `rating_screen.dart` (interactive gold star rating selector).
  - **Automated Test Coverage**: Added 40 unit and widget tests in `test/shared_widgets_test.dart` and updated auth/job tests for 100% pass across all 259 tests.
- **Commit SHA**: ``68564580dde73d3c512c2648bd21f9c3a3c6c28e``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (259/259 pass), RTL layout check with `ar_EG`, live backend connectivity against `https://api.logiclinkeg.tech`, `make docs-check`, and pre-push hooks gate. ✅

## Maps, Dialogs & Update Required Screen Design System Migration

- **Implementation Detail**:
  - **Live Tracking & Fleet Maps (`frontend/lib/screens/customer_job_map_screen.dart`, `frontend/lib/screens/owner_fleet_map_screen.dart`)**:
    - Replaced raw `CircularProgressIndicator` with `ThemedLoadingIndicator`.
    - Replaced raw `Material` floating overlay notices with `ThemedCard(variant: ThemedCardVariant.elevated)`.
    - Replaced raw marker typography styles with tokenized `AppTypography.labelMd.copyWith(fontSize: 10, fontWeight: FontWeight.bold)`.
    - Replaced raw reconnecting/error banners with `ThemedWarningBanner` and `ThemedErrorBanner`.
  - **Dialog Components (`frontend/lib/widgets/cancel_job_dialog.dart`, `frontend/lib/widgets/confirm_action_dialog.dart`)**:
    - `CancelJobDialog`: Replaced raw `TextField` with `ThemedTextField`; replaced raw action buttons with `SecondaryButton(isFullWidth: false)` and `PrimaryButton(isFullWidth: false, isDestructive: true, isLoading: _isSubmitting)`; replaced inline error text with `ThemedErrorBanner`.
    - `ConfirmActionDialog`: Replaced raw `TextButton`/`ElevatedButton` with `SecondaryButton(isFullWidth: false)` and `PrimaryButton(isFullWidth: false, isDestructive: isDestructive)`.
    - `PrimaryButton` (`frontend/lib/widgets/primary_button.dart`): Added `isDestructive: bool = false` parameter rendering filled `AppColors.error` background for destructive confirmation actions.
  - **Update Required Screen (`frontend/lib/screens/update_required_screen.dart`)**:
    - Replaced version comparison container with `ThemedCard`.
    - Replaced raw `ElevatedButton.icon` with `PrimaryButton`.
    - Replaced hardcoded padding and border radii with `AppSpacing` and `AppRadius` tokens.
  - **Widget Test Coverage (`frontend/test/cancel_job_dialog_test.dart`, `frontend/test/job_cancellation_test.dart`)**: Added automated tests covering `CancelJobDialog` rendering, validation, submission, and error states; updated button widget finders.
- **Commit SHA**: ``0091b8eb23f3be77f0681d976a08a7dcc1ecd825``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (212/212 pass), `make docs-check`, and pre-push hooks gate. ✅

## Subscription Screen Design System Migration

- **Implementation Detail**:
  - **Pending Payment Banner (`frontend/lib/screens/subscription_screen.dart`)**: Replaced hand-coded pending payment container with `ThemedWarningBanner` (semantically accurate for the non-blocking "Pending activation. Please contact support to complete payment." warning state).
  - **Plan Card Highlights (`frontend/lib/screens/subscription_screen.dart`)**: Migrated `_buildPlanCard` to use `ThemedCard(variant: highlighted ? ThemedCardVariant.highlighted : ThemedCardVariant.normal)` eliminating manual border-side and shadow overrides.
  - **Current Plan Inverted Header Card (`frontend/lib/screens/subscription_screen.dart`)**: Preserved intentional inverted solid primary styling (`ThemedCard(color: AppColors.primary)`) as it represents a dark hero container rather than an outlined card.
  - **Typography Standardization (`frontend/lib/screens/subscription_screen.dart`)**: Replaced raw `fontSize: 36` with `AppTypography.headlineLg.copyWith(fontWeight: FontWeight.bold)` (32pt headline token).
  - **Widget Test Coverage (`frontend/test/subscription_screen_test.dart`)**: Added automated widget test suite testing free tier active state, highlighted professional card, pending payment warning banner, and tier upgrade actions.
- **Commit SHA**: ``de9f1e93f787d12eadf9fdc10814bf592adc83d3``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (209/209 pass), `make docs-check`, and pre-push hooks gate. ✅

## KYC Document Upload & Owner Reconciliation Design System Migration

- **Implementation Detail**:
  - **KYC Upload Screen Standardization (`frontend/lib/screens/kyc_document_upload_screen.dart`)**:
    - Replaced hand-rolled `_buildApprovedLockedBanner` container with tokenized `ThemedSuccessBanner`.
    - Standardized hand-rolled "Uploaded" green status pill with tokenized `StatusBadge(status: 'uploaded', compact: true)` (extended `StatusBadge` in `frontend/lib/widgets/status_badge.dart` to support the `'uploaded'` status key).
    - Replaced raw `fontSize: 13` font override with formal token `AppTypography.bodySm` (added to `AppTypography` in `frontend/lib/core/theme.dart`).
    - Replaced raw `CircularProgressIndicator` box in slot action buttons with `SecondaryButton(isLoading: isUploading)` / `PrimaryButton(isLoading: isUploading)`.
  - **Owner Reconciliation Queue Screen Standardization (`frontend/lib/screens/owner_reconciliation_queue_screen.dart`)**:
    - Replaced raw `CircularProgressIndicator` with `ThemedLoadingIndicator`.
    - Replaced raw `fontSize: 18` override on order header with `AppTypography.titleMd.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)`.
    - Replaced raw `OutlinedButton.icon` / `ElevatedButton.icon` pair with `SecondaryButton(isFullWidth: false, isOutlined: true, isDestructive: true, icon: Icons.undo)` and `PrimaryButton(isFullWidth: false, icon: Icons.check_circle_outline)` side-by-side in `Row`. Extended `SecondaryButton` (`frontend/lib/widgets/secondary_button.dart`) to support `isDestructive` styling with `AppColors.error`.
  - **Test Suite Updates (`frontend/test/kyc_document_upload_screen_test.dart`, `reconciliation_queue_test.dart`)**: Updated KYC upload widget tests to verify standardized uppercase `StatusBadge` `'UPLOADED'` rendering alongside `ThemedSuccessBanner` lock state.
- **Commit SHA**: ``95ec302c6464f225d7602a2081791d5b28563bb5``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (205/205 pass), `make docs-check`, and pre-push hooks gate. ✅

## Design System Component Extensions (In-Row Sizing, ThemedCardVariant, ThemedBanner)

- **Implementation Detail**:
  - **In-Row Button Sizing (`frontend/lib/widgets/primary_button.dart`, `frontend/lib/widgets/secondary_button.dart`)**: Added `isFullWidth: bool = true` and `height: double? = 52` parameters to `PrimaryButton` and `SecondaryButton`. When `isFullWidth` is `false`, the button sizes to its intrinsic content width using `MainAxisSize.min` and unconstrained width, enabling side-by-side row placements while preserving full-width block defaults for all existing call sites.
  - **ThemedCard Variants (`frontend/lib/widgets/themed_card.dart`)**: Introduced `ThemedCardVariant` enum (`normal`, `highlighted`, `elevated`) with automatic token-driven border and elevation resolution. `highlighted` renders a 2px `AppColors.secondary` amber border with `shadowLevel2` (for featured subscription plans and promo cards); `elevated` renders `shadowLevel3` for floating map overlays; `normal` preserves 1px `outlineVariant` border with `shadowLevel1` by default.
  - **Unified ThemedBanner & Warning/Info Banners (`frontend/lib/widgets/themed_banner.dart`, `themed_error_banner.dart`, `themed_success_banner.dart`)**: Added unified `ThemedBanner` supporting `ThemedBannerType.error`, `ThemedBannerType.success`, `ThemedBannerType.warning`, and `ThemedBannerType.info` alongside dedicated `ThemedWarningBanner` and `ThemedInfoBanner` widgets with tokenized amber/blue styling, action buttons, and dismiss callbacks. Refactored `ThemedErrorBanner` and `ThemedSuccessBanner` to delegate to `ThemedBanner` with zero breaking changes to existing call sites.
  - **ThemedSnackBar Extensions (`frontend/lib/widgets/themed_success_banner.dart`)**: Added `ThemedSnackBar.showWarning` and `ThemedSnackBar.showInfo` floating toasts.
  - **Automated Widget Test Suite (`frontend/test/shared_widgets_test.dart`)**: Added test coverage verifying `isFullWidth` toggle, `ThemedCardVariant` styling/shadow levels, `ThemedWarningBanner`/`ThemedInfoBanner` dismiss/retry actions, and floating warning/info snackbars.
- **Commit SHA**: ``d7418b73176a14b05cba92d4119e7ad05a750dd0``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (205/205 pass), `make docs-check`, and pre-push hooks gate. ✅

## OTP-Verified Email Change Flow (POST /auth/email-change/request & POST /auth/email-change/confirm)

- **Implementation Detail**:
  - **Backend (`auth-service`)**:
    - `models/models.go`: Added `EmailChangeRequest`, `EmailChangeConfirmRequest`, and `PendingEmailChange` data models.
    - `store/mongodb.go`: Created `pending_email_changes` collection with a unique index on `user_id`. Added `SetPendingEmailChange` (AES-256-GCM encrypts OTP, 5-min expiration, upserts record), `GetPendingEmailChange`, `GetAndConsumePendingEmailChange` (validates OTP via constant-time comparison, checks expiration, atomically deletes record on success), and `UpdateEmail`. Updated `StartOTPCleanup` worker to periodically purge expired pending email changes.
    - `handlers/auth.go`: Implemented `POST /auth/email-change/request` (validates JWT, email format, non-sameness, and case-insensitive email uniqueness check against existing users; rate-limits by IP and user ID; generates 6-digit OTP and dispatches to new email) and `POST /auth/email-change/confirm` (validates 6-digit OTP, updates user email in MongoDB, consumes pending record, and issues fresh signed JWT token reflecting updated email claim).
    - `handlers/email_change_test.go`: Added unit test suite covering full lifecycle happy path, duplicate/taken email conflict (409), current email request (400), wrong/expired OTP (401), rate-limiting (429), and unauthenticated access (401).
  - **Frontend (Flutter)**:
    - `AuthProvider` (`frontend/lib/providers/auth_provider.dart`): Added `requestEmailChange(newEmail)` and `confirmEmailChange(otp)` methods with error handling, loading states, and automatic local user/token storage updates upon successful email confirmation.
    - `MyAccountScreen` (`frontend/lib/screens/my_account_screen.dart`): Replaced static read-only email note with an interactive "Change Email" action button triggering a two-step `EmailChangeDialog` (Step 1: enter new email -> call request endpoint; Step 2: enter 6-digit OTP code -> call confirm endpoint with dev_otp auto-fill support in local mode). Updated `myAccountEmailNote` and added localized strings in `app_en.arb` and `app_ar.arb`.
    - `my_account_screen_test.dart`: Added widget tests for the `EmailChangeDialog` flow (validation, request, OTP entry, success snackbar, and dialog dismissal).
- **Commit SHA**: ``217be08c0407a560bca20a89d556d2ab35442a35``
- **Verification**: Verified via Go unit test suite (`go test ./...` in `auth-service`, 100% pass), `flutter analyze` (0 issues found), `flutter test` (100% pass, 194/194 tests passed), `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## Owner Home Screen Settings Navigation Duplication Removal

- **Implementation Detail**:
  - **Duplicate Navigation Path Elimination (`frontend/lib/screens/home_screen.dart`)**: Audited role-branching logic in `home_screen.dart`. Removed the duplicate top AppBar settings `IconButton` (`key: const Key('settings_button')`) from the tabbed Owner role branch (`isOwner == true`), making Settings reachable exclusively via the bottom navigation bar (`owner_nav_tab_settings`).
  - **Preserved Non-Tabbed Fallback Access**: Retained the AppBar settings `IconButton` in the fallback non-tabbed branch (`!isOwner`) where no bottom navigation bar exists, preserving Settings access for basic/unrecognized roles.
- **Commit SHA**: ``20b66174a93713d3a5f35bdb2095614e863f0684``
- **Verification**: Verified via `grep -n "Icons.settings"` (0 duplicate access paths remaining), `flutter analyze` (0 issues found), `flutter test` (100% pass, 191/191 tests passed), `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## Enterprise UI/UX Polish & Frontend Hardening Pass

- **Implementation Detail**:
  - **1. Raw Numeric Coordinates Removal**: Replaced raw decimal coordinate strings (`"${_customerLat.toStringAsFixed(4)}, ${_customerLon.toStringAsFixed(4)}"`) across `customer_marketplace_screen.dart`, `job_status_screen.dart`, `employee_jobs_screen.dart`, and `service_screen.dart` with neutral map preview labels (`l10n.customerMarketplaceChooseMap`, `"📍 Delivery Location"`, `"📍 Service Location"`).
  - **2. Streamlined Marketplace Filter Bar**: Restructured `CustomerMarketplaceScreen` control panel into a clean 2-row layout separating Location/Radius controls from Category/Sort filters, preserving widget keys (`choose_location_map_button`, radius field, category, sort dropdowns) while eliminating visual crowding.
  - **3. WCAG AA Compliant Dark Mode Contrast Pass**: Replaced `ColorScheme.fromSeed` generated Material scheme in `quickDeliveryDarkTheme` (`lib/core/theme.dart`) with explicit, hand-tuned dark mode color scheme tokens (`surface: Color(0xFF0F172A)`, `onSurface: Color(0xFFF8FAFC)` with 15.8:1 contrast, `onSurfaceVariant: Color(0xFFCBD5E1)` with 10.5:1 contrast, `primary: Color(0xFFFFC107)` with 13.5:1 contrast, `scaffoldBackgroundColor: Color(0xFF0A0E17)`).
  - **4. Brand Name Translation Exclusion**: Consolidated fixed brand name constant `quickDeliveryAppName = 'Quick Delivery'` in `lib/core/constants.dart`. Removed localized `"appName"` from `app_en.arb` and `app_ar.arb` and updated composite string templates (`signupSubtitle`, `quickDeliveryDashboard`, `ownerHomeTabTitleDashboard`) to keep the brand name un-localized across all locales.
  - **5. Button Auto-Scaling & Multi-Line Text Wrapping**: Added `maxLines: 2` support and `FittedBox(fit: BoxFit.scaleDown)` font-size auto-scaling inside `PrimaryButton` and `SecondaryButton` to prevent long localized labels from truncating with ellipsis.
  - **6. Interactive Owner Image Upload Section**: Replaced raw text URL field `_photoUrlController` in `OwnerConfigurationScreen` with an interactive image upload container featuring a 64x64dp preview thumbnail card, placeholder fallback icon, image URL/path display, and `OutlinedButton.icon` (`owner_config_pick_image_button`) calling `_pickImage`.
  - **7. Form Validator Hardening & Accuracy Suite**: Audited and hardened form field validators across `signup_screen.dart`, `login_screen.dart`, `forgot_password_screen.dart`, and `employee_screen.dart`. Enforced precise email regex (`r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'`), 3-30 character username bounds with Arabic/Latin Unicode support (`r'^[a-zA-Z0-9_\s\u0600-\u06FF]+$'`), and clear localized error messages. Created unit test suite `frontend/test/form_validators_test.dart`.
- **Commit SHAs**: ``4396883a214a65551e97cc4a57a472227c82a2fa``, ``f669ab9c62b196c6d8d7366f979125b6fa1fb793``, ``1562d0cc584d9ee3927b8ebfa3cae49c38250e92``, ``e76082644256a7472bede50605cf21682a89fb20``, ``5f428f86256b5c0772739a0a1f471f01567c8958``, ``e393590a96f825526c0c832795700417efe446bc``, ``5962e9d0b6025dcf5af3ee0155e746bc9d9b2737``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (100% pass, 191/191 tests passed), `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## Phase 5 Performance Perception & Skeleton Loading States (UI/UX Roadmap)

- **Implementation Detail**:
  - **Skeleton Shimmer Primitive (`frontend/lib/widgets/skeleton_loader.dart`)**: Built reusable shimmer placeholder animation block (`SkeletonLoader`) driven by `AppMotion.durationSlow` loop animation and `AppColors.outlineVariant` gradient sweep. Accepts configurable width, height, and border radius (`AppRadius`) parameters.
  - **Per-Screen Card Geometry Skeletons**: Built 4 exact-geometry card skeleton widgets matching real card dimensions, padding, avatars, and layout bounds: `MarketplaceCardSkeleton`, `HomeDashboardSkeleton`, `EmployeeJobCardSkeleton`, and `WalletScreenSkeleton`.
  - **Animated Cross-Fade Transitions**: Wired `AnimatedSwitcher` (`AppMotion.durationMedium`, `AppMotion.curveStateChange`) across initial async loading states in `customer_marketplace_screen.dart`, `home_screen.dart`, `employee_jobs_screen.dart`, and `wallet_screen.dart`. Preserved existing `RefreshIndicator` pull-to-refresh spinner behavior for subsequent updates.
  - **Widget & Unit Test Suite (`frontend/test/skeleton_loader_test.dart`)**: Created 9 widget & state transition tests verifying skeleton rendering on initial load, provider state transitions, and smooth cross-fade to real content.
- **Commit SHA**: ``cf957f56a6342a9f02dfb1d9afbe61b1004ed881``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (100% pass, 186/186 tests passed), live backend health check against `https://api.logiclinkeg.tech/health` (HTTP 200 OK), `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## ADR-0017 Zero-Commission Subscription-Only Revenue Model & Gateway Readiness

- **Implementation Detail**:
  - **Zero-Commission COD Completion**: Created `CompleteCODJob` in `store/mongodb.go` for pure cash collection logging with 0 wallet mutation. Updated `CompleteJob` COD path and `ResolveReconciliation` to log collection timestamps without wallet balance deduction.
  - **100% Electronic Payment Credits**: Updated `ReleaseEscrowWithSplit` in `store/mongodb.go` to release 100% of escrow balance to tenant owner withdrawable balance with 0% platform commission. Set default platform fee percentage to 0.0%.
  - **Owner Payout Request Capability**: Added `PayoutRequest` model, `payout_requests` MongoDB collection, and store methods (`CreatePayoutRequest`, `GetPayoutRequests`). Exposed endpoints `POST /users/wallet/payout/request` and `GET /users/wallet/payout/requests` with IDOR owner authorization and withdrawable balance checks.
  - **Gateway-Ready Feature Flag**: Added `ELECTRONIC_PAYMENTS_ENABLED` feature flag to `config.go` (defaulting to `false`). Gated non-COD payment methods in `TrackJob`.
  - **Test Suite (`services/user-service/internal/handlers/payout_and_cod_zero_fee_test.go`)**: Built unit tests `TestCODZeroFeeCompletion`, `TestOwnerPayoutRequestFlow`, and `TestElectronicPaymentsFeatureFlag`. Updated `escrow_state_audit_test.go` and `handlers_test.go` for 0% commission assertions.
- **Commit SHA**: ``63d300dbca13738da64edaaa18ec9d43292e0e44``
- **Verification**: Verified via `gofmt`, `go build`, `go vet`, and `go test -v ./...` (100% test pass). ✅

## Phase 15 (b) Customer Home Redesign & (d) Employee Capability Audit & Screen Redesign (ADR-0014)

- **Implementation Detail**:
  - **Employee Capability Audit (`docs/frontend/EMPLOYEE_CAPABILITY_AUDIT.md`)**: Audited all 11 employee-gated backend endpoints across `user-service`, `auth-service`, `notification-service`, and `chat-service`. Identified 2 reachability gaps in `EmployeeJobsScreen`: (1) Employee Chat missing card action button, and (2) Verification Upload (`POST /auth/kye/upload`) missing entry point. (Commit `8afbc4c`).
  - **Customer Home 4-Tab Redesign (`frontend/lib/screens/customer_home_screen.dart`)**: Restructured customer role interface around a persistent 4-tab bottom navigation bar (`NavigationBar` with `IndexedStack` lazy tab hydration preserving scroll positions). Tabs: Home (dashboard with greeting, 4 quick access category tiles for Delivery, Ride, Shipping, and Browse All, recent activity summary card, and quick booking banner), Services (relocated marketplace directory), History (relocated customer orders list), and Settings. Embedded persistent top app bar with notification bell. (Commit `ebdbf1a`).
  - **Employee Capabilities Screen Redesign (`frontend/lib/screens/employee_jobs_screen.dart`)**: Resolved reachability gaps by adding Verification Documents icon button (`key: Key('employee_verification_button')`) in AppBar navigating to `KycDocumentUploadScreen` and Chat button (`key: Key('employee_chat_button_<job_id>')`) on active job cards navigating to `ChatScreen`.
  - **Widget & Unit Tests**: Created `frontend/test/customer_home_screen_test.dart` and `frontend/test/employee_jobs_screen_audit_test.dart`.
- **Commit SHAs**: `8afbc4c` (Audit), `ebdbf1a` (Implementation)
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (126/126 full test suite pass), live backend health check against `https://api.logiclinkeg.tech`, and `make docs-check`. ✅

## Self-Service Profile Update & Frequent Addresses (PATCH /auth/user - ADR-0014)

- **Implementation Detail**: Extended `User` model (`services/auth-service/internal/models/models.go`) with `FrequentAddresses []string` and added `UpdateProfileRequest` DTO. Built `PATCH /auth/user` handler in `auth-service` (`services/auth-service/internal/handlers/auth.go`) allowing authenticated users to update their `username`, `phone`, and `frequent_addresses` (capped at max 10 entries). Enforced strict IDOR protection by deriving target user ID solely from validated JWT claims (rejecting mismatched payload user IDs with 403 Forbidden) and stripping/ignoring sensitive field smuggling (`email`, `password`, `role`, `kyc_status`). Created test suite in `services/auth-service/internal/handlers/user_profile_test.go`. Regenerated `docs/APPLICATION_MAP.md` via `make docs`.
- **Commit SHA**: ``ad55855bf797c7c4acbf840a2a42f8a0c8483ca2``
- **Verification**: Verified via `gofmt -w .`, `go build ./...`, `go vet ./...`, `go test ./...`, `gosec`, and `make docs-check`. ✅

## Service Model Owner Configuration Fields & UpdateService Handler (ADR-0014)

- **Implementation Detail**: Extended `Service` model (`services/user-service/internal/models/models.go`) with `PhotoURL`, `Address`, `WorkingHours`, and `CoverageRadiusKM`. Extended `CreateServiceRequest` and added `UpdateServiceRequest` DTOs. Built `UpdateService` handler in `user-service` (`services/user-service/internal/handlers/handlers.go`) and MongoDB store (`UpdateService`), supporting `PUT /users/services` and `POST /users/services/update` with KYC approval checks and IDOR tenant ownership protection. Built unit test suite (`services/user-service/internal/handlers/service_owner_config_test.go`) verifying service creation with new fields, updating existing service fields, backward compatibility for legacy payloads omitting new fields, and IDOR protection. Regenerated `docs/APPLICATION_MAP.md` via `make docs`.
- **Commit SHA**: ``405d0de263d2f8fd6e554800caa565b7cf311238``
- **Verification**: Verified via `gofmt -w .`, `go build ./...`, `go vet ./...`, `go test ./...`, and `make docs-check`. ✅

## Interactive Map-Based Location Picker (ADR-0014 Decision #5)

- **Implementation Detail**: Implemented interactive map-based location picker replacing legacy Latitude/Longitude text input fields in `customer_marketplace_screen.dart`. Created reusable `LocationPickerMap` widget (`frontend/lib/widgets/location_picker_map.dart`) built with `flutter_map`, `latlong2`, and `geolocator`. Reused `requestLocationPermission()` helper from `core/location_permission.dart` for a "Use My Location" re-center button (defaulting to Cairo `30.0444, 31.2357` if permission is denied or service disabled). Integrated into `customer_marketplace_screen.dart` via a centered Dialog presenting the interactive map and a "Confirm Location" button, updating latitude/longitude state used by `fetchServices()` and job booking navigation while preserving compact Radius (KM) input. Created widget tests in `frontend/test/location_picker_map_test.dart` and `frontend/test/customer_marketplace_screen_test.dart`.
- **Commit SHA**: ``0e355d5fa55f61579beaacf53c130c741ee6918d``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (117/117 full test suite pass), `make docs-check`, and `.githooks/pre-push` gate validation. ✅

## Unified Settings Screen (Account Action Center) & Theme Persistence (ADR-0014 Part 1)

- **Implementation Detail**: Implemented Part 1 of the Unified Settings screen per ADR-0014. Created `ThemeProvider` (`frontend/lib/providers/theme_provider.dart`) managing dynamic `ThemeMode` (Light, Dark, System) and persisting choices across app restarts via `FlutterSecureStorage` under key `theme_mode`. Wired `ThemeProvider` into `main.dart` `MultiProvider` and `MaterialApp`. Created `SettingsScreen` (`frontend/lib/screens/settings_screen.dart`) featuring: (1) 3-way SegmentedButton theme mode selector, (2) Language row with "Coming Soon" badge and feedback snackbar, (3) Role-conditional sections ("Owner Configuration" for owner, "My Account" for customer/user, omitted for employee) with "Coming Soon" badges, (4) Support section ("Customer Service") with coming-soon feedback and `// TODO: wire to POST /chat/tickets once built` comment, and (5) Centralized red Logout button calling `logoutAndClearProviders`. Replaced duplicated Logout buttons in `home_screen.dart`, `customer_marketplace_screen.dart`, and `employee_jobs_screen.dart` with a single Settings gear icon. Created unit/widget test suite in `frontend/test/settings_screen_test.dart`.
- **Commit SHA**: ``88a392ebe86aabe97315c95cab6f56be3234cee5``
- **Verification**: Verified via `flutter analyze` (0 issues found) and `flutter test` (112/112 unit & widget tests pass cleanly). ✅

## Frontend Batch 1 Auth & Token Lifecycle Wiring

- **Implementation Detail**: Implemented full Auth & Token Lifecycle wiring (Batch 1 of `FRONTEND_INTEGRATION_SCOPE.md`). Updated `ApiClient` (`frontend/lib/core/api_client.dart`) with a concurrency-locked HTTP 401 response interceptor that executes silent `/auth/refresh` calls using current JWT, retries original requests on success, and invokes `onAuthFailed` on failure. Extended `AuthProvider` (`frontend/lib/providers/auth_provider.dart`) with `logout()` (calling `POST /auth/logout` and unregistering FCM device token), `forgotPassword(email)` (calling `POST /auth/forgot-password`), and `resetPassword(email, otp, newPassword)` (calling `POST /auth/reset-password`). Created `ForgotPasswordScreen` and `ResetPasswordScreen` following existing OTP/themed UI conventions (`ThemedTextField`, `PrimaryButton`, `ThemedErrorBanner`). Added "Forgot password?" link to `LoginScreen` and wired `logoutAndClearProviders` across all main role screens (`home_screen.dart`, `customer_marketplace_screen.dart`, `employee_jobs_screen.dart`). Updated `STATUS.md` file tracking index. Verified end-to-end against live backend at `https://api.logiclinkeg.tech`.
- **Commit SHA**: ``272294b8b51621928c08c7ee649c0d8e65255889``
- **Verification**: Verified via `flutter test` (46/46 full suite pass), `flutter analyze` (0 issues), live backend `curl` responses (`POST /auth/forgot-password` 200 OK, `POST /auth/reset-password` 401 on invalid OTP, `POST /auth/refresh` 401 on invalid JWT, `POST /auth/logout` 401 on invalid JWT), and pre-push hook validation (`.githooks/pre-push` gate exit code 0). ✅

## Frontend Owner Escrow Reconciliation Review Screen & Provider Implementation

- **Implementation Detail**: Implemented Flutter frontend Owner Escrow Reconciliation Review screen and provider consuming backend endpoints `GET /users/jobs/reconciliation-queue` and `POST /users/jobs/reconciliation-resolve`. Created `ReconciliationJob` model (mapping `escrowFailureReason` to human-readable explanations like "Distance mismatch — under 70% of booked distance"), `ReconciliationProvider` (with queue fetching and resolution execution, surfacing 409 conflict and 429 rate-limit responses explicitly), and `OwnerReconciliationQueueScreen` (card list with detailed notes, locked escrow amounts, empty/loading states, and confirmation dialogs before fund movement). Wired provider in `main.dart` and added navigation entry points in `home_screen.dart` (AppBar icon & dashboard metric card).
- **Commit SHA**: ``cd94f15851ca13b561f05aad65b424e598461f22``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test test/reconciliation_queue_test.dart` (5/5 widget tests pass), `flutter test` (all pass), `make docs-check`, and `.githooks/pre-push` gate (exit code 0). ✅

## Admin/Owner Escrow Reconciliation Review Endpoints Implementation

- **Implementation Detail**: Implemented owner/admin escrow reconciliation queue review and resolution endpoints in `user-service`. Added `GET /users/jobs/reconciliation-queue` for tenant owners to list jobs in status `escrow_reconciliation_required` with full context (`ReconciliationNote`, `EscrowFailureReason`, `LockedEscrowAmount`). Added `POST /users/jobs/reconciliation-resolve` accepting resolution decisions (`release_to_employee` or `refund_to_customer`), executing fund release/refund via existing wallet/escrow methods, updating job status and reconciliation fields, and shipping security audit events (`ESCROW_RECONCILIATION_RESOLVED`). Enforced strict owner role gating (`resolveTokenWithRole`), tenant isolation IDOR protection, identity-based rate limiting (30 req/min), and status idempotency (409 Conflict on double resolution). Added `{owner_id, status}` index to MongoDB store (`GetReconciliationQueueByOwner`). Updated ADR-0007 tradeoffs to reflect completed Redis throttle migration.
- **Commit SHA**: ``cba5f6c82dcd85cd4192261f5c9d973b12faaf21``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run "TestGetReconciliationQueue|TestResolveReconciliation"` (8/8 subtests pass), `go test ./services/user-service/internal/handlers/...` (all pass), `make docs-check`, `gofmt -l .`, and `.githooks/pre-push` gate (exit code 0). ✅

## ADR-0008 Live Employee Map Tracking Backend & End-to-End Verification

- **Implementation Detail**: Implemented backend support for ADR-0008 Live Employee Map Tracking across microservices. Extended `canAccessChannel` in `services/chat-service/internal/handlers/chat.go` to authorize `"fleet:<owner_id>"` channel subscriptions for users with the `"owner"` role. Wired `UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go` to send background HTTP location broadcast POST requests to `chat-service` for BOTH `"job:<job.ID>"` and `"fleet:<job.OwnerID>"`. Added `active_only=true` query filtering to `GET /users/jobs/owner` for initial fleet hydration. Added `CurrentLocation` field to `OwnerJobResponse` DTO and `NewOwnerJobResponse` mapping. Built `TestADR0008_E2E_LiveEmployeeMapTracking` non-mocked integration test verifying real WebSockets connections, `"fleet:<owner_id>"` channel subscription authorization, and real-time location update broadcasts. Updated ADR-0008 status to Accepted.
- **Commit SHA**: ``17ebd52e1d88246c5141f793abfd08c5515cc133``
- **Verification**: Verified via `go test ./services/chat-service/...` (`TestCanAccessChannel` 11/11 subtests pass), `go test ./services/user-service/...` (`TestADR0008_E2E_LiveEmployeeMapTracking` passes cleanly), `gofmt -l .`, `make docs-check`, `flutter analyze` (0 issues), and `flutter test` (10/10 tests pass). ✅

## ADR-0008 Live Employee Map Tracking Frontend Implementation

- **Implementation Detail**: Implemented ADR-0008 Flutter frontend screens, provider, and models for live employee map tracking using `flutter_map` (v7.0.2) and OpenStreetMap raster tiles with required custom `User-Agent` header (`QuickDeliveryApp/1.0`) and configurable compile-time tile URL template (`MAP_TILE_URL`). Created `OwnerFleetMapScreen` for tenant owners (subscribing to `fleet:<owner_id>` WebSocket stream with initial state hydration via `GET /users/jobs/owner`) and `CustomerJobMapScreen` for customer active job tracking (subscribing to `job:<job_id>` WebSocket stream with initial state hydration via `GET /users/jobs/get`). Added `MapTrackingProvider` with initial HTTP hydration and WebSocket streaming, exponential backoff reconnection, and connection status banners.
- **Commit SHA**: ``7e3c3eb59faaab14f1d576ac217a50e221e3e116``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (6 new widget unit tests in `map_tracking_test.dart` passing cleanly). ✅

## Negotiable Transport Pricing Handler Wiring & Endpoints

- **Implementation Detail**: Updated `TrackJob` for `transport` category services to initialize `JobStatusAwaitingPriceResponse`, compute `SuggestedPrice`, validate optional customer initial proposal, and defer escrow locking. Added endpoints `POST /users/jobs/propose-price` (single-shot proposal enforcement, ±50% bound check, 5m expiry timer) and `POST /users/jobs/respond-price` (accept sets `AgreedPrice` and activates job; decline cancels with `price_disagreement`). Implemented lazy proposal expiry in `GetJob` and proposal endpoints. Added unit test suite `TestNegotiableTransportPricing`.
- **Commit SHA**: ``036901ba292a73d2bf67cd14603f643d5d25e74c``
- **Verification**: Verified via `gofmt -l .`, `go vet ./...`, `go test ./... -v -race -count=1`, `make docs-check`, and pre-push CI gate. ✅

## Negotiable Transport Pricing Data Model Foundation

- **Implementation Detail**: Added negotiable pricing fields to `Job` struct (`SuggestedPrice`, `ProposedPrice`, `ProposedBy`, `AgreedPrice`, `PriceProposalExpiresAt`), defined explicit `JobStatusAwaitingPriceResponse` enum state, and implemented `ValidPriceProposal` validation helper enforcing bounds $[0.5 \times P_{\text{system}}, 1.5 \times P_{\text{system}}]$.
- **Commit SHA**: ``beac4e3030b1909cbc08ee6cdefe32923198b185``
- **Verification**: Verified via `go test ./... -v -race -count=1` from `services/user-service` passing all table-driven unit tests. ✅

## Owner Employee Listing Endpoint (GET /auth/employees)

- **Implementation Detail**: Added GET /auth/employees endpoint letting tenant owners list all employees registered under their account. Authenticated via JWT (Authorization Bearer header or owner_token query parameter), IDOR-protected by resolving owner ID directly from claims, returns employee ID, username, email, is_active status (including frozen accounts), and created_at while omitting sensitive fields. Protected by Redis-backed rate limiting (30 req/min per owner).
- **Commit SHA**: ``13e6c2b832667cec57135811e3a122727b730eea``
- **Verification**: Verified via auth-service unit tests (TestGetEmployees) and E2E curl testing against Docker stack. ✅

## COD Platform Fee Overdraft

- **Implementation Detail**: Deducts 15% platform fee directly from Owner e-wallet upon job completion, allowing negative balances.
- **Commit SHA**: ``6edf1b7c825b37cc15b16dbc348026c4b689724b``
- **Verification**: Verified in `user-service/internal/store/mongodb.go`. ✅

## Rating & Comment System

- **Implementation Detail**: Rating and comment submissions on completed jobs with average rating queries.
- **Commit SHA**: ``6edf1b7c825b37cc15b16dbc348026c4b689724b``
- **Verification**: Verified in `user-service/internal/handlers/handlers.go`. ✅

## Job Cancellation & Escrow Refund

- **Implementation Detail**: Added job status cancelled, CancelJob handler, validation checks, and automatic escrow refund to owner.
- **Commit SHA**: ``6edf1b7c825b37cc15b16dbc348026c4b689724b``
- **Verification**: Verified via user-service integration tests. ✅

## Live Location Tracking

- **Implementation Detail**: Broadcast real-time employee locations via WebSockets to owner and client.
- **Commit SHA**: ``6b473a730fa632e45dea42335c2b899488e0aad3``
- **Verification**: Verified via integration tests and E2E simulation. ✅

## Redis Rate Limiting Stage 1: Wrapper & Config

- **Implementation Detail**: Created shared ratelimit package wrapping Redis client with atomic Lua scripts, and updated all 5 config packages to load REDIS_URI.
- **Commit SHA**: ``b8e33bf7f793d6bcf4a67927a4db4bc182daf275``
- **Verification**: Verified via compilation and unit tests. ✅

## Redis Rate Limiting Stage 2: api-gateway

- **Implementation Detail**: Migrated the api-gateway edge rate limiter to use the Redis-backed wrapper.
- **Commit SHA**: ``198123af7a0597195afc587c036b29bd42ee15b3``
- **Verification**: Verified via compilation. ✅

## Redis Rate Limiting Stage 3: auth-service

- **Implementation Detail**: Migrated the auth-service dual-key (IP + email) rate limiter to use Redis.
- **Commit SHA**: ``a1011c78986282bc86368cac253804b2b04a79d5``
- **Verification**: Verified via compilation and test execution. ✅

## Redis Rate Limiting Stage 4: chat, user & notification services

- **Implementation Detail**: Migrated rate limiters in chat, user, and notification services to use Redis-backed wrapper.
- **Commit SHA**: ``315a0aa7cf056b4782759c5b6c5c75d46792e5e5``
- **Verification**: Verified via compilation and test execution. ✅

## Redis Rate Limiting Stage 6: Verification & Concurrency Tests

- **Implementation Detail**: Created concurrency and cross-instance rate limit tests, and ran full test suite verification.
- **Commit SHA**: ``a24759a6621f053c202fdcfeded9e0c1117be9c8``
- **Verification**: Verified via integration and concurrency tests. ✅

## Resilience Stage 1: Wrapper Client

- **Implementation Detail**: Created shared resilience package implementing retry-with-backoff + jitter and circuit-breaker wrapper around http.Client.
- **Commit SHA**: ``d44b18ef176d2a3877d065376f67ecad374afe27``
- **Verification**: Verified via compilation. ✅

## Resilience Stage 2 & 3: Wiring & Fail-Closed Errors

- **Implementation Detail**: Wired separate circuit breaker and retry instances into internal HTTP clients and proxies, returning 503 Service Unavailable and failing closed on timeouts.
- **Commit SHA**: ``d81e578f9c6c7042cea715d7f6eba8a57922764f``
- **Verification**: Verified via compilation and test execution. ✅

## Resilience Stage 4: Observability & Health Integration

- **Implementation Detail**: Configured structured logs for circuit breaker transitions and exposed dependency breaker status on /health endpoints.
- **Commit SHA**: ``c6a6013cd021e518650a80280b29aa6d298f8c95``
- **Verification**: Verified via compilation and test execution. ✅

## Resilience Stage 5: Resilience Tests & Verification

- **Implementation Detail**: Created unit and integration tests verifying retry limit capping, circuit breaker trip/recovery transitions, and fail-closed security properties.
- **Commit SHA**: ``c7a5049f90956626b333ea1fbaf1dfcc593fc5b4``
- **Verification**: Verified via integration tests. ✅

## Complaint Routing Stage 1: Data Model

- **Implementation Detail**: Added database collections, Go model structs, and indexes for support agents and complaint tickets in chat-service store.
- **Commit SHA**: ``d4d6e95a5a2d2dec1ca4ed2cc0b91ddc5ac41a0c``
- **Verification**: Verified via compilation. ✅

## Complaint Routing Stage 3, 4, 5: WebSocket & HTTP Wiring

- **Implementation Detail**: Wired complaint ticket channel/access checks into chat WebSocket/Hub, added structured security audit logging, and applied Redis rate limiter.
- **Commit SHA**: ``e211e6dc8c79bf271e66f6fe63b54e5d38598a28``
- **Verification**: Verified via compilation. ✅

## Complaint Routing Stage 6: Concurrency & Access Tests

- **Implementation Detail**: Added unit and concurrency tests proving atomic support agent assignment, queueing, and IDOR mitigation for ticket access.
- **Commit SHA**: ``16dc62ede98c8bb0ce5aaf41ceea267e0cbe11c7``
- **Verification**: Verified via test execution. ✅

## KYB/KYE Data Model

- **Implementation Detail**: Extended auth-service User model to support IDFrontDoc, IDBackDoc, SelfieDoc, BusinessProofDoc, and review metadata.
- **Commit SHA**: ``d4d6e95a5a2d2dec1ca4ed2cc0b91ddc5ac41a0c``
- **Verification**: Verified via compilation. ✅

## KYB/KYE Local Storage

- **Implementation Detail**: Created local-disk storage implementation (securing document files on disk and generating short-lived signed token URLs).
- **Commit SHA**: ``2fc19e412253afda248acab62720bdaa2bbe9da4``
- **Verification**: Verified via compilation. ✅

## KYB/KYE Uploads & Reviews

- **Implementation Detail**: Implemented file validation, multipart uploads, pending submissions list, review gating, signed document views, and audit logging.
- **Commit SHA**: ``35dab58ce5cc4150e778b32c1ca66c66de43431e``
- **Verification**: Verified via integration tests. ✅

## Reviewers Collection

- **Implementation Detail**: Added reviewers collection, unique token indexing, and query/insert methods in auth-service store.
- **Commit SHA**: ``1f46ed23763eca30135f43afdd0f52589174ec0f``
- **Verification**: Verified via compilation. ✅

## Username Field & Validation

- **Implementation Detail**: Added `Username` field to the `User` model and `SignupRequest` structs (required, not omitempty). Added a validation check to `Signup` handler requiring 3-30 character username length (measured by runes to support multi-byte strings) and allowed character whitelist supporting both Latin and Arabic scripts (U+0600–U+06FF) alongside spaces, digits, and underscores, while blocking unsafe injection strings. Enforced global uniqueness on `username` via a MongoDB unique index in `ensureIndexes`, returning clear, differentiated errors (`username already taken` vs `email already registered`) on duplicate key conflicts.
- **Commit SHA**: ``7fa065a742bb209cfc8fe9e0a13a960495066bf0``
- **Verification**: Verified via `TestSignupUsernameValidation` covering success, missing, short/long, invalid chars, valid Arabic, mixed Arabic/Latin, XSS tag rejection, and differentiated duplicate-key errors. ✅

- **Implementation Detail**: Updated `GET /auth/user` response to return `username`. Updated `GET /auth/kyb-kye/pending` (`GetPendingKYBKYESubmissions`) response to return `username` per submission. Updated `chat-service` to cache usernames upon WebSocket handshake (refreshed at connection init time or every 60 seconds on cache expiry), attach it to WebSocket clients, and embed `sender_username` inside real-time messages and the persisted database schema as a point-in-time snapshot captured at send-time (historical messages preserve the username active when sent). Support agents are assigned a fallback display name matching `Agent <agent_id>` because they are system operators who do not have a standard `models.User` record.
  On the frontend: added a username input field to the signup and employee registration forms with rune-aware length check and dynamic RTL text direction detection for Arabic script input. Updated `UserProfile` and `ChatMessage` Dart models to parse `username` and `sender_username` respectively. Propagated the username display to the chat screen (with agent/legacy user fallbacks), home dashboard banners, profile detail tables, and employee dashboard screen.
  
  *Security & Minimal Disclosure Design*: To resolve employee usernames on the job status screen client-side without exposing sensitive attributes (such as `kyc_status`, `role`, `tenant_id`, `email`), a scoped public profile endpoint (`GET /auth/user/public-profile`) was introduced. It requires a valid signed requester token and returns only the target user's `id` and `username` (public display name lookups are allowed, but sensitive account data is strictly protected from disclosure).
- **Commit SHA (backend)**: `0c7930212a897a3f31daa42dab802597089fd0f5`
- **Commit SHA (frontend)**: `74ffbb7e4d269c405b6caff4c883459430508e22`
- **Verification**: Verified via backend integration tests in `auth-service` and `chat-service`, and Flutter widget tests in `widget_test.dart` asserting signup validation logic and chat sender name rendering. ✅

## Programmatic Dark Theme

- **Implementation Detail**: Added programmatic dark theme support to the Flutter frontend application using `quickDeliveryDarkTheme`. Seeded the dark scheme from `Color(0xFF0D1321)` with `Brightness.dark`, overriding the `secondary` role to preserve the brand gold (`Color(0xFFFFC107)`). Configured `MaterialApp` with both light and dark themes and set `themeMode` to `ThemeMode.system`.
- **Commit SHA**: ``149c3a823908a144511f1226767f17d4505ee80b``
- **Verification**: Verified via `flutter analyze` and widget tests confirming clean compilation and theme initialization. ✅

## Server-Sent Events Notifications

- **Implementation Detail**: Built the SSE notifications screen (Phase 6 - SSE) on the frontend. Created `NotificationModel` and `NotificationsProvider` to subscribe to the API Gateway proxied SSE stream `/notifications/stream?token=<token>` using the `flutter_client_sse` package. Implemented `NotificationsScreen` with category chip filtering, chronological group splits (Today, Yesterday, Earlier), dynamic connection status/errors banner, and deep-link tracking to `JobStatusScreen`. Registered the provider in `main.dart` and added a notification bell icon with an unread badge to dashboard AppBars in `home_screen.dart`, `customer_marketplace_screen.dart`, and `employee_jobs_screen.dart`.
- **Commit SHA**: ``a025ecebaad7edfeeb4f2dd7f620856c664d7cf9``
- **Verification**: Verified via `flutter analyze` and widget tests checking clean compilation, state mapping, and setup. ✅

## Subscription Plans Screen

- **Implementation Detail**: Built the Subscription screen (Phase 7 - Ratings & Subscriptions) on the frontend. Created `SubscriptionScreen` and wired it to `OwnerProvider.updateSubscription` to interact with POST `/users/subscription`. Displays the current subscription tier, supports instant downgrades/switches to the Free Plan, and alerts/warns the user when the Professional Plan is selected and activation is pending manual approval. Integrated the page navigation as a tap interaction on the "Subscription Tier" dashboard card in `home_screen.dart`.
- **Commit SHA**: ``eed6786bb28254b553cd272e6d979c18ff58abfb``
- **Verification**: Verified via `flutter analyze` and widget tests checking clean compilation and metric integration. ✅

## Blind Rating Screen

- **Implementation Detail**: Built the Blind Rating screen (Phase 7 - Ratings & Subscriptions) on the frontend. Created `RatingScreen` supporting 1-5 star score selection and text comment inputs. Wired it via `MarketplaceProvider.rateJob` to query POST `/users/jobs/rate`. Implemented a fallback in the backend handler `RateJob` so that it accepts the raw ratee user ID directly when JWT resolution fails, correcting a design gap where the frontend previously had to pass the other party's private token. Queries the user's received ratings via GET `/users/ratings` to dynamically determine if the partner has rated the job, displaying a live blind status card. Added the navigation trigger button to `JobStatusScreen` for completed jobs.
- **Commit SHA**: ``8d3d17752486b92d71435108f6803e4ac22d07d9``
- **Verification**: Verified via backend unit tests (`TestUserServiceHandlers`) and frontend static analysis + widget tests. ✅

## Rating Summary Component

- **Implementation Detail**: Built the reusable `RatingSummaryCard` (Phase 7 - Ratings & Subscriptions) on the frontend. Renders an average star rating using full, half, and empty icons, alongside a total review count. Embedded the component inside the Owner dashboard welcome panel to show service reputation, and inside Customer Marketplace service cards to highlight carrier trustworthiness.
- **Commit SHA**: ``f01d25be38c7d0cdd70f59ca696c043e2f0db08e``
- **Verification**: Verified via `flutter analyze` and widget tests confirming clean layout integration. ✅

## Request Field Token Aliases

- **Implementation Detail**: Added clearer `_token` field name aliases alongside legacy `_id` and raw parameter names across Go backend handlers (`user-service` and `auth-service`) to resolve naming clarity issues (since these fields carried signed JWT tokens instead of raw database IDs). Implemented alias mappings for: `user_token` (as alias for `user_id` / `id`), `owner_token` (as alias for `owner_id`), `employee_token` (as alias for `employee_id`), `requester_token` (as alias for `requester_token`), `tenant_token` (as alias for `tenant_id`), and `rated_by_token`/`rated_user_token` (as aliases for `rated_by`/`rated_user`). Enforced backward compatibility by resolving either variant, preferring the new naming. Updated API generator `KnownEndpoints` descriptions and updated `APPLICATION_MAP.md` via `make docs`.
- **Commit SHA**: ``f967906b413fedadc38dae163766697c9e7aeb60``
- **Verification**: Verified via backend integration test suites (`TestTokenNameAliasesCompatibility` in `user-service`, `TestTokenNameAliasesInAuth` in `auth-service`) and local `make docs-check`. ✅

## Resend Email OTP Dispatcher

- **Implementation Detail**: Implemented `ResendDispatcher` in `services/auth-service/internal/otp/resend_dispatcher.go` to dispatch 2FA and signup OTP codes via the Resend REST API (`POST https://api.resend.com/emails`). Configured non-local mode (`APP_ENV!=local`) to activate `ResendDispatcher` when `RESEND_API_KEY` is present and fall back to `MockSMSDispatcher` with a warning when omitted. Preserved `MockSMSDispatcher` for local development (`APP_ENV=local`). Input parameters and log outputs are sanitized against carriage return/newline characters to prevent header and log injection vulnerabilities (satisfying gosec G704/G705/G706 rules). Added `RESEND_API_KEY` and `RESEND_FROM_EMAIL` configuration settings to `auth-service` and `infrastructure/.env.example`.
- **Commit SHA**: ``a95e5254d6b58706f6174a67187b0b722c43f711``
- **Verification**: Verified via unit tests (`TestResendDispatcher_Dispatch_Success`, `TestResendDispatcher_Dispatch_APIErrorResponse`, `TestResendDispatcher_Dispatch_NetworkError`, `TestResendDispatcher_Dispatch_InputSanitizationAndValidation`) using an `httptest.Server` mock, and full-scope gosec scanning. ✅

## Forgot Password & Reset Password Endpoints

- **Implementation Detail**: Implemented `POST /auth/forgot-password` and `POST /auth/reset-password` in `auth-service` reusing the existing AES-256-GCM encrypted OTP infrastructure (`SetOTP` / `VerifyOTP` in `mongodb.go`). `POST /auth/forgot-password` returns an anti-enumeration generic 200 OK response regardless of email existence, rate limits per IP and per email, generates/encrypts a 5-minute OTP code, and dispatches it via `a.dispatcher.Dispatch`. `POST /auth/reset-password` validates `email`, `otp`, and `new_password`, enforces IP/email rate-limiting lockouts, calls `store.VerifyOTP`, bcrypt-hashes the new password, updates the user password, and clears OTP fields (`otp_code`, `otp_verified`, `otp_expires_at`) to prevent replay attacks. Added unit test suite covering (a) identical anti-enumeration response for existing vs non-existent emails, (b) forgot-password rate limiting, (c) reset-password password update and old password failure, (d) invalid/expired OTP rejection with generic error & rate-limit recording, (e) missing password policy validation, and (f) OTP reuse prevention. Updated API map documentation via `make docs`.
- **Commit SHA**: ``ee443e39358b7f4c06fe7eb2f2a57b2f4e4c8d79``
- **Verification**: Verified via `go test -v ./internal/handlers -run "TestForgotPassword_|TestResetPassword_"` (6/6 pass) and `make docs`. ✅

## Job Completion Frontend Wiring

- **Implementation Detail**: Wired `POST /users/jobs/complete` into the Flutter frontend. Added `completeJob(String jobId)` method to `EmployeeJobsProvider` (`frontend/lib/providers/employee_jobs_provider.dart`) and rendered "Complete Job" action button in `EmployeeJobsScreen` (`frontend/lib/screens/employee_jobs_screen.dart`) exclusively for active/in-progress jobs. Features confirmation modal (`ConfirmActionDialog`), double-submission loading state, inline error banner via `friendlyErrorMessage`, and immediate job status update to COMPLETED. Added 4 widget tests (`frontend/test/employee_jobs_screen_test.dart`).
- **Commit SHA**: ``8f20aa6c78ec97ccf4adb605b57003743579880d``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (100% pass, 50/50 test cases). ✅

## Job Cancellation Frontend Wiring (POST /users/jobs/cancel)

- **Implementation Detail**: Wired `POST /users/jobs/cancel` into the Flutter frontend with strict role-specific and state-specific authorization logic. Added `cancelJob` method to `MarketplaceProvider` (`frontend/lib/providers/marketplace_provider.dart`) and `OwnerProvider` (`frontend/lib/providers/owner_provider.dart`). Created reusable `CancelJobDialog` (`frontend/lib/widgets/cancel_job_dialog.dart`) requiring a non-empty cancellation reason (confirm button disabled when empty). For tenant Owners: rendered "Cancel Job" buttons on `home_screen.dart` (Owner Dashboard) for pending and active jobs. For Customers: rendered "Cancel Job" button on `job_status_screen.dart` for pending jobs, and presented "Open a Complaint Ticket" affordance for active jobs with `// TODO` annotation referencing upcoming ticket endpoint wiring. Cancel buttons are completely omitted for completed and cancelled jobs. Added 6 widget tests in `frontend/test/job_cancellation_test.dart`.
- **Commit SHA**: ``c9e9c9cdbc8bdce1194098ccb5c4d67a4f457fa1``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (100% pass, 57/57 test cases). ✅

## Device GPS Location Permission Infrastructure (Part 1 of 2)

- **Implementation Detail**: Added `geolocator: ^12.0.0` dependency to `frontend/pubspec.yaml` (resolving cleanly without version conflicts against `web_socket_channel`). Configured foreground-only Android permission (`ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` in `AndroidManifest.xml`) and iOS permission (`NSLocationWhenInUseUsageDescription` in `Info.plist`). Created isolated `requestLocationPermission` helper utility (`frontend/lib/core/location_permission.dart`) returning unified `LocationPermissionResult` enum (`granted`, `denied`, `deniedForever`, `serviceDisabled`). Added unit test suite in `frontend/test/location_permission_test.dart` using `MockGeolocatorPlatform` with `MockPlatformInterfaceMixin` covering all permission result states.
- **Commit SHA**: ``0ee8e7858bcb87dd1e92bbcbc4c121155f673546``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (100% pass, 64/64 test cases). ✅

## Employee Screen Visual Redesign & Presentation Overhaul

- **Implementation Detail**: Redesigned `EmployeeJobsScreen` (`frontend/lib/screens/employee_jobs_screen.dart`) while retaining its single-screen sectional dashboard architecture. Upgraded solid gray `AppBar` to transparent header (`backgroundColor: Colors.transparent`, `elevation: 0`, `scrolledUnderElevation: 0`) matching owner and customer home screen navigation headers. Added top gradient welcome card featuring user profile badge and glanceable live GPS tracking status pill (`TweenAnimationBuilder` scale animation). Converted Action Simulator into interactive `ChoiceChip` selection chips for rapid event text population. Restructured `_buildJobCard` visual hierarchy with highlighted destination coordinates container, subordinate metadata chips (Customer ID, Payment Method, Escrow), and bottom action bar separating Real-time Chat (`key: Key('employee_chat_button_<job_id>')`) and Job Completion (`key: Key('complete_job_button_<job_id>')`). Preserved all key identifiers and directional RTL properties.
- **Commit SHA**: ``9a80b3f06df2bfe64efe1acc4ef2da5ab1bbaf23``
## Real-Time Job-Assignment Notifications End-to-End Wiring

- **Implementation Detail**: Wired up real-time job-assignment notifications end-to-end across `user-service`, `notification-service`, and the Flutter frontend. Added `NotificationServiceURL` configuration to `user-service/internal/config/config.go` (default `http://localhost:3004`). In `user-service/internal/handlers/handlers.go`, added `notificationClient` (`resilience.NewClient` with 2 retries and 5s timeout) and `broadcastJobAlert` non-blocking helper goroutine executing on `TrackJob` when an `EmployeeID` is assigned. The request includes `X-Internal-Token` header and JSON body `{tenant_id, job_id, employee_id, service_name, description}` without delaying or failing parent job creation. In `notification-service/internal/handlers/handlers.go`, updated `jobAlertRequest` and `BroadcastJobAlert` to accept `employee_id` and assign `UserID: req.EmployeeID` on `hub.Notification` so targeted push notifications work. On the frontend (`frontend/lib/screens/employee_home_screen.dart`), wired a `NotificationsProvider` listener to reactively call `_refreshData()` whenever a `job_alert` SSE event arrives. Added integration test suite `services/user-service/internal/handlers/job_alert_broadcast_test.go`.
- **Commit SHA**: ``6b7fd32e2db76f8ca7afb337b11ec633d4ab0104``
- **Verification**: Verified via `make ci` (0 issues across all Go services), `flutter analyze` (0 issues), `flutter test` (100% pass across 202 test cases), and `make docs-check`. ✅








