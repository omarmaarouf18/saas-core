# Bug Fixes Changelog

This file tracks historical entries for the primary category: **Bug Fixes Changelog**.

## Remediation of Stitch Mockup Freight & Warehousing Content Leak

- **Implementation Detail**:
  - **Root Cause**: The Stitch-derived UI redesign (commits `6856458` through `c8de30a`) used Google Stitch mockups as an implementation reference without a domain content-accuracy review pass before merging, causing generic freight, warehousing, loading bay/dock, and supply chain placeholder copy to leak into production Flutter code.
  - **`customer_home_screen.dart`**: Replaced generic freight/warehousing placeholder copy across category tiles with real quick delivery and home services copy ("Fast on-demand delivery for orders, packages, and essentials.", "Local ride booking, moving transport, and courier transport.", "On-demand home cleaning, maintenance, and handyman services.", "Browse all available home services and delivery options."). Updated category icon from `Icons.warehouse_outlined` to `Icons.home_repair_service_outlined`.
  - **`employee_jobs_screen.dart`**: Replaced "Pickup Depot / Loading Bay" and "Dock / Gate Access Verified" placeholder text with "Pickup Location" and "Client Address Confirmed".
  - **`employee_history_screen.dart`**: Replaced "Pickup Depot" and "Dispatched & Logged" with "Pickup Location" and "Order Dispatched".
  - **`job_status_screen.dart`**: Corrected misleading code comment `// Cargo load & vehicle spec` above payment details to `// Payment method & fare details`.
  - **`service_screen.dart`**: Replaced "Configure and monitor active logistics services." with "Configure and monitor active business services.".
  - **`theme.dart`**: Corrected comment tag from `Stitch Kinetic Logistics` to `Stitch Unified Theme`.
  - **`update_required_screen.dart`**: Updated "Enhanced security protocols for shipment tracking." to "Enhanced security protocols for order and delivery tracking.".
  - **`app_en.arb` & `app_ar.arb`**: Updated `ownerConfigNameHint` from "e.g. Quick Cargo Express" / "مثلاً: النسر للشحن السريع" to "e.g. Quick Delivery Services" / "مثلاً: النسر للخدمات السريعة".
  - **`shared_widgets_test.dart`**: Updated `RouteTimeline` widget tests to use realistic Egyptian address examples instead of US logistics parkway/dock/pallets mock data.
- **Commit SHA**: ``7de3442a319640c606d2612edbdfc8fe81e118c6``
- **Verification**: Verified via `flutter analyze` (0 issues), `flutter test` (100% pass, 260/260 tests passed), and literal grep proving zero remaining freight/warehousing/dock placeholder content in `frontend/lib/`. ✅

## Corrected Unauthorized Reintroduction of KYB/KYE Reviewer Screens (Re-Reverting Commit ab9073a)

- **Implementation Detail**:
  - **Enforcement of ADR-0013 Scope Boundary**: Re-reverted commit `ab9073ab497d26a30b67c4bcf53ae045eec5cab0` which had reintroduced administrative KYC/KYB reviewer interfaces into the consumer mobile app.
  - **Deleted Screens & Dialogs**: Removed `frontend/lib/screens/kyb_kye_review_screen.dart` and `frontend/lib/widgets/document_viewer_dialog.dart`.
  - **Provider Cleanup**: Removed `fetchPendingSubmissions`, `fetchDocumentBytes`, and `reviewSubmission` from `frontend/lib/providers/auth_provider.dart`.
  - **Navigation Routes Removed**: Removed `KybKyeReviewScreen` role-gated root route and `reviewer_queue_button` AppBar actions from `frontend/lib/screens/home_screen.dart`.
  - **Tests Removed**: Deleted `frontend/test/kyb_kye_review_screen_test.dart` (13 tests), returning consumer app test suite to 254 passing tests.
  - **Cross-Reference**: Documented in [ADR-0013](../adr/0013-support-agent-console-as-separate-client-application.md) addenda.
- **Commit SHA**: ``54baeb8df27334dd8c5167d72b79900f693ad1b6``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), and `flutter test` (100% pass, 254/254 tests passed). ✅

## Real-Time Communication, Map Tracking & Job Details (Consistency Audit Batch 5)

- **Implementation Detail**:
  - **`job_status_screen.dart`**: Migrated raw `TextField` with custom `InputDecoration` on counter-offer input to `ThemedTextField(key: const Key('counter_offer_input'), controller: _counterOfferController, prefixIcon: Icon(Icons.attach_money, size: AppIconSize.sm, color: AppColors.outline))` with inline `_proposalError` messaging.
  - **`rating_screen.dart`**: Replaced un-tokenized `AppTypography.bodyMd.copyWith(fontSize: 13, color: AppColors.onSurfaceVariant)` with canonical `AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant)`.
  - **`owner_history_screen.dart`**: Standardized TabBar typography to `AppTypography.bodySm.copyWith(fontWeight: FontWeight.bold)` and `AppTypography.bodySm` across both tab shells, and standardized spacing from magic numbers to `AppSpacing.xxs`.
  - **`customer_job_map_screen.dart`**: Replaced magic padding number `horizontal: 6` with canonical token `AppSpacing.xs`, removed un-tokenized `fontSize: 10` overrides from marker labels, adjusted Marker bounds to `60.0` with `MainAxisSize.min` Column to prevent flex overflows, and verified strict `AppColors` token adoption.
  - **`owner_fleet_map_screen.dart`**: Replaced raw `Colors.white` with `AppColors.onPrimary`, replaced magic padding `horizontal: 6` with `AppSpacing.xs`, removed `fontSize: 10` override, and standardized Marker bounds to `60.0` with `MainAxisSize.min`.
  - **`employee_home_screen.dart`, `employee_jobs_screen.dart`, `home_screen.dart`**: Removed `fontSize: 10` overrides on unread notification badges so standard `AppTypography.labelMd` applies.
- **Commit SHA**: ``b65b8a1f0100c4c7bd1db3758f842a1993c524d7``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), and `flutter test` (100% pass, 267/267 tests passed). ✅

## Attempted KYB/KYE Reviewer Screen Restoration (Subsequently Re-Reverted)

- **Implementation Detail**:
  - **Context**: Commit `ab9073ab497d26a30b67c4bcf53ae045eec5cab0` attempted to restore `KybKyeReviewScreen`, `DocumentViewerDialog`, `AuthProvider` reviewer methods, and `home_screen.dart` navigation routes under the mistaken impression that the original removal was an error.
  - **Re-Reversion**: Following explicit project owner reconfirmation of the ADR-0013 scope boundary, all restored reviewer screens, dialogs, routes, and provider methods were re-reverted and permanently removed from the consumer Flutter app binary.
- **Commit SHA**: ``ab9073ab497d26a30b67c4bcf53ae045eec5cab0``
- **Status**: Re-reverted.

## Owner Operations & Service Management (Consistency Audit Batch 4)

- **Implementation Detail**:
  - **`wallet_screen.dart`**: Replaced inline `_showPayoutRequestDialog` and `_showDepositDialog` implementations with standalone reusable `PayoutRequestDialog.show(context)` and `DepositFundsDialog.show(context)`, eliminating over 420 lines of inline boilerplate. Standardized transaction ledger job chip typography override from `fontSize: 10` to canonical `AppTypography.labelMd`.
  - **`owner_configuration_screen.dart`**: Standardized location picker map dialog header typography to `AppTypography.titleMd.copyWith(fontWeight: FontWeight.bold)`. Replaced raw `OutlinedButton.icon` location and photo picker buttons with canonical `SecondaryButton(key: Key(...), isOutlined: true, isFullWidth: false)`.
  - **`service_screen.dart`**: Replaced duplicate inline `_showCreateServiceDialog` implementations (~230 lines) in both the empty state and floating action button with `CreateServiceDialog.show(context, ownerId: user.id)`. Wired `ThemedSnackBar.showSuccess` and `ThemedSnackBar.showError`.
  - **`employee_screen.dart`**: Standardized registered worker roster items using `EntityAvatar(name: username, radius: 20)` and `StatusBadge`, and tokenized email and IP address typography to `AppTypography.labelLg` and `AppTypography.labelMd`. Applied `isDestructive: !_togSetActive` to `PrimaryButton` in worker freeze/unfreeze form. Replaced raw `AlertDialog` success popup with `ThemedSnackBar.showSuccess`.
  - **`owner_reconciliation_queue_screen.dart`**: Replaced raw error column and `ElevatedButton` with `ThemedErrorBanner(message: provider.error!, onRetry: () => provider.fetchQueue())`.
  - **`payout_request_dialog.dart`**: Extracted standalone 2-step payout request dialog widget supporting Step 1 (amount, method dropdown, account details) and Step 2 (warning confirmation banner, account preview) with `ThemedTextField`, `ThemedErrorBanner`, `ThemedSuccessBanner`, `PrimaryButton`, `SecondaryButton`, and responsive 360dp bounding.
  - **`deposit_funds_dialog.dart`**: Extracted standalone deposit dialog widget supporting amount input, validation (max 1M credits limit), error banner, Cancel, and Confirm `PrimaryButton` with responsive 360dp bounding.
  - **`create_service_dialog.dart`**: Extracted standalone create service dialog widget supporting service name, category dropdown, base price, price per KM, lat/lon bounds validation (-90..90, -180..180), Cancel, and Create `PrimaryButton` with responsive 360dp bounding.
- **Commit SHA**: ``8c864e4b3daabdffd58fe808ea7251efcd86c786``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (100% pass, 254/254 tests passed including new dedicated test suites `test/payout_request_dialog_test.dart`, `test/deposit_funds_dialog_test.dart`, and `test/create_service_dialog_test.dart`), and 360dp narrow viewport rendering tests. ✅

## Settings, Account & Notifications Center (Consistency Audit Batch 3)

- **Implementation Detail**:
  - **`settings_screen.dart`**: Removed bespoke `_segmentedButtonStyle` with hardcoded hex colors and font sizes; aligned `SegmentedButton` directly with canonical `SegmentedButtonThemeData` from `theme.dart`. Standardized section labels and button segment typography to `AppTypography.titleMd` and `AppTypography.labelLg`. Replaced raw `ElevatedButton.icon` with `PrimaryButton(key: Key('settings_logout_button'), text: l10n.settingsLogout, icon: Icons.logout, isDestructive: true)` providing built-in 600ms tap-debounce protection (`AppMotion.debounceGuard`) and destructive styling (`AppColors.error`).
  - **`my_account_screen.dart`**: Migrated raw "Change Email" `OutlinedButton.icon` to `SecondaryButton(key: Key('change_email_button'), isOutlined: true, isFullWidth: false)`. Migrated raw "+ Add Address" `ElevatedButton` to `PrimaryButton(key: Key('my_account_add_address_button'), isFullWidth: false)`. Extracted inline `EmailChangeDialog` into a standalone reusable widget file.
  - **`notifications_screen.dart`**: Replaced hand-rolled `AlertDialog` clear confirmation dialog with canonical `ConfirmActionDialog.show(context, isDestructive: true)`. Standardized delete icon sizes to `AppIconSize.sm` and added `AppMotion.debounceGuard` tap-debounce protection to notification card items.
  - **`email_change_dialog.dart`**: Extracted standalone reusable dialog widget with responsive 360dp bounds, `ThemedTextField`, `ThemedErrorBanner`, `ThemedSuccessBanner`, and `PrimaryButton`.
- **Commit SHA**: ``6b5be11f3107687d301e00c9fbe21671c97fc968``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (100% pass, 234/234 tests passed including new dedicated test suites `test/email_change_dialog_test.dart` and `test/notifications_screen_test.dart`), and `make docs-check`. ✅

## High-Traffic Customer & Auth Experience (Consistency Audit Batch 2)

- **Implementation Detail**:
  - **`customer_marketplace_screen.dart`**: Replaced raw `ElevatedButton` location picker with `SecondaryButton(isOutlined: true)`, standardized dialog title typography with `AppTypography.titleMd`, refactored `_BookingDialog` with `ThemedWarningBanner`, `PrimaryButton(isFullWidth: false)`, and `SecondaryButton(isFullWidth: false)` in responsive `Row`/`Wrap` layout preventing horizontal overflow on 360dp mobile viewports, and standardized category chip tokens (`AppTypography.labelLg`, `AppSpacing.base`, `AppSpacing.xxs`).
  - **`customer_home_screen.dart`**: Standardized unread notification badge typography to `AppTypography.labelMd`, "Browse All" header action to `AppTypography.labelLg` and `AppIconSize.sm`, category tile icons to `AppIconSize.lg`, and converted `_CustomerHomeDashboardTab` into a `StatefulWidget` with `AppMotion.debounceGuard` tap-debounce protection on quick category tiles.
  - **`customer_jobs_screen.dart`**: Migrated raw retry `ElevatedButton` to `PrimaryButton`, standardized typography to `AppTypography.bodySm`, and replaced hardcoded padding and icon dimensions with `AppSpacing.sm`, `AppIconSize.sm`, and `AppIconSize.xs`.
  - **`login_screen.dart`**: Standardized QD logo wordmark typography to `AppTypography.titleMd` and icon size to `AppIconSize.md`, and wrapped "Forgot Password?" and "Sign Up" navigation text buttons with `AppMotion.debounceGuard`.
  - **`signup_screen.dart`**: Wrapped "Already have an account? Sign In" navigation text button with `AppMotion.debounceGuard`.
  - **`otp_screen.dart`**: Replaced raw `TextButton` resend code trigger with `SecondaryButton(isOutlined: true, icon: Icons.refresh)` with debounced tap protection.
- **Commit SHA**: ``0742970a26df8d8de4331123fe4325d1532edffd``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (100% pass, 223/223 tests passed including new test suite `test/auth_screens_test.dart` and 360dp narrow viewport test in `test/customer_marketplace_screen_test.dart`). ✅

## Shared Widgets & Foundation Hardening (Consistency Audit Batch 1)

- **Implementation Detail**:
  - **`create_ticket_dialog.dart`**: Removed fixed `SizedBox(width: 100/130)` button wrappers, utilizing `SecondaryButton(isFullWidth: false)` and `PrimaryButton(isFullWidth: false)` to prevent RenderFlex horizontal overflows on narrow 360dp mobile viewports. Standardized reference ID metadata text to `AppTypography.bodySm` and replaced raw `ScaffoldMessenger` SnackBar with `ThemedSnackBar.showSuccess`.
  - **`entity_avatar.dart`**: Replaced raw `TextStyle` definitions with `GoogleFonts.poppins(color: fg, fontWeight: FontWeight.bold, fontSize: radius * 0.8)`. Wrapped `onTap` callback with 600ms tap-debounce protection (`AppMotion.debounceGuard`) to prevent double-submit and race conditions during async navigation.
  - **`rating_summary_card.dart`**: Replaced hardcoded star icon sizes with `AppIconSize.md`, vertical divider spacing arithmetic with `AppSpacing.baseSm`, sub-element spacing with `AppSpacing.xxs`, and score summary text to `AppTypography.bodySm`.
  - **`stat_card.dart`**: Standardized header icon size to `AppIconSize.md`, trend indicator icon size to `AppIconSize.xs`, and trend label gap to `AppSpacing.xs`.
  - **`status_badge.dart`**: Replaced spacing arithmetic and hardcoded icon dimensions with canonical tokens: `compact ? AppSpacing.xxs : AppSpacing.xs` vertical padding, `compact ? AppSpacing.xs : AppSpacing.sm` horizontal padding, and `compact ? AppIconSize.xs : AppIconSize.sm` icon size.
  - **`location_picker_map.dart`**: Replaced raw `ScaffoldMessenger` SnackBars with `ThemedSnackBar.showError` and standardized floating action button label to `AppTypography.labelLg.copyWith(color: AppColors.onPrimary)`.
- **Commit SHA**: ``4f4623c0a7f287942d7845ac81ff1cc0fa376022``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (100% pass, 216/216 tests passed including 35 unit/widget tests in `test/shared_widgets_test.dart`), and 360dp narrow viewport rendering test. ✅

## Owner Reconciliation Queue Refresh & Retry Wiring Fix

- **Implementation Detail**:
  - **Provider Refresh Connection (`frontend/lib/screens/owner_reconciliation_queue_screen.dart`)**: Resolved a functional defect identified during the UI consistency audit where `_onRefresh` was stubbed as an empty static function (`static Future<void> _onRefresh() async {}`), causing both pull-to-refresh and the empty-state "Refresh Queue" / "Retry" action to be silent no-ops.
  - **Dynamic State Scope (`frontend/lib/screens/owner_reconciliation_queue_screen.dart`)**: Converted `_onRefresh` into a non-static instance method on `_OwnerReconciliationQueueScreenState` that accesses `BuildContext` and invokes `Provider.of<ReconciliationProvider>(context, listen: false).fetchQueue()`, ensuring proper reloading and UI state re-rendering across empty, error, and populated states.
  - **Behavioral Regression Test Suite (`frontend/test/reconciliation_queue_test.dart`)**: Added tests `(f)`, `(g)`, `(h)`, and `(i)` verifying:
    - Empty-state "Refresh Queue" button triggers `fetchQueue()` and transitions UI to populated job list upon data arrival.
    - Pull-to-refresh on empty queue triggers `fetchQueue()`.
    - Pull-to-refresh on populated queue triggers `fetchQueue()`.
    - Error-state "Retry" button triggers `fetchQueue()` and transitions UI from error message to loaded state.
- **Commit SHA**: ``ade35b15e893175b263cb6c9a07489480d6a8046``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (196/196 pass), `make docs-check`, and pre-push hooks gate. ✅

## SegmentedButton Contrast Defect Resolution & Typography Refinement

- **Implementation Detail**:
  - **Color Contrast Resolution (`frontend/lib/core/theme.dart`, `frontend/lib/screens/settings_screen.dart`)**: Fixed real, screenshot-confirmed contrast and legibility defect in `SegmentedButton` (Theme Mode and Language selectors in `SettingsScreen`). Previously, unselected segments relied on Material 3 default color resolution, which rendered text and icons in low-contrast, washed-out pale gray. Added explicit `segmentedButtonTheme` to both `quickDeliveryTheme` (Light) and `quickDeliveryDarkTheme` (Dark) and explicit `_segmentedButtonStyle(context)` in `SettingsScreen` resolving unselected foreground to `AppColors.onSurface` (Light: `#1A1C1C` on `#EEEEEE` container, 13.1:1 contrast) and `0xFFF8FAFC` (Dark: on `#1E293B` container, 11.5:1 contrast), exceeding WCAG AA minimums (>= 4.5:1).
  - **Typography & Font Size Optimization**: Reduced segment label font size from default 14sp to compact 12sp (`AppTypography.labelLg` scale) and applied bold font weight (`FontWeight.bold` / `FontWeight.w700`), reinforcing legibility and tactile visual hierarchy without overflowing mobile viewports.
  - **Theme-Aware Icon & Background Alignment**: Updated `SettingsScreen` scaffold, app bar, and list tile leading/trailing icons to dynamic `Theme.of(context).colorScheme` values (`colorScheme.primary`, `colorScheme.outline`, `scaffoldBackgroundColor`), ensuring consistent high-contrast rendering across light and dark themes.
  - **Automated Contrast Ratio & Style Test Suite (`frontend/test/settings_screen_test.dart`)**: Added widget test `(f)` calculating mathematical relative luminance contrast ratios for both unselected and selected states in Light and Dark mode, asserting compliance with WCAG AA (>= 4.5:1), 12sp font size, and bold font weight.
- **Commit SHA**: ``c3fd65b3aa35cfc376394a8eb29d0900259d3799``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (197/197 pass), `make docs-check`, and pre-push hooks gate. ✅

## Standalone Container Build Dependency Resolution for API Gateway

- **Implementation Detail**: Added `go.mongodb.org/mongo-driver/v2` dependencies to `services/api-gateway/go.mod` (introduced by version-gating MongoDB client initialization in `internal/version/version.go`). In multi-module monorepos, `go.work` resolves sibling modules during local development, but container builds (`services/api-gateway/Dockerfile`) build in module isolation where all direct dependencies must be present in the module's `go.mod`.
- **Commit SHA**: ``36c776b1beda5c43158d6310d155469fbc94b610``
- **Verification**: Verified via `GOWORK=off go build ./cmd/main.go` across all 5 microservices, `make docs-check`, and pre-push hook validation. ✅

## Restoration of Independent Dual-Layer Rate Limiting for GetLedger (Correction to `45431d5`)

- **Implementation Detail**:
  - **Correction — Independent IP Rate Limiter (`services/user-service/internal/handlers/handlers.go`)**: Restored the pre-authentication IP-based rate limiter on `GetLedger` (`ledgerIPLimiter`, `user:ledger_ip`, 60 req/min) using a dedicated, decoupled `handlerutil.RateLimiter` field on `UserService`. This corrects the unauthorized removal of the IP check in commit `45431d5` while preserving true dual-layer protection.
  - **Dual-Layer Execution Model**: `GetLedger` evaluates `ledgerIPLimiter` (`get_ledger_ip:` + ip) BEFORE token resolution to guard against unauthenticated ledger scraping attempts. Validated requests are subsequently evaluated against `ledgerLimiter` (`ledger_tenant:` + tenantID) AFTER token resolution. Both limiters operate on completely independent Redis budgets (separate key namespaces and limiter instances), eliminating the single-bucket double-charge bug.
  - **Independent Test Suite (`services/user-service/internal/handlers/read_rate_limiters_test.go`)**: Added `TestGetLedger_IPRateLimitCheck` (verifying `ledgerIPLimiter` independently triggers HTTP 429 across different tenants) and `TestGetLedger_TenantRateLimitCheck` (verifying `ledgerLimiter` independently triggers HTTP 429 across different IPs), while re-confirming `TestReadRateLimiters_Independence`.
- **Commit SHA**: ``8c6d982c3aba99642ffc3d11cf5c9ec22f21d577``
- **Verification**: Verified via `go build ./...`, `go vet ./...`, `go test ./...` (100% pass across all 6 modules), `make docs-check`, and pre-push hooks gate. ✅

## Shared-Bucket Rate Limiter Refactoring & GetLedger Double-Charge Resolution

- **Implementation Detail**:
  - **Independent Rate Limiter Instances (`services/user-service/internal/handlers/handlers.go`)**: Replaced single shared `readLimiter` (`user:read`, 30 req/min) in `UserService` struct and `NewUserService` with 5 independent `RateLimiter` instances: `ownerJobsLimiter` (`user:owner_jobs`, 60 req/min), `customerJobsLimiter` (`user:customer_jobs`, 60 req/min), `ledgerLimiter` (`user:ledger`, 60 req/min), `ratingsLimiter` (`user:ratings`, 30 req/min), and `reconciliationLimiter` (`user:reconciliation`, 30 req/min). Navigating one screen (e.g. Wallet) no longer drains the rate budget of unrelated screens (e.g. Job History).
  - **Single Tenant-Scoped Check for `GetLedger` (`services/user-service/internal/handlers/handlers.go`)**: Removed redundant pre-authentication IP rate-limit check (`"get_ledger_ip:" + ip`) in `GetLedger`. Token resolution and role validation (`resolveTokenWithRole`) now execute first. Validated requests are evaluated against a single tenant-scoped check (`ledger_tenant:<tenantID>`), eliminating the double-charge bug that previously deducted 2 credits per request.
  - **Nil Receiver Store Safety (`services/user-service/internal/store/mongodb.go`)**: Added nil receiver checks (`if s == nil || s.ledger == nil`) to `store.MongoDB` read methods (`GetLedger`, `GetJobsByOwner`, `GetJobsByCustomer`, `GetRatingsForUser`) preventing nil pointer panics during isolated unit test execution.
  - **Cross-Service Audit & Dedicated Unit Test Suite**: Audited `chat-service`, `notification-service`, `auth-service`, and `api-gateway`, confirming no shared-bucket patterns exist in other services. Added `services/user-service/internal/handlers/read_rate_limiters_test.go` with `TestGetLedger_SingleRateLimitCheck` and `TestReadRateLimiters_Independence`.
- **Commit SHA**: ``d743f8109416b9104e73b18867201c004c112be5``
- **Verification**: Verified via `go build ./...`, `go vet ./...`, `go test ./...` (100% pass across all 6 modules), `make docs-check`, and pre-push hooks gate. ✅

## Remediation & Removal of Unnecessary Test Retry Loop in Chat Service Concurrency Test

- **Implementation Detail**:
  - **Removal of Unnecessary Test Retry Loop (`services/chat-service/internal/handlers/chat_test.go`)**: Audit of commit `1e49e77...` revealed that the 3-attempt retry loop with `10ms` sleep added around `CreateTicketAndAssign` in `TestComplaintRoutingConcurrency` was a misdiagnosis. The underlying test failure was caused by unauthenticated connection ordering in `connectTestMongoDB`, which was already resolved by commit `cc54b63...`. Removed the retry loop, restoring direct single-call execution. Verified 20/20 clean passes under `go test -v -race -count=20`.
  - **Revert of Inert `SetMaxPoolSize(100)` & CAS Audit Comment (`services/chat-service/internal/store/mongodb.go`)**: Reverted redundant `SetMaxPoolSize(100)` in `NewMongoDB` because 100 is already the mongo-driver v2 (`go.mongodb.org/mongo-driver/v2`) default, making `SetMaxPoolSize(100)` a complete no-op. Audited `CreateTicketAndAssign` and confirmed its single-document `FindOneAndUpdate` is a verified atomic Compare-And-Swap (CAS) operation that cleanly handles `mongo.ErrNoDocuments` without race conditions. Added explicit audit documentation comment above `FindOneAndUpdate`.
- **Commit SHA**: ``94fe6e43987396fb609c62185bb254db953a2a3f``
- **Verification**: Verified via `gofmt`, `go vet ./...`, and `go test -v -race -count=20 ./...` (20/20 pass). ✅

## Business Location Map Selection in Owner Configuration & Services Directory Distance Filter Fix (BUG 1 & BUG 2)

- **Implementation Detail**:
  - **Owner Configuration Location Selection (`frontend/lib/screens/owner_configuration_screen.dart`, `frontend/lib/providers/owner_provider.dart`)**: Fixed BUG 1 where `OwnerConfigurationScreen` hardcoded Cairo coordinates (`latitude: 30.0444, longitude: 31.2357`) for every service creation/configuration. Integrated `LocationPickerMap` (`frontend/lib/widgets/location_picker_map.dart`, per ADR-0014) into `OwnerConfigurationScreen` with an interactive map dialog. Added `latitude` and `longitude` optional parameters to `updateOwnerServiceConfig` in `OwnerProvider` to pass coordinates on `PUT /users/services`. Pre-populates the map picker with the service's stored coordinates if editing, while falling back to Cairo as map center for new services (requiring pin confirmation before form submission).
  - **Services Tab Unfiltered Directory Filter (`frontend/lib/screens/customer_marketplace_screen.dart`)**: Fixed BUG 2 where `_nearBy` was hardcoded to `final bool _nearBy = true`, forcing distance radius filtering and hiding businesses outside Cairo. Made `_nearBy` a mutable state variable defaulting to `false` (returning all directory services across all locations per ADR-0014 when reached via the Services tab), and added a visible `Nearby Only` toggle switch control allowing customers to optionally filter by distance.
  - **Localization & Unit Tests**: Added localization keys (`ownerConfigLocationLabel`, `ownerConfigLocationReq`, `customerMarketplaceFilterNearby`) to `app_en.arb` and `app_ar.arb`. Updated widget tests in `frontend/test/owner_configuration_screen_test.dart` and `frontend/test/customer_marketplace_screen_test.dart` verifying map picker selection, coordinate submission, `nearBy: false` default, and distance toggle behavior.
- **Commit SHA**: ``0cc9fc6ecdb40edb5f91384008a4879593de18b5``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues), `flutter test` (100% pass across 196 tests), `make docs-check`, and pre-push hooks gate. ✅

## Atomic Single-Use Email Change OTP Consumption (`GetAndConsumePendingEmailChange`)

- **Implementation Detail**:
  - **Single-Operation Atomic FindOneAndDelete (`services/auth-service/internal/store/mongodb.go`)**: Replaced non-atomic `FindOne` followed by separate `DeleteOne` in `GetAndConsumePendingEmailChange` with a single atomic `FindOneAndDelete` operation. The prior implementation (introduced in commit `9a94d94...`) claimed single-use atomic deletion but suffered from a TOCTOU race condition where concurrent requests could both execute `FindOne` and validate the same OTP before either `DeleteOne` completed.
  - **Single-Attempt OTP Security Pattern**: `FindOneAndDelete` atomically fetches and deletes the pending record in one round trip. Expiry and OTP verification are evaluated against the returned record; if the OTP is wrong or expired, the record remains consumed (single-attempt pattern), requiring the user to request a fresh OTP and preventing brute-force code guessing.
  - **Concurrency Regression Test (`services/auth-service/internal/handlers/email_change_test.go`)**: Added `TestEmailChange_ConcurrentConfirmRace` firing 2 concurrent goroutines submitting the same valid OTP simultaneously. Asserts exactly one request receives `200 OK` while the second receives a clean rejection, and verifies the user email in MongoDB is correctly updated to `new_email`. Tested with `go test -v -race -count=20` to verify zero data races and 100% test stability.
- **Commit SHA**: ``488723bda77c89b4a4387d8170cbab5c456b53f5``
- **Verification**: Verified via `go test -v -race -count=20 ./internal/handlers -run TestEmailChange_ConcurrentConfirmRace` (20/20 pass), full `auth-service` test suite (`go test ./...`, 100% pass), `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## Repository Dead-Code & Scratch Directory Cleanup Pass

- **Implementation Detail**:
  - **Removal of Untracked Scratch Directory (`scratch/`)**: Removed temporary python audit scripts (`audit_debt.py`, `audit_hierarchy.py`, `audit_motion.py`, `audit_states.py`, `audit_widgets.py`) and temporary text finding files (`design_debt_findings.txt`, `hierarchy_findings.txt`, `motion_findings.txt`, `states_findings.txt`) committed during earlier UI audit passes. Added `scratch/` to `.gitignore`.
  - **Polling Interval Magic Numbers Remediation (`frontend/lib/screens/job_status_screen.dart`)**: Replaced inline magic duration calls (`Duration(seconds: 5)`, `Duration(seconds: 1)`) with named class constants `_jobStatusPollingInterval` and `_countdownTimerInterval`.
  - **Chat Empty State Clarifying Documentation (`frontend/lib/screens/chat_screen.dart`)**: Documented why `ThemedEmptyState` intentionally omits an action button in empty chat views (since the persistent text input bar and send button are rendered directly below).
  - **Codebase Dead-Code Sweep**: Ran `go vet ./...` across all 6 Go modules (`services/api-gateway`, `services/auth-service`, `services/chat-service`, `services/notification-service`, `services/user-service`, `shared/infra`) and `flutter analyze` across frontend, confirming 0 dead code or unused import warnings.
- **Commit SHA**: ``0c046f526420a0c8d1b94cdca01ed5a7b829f08d``
- **Verification**: Verified via `make ci` (full Go backend & Flutter frontend suite passing 100%), `make docs-check`, and `.githooks/pre-push` gate exit code 0. ✅

## ADR-0017 Migration Script Database Name Target Remediation (Finding #8 Alignment)

- **Implementation Detail**: Remediated critical migration script bug in `docs/DEPLOYMENT.md` §11.1 where the ADR-0017 `platform_config` migration script targeted the obsolete shared database name `saas_platform` instead of `user_db` (`${USER_MONGO_DATABASE:-user_db}`). Following Finding #8's database-per-service separation, `user-service` connects to `user_db`. Running the old script would have left production charging the old 15% platform fee. Updated `docs/DEPLOYMENT.md` §11.1 and `mongodump` backup commands, as well as `README.md` manual database ops procedures (`users` -> `auth_db`, `subscriptions` -> `user_db`). Executed the corrected migration against live `user_db.platform_config` setting `platform_fee_percentage: 0.0`.
- **Commit SHA**: ``d97ef3a3ef5051be2b4adb85cc67004b35237ee4``
- **Verification**: Verified via `mongosh` against `user_db.platform_config` returning `{ _id: "global", platform_fee_percentage: 0 }`. Passed `go test ./shared/infra/changelog_validation_test.go`. ✅

## Removal of Dead DeductCODFee Store Method (ADR-0017 Cleanup)

- **Implementation Detail**: Removed `DeductCODFee` store method from `services/user-service/internal/store/mongodb.go` and corresponding test step in `mongodb_test.go`. The function was dead code left over from pre-ADR-0017 fee-deduction logic and contradicted the zero-commission COD model implemented in commit ``aaaacc531ffe24a9aa6da3c99231844ef4fa8803`` (where `CompleteCODJob` in `handlers.go` performs pure status-only logging with 0% platform fee and zero wallet mutation). Updated architecture maps (`DESIGN.md`, `docs/APPLICATION_MAP.md`, `docs/BUSINESS_LOGIC_AUDIT.md`, `docs/adr/0017-zero-commission-subscription-only-revenue-model.md`).
- **Commit SHA**: ``431d42a8c0c426fe66037257d42878a84f74c73f``
- **Verification**: Verified via `gofmt`, `go build`, `go vet`, `go test ./services/user-service/...` (100% pass), and repo-wide grep confirming zero remaining references. ✅

## COD Job Cancel/Complete Race Condition & AgreedPrice Escrow Refund Math (Audit Findings 1 & 2)

- **Implementation Detail**:
  - **Finding 1 Fix (`services/user-service/internal/store/mongodb.go`)**: Added atomic CAS status precondition `status: {$in: [JobStatusActive, JobStatusPending, JobStatusAwaitingPriceResponse, JobStatusEscrowReconciliationRequired, JobStatusCancelled]}` to `CancelJob`, eliminating the race condition between concurrent `CompleteJob` and `CancelJob` requests. Returned HTTP 409 Conflict when a non-cancellable state transition occurs.
  - **Finding 2 Fix (`services/user-service/internal/handlers/handlers.go`)**: Updated `CancelJob` refund calculation to inspect `job.AgreedPrice` before falling back to `job.LockedEscrowAmount`, eliminating stranded locked escrow on negotiated transport cancellations.
  - **Test Suite (`services/user-service/internal/handlers/business_logic_audit_fixes_test.go`)**: Built integration tests `TestFinding1_CODCancelCompleteRaceCondition` and `TestFinding2_CancelJob_NegotiatedTransport_AgreedPriceRefund`.
- **Commit SHA**: ``85a5c0478729593363a1beb309b9d6e14cb5145d``
- **Verification**: Verified via `gofmt`, `go build`, `go vet`, and `go test -v ./...`. ✅

## Settings KYC Role Gating, Redundant Refresh Button Cleanup, and Owner Arabic Localization

- **Implementation Detail**:
  1. **Settings KYC Role Gating (Bug 1)**: Updated `frontend/lib/screens/settings_screen.dart` to gate identity verification (KYC/KYB) display with `showKycRow = user != null && (user.role == 'owner' || user.role == 'employee') && user.kycStatus != 'approved'`. Updated `frontend/test/settings_screen_test.dart` to verify customer role (`user`) hides the KYC row even when unverified, while owner and employee roles display the row when unverified and hide it when approved.
  2. **Redundant Refresh Button Cleanup (Bug 2)**: Removed redundant refresh `IconButton` widgets from AppBar `actions` across 5 screens (`employee_jobs_screen.dart`, `home_screen.dart`, `customer_jobs_screen.dart`, `kyb_kye_review_screen.dart`, `owner_reconciliation_queue_screen.dart`) while retaining `RefreshIndicator` pull-to-refresh gestures. Added widget tests covering `RefreshIndicator` pull gestures in `employee_jobs_screen_audit_test.dart` and `owner_home_screen_test.dart`.
  3. **Owner Arabic Localization Pass (Bug 3)**: Extracted and localized ~90 hardcoded strings across `home_screen.dart`, `owner_history_screen.dart`, `employee_jobs_screen.dart`, and `settings_screen.dart`. Added keys to `app_en.arb` and natural Egyptian colloquial Arabic translations (`ar_EG`) in `app_ar.arb`. Ran `flutter gen-l10n`.
- **Commit SHA**: ``13a554168c2c358079ce5b806352d931f84e61b2``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (167/167 pass 100%), live backend health check (`https://api.logiclinkeg.tech/health` -> `{"status":"ok"}`), and `.githooks/pre-push` gate passing cleanly. ✅

## /users/services/update HTTP Method Restriction & PATCH /auth/user Docgen Registration

- **Implementation Detail**: Restricted `/users/services/update` route in `services/user-service/internal/handlers/handlers.go` to HTTP `POST`, `PUT`, and `PATCH` methods (returning 405 Method Not Allowed for GET/DELETE/etc). Extended AST route parser in `shared/infra/docgen/generator.go` to handle `http.MethodPatch` selector expressions and added `PUT/PATCH /users/services/update` and `PATCH /auth/user` entries to `KnownEndpoints`. Regenerated `docs/APPLICATION_MAP.md` via `make docs` and confirmed `PATCH /auth/user` and `/users/services/update` appear in generated application map without TODOs.
- **Commit SHA**: ``d43b5ecf997c1758fda7940debdd2c2dff846954``
- **Verification**: Verified via `gofmt -w .`, `go build ./...`, `go vet ./...`, `go test ./...`, and `make docs-check`. ✅

## LocationPickerMap Dialog & Dropdown Sizing Mobile Overflow Fix

- **Implementation Detail**: Fixed fixed-size container overflow (`width: 500, height: 550`) in `_openLocationPickerDialog` inside `customer_marketplace_screen.dart`. Replaced fixed dimensions with dynamic `MediaQuery` viewport calculations (`dialogWidth = screenSize.width > 600 ? 500.0 : screenSize.width * 0.92`, `dialogHeight = screenSize.height > 700 ? 550.0 : screenSize.height * 0.85`) with `insetPadding: const EdgeInsets.all(AppSpacing.md)`. Wrapped header title `Text` in `Expanded` to prevent horizontal header overflow on small viewports. Added `isExpanded: true` to Category and Sort By `DropdownButtonFormField` widgets to prevent dropdown item text overflow. Added explicit 360x800 mobile viewport regression tests in `customer_marketplace_screen_test.dart` and 330x480 narrow container tests in `location_picker_map_test.dart`.
- **Commit SHA**: ``e82cbf79a6db429bc1bfcf9c2a3bd116925f7f5a``
- **Verification**: Verified via `flutter analyze` (0 issues found), `flutter test` (119/119 full test suite pass cleanly including 360x800 mobile viewport regression tests), and `make docs-check`. ✅

## ProposePrice Concurrency Race Test Assertion Flakiness Fix

- **Implementation Detail**: Resolved flaky test assertion in `TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention` (`services/user-service/internal/handlers/negotiation_concurrency_test.go`). Production data integrity and atomic CAS write in `store.UpdateJobPriceProposal` (`{_id, status, proposed_price: nil}`) were verified as 100% correct (preventing any double-proposals, `successCount == 1` always held). However, the test assertion previously rejected HTTP 400 `proposal_already_submitted` rejections occurring when the losing concurrent goroutine executed an early non-atomic snapshot read before hitting the CAS path. Updated the test assertion to accept either valid rejection outcome (400 `proposal_already_submitted` or 409 `job_state_changed`), and added an explanatory comment above the early non-atomic read in `services/user-service/internal/handlers/handlers.go` clarifying that atomic CAS enforcement remains the authoritative protection mechanism. No production handler logic or business behavior was changed.
- **Commit SHA**: ``ecec165c399b7c70f0c04991c0c5c402a1fdfffc``
- **Verification**: Verified via `go test ./services/user-service/...` passing 100% cleanly and `go test ./services/user-service/internal/handlers/... -run TestProposePrice_ConcurrencyRace_OverwrittenProposalPrevention -count=20 -race` passing 20 consecutive iterations with 0 failures. ✅

## Forgot Password Consolidation Dead Code Cleanup

- **Implementation Detail**: Removed unused `ResetPasswordScreen` (`frontend/lib/screens/reset_password_screen.dart`) left behind after consolidating the forgot password flow into a single-step screen in commit `f2495a3...`. Updated `docs/frontend/STATUS.md` and `docs/frontend/ARCHITECTURE.md` to keep documentation and docgen verification tests in sync.
- **Commit SHA**: ``bbd869d891205089877a5f1e0a46a2e6814360ca``
- **Verification**: Verified via `grep` confirming 0 remaining references, `flutter analyze` passing with 0 issues, and `flutter test` passing 106/106 tests cleanly. ✅

## Deferred User Account Creation Until OTP Verification & IsConfirmed Removal Fix

- **Implementation Detail**: Fixed permanent login block for confirmed accounts and restructured owner/user registration flow. User accounts for `RoleOwner` and `RoleUser` are now stored in a dedicated `pending_signups` MongoDB collection (encrypted with AES-256-GCM and 5-minute expiry) during `Signup`. Accounts are persisted to the `users` collection only when `VerifyOTP` succeeds, making DB existence inherently mean "confirmed" and eliminating the redundant `IsConfirmed` field across models, store methods, handlers, and unit tests. Employee signups remain immediate and auto-confirmed. Fixed abandoned signups by overwriting existing pending records for the same email during subsequent signup attempts.
- **Commit SHA**: ``c9e27c4a322ed7725af7454f692f6b51184a2d91``
- **Verification**: Verified via `go test ./...` across all Go microservices passing cleanly, including 4 new unit test cases covering abandoned signup overwrites, confirmed user login after JWT expiry, 5-minute pending signup expiration, and wrong OTP failures without user creation. ✅

## UpdateJobLocation `requireTier` Error Branch Missing Return Fix

- **Implementation Detail**: Resolved a critical control-flow defect in `user-service` (`UpdateJobLocation` in `services/user-service/internal/handlers/handlers.go`). When `requireTier` returned a non-`ErrUpgradeRequired` internal error, the handler invoked `clearInFlight()` and `writeJSON(w, http.StatusInternalServerError, ...)` but lacked a `return` statement. This missing return allowed execution to fall through to speed checks and database persistence, attempting to process the update and write a second HTTP 200 response header. This single root cause explained two symptoms: (1) security control-flow bypass where 500 error responses continued execution, and (2) concurrent race test failure (`UpdateJobLocation_Throttle_Concurrent_Race_Handling` getting `[200 200]`) due to `clearInFlight()` releasing the in-flight lock prematurely on fallthrough. Added missing `return` statement immediately following `writeJSON(500)`. Explicitly noted that prior local analysis framing this as an "in-memory path" issue investigated the correct symptom but the wrong layer; the fix belongs in shared control flow. Added regression test `UpdateJobLocation RequireTier InternalError Regression Guard` in `handlers_test.go`.
- **Commit SHA**: ``89d1f0423315851a25479564996b0620a7ce34f6``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers/... -run TestUserServiceHandlers/UpdateJobLocation_Throttle -race -count=20` passing 20 consecutive iterations, `TestUserServiceHandlers/UpdateJobLocation_RequireTier_InternalError_Regression_Guard` passing, and `make ci`. ✅

## WalletDeposit Upper Limit

- **Implementation Detail**: Enforced a maximum limit of 1,000,000 on WalletDeposit amounts in user-service.
- **Commit SHA**: ``a1e965f76f3b2e436b1f76d3c13d0d390e6529f1``
- **Verification**: Verified via user-service unit tests. ✅

## Graceful Employee Deactivation

- **Implementation Detail**: Gated new job assignment in TrackJob behind employee IsActive lookup. Allowed deactivated employees to complete existing in-progress jobs.
- **Commit SHA**: ``ebe5f62e41459ede18a1a9a4644d9e99cb5574cd``
- **Verification**: Verified via auth-service and user-service integration tests. ✅

## Per-Job Location Throttling

- **Implementation Detail**: Throttled consecutive location updates under 3s per Job ID with in-flight reservations and rollback.
- **Commit SHA**: ``8ba1b34dd5fbb068f43bd94ce29692620ce8877e``
- **Verification**: Verified via unit, race, and integration tests. ✅

## CORS headers on SSE stream errors

- **Implementation Detail**: Moved Access-Control-Allow-Origin header injection to the top of SSE Stream handler so that connection error responses are readable by browser JS.
- **Commit SHA**: ``bb80f2bcc6dde695861c6547db6152662b7e1e0a``
- **Verification**: Verified via compilation and test execution. ✅

## Removed dead SSE Done channel

- **Implementation Detail**: Deleted the unused Done channel field from SSEClient and its initialization as client connection disconnects are already handled gracefully by the context and Send channel closure.
- **Commit SHA**: ``0d9caf82127392992ac60677ad1f0ca60760d7c6``
- **Verification**: Verified via compilation and test execution. ✅

## Random Notification IDs

- **Implementation Detail**: Switched notification ID generation from UnixNano timestamp to crypto/rand-based 16-byte random hex string to eliminate collision risks.
- **Commit SHA**: ``8cab6c2fe22909455ebed3f351706a0d0d8f6967``
- **Verification**: Verified via compilation and test execution. ✅

## Token Refresh Panic on Expired Token

- **Implementation Detail**: Updated `ValidateToken` in `jwtutil` to return the parsed claims even when `ErrExpiredToken` is encountered. This prevents nil-pointer panics in `/auth/refresh` when accessing `claims.ExpiresAt` on expired tokens.
- **Commit SHA**: ``5ac1d9e3173d94f91bb2c8d6217795a1c7775e62``
- **Verification**: Verified via auth-service unit tests (`TestTokenRefresh`) and jwtutil unit tests (`TestValidateToken_Expired`). ✅

## Signup Rollback on OTP Set Failure

- **Implementation Detail**: Updated `Signup` in `auth-service` to delete/rollback the newly created user record in MongoDB if generating/saving the OTP code via `SetOTP` fails. This prevents leaving an orphaned user record in a stuck `is_confirmed = false` state.
- **Commit SHA**: ``5a17284748a87a5b24467d4397183e7b8b5768f7``
- **Verification**: Verified via auth-service unit tests (`TestSignupRollbackOnOTPFailure`). ✅

## KYB/KYE Signed URL Error Propagation

- **Implementation Detail**: Captured and propagated S3/local storage `GetSignedURL` errors in `GetPendingKYBKYESubmissions` (`/auth/kyb-kye/pending`). Server-side failures are now logged with details and surfaced in the client response under `document_errors` per submission rather than silently rendering an empty URL.
- **Commit SHA**: ``f95367ee3f2cc95be594c795037c874d219269b9``
- **Verification**: Verified via auth-service integration tests (`TestGetPendingKYBKYESubmissions_StorageError`). ✅


## Unconfirmed User OTP Verification Deadlock & Resend Path

- **Implementation Detail**: Added a new `POST /auth/resend-otp` endpoint to `auth-service` allowing unconfirmed users to request a fresh OTP. This breaks the deadlock where an unconfirmed account could not log in, sign up again, or trigger a new code. The endpoint validates parameters, enforces IP and email rate limiting via the existing rate limiter, prevents identity/state leakage by returning a generic success message if the account doesn't exist or is already confirmed, and updates the OTP and expiration in MongoDB. Updated the Flutter frontend's `OtpScreen` to include a "Resend Code" button that invokes this endpoint, dynamically handles the response, and displays the new dev OTP code in development environments.
- **Commit SHA**: ``119f4f1d2b38527ecb13280574334506b3456a83``
- **Verification**: Verified via auth-service unit tests (`TestOTPResendFlow`). ✅

## Resilience Client Connection Leak Fix

- **Implementation Detail**: Corrected a resource leak in `ResilienceClient.Do` and `ResilienceRoundTripper.RoundTrip` where intermediate responses returned by the circuit breaker execution on HTTP 5xx failures were not closed during retries or prior to returning the error, leading to connection/file descriptor leaks. Added explicit body closure on error states.
- **Commit SHA**: ``eb0ddb54b537358b46f00b82b9540d069b531705``
- **Verification**: Verified via `shared/infra/resilience/resilience_test.go` (`TestResilienceClient_ConnectionLeak`). ✅

## Documentation Sync and Code Formatting Drift Correction

- **Implementation Detail**: Corrected formatting drift in the notification-service tests, synchronized the APPLICATION_MAP.md Git commit version, and established a pre-commit verification gate in CLAUDE.md to require gofmt, go build, and go test checks before code changes are committed and pushed.
- **Commit SHA**: ``4e57ef7c5127730198f67800f80b260ab877a2fd``
- **Verification**: Verified by executing formatting checks (`gofmt -l .`) and running the documentation AST/SHA validators (`TestDocgenFreshness` and `TestChangelogCommitSHAs`). ✅

## API Gateway Container go.sum Drift

- **Implementation Detail**: Ran `go mod tidy` in the `api-gateway`, `chat-service`, and `notification-service` modules to resolve build-blocking dependency drift. The addition of CloudWatch logging dependencies in `shared/infra/handlerutil/security_logs.go` caused `docker compose build` to fail for `api-gateway` with a missing module entry in `go.sum`. Added missing indirect dependencies to `api-gateway/go.mod` and cleanups to `chat-service/go.mod` and `notification-service/go.mod`.
- **Commit SHA**: ``8d62ee0e54b60a0aff65059039fa9557950b52b8``
- **Verification**: Verified by executing a clean `docker compose down`, `docker compose build --no-cache`, and `docker compose up -d` locally, confirming the gateway successfully builds, resolves dependencies, listens on HTTPS port 8080, and responds to health checks. ✅

## UpdateJobLocation Throttle Rollback Test Flakiness

- **Implementation Detail**: Eliminated a timing race in `TestUserServiceHandlers/UpdateJobLocation_Throttle_Error_Rollback` where a polling goroutine canceled the request context to simulate a database write failure. On slower CI machines, the write could complete before the cancel signal, causing the request to succeed (returning 200 instead of 500) and setting a new throttle timestamp, which then caused the retry call to fail with 429. Added an unexported test hook `updateJobLocationBeforeWriteHook` on `UserService` to allow the test to deterministically synchronize and cancel the context *after* the in-flight state is established but *before* the MongoDB write is executed.
- **Commit SHA**: ``b6cae1753e1146c5b1900cafbce9935f3b18389f``
- **Verification**: Verified via `services/user-service` handlers tests (`TestUserServiceHandlers/UpdateJobLocation_Throttle_Error_Rollback`) running in a tight loop of 50 runs with zero failures. ✅

## Notification-Service Handlers Test Sleep Auditing

- **Implementation Detail**: Audited and replaced 5 flaky, fixed `time.Sleep` calls in `services/notification-service/internal/handlers/handlers_test.go` with deterministic polling loops using generous timeouts (2s). Introduced a thread-safe `safeRecorder` helper struct to prevent data races on `httptest.ResponseRecorder`'s unsynchronized `bytes.Buffer` when polling for writes concurrently. Staggered client disconnect stress testing is now synchronized to wait for active hub registration before scheduling disconnect timers, ensuring robust execution under load.
- **Commit SHA**: ``f6aedfa84b70cba80ba9f88370dc376b24c55dea``
- **Verification**: Verified via `services/notification-service` handlers tests running in a loop of 50 runs under the Go race detector with zero failures. ✅

## Chat-Service Hub Test Sleep Auditing

- **Implementation Detail**: Audited and replaced flaky `time.Sleep` calls in `services/chat-service` tests. Replaced the fixed `time.Sleep(50 * time.Millisecond)` in `internal/chat/hub_test.go` with a deterministic, thread-safe polling loop on `hub.ClientCount()` and `hub.ChannelCount()` to synchronize after concurrent client unregistrations. The remaining `time.Sleep` calls in `hub_test.go` (spacing simulated active overlapping traffic) and `chat_test.go` (spacing database write timestamps) were verified as safe timing configurations with no active I/O races, and were left unmodified.
- **Commit SHA**: ``51c50e96efba171d6c0b115db0601972ee508389``
- **Verification**: Verified via `services/chat-service` unit and stress tests running in a loop of 50 runs under the Go race detector with zero failures. ✅

## Resend From-Email Configuration Validation

- **Implementation Detail**: Enforced fail-fast startup validation in `auth-service`'s `config.Load()` requiring `RESEND_FROM_EMAIL` to be specified whenever `RESEND_API_KEY` is set. Removed silent fallback to Resend's shared test domain (`onboarding@resend.dev`), preventing production deployments from accidentally dispatching emails from the sandbox address.
- **Commit SHA**: ``7cd13c04e407ae527d8a641193d0cb37fc2db777``
- **Verification**: Verified via `services/auth-service/internal/config` unit tests (`TestLoad_ResendConfig`) covering error on missing sender email, success on full config, and un-gated fallback when Resend is disabled. ✅

## Rate Limiting for RateJob and GetRatings Handlers (Item #3)

- **Implementation Detail**: Resolved deep-tester Item #3 (severity 5/10, priority 6/10). Added IP-based rate limiting via `u.limiter.CheckAndRecord` to `RateJob` (`POST /users/jobs/rate`) and `GetRatings` (`GET /users/ratings`), matching the security controls on `TrackJob` and `WalletDeposit` to prevent request flooding and rating enumeration attacks.
- **Commit SHA**: ``12fde32e15a4f150ac9f10f6f9223ff2163f5d5c``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRateJobAndGetRatings_RateLimiting -v` (asserting 429 Too Many Requests response after exceeding rate limit). ✅

## Expected Role Enforcement via resolveTokenWithRole (Item #4)

- **Implementation Detail**: Resolved deep-tester Item #4 (severity 4/10, priority 6/10). Replaced raw `resolveToken` calls with `resolveTokenWithRole` across handlers, enforcing expected roles (`owner`, `employee`, `user`/`customer`) during JWT claim resolution and rejecting tokens early on role mismatch.
- **Commit SHA**: ``a81a75323978195cf3d22c40dbc2c9400adc89a7``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestResolveTokenWithRole -v` (asserting role matching, multi-role acceptance, and role mismatch rejection). ✅

## Rating Summary Access Model for Authenticated Requesters (Item #5)

- **Implementation Detail**: Resolved deep-tester Item #5 (severity 4/10, priority 5/10). Updated `GetRatings` (`GET /users/ratings`) to authenticate the caller via JWT token while allowing target `user_id` query parameter to specify any candidate employee/user ID. This enables business flows such as owners evaluating candidate employee rating summaries before hiring without requiring possession of the candidate's JWT token.
- **Commit SHA**: ``0213d4674fbd411923b1511262417edecceda47d``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestUserServiceHandlers/GetRatings -v` (asserting authenticated owner query for target employee rating summary returns 200 OK). ✅

## Dual-Layer Rate Limiting for GetLedger Handler (Item #6)

- **Implementation Detail**: Resolved deep-tester Item #6 (severity 3/10, priority 4/10). Added IP-based and tenant-based rate limiting via `u.limiter.CheckAndRecord` to `GetLedger` (`GET /users/ledger`), matching the financial rate limiting protections on `WalletDeposit` to prevent ledger scraping and resource exhaustion attacks.
- **Commit SHA**: ``2398fcd44ee834b78f073d424c9cb08e7ad5094a``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestGetLedger_RateLimiting -v` (asserting 429 Too Many Requests response after 5 requests from same IP). ✅

## Test Payment Bypass Gating & Production Safeguard (Item #7)

- **Implementation Detail**: Resolved deep-tester Item #7 (severity 3/10, priority 4/10). Hardened payment bypass controls in `TrackJob` and `WalletDeposit` to require the explicit environment variable `ALLOW_TEST_PAYMENT_BYPASS=true` in addition to non-production environment checks (`APP_ENV=test` or `local`). Added startup validation in `config.Load()` that immediately fails service startup if `ALLOW_TEST_PAYMENT_BYPASS=true` is set when `APP_ENV=production`.
- **Commit SHA**: ``0a8cfb789c6eb95b40087557884d179ff58863a7``
- **Verification**: Verified via `go test ./services/user-service/internal/config -run TestLoad_AllowTestPaymentBypass -v` (asserting production startup error) and `go test ./services/user-service/internal/handlers -run TestTestPaymentBypass_Gating -v` (asserting 400 Bad Request when flag is unset). ✅

## RateJob Comment Sanitization & Length Bound (Item #8)

- **Implementation Detail**: Resolved deep-tester Item #8 (severity 3/10, priority 3/10). Added 1000-character maximum length validation on incoming comments in `RateJob` (`POST /users/jobs/rate`) and sanitized comments using `html.EscapeString` server-side to neutralize HTML/XSS injection payloads. Confirmed frontend rendering in `frontend/lib` uses standard Flutter `Text` widgets to display comments strictly as plain text.
- **Commit SHA**: ``48546bdb5f768af3d75aadb73c5adb7fdf414595``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRateJob_CommentSanitizationAndLengthLimit -v` (asserting 400 Bad Request response when comment exceeds 1000 characters). ✅

## E2E Integration Test Redis Port Resolution & Nil Safety Guards

- **Implementation Detail**: Fixed hardcoded Redis port (`localhost:6380`) in `adr0006_e2e_integration_test.go` and `adr0007_e2e_integration_test.go` to dynamically parse `REDIS_URI` / `REDIS_ADDR` with fallback to default port `6379`, matching `ci.yml` runner configuration (`redis://localhost:6379`). Added Redis `Ping` connectivity checks to skip E2E integration tests gracefully when Redis is unreachable, and added explicit HTTP status code assertions and nil pointer safety guards across all test subtests to prevent test runner crashes. Updated documentation guidelines requiring explicit disclosure of local vs CI environment verification scope.
- **Commit SHA**: ``cd824bfc90427e18d5ccab9ddde5c441fdec93c7``
- **Verification**: Verified via local Go test execution (`go test ./services/user-service/internal/handlers -run TestADR0006_E2E_NegotiableTransportPricing -v` and `TestADR0007_E2E_DeliveryGPSReconciliation -v`). Pending GitHub Actions CI runner verification. ✅

## Negotiable Transport Pricing Escrow Locking & Reconciliation Fallback in RespondPrice

- **Implementation Detail**: Resolved non-COD negotiable transport job escrow locking gap in `RespondPrice` (`POST /users/jobs/respond-price`). When a price proposal is accepted (`decision == "accept"`), `LockEscrow` locks the agreed price in the owner wallet before transitioning status to `active`. On `UpdateJobLockedEscrow` persistence failure, `performRollbackEscrow` executes with single retry; if rollback fails, the job transitions to `models.JobStatusEscrowReconciliationRequired` with `ReconciliationNote` set, preventing silent unrecorded escrow state and routing the job to `GET /users/jobs/reconciliation-queue`.
- **Commit SHA**: ``e8eb530ebcd0529369596d87f807052b55ff7d8a``
- **Verification**: Verified via `go test ./services/user-service/internal/handlers -run TestRespondPrice_EscrowLockingAndReconciliationFallback -v` (6/6 passing including COD skip, insufficient funds 400, rollback failure reconciliation queue routing, and full accept-then-complete end-to-end chain) and `make docs-check`. ✅

## AI_CONTEXT.md Orphaned Commit SHA Citation Correction

- **Implementation Detail**: Corrected an orphaned commit SHA citation in `AI_CONTEXT.md` under "Verified Android Emulator End-to-End Backend Connectivity". The citation previously referenced an orphaned reflog object (short ref `05b5ca7...`, no longer reachable from branch history) resulting from a local `git commit --amend`, which was caught by CI SHA validation. Updated the entry to cite the real commit (`807f98bbca30bf072824b11892a60af02ff310ba`) that introduced the verification entry.
- **Commit SHA**: ``930c346070c5f866ce0638ab0d091e9abae95e38``
- **Verification**: Verified via local SHA verification loop (`grep -oE '[0-9a-f]{40}' AI_CONTEXT.md docs/changelog/*.md | while read -r line; do sha=$(echo "$line" | cut -d: -f2); if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then echo "BLOCKED: fabricated/non-existent SHA $sha"; fi; done` printed 0 output). ✅

## Android Gradle compileSdk Pinning for AAR Metadata Alignment

- **Implementation Detail**: Resolved Android APK compilation failure caused by AAR metadata requirement mismatch. The transitive dependency `flutter_plugin_android_lifecycle` (v2.0.35, pulled in via `file_picker: ^8.0.0`) requires compiling against Android SDK 36 (`compileSdkVersion 36`), whereas default `flutter.compileSdkVersion` resolved to a lower version. Updated `frontend/android/app/build.gradle.kts` to explicitly pin `compileSdk = 36`. Exact error signature resolved: `checkDebugAarMetadata... Dependency 'flutter_plugin_android_lifecycle' requires 'compileSdkVersion' 36 or higher`. Updated troubleshooting matrix in `frontend/CONNECTING_TO_BACKEND.md`.
- **Commit SHA**: ``c1f00d3d026207acb4f78741afaae121c07afa88``
- **Verification**: Verified via `flutter analyze` (0 issues), `flutter test` (35/35 test suites passing), and local SHA verification check. ✅

## Job Completion Payment Method Distinction (COD vs Non-COD cash_collected Gate)

- **Implementation Detail**: Resolved a financial-logic bug in `completeJob()` (`frontend/lib/providers/employee_jobs_provider.dart` and `frontend/lib/screens/employee_jobs_screen.dart`). Previously introduced in commit `8f20aa6...`, `completeJob()` hardcoded `cash_collected: true` for all job completion requests sent to `POST /users/jobs/complete`. For COD (cash-on-delivery) jobs, the backend handler (`handlers.go:CompleteJob`) checks `cash_collected: true` as an explicit confirmation gate to trigger immediate platform-fee deduction from the tenant owner's wallet. Hardcoding this to `true` automatically triggered fee deduction on COD jobs without verifying cash was physically collected by the employee. Updated `completeJob(String jobId, {bool cashCollected = false})` signature to pass `cashCollected` dynamically based on `job.paymentMethod`. Updated `EmployeeJobsScreen` confirmation dialog copy to differentiate COD jobs (`"Confirm Cash Collection & Complete"` with explicit physical cash collection prompt) vs non-COD jobs (`"Complete Job"`). Updated widget tests in `frontend/test/employee_jobs_screen_test.dart` to verify COD vs non-COD dialog copy and payload parameter distinction. Audit of previous test gap: earlier tests used a single COD job fixture and mocked `completeJob` without inspecting the `cash_collected` payload boolean.
- **Commit SHA**: ``73dc64ca3d34bf45333df400cc1fff336e1cf166``
- **Verification**: Verified via `flutter analyze` (0 issues) and `flutter test` (51/51 test cases passing across all 5 widget test cases covering COD vs non-COD flows). ✅

## Separate WebSocket & Read-Endpoint Rate Limiters from Write-Action Limits

- **Implementation Detail**: Separated overly-restrictive blanket 5-req/min rate limiters into dedicated read and connection limiters to prevent chat lockouts during normal client lifecycle reconnections and smooth out high-frequency data browsing. In `chat-service` (`services/chat-service/internal/handlers/chat.go`), introduced `wsLimiter` (`chat:ws`, 30 req/min) for `GET /chat/ws`, while keeping `HandleCreateTicket` on `limiter` (`chat`, 5 req/min). In `user-service` (`services/user-service/internal/handlers/handlers.go`), introduced `readLimiter` (`user:read`, 30 req/min) for read-heavy endpoints (`GetOwnerJobs`, `GetCustomerJobs`, `GetLedger` at both call sites, `GetRatings`, `GetReconciliationQueue`), while preserving 5 req/min write limits on `WalletDeposit`, `RateJob`, `CancelJob`, `ProposePrice`, `RespondPrice`, `TrackJob`, and `ResolveReconciliation`.
- **Commit SHA**: ``131a8a8133b8a4b7f58ada9a92cb0ed0cc0e6e96``
- **Verification**: Verified via unit test suites in `chat-service` (`TestHandleWebSocket_RateLimiting`) and `user-service` (`TestGetJobsByOwner`, `TestGetJobsByCustomer`, `TestRateJob_RateLimiting`, `TestGetLedger_RateLimiting`, `TestGetReconciliationQueue`), `gofmt`, `go build`, and `go vet`. ✅





