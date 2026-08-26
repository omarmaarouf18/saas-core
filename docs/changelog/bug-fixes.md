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






## Resilience Wrapper Cancelled Streamed Proxied Responses (SSE Dead Through Gateway)

- **Implementation Detail**: Fixed a Critical availability defect in `shared/infra/resilience/resilience.go` affecting both `ResilienceClient.Do` and `ResilienceRoundTripper.RoundTrip`. The per-attempt timeout context was created with `context.WithTimeout` and released via `defer cancel()` INSIDE the circuit-breaker closure; because the closure returns the `*http.Response` immediately after headers arrive, `cancel()` fired before `httputil.ReverseProxy` (or any caller) read the body, truncating every streamed/large proxied response — production SSE notification streams through the API gateway died right after the first buffered chunk. The fix bounds only time-to-response-headers using a stoppable `time.AfterFunc` timer and transfers cancellation ownership to a new `cancelReadCloser` body wrapper that fires `cancel` exactly once on `Body.Close()`, keeping bodies readable for their full caller-governed lifetime while still releasing context resources on error paths. Added regression tests in `shared/infra/resilience/resilience_test.go` (`TestResilienceRoundTripper_StreamingResponseSurvivesBodyRead`, `TestResilienceClient_StreamingResponseBodyReadable`) and the previously missing integration test wiring `ResilienceRoundTripper` into the real reverse proxy in `services/api-gateway/internal/proxy/proxy_test.go` (`TestProxyStreamingResponseWithResilientTransport`) — prior proxy tests injected `http.DefaultTransport`, bypassing the wrapper entirely, which is why the defect shipped.
- **Commit SHA**: ``aac250b30a4b31e27879625403c0e49adebfd098``
- **Verification**: Bug reproduced on unfixed code with literal failures `context canceled` (both resilience regression tests) and `unexpected EOF` (gateway integration test); post-fix all three tests PASS, plus `go build ./...`, `go vet ./...`, and full `go test ./... -count=1` pass in both `shared/infra` and `services/api-gateway`. ✅

## GetJob Job-ID Resolution & Customer Map Hydration (user_token Alias Collision)

- **Implementation Detail**: `GET /users/jobs/get` resolved the job ID from the `user_token` query parameter FIRST, falling back to `id`. The Flutter map-tracking provider (`MapTrackingProvider.hydrateCustomerJob`) sent both parameters (`?id=<jobID>&user_token=<JWT>`), so the backend looked up the JWT string as a job ID and customer map hydration always failed with 404 — initial courier position on the customer tracking map never loaded. The handler now resolves the job ID solely from `id` (party authorization still requires `requester_id`/`requester_token`, unchanged). `MapTrackingProvider.hydrateCustomerJob` updated to send `{id, requester_id}`, matching the contract already used successfully by `MarketplaceProvider.fetchJobStatus` polling.
- **Commit SHA**: ``ee50f26df5ec65935c7a6d4d2117cd30e3742d6d``
- **Verification**: New regression test `TestGetJob_UserTokenParamDoesNotShadowJobID` — pre-fix literal failure: "expected 200 when id and user_token are both supplied, got 404 {"error":"job not found"}"; post-fix asserts 200 for `?id=&requester_id=` and that appending a legacy `user_token` can no longer shadow ID resolution. Frontend: `flutter analyze` → "No issues found!", `flutter test test/map_tracking_test.dart` → "All tests passed!" (6/6). Full user-service module suite passes. ✅

## CreateTicketDialog Ticket ID Display & Snackbar Render Order

- **Implementation Detail**: Two defects in the ticket-creation success path (`frontend/lib/widgets/create_ticket_dialog.dart`). (1) The dialog read `res['id']` from the create response, but chat-service serializes `ComplaintTicket.ID` with JSON tag `ticket_id` — every success toast displayed "Ticket ID: " with an empty value. (2) The dialog called `Navigator.of(context).pop(res)` BEFORE invoking `ThemedSnackBar.showSuccess(context, …)`; popping first deactivated the dialog's context, so `ScaffoldMessenger.of(context)` resolved against an unmounted element and the success snackbar never rendered at all — affecting real users, not just tests. The snackbar now displays the backend `ticket_id` and is shown before pop.
- **Commit SHA**: ``2239300c8bb44082b1e19ef74676a8378e9692b8``
- **Verification**: New widget test "Success snackbar displays the real backend ticket_id" — pre-fix literal failure: "Found 0 widgets with text containing Ticket ID: ticket-999"; post-fix passes. Full `test/create_ticket_test.dart`: 6/6 pass. `flutter analyze`: "No issues found!". ✅

## Cancellation Reason Missing from Customer Job History DTO

- **Implementation Detail**: `CustomerJobResponse` (`services/user-service/internal/models/models.go`) — the redacted DTO served by `GET /users/jobs/mine` — omitted `cancellation_reason`, so the Flutter "My Orders" screen's cancellation callout (`customer_jobs_screen.dart` reads `job.cancellation_reason`) could never render why an order was cancelled. Added the field (`json:"cancellation_reason,omitempty"`) and mapped it in `NewCustomerJobResponse`. The customer is a party to their own job, so no disclosure concern arises.
- **Commit SHA**: ``7518259e33fa6eedef8f1966df6f4f05a61e87aa``
- **Verification**: New unit test `TestNewCustomerJobResponse_IncludesCancellationReason` — pre-fix literal failure: "expected cancellation_reason in marshaled DTO, got: {\"id\":\"job-cxl-1\",...\"status\":\"cancelled\"...}" (field absent); post-fix asserts the reason round-trips through JSON. Full user-service module suite passes (config/handlers/models/store all `ok`). ✅

## WebSocket Origin Policy Decoupling (Non-Browser Clients + Configurable Client Origin)

- **Implementation Detail**: Two coupled realtime-availability defects. (1) `chat-service`'s `CheckOrigin` enforced strict `Origin == allowedOrigin`, rejecting handshakes with no Origin header — exactly what non-browser clients (dart:io `WebSocket` on Android/iOS, CLI tools) send — so mobile connections depended on forging a browser-only header. The decision is now `isOriginAllowed`: empty Origin admitted (CSRF is a browser threat model), present Origin matched exactly. (2) The Flutter client hardcoded `headers: {'Origin': 'http://localhost:3000'}` in both `ChatProvider` and `MapTrackingProvider`; changing the server's `ALLOWED_ORIGIN` in production would have broken every WebSocket handshake with no client-side remedy short of source edits. Replaced with the `chatWsOrigin` constant (`String.fromEnvironment('CHAT_WS_ORIGIN', defaultValue: 'http://localhost:3000')`) in `frontend/lib/core/constants.dart`, pairable per build via `--dart-define`. End-to-end production origin pairing remains NOT device-verified and is documented as such in AI_CONTEXT.md.
- **Commit SHA**: ``e49425cb0b0d2343b14d319577085c52462e66d4``
- **Verification**: New table test `TestIsOriginAllowed` passes (empty → admit; exact match → admit; scheme-mismatch/suffix-spoof (`localhost:3000.evil.com`)/foreign origins → reject). Full chat-service suite passes. Frontend: `flutter analyze` → "No issues found!", full `flutter test` → "+289: All tests passed!". ✅

## RTL Directional Alignment & Accessibility Semantics Hardening (P7)

- **Implementation Detail**:
  - Fixed two trailing-edge `Alignment.centerRight` alignments (home_screen job-card cancel action, wallet_screen platform-fee note) to `AlignmentDirectional.centerEnd` so they mirror correctly under RTL (ar_EG). Full directional audit: zero `EdgeInsets.only(left:/right:)` in screens/, all fromLTRB paddings symmetric.
  - Added accessibility tooltips to all 11 previously-unlabeled icon-only `IconButton`s via 6 new localized arb keys (`tooltipClose`, `tooltipOpenChat`, `tooltipRemoveAddress`, `tooltipZoomIn`, `tooltipZoomOut`, `tooltipRecenter`; English + Egyptian Arabic). Post-fix audit: 0 icon-only buttons without semantics.
  - Aligned two widget-test harnesses (customer_marketplace, owner_configuration) with the production MaterialApp by adding localization delegates; tooltips use the null-safe `context.l10n` fallback convention.
- **Commit SHA**: ``f54f867119470cba0060985255b671d658899796``
- **Verification**: Verified via `flutter analyze` (No issues found!), full suite `flutter test` (304/304 All tests passed), and re-run of the icon-only button audit script (0 remaining). ✅

## Complete Frontend l10n Sweep — All Hardcoded UI Strings Routed Through ARB (Audit A2)

**Date**: 2026-08-22
**Category**: Bug Fix / Localization
**Related Commit SHA**: ``679660737018f3d5959062cfedb6aeae3be69ec8``

- **Re-runnable Audit Script (`scripts/frontend_l10n_audit.py`)**: Multiline-aware full-text scanner auditing string literals at `Text(`/`Text.rich(`/`uppercaseLabel(`/provider-error/named-property call sites across all 87 dart files under `frontend/lib` (excluding l10n infra and theme.dart). Skips test keys, routes, asset paths, snake_case enums, lowercase technical tokens, and literals already interpolating `l10n.*`. Pre-fix: **241 literals audited, 202 flagged** (168 real fixes + 34 accepted exceptions).
- **Scanner Blind Spots Found & Fixed Manually**: 29 validator `return "..."` literals (employee_screen ×10, signup ×3, create_service_dialog ×8, deposit_funds_dialog ×2, forgot_password ×1, otp_screen ×1, email_change_dialog ×2 + required-label), 4 StatCard `value:` unit strings ("X Credits" — property not in scanner list), 5 ternary-branch copy strings (courier-assigned variants, employee freeze/unfreeze labels), and 2 KYC subtitle ternaries.
- **ARB Keys Added**: 185 keys injected into `app_en.arb` + Egyptian colloquial `app_ar.arb` via idempotent injector script `scripts/add_a2_l10n_keys.py`; `flutter gen-l10n` regenerated. Placeholders use the existing `@key` metadata convention. English output is byte-identical to prior literals (zero visual/copy change).
- **Call Sites Replaced**: All flagged sites routed through `context.l10n`/local `l10n` across 24 screen files, 8 widget files, and 1 provider file, with `const` dropped where localization made expressions non-const.
- **Dead Provider Error Strings Removed**: Two hardcoded GPS error strings in `EmployeeLocationProvider` were never rendered by any UI path (the permission-denied/service-disabled states render their own localized panel); removed rather than localized. Verified no test asserted them.
- **Accepted Exceptions (33, documented not fixed)**: brand names ('Quick Delivery' in MaterialApp.title; 'QD' login logotype), 4 `#QD-<id>` tracking-ID badges (brand format, no translatable word), and 27 strings in the kDebugMode-gated debug-only component library screen (never shipped to production users).
- **Golden Date-Dependency Root Cause & Fix**: The notifications golden fixtures used timestamps pinned to 2026-08-21 while `_getSectionTitle` grouped against the real system clock — guaranteeing failure every day after generation date (first reproduced on clean HEAD at commit ``d0e487e...``, pre-existing). Added injectable `clock` parameter to `NotificationsScreen`, pinned it in the harness, and regenerated baselines using the FULL-file command (single-test filtered regeneration produces baselines inconsistent with full-suite global state — capture-ordering caveat now documented in STATUS.md).
- **Verification**: `flutter analyze` → No issues found!; `dart format --set-exit-if-changed lib/` → exit 0; `scripts/frontend_composition_gate.sh` → pass; full suite `flutter test` → **305/305 All tests passed**; post-fix audit re-run → **33 flagged = exactly the documented exceptions**; golden verification run repeated 3× → 7/7 each. ✅
## Collision-Proof Ledger & Record ID Generation (tx-%d Nanosecond Collisions)

- **Implementation Detail**: All persisted record IDs in `user-service` built from `time.Now().UnixNano()` (`fmt.Sprintf("tx-%d", …)` and the `payout-%d` / `rate-%d` / `sub-%d` variants) collide whenever two concurrent operations read the wall clock in the same nanosecond. Because `TransactionLedger.ID` maps to `_id`, the losing insert aborts with a duplicate-key error — and `Deposit`, `LockEscrow`, and `RejectPayoutRequest` only log that failure, silently dropping the immutable audit entry for a real money movement (balance mutated, no ledger trace). Replaced all 12 UnixNano-based `_id` generation sites with a collision-proof scheme: `newRecordID(prefix, suffix)` in `services/user-service/internal/store/mongodb.go` producing `<prefix>-<8 crypto/rand bytes hex><suffix>` (e.g. `tx-a1b2c3d4e5f60718-release`), matching the existing `handlers.generateID` entropy pattern. Covered sites: ledger entries in `Deposit`, `LockEscrow`, `ReleaseEscrowWithSplit` (-release/-payout pair), `CreatePayoutRequest` (+ its `-payout-req` entry), `RefundEscrow` (-refund), `RollbackEscrow` (-rollback), `RejectPayoutRequest`; payout request IDs; rating IDs (`rate-` + `generateID()`); subscription IDs (`sub-` + `generateID()`).
- **Commit SHA**: ``a2e20e55c9771a31ae29deee29bce5dfe72d07b2``
- **Verification**: New two-layer regression test `TestLedger_ConcurrentDepositNoIDCollision`. Pre-fix literal failure (Layer 1 exercised the verbatim production expression under 20000 concurrent generations): `PRODUCTION ID EXPRESSION COLLIDES UNDER CONCURRENCY: 84 duplicate tx IDs out of 20000 generations (each duplicate would abort its ledger insert on _id)` with colliding samples `tx-1787373670033391766`, `tx-1787373670033666447`, `tx-1787373670033797848` logged; repeated runs produced 79–101 duplicates every time. Layer 2 (end-to-end) seeded 400 concurrent `Deposit` calls against live MongoDB and asserts one persisted deposit ledger entry per deposit — this layer passed even pre-fix on this host (Linux nanosecond clock resolution spreads DB-bound goroutines' clock reads; documented honestly rather than claimed as a pre-fix failure). Post-fix: full test passes 5/5 consecutive runs (`go test ./internal/store -run TestLedger_ConcurrentDepositNoIDCollision -count=5` → `ok ... 2.413s`, EXIT_CODE=0). Full user-service suite passes: config/handlers/models/store all `ok` via `go test ./... -count=1` (EXIT_CODE=0). ✅

## RefundEscrow Fallback-Path Compensating Reverts (Partial-Failure Inconsistency)

- **Implementation Detail**: `MongoDB.RefundEscrow` (`services/user-service/internal/store/mongodb.go`) executes three sequential steps — job CAS (deduct `locked_escrow_amount`, set status `cancelled`), wallet CAS (`escrow_balance -= amount`, `withdrawable_balance += amount`), ledger insert. Inside the non-transactional fallback path (standalone mongod without replica-set transactions, or session-start failure), each step commits immediately; if a later step failed, nothing undid earlier ones — a wallet-step failure left the job cancelled with its lock deducted and funds stranded, and a ledger-step failure left funds moved to withdrawable with zero audit trail and the job mutated. Added compensating reverts mirroring the established `ReleaseEscrowWithSplit` pattern: prior job status is captured before mutation, `revertJob()` fires on wallet-step failure, and `revertWalletAndJob()` fires on ledger-step failure — all gated to fallback mode where transaction abort cannot clean up.
- **Commit SHA**: ``78d4d144a59ecaa7f0745f638bcf9ecaf3f1461a``
- **Verification**: New regression test `TestRefundEscrow_FallbackLedgerFailureRevertsFunds` deterministically forces the final step to fail by rebinding the unexported ledger collection handle to an invalid namespace (steps a+b complete normally). Pre-fix literal failure, identical across 3+ runs: `FUNDS NOT COMPENSATED AFTER LEDGER FAILURE: escrow=0.00 withdrawable=100.00, want escrow=60.00 withdrawable=40.00 (money moved with no audit trail and no revert)` + `JOB MUTATION NOT COMPENSATED: status="cancelled" locked=0.00, want active/60.00`. Post-fix: 5/5 consecutive passes (`go test ./internal/store -run TestRefundEscrow_FallbackLedgerFailureRevertsFunds -count=5` → `ok ... 2.103s`). A wallet-step-failure variant was attempted but proved vacuous (the sabotaged handle is shared with the entry read, aborting before any mutation) and was removed rather than kept green for the wrong reason — documented in the test file header. Full user-service suite: config/handlers/models/store all `ok`. ✅

## COD Actual-Cash Capture & Phantom Fee Display Removal

- **Implementation Detail**: Two financial-display/capture defects in `CompleteJob` (`services/user-service/internal/handlers/jobs_handlers.go`). (1) COD completions never recorded how much cash was actually collected — the employee collects real money at the door, but the system only logged a recomputed estimate from CURRENT service pricing; on-site shortfalls/discounts were silently unrecoverable and the response echoed the estimate as fact. Added `actual_cash_amount` to `CompleteJobRequest` and `models.Job` (+`OwnerJobResponse`), persisted cent-rounded inside `CompleteCODJob`'s atomic status flip, and echoed as `total_amount`. (2) Non-COD completion responses derived a percentage fee/net split from mutable `platform_config` (defaulting to 15%) while `ReleaseEscrowWithSplit` credits 100% per ADR-0017 — under any legacy/non-zero config the displayed `net_to_tenant` contradicted the real credit by exactly the phantom fee. Response now reflects actual movement: `platform_fee: 0`, `net_to_tenant == released amount`. Also added `store.UpsertPlatformConfig` (ops parity with `UpsertSubscription`).
- **Commit SHA**: ``0f031bf2a21a72515a367d86b589b4be54bf8d76``
- **Verification**: New regression tests `TestCompleteJob_CODCapturesActualCashCollected` and `TestCompleteJob_NonCODResponseMatchesRealCredit`. Pre-fix literal failures: `PHANTOM COLLECTION AMOUNT: response total_amount = 100, want 85.50 (the actually-collected cash)` + `CASH COLLECTION DATA GAP: persisted job JSON {...} lacks actual_cash_amount=85.5 (real cash collected was never captured)`; and with a simulated legacy 15% config: `PHANTOM FEE DISPLAY: wallet was credited 100.00 but response net_to_tenant = 85.00 (displayed split contradicts real fund movement)` + `PHANTOM FEE DISPLAY: response platform_fee = 15.00, want 0`. Post-fix: both pass 3/3 consecutive runs; full user-service suite passes (`go test ./... -count=1`: config/handlers/models/store all `ok`). ✅

## Money-Precision Cent Boundaries (float64 Ingestion Rounding)

- **Implementation Detail**: Client-supplied monetary values flowed into the financial pipeline as raw float64 with sub-cent residue intact: transport fare proposals (`TrackJob`), standalone proposals (`ProposePrice`), accepted prices driving escrow locks (`RespondPrice`), wallet deposits, and payout deductions. Examples reproduced pre-fix: deposit `10.99999999` produced `total_balance = 10.9999999900`; payout `20.0055555` was logged by `%.2f` formatting as `amount=20.01` while storing and deducting the unrounded value (withdrawable drifted to `479.9944445000`). Added a single sanctioned helper `roundMoney()` (half-away-from-zero at cents) in `services/user-service/internal/handlers/handlers.go`, applied at all five ingestion boundaries: TrackJob proposal, ProposePrice (re-validated after rounding), RespondPrice active/agreed price, WalletDeposit (post-validation, zero-after-round rejected), RequestPayout (same).
- **Coverage vs Deferred (float64 money audit)**: Covered — all client-money ingestion boundaries above; server-computed amounts were already cent-rounded (`math.Round(...*100)/100`) in TrackJob pricing, CompleteJob ADR-0007 settlement, COD actual-cash capture, and exact-locked-escrow release/refund. **Deferred**: full integer-minor-units migration of `Wallet`/`TransactionLedger`/`PayoutRequest`/`Service` money fields — requires coordinated MongoDB document migration, API contract changes for every consumer, and frontend currency formatting changes; explicitly out of scope for this pass and tracked as the follow-up architectural task.
- **Commit SHA**: ``09ad08bcbff6a74ad3b7a34c6ee8f72f29b822ce``
- **Verification**: Five new regression tests in `money_precision_regression_test.go`. Pre-fix literal failures: `UNROUNDED PROPOSAL PERSISTED: proposed_price = 40.123456789, want 40.12`; `proposed_price = 51.9876543210, want 51.99`; `UNROUNDED AGREED PRICE: agreed_price = ...want 44.44`; `SUB-CENT DEPOSIT RESIDUE: total_balance = 10.9999999900, want 11.00`; `SUB-CENT PAYOUT RESIDUE: payout amount = 20.0055555000, want 20.01` + `SUB-CENT PAYOUT DEDUCTION DRIFT: withdrawable = 479.9944445000, want 479.99`. Post-fix: all five pass 3/3 consecutive runs; full user-service suite passes. ✅

## Semver Prerelease Parsing in Client Version Gate

- **Implementation Detail**: `ParseSemVer` (`services/api-gateway/internal/version/semver.go`) stripped `+build` metadata but not `-prerelease` suffixes, so `"1.2.3-beta"` yielded patch component `"3-beta"` and `strconv.Atoi` failed — the `VersionGate` middleware rejected every prerelease client build. The prerelease segment is now stripped after build-metadata stripping; numeric major.minor.patch drives the minimum-version comparison (prerelease ordering is not required by the gate).
- **Commit SHA**: ``218748d7100e7fce5d8b39b4fdeaad81810ad173``
- **Verification**: New table cases (`1.2.3-beta`, `1.2.3-beta.1+build5`, `v2.0.0-rc.2`). Pre-fix literal failures: `invalid semver integers in "1.2.3-beta"` (+ both other variants). Post-fix: full api-gateway suite passes (iputil/middleware/proxy/version all `ok`). ✅

## Rejected-Payout Fund Stranding on Restore Failure (QA Audit Q2)

- **Implementation Detail**: Independent QA audit finding. `MongoDB.RejectPayoutRequest` (`services/user-service/internal/store/mongodb.go`) consumed its `requested -> rejected` CAS **before** the wallet restore, which was a separate unguarded write. When the restore failed — wallet document missing (`MatchedCount == 0`) or a transient error — the function returned with the payout already `rejected`: retry was refused by the consumed CAS slot ("not found or not in requested state"), no compensating path existed anywhere, and no `payout_refund` ledger entry was ever written — the owner's deducted funds were permanently stranded with zero audit trace. The wallet restore is now wrapped in a compensating revert mirroring the established RefundEscrow/ReleaseEscrowWithSplit pattern: any restore failure reverts the status flip through a guarded CAS back to `requested` (rejection_reason unset) so the rejection stays retryable; if the compensation itself fails it logs `[USER-STORE] CRITICAL` with the payout ID. Double-reject CAS protection and the happy path are unchanged.
- **Commit SHA**: ``03d88c370cc665720208a106438bf6b8ff072d11``
- **Verification**: New regression test `TestRejectPayoutRequest_FailedRejectStaysRetryable` (wallet document removed mid-flow). Pre-fix literal failure: `STRANDED REJECTION: payout consumed by failed reject (status="rejected"); must revert to "requested" so the rejection can be retried` with first reject error `wallet for tenant qa-stuck-reject not found while restoring rejected payout` and retry refused via `not found or not in requested state`. Post-fix: test passes 5/5 consecutive runs including full recovery arc (retry after wallet recreation restores withdrawable to exactly the refund amount, one `payout_refund` ledger entry, terminal status `rejected`, triple-reject still CAS-refused). Full user-service suite green (config/handlers/models/store all `ok`; handlers 219s against isolated QA containers). Disclosure: one uncaptured store-package transient occurred during the first post-fix full-suite run (output beyond the FAIL line not retained); four subsequent store runs plus a complete suite run were all green — attributed to slow mounted-FS variance, noted per repo honesty rules rather than silently retried. ✅

## Payout Request Idempotency Keys (QA Audit Q1)

- **Implementation Detail**: Independent QA audit finding. `POST /users/wallet/payout/request` had no idempotency handling — a client network retry of the same logical request created duplicate payout requests and deducted funds twice (pre-fix literal repro: `first attempt status=201, retry status=201; payout requests created=2, withdrawable=100.00 (started 500.00)`). With an `Idempotency-Key` header (or body field) present, the request is now reserved atomically via Redis SETNX namespaced per verified owner (`idempotency:payout:<tenant>:<key>`, 24h TTL, pending marker), mirroring TrackJob's established pattern (`services/user-service/internal/handlers/handlers.go`). Retries replay the stored payout as a **drop-in HTTP 200 with the identical top-level shape as the 201 create** plus an `X-Idempotent-Replay: true` header; concurrent in-flight duplicates receive `409 duplicate_request_in_progress`; failure paths release the reservation so legitimate retries work. Requests without a key keep unchanged per-request semantics; Redis unavailability degrades to non-idempotent operation (logged), matching TrackJob's availability behaviour.
- **Commit SHA**: ``4e30aad8079c6f81f4c3d7abbdbe4c9485e41725``
- **Verification**: New regression test `TestRequestPayout_IdempotencyKeyReplaysAndDeduplicates`. Pre-fix literal failures: `RETRY NOT REPLAYED: same Idempotency-Key returned 201, want 200`; `RETRY DOUBLE-CREATED: retry returned payout "payout-16bb…", want original "payout-5a9e…" (funds deducted twice)`; `DOUBLE DEDUCTION: withdrawable = 100.00 after keyed retry, want 300.00`. Post-fix: passes 3/3 consecutive runs asserting replay parity (same payout ID, replay header set on retry and absent on create), single deduction (300.00 after keyed pair), independent creation under a distinct key, legacy no-key behavior (4 total requests, exactly 420.00 deducted). Full user-service suite green against isolated QA containers. ✅

## CancelJob Trap Arms Removed — Narrow Reason Stamping (QA Audit Q5)

- **Implementation Detail**: Independent QA audit finding (latent HIGH / current MEDIUM). `MongoDB.CancelJob`'s `$in` filter included `escrow_reconciliation_required` and `cancelled` while the write touched only status/reason — never locked escrow. Safety depended entirely on the handler's undocumented RefundEscrow-first ordering: any direct/internal caller cancelling a reconciliation-flagged funded job would strand the lock permanently (resolution gated on recon state; every other guarded path excludes cancelled). Reproduced live pre-fix: `TRAP ARM CONFIRMED: direct store cancel of a reconciliation-flagged FUNDED job succeeded — job status="cancelled", locked_escrow_amount=60.00 still recorded, wallet escrow_balance=60.00 still held, and no refund path remains`. Split into two operations: `CancelJob` is now the non-money transition only (`$in`: active/pending/awaiting_price_response), and new `SetCancellationReason` stamps the reason through a CAS filtered strictly on `status=cancelled`. Handler wiring: COD jobs cancel directly through the narrowed op (no escrow involved); non-COD jobs stamp via `SetCancellationReason` after their existing RefundEscrow call. Reconciliation-flagged jobs are now correctly reachable only via their dedicated resolution path, and a rejected direct cancel leaves the job fully recoverable (verified: post-rejection RefundEscrow restores balances to 100.00/0.00).
- **Commit SHA**: ``be46de20e3fc6c873be45c6d7e7a3c912c57d8c6``
- **Verification**: New store-level regression tests in `cancel_job_guard_regression_test.go`. Pre-fix literal failure quoted above. Post-fix: `TestCancelJob_ReconFundedJobNotSilentlyCancellable` and `TestSetCancellationReason_OnlyStampsCancelledJobs` pass 3/3 consecutive runs each (rejection + state preservation + recovery arc; reason stamping refuses non-cancelled jobs). Full user-service suite green on the fix branch (`go test ./... -count=1`: config/handlers/models/store all `ok`, including all pre-existing COD/non-COD/reconcile cancel flows through the split path). ✅

## Double-Submit Protection for Network-Triggering Controls (QA Audit A4)

- **Implementation Detail**: Systematic audit of every `onPressed:`/`onTap:` across all 28 production screens and 30 widgets (~170 tap sites), each traced to its provider call and classified: NONE / DEBOUNCE-600MS / ISLOADING-DISABLE / LOCAL-BUSY-FLAG. The six headline money flows were already triple-guarded (booking dialog confirm, deposit, payout two-step, subscription change, employee complete-job, KYC per-slot upload — local flag set synchronously before the first await plus wired `isLoading`). Four real gaps closed:
  - **Priority 1 — reconciliation resolve (escrow release/refund)**: after `ConfirmActionDialog` closed, `await provider.resolveJob(...)` ran with no busy state on `owner_reconciliation_queue_screen.dart`; a second Release/Refund confirm during the pending POST fired a duplicate money-moving request (the exact window a slow backend leaves open). New `_resolvingJobId` flag scopes strictly to the post-confirm await — buttons hard-disable with spinners, entry refuses re-entry. A pre-dialog variant was tried first and REVERTED after the existing suite demonstrated it shows misleading in-flight spinners while the user is merely deciding.
  - **Template fix — PrimaryButton/SecondaryButton in-flight lock**: when the handler returns a Future, the button ignores taps until completion. The pre-existing 600ms timestamp debounce cannot cover calls that outlive it (the classic second tap when "nothing happened"). Zero call-site changes; sync handlers keep pure timestamp behavior. This alone also closes settings-screen logout (previously debounce-only).
  - **chat_screen send**: raw InkWell with zero guard and controller cleared only post-await — double-tap delivered duplicate messages; `_isSending` flag now guards both InkWell and keyboard-send paths.
  - **ThemedBanner retry**: raw TextButton shared by ~10 screens (three re-fire state-changing submits) now carries the standard 600ms tap guard with injectable `nowProvider`.
- **Commit SHA**: ``4babf7cb205d727cc325ac1585f5b48f19776ba8``
- **Verification**: new `frontend/test/a4_double_submit_test.dart` asserts network-call/handler COUNTS (not disabled visuals): double-taps past the debounce window against completer-gated mocks fire exactly once — both button types, banner retry, reconciliation resolve end-to-end through the confirm dialog (including spinner-state and hard-disable assertions mid-flight), chat send, logout. Full suite 369 passed / 0 failed (baseline 361 at `e50cce0`); `flutter analyze` 0 issues. Deferred as documented-benign: read-only refresh IconButtons ×5, marketplace search/switch/sort GET triggers, OTP auto-submit keystroke path (server rate-limits), `FormScreenTemplate` busy wiring currently supplied by zero callers (dead-but-correct template path noted for future adoption). ✅

## Error-Handling Consistency Across All Network Call Sites (QA Audit A5)

- **Implementation Detail**: Failure-path audit of all 43 provider network methods plus ApiClient internals and every caller: try/catch presence, sink (getter/swallow/rethrow), UI surface, message style, plus fire-and-forget futures and timeout behaviour. Findings closed:
  - **No request timeout existed anywhere** (`api_client.dart`): a hung backend left loading states unresolved forever — including money flows mid-dialog. Every request path now carries an injectable `requestTimeout` (default 30s; refresh POST included), `HttpClient.connectionTimeout` 15s, and `TimeoutException` passes through the catch-alls so the established `friendlyErrorMessage` mapper renders connectivity copy.
  - **HTTP 426 forced-update gate was dead code**: `ApiClient.onUpdateRequired` was never assigned, so a mandated update surfaced as unmapped-status generic text. New `UpdateGate` (lib/core/update_gate.dart) wired in main.dart through a shared navigator key: navigates to `UpdateRequiredScreen` replacing the whole stack, idempotent per session, defensive body parsing with screen-side defaults.
  - **Raw exception dumps on four user-facing failures**: booking confirm (`bookingFailed(e.toString())`), subscription change (literally `"Error: <dump>"` via a copy-pasted rating l10n key), rating submit, create-service dialog, chat send — all now route through `friendlyErrorMessage(e)` inside their existing message templates (status-mapped copy; non-auth contract intentionally discards backend strings).
  - **verifyOtp token-less 2xx was a silent dead-end** on an auth-critical flow: success-shaped response without a token returned false with `_error == null`, rendering nothing. Now sets the generic fallback so the OTP screen always shows feedback.
  - **Marketplace outage masqueraded as empty state**: failed `fetchServices` rendered "No services found nearby." — customers read a backend outage as "no couriers exist". Wired the template's `errorMessage`/`errorWidget` (retryable banner) following the customer_jobs pattern.
  - **updateOwnProfile** now prefers the provider's stored verbatim message (auth-path endpoint), aligning with the adjacent email-change dialog pattern.
- **Commit SHA**: ``0e4a42c6b850991b4220c61160ee0d5b1c5b8066``
- **Verification**: new `frontend/test/a5_error_handling_test.dart` — 10 failure simulations asserting user-visible outcomes: hung-mock transport timeouts throw `TimeoutException` (get+post) and map to connectivity copy; 426 fires the callback + throws status-426 + gate navigates exactly once; marketplace outage shows retryable banner and NOT the empty-state copy; booking/subscription/create-service/chat failures show mapped copy with zero raw `Exception:`/backend-string leakage; verifyOtp dead-end sets visible error. Existing rating-screen failure test re-pinned from asserting the raw dump to asserting the friendly contract. Full suite **379 passed / 0 failed** (baseline 369 at `8040a7c`); `flutter analyze` 0 issues. Deferred with reasoning: map-screen hydration errors remain unread (both screens render only subscription errors — widget harness for flutter_map tiles doesn't exist yet); job-status poll stays silent by design pending a product decision on poll-failure UX; employee audit-log/service/home dashboard informational reads share the silent-empty pattern (batch follow-up candidate); no global `runZonedGuarded`/`FlutterError.onError` net (app-level hardening decision); three hardcoded-EN success strings (l10n debt, not error-path). ✅

## Disposal Correctness & Live-Connection Teardown (QA Audit A6)

- **Implementation Detail**: State-management audit of every `ChangeNotifier` subclass (11 providers), every `State<T>` holding controllers/subscriptions/timers/focus nodes across 28 screens + 30 widgets, plus all `addListener` pairings and `Timer.periodic` sites. Cross-referenced creation sites against dispose bodies file by file. Findings closed:
  - **P1 — chat_screen disconnect was dead code** (`lib/screens/chat_screen.dart`): dispose() scheduled the ChatProvider teardown inside a post-frame callback guarded by `if (mounted)` — `mounted` is always false once dispose runs, so `disconnect()` never executed and the app-lifetime provider's WebSocket, stream subscription, and exponential-backoff reconnect timer survived every screen pop. Literal pre-fix repro: `Expected: <1> / Actual: <0>` on a spy-provider disconnect counter.
  - **P1 — map screens never disconnected at all** (`customer_job_map_screen.dart`, `owner_fleet_map_screen.dart`): both call `MapTrackingProvider.connectAndSubscribe(...)` in initState with zero `disconnect()` call sites anywhere in the codebase — job/fleet location streams kept pumping after leaving either map. Pre-fix repro: `Expected: <1> / Actual: <0>` ×2.
  - **Shared-pattern fix over one-offs**: new `frontend/lib/core/provider_connection_cleanup.dart` mixin. Screens register teardown closures while `context` is valid; they run exactly once when the State disposes, unconditionally (no mounted guard — the precise bug class being fixed), deferred to end-of-frame so `notifyListeners()` never fires during tree finalization. Adopted by chat + both map screens.
  - **Same-frame unmount ordering hardening exposed by the new teardown**: when a screen and its ancestor `ChangeNotifierProvider` unmount together (logout swaps whole tree), the deferred disconnect can land after the framework disposed the provider. `ChatProvider.disconnect()` and `MapTrackingProvider.disconnect()` are now disposal-tolerant (`_isDisposed` guard; silent `_teardownConnection()` shared with dispose). Surfaced by the localization/employee-audit suites mid-pass; regression-tested directly (`disconnect()` after `dispose()` is a silent no-op).
  - **P2 — NotificationsProvider SSE lifecycle**: the `.listen()` result was discarded (uncancellable subscription); `unsubscribe()` early-returned on `!_isConnected`, skipping cleanup precisely when an errored-but-open connection most needed releasing; and any MyApp rebuild (theme/locale/auth changes) while disconnected spawned a duplicate SSE HTTP connection. Now the provider owns its stored subscription, cancels-before-replace (at most one underlying connection ever), unsubscribes unconditionally, overrides dispose, and exposes an injectable `sseStreamSource` for lifecycle tests. Honest limitation: pre-fix duplication was externally unobservable (the discarded listen result made it invisible to any test), so this item's pre-fix evidence is code-level audit rather than a failing repro; post-fix behaviour is proven by 5 regression tests against a fake stream source.
  - **P3 — OtpPinInput auxiliary focus nodes**: `_buildPinBox` allocated `FocusNode()` inline per box per build (6 fresh nodes per keystroke-driven rebuild), never disposed; now created once in initState and disposed. Measured pre-fix via instance-identity across rebuilds: `Expected: true / Actual: false`.
  - **P3 — my_account_screen email field** allocated an inline `TextEditingController(text: userEmail)` on every rebuild; now an owned, disposed field populated from profile load. **ChatScreen one-shot scroll timer** is now cancelled on dispose (hardening; no user-visible crash path was provable because `hasClients` guards the callback).
- **Commit SHA**: ``dfccd42e229ecabd5f196ffa7826c1250a69fc11``
- **Verification**: new `frontend/test/a6_disposal_test.dart` (spy-provider disconnect counters for all three screens, OTP focus-node identity across rebuilds, post-dispose no-op safety ×2) and `frontend/test/a6_notifications_sse_test.dart` (5 SSE lifecycle assertions). All headline repros failed before the fix and pass after. Two existing suites (`employee_jobs_screen_audit_test.dart`, `localization_test.dart`) initially failed against the stricter teardown contract — their `MockChatProvider` gained the now-mandatory `disconnect()` implementation, converting them into extra coverage of the new guarantee. Full suite **390 passed / 0 failed** (baseline 379 at `afb425d`); `flutter analyze` 0 issues; `dart fix --dry-run` reports nothing to fix (re-confirming the const-constructor pass completeness). Deferred: `component_library_screen.dart` inline controller (kDebugMode-gated debug catalog, zero production exposure); map-screen `Consumer<MapTrackingProvider>` body scope left as-is (marker updates are the high-frequency notify source and must rebuild the marker layer anyway — Selector cannot reduce meaningful work). ✅

## Dark-Mode Correctness & Visual-Consistency Pass (V1 — evidence-driven)

- **Implementation Detail**: Full 28-screen light+dark evidence set rendered via a deterministic scratch harness (pinned Flutter 3.44.6 == CI pin, bundled Poppins preloaded) and visually reviewed screen-by-screen. Findings and fixes, all at token/shared-widget level:
  - **WCAG failures in dark tokens** (`theme.dart`): `outlineVariantDark` #475569 measured 2.36:1 against dark containers (3:1 UI floor) — border hierarchy re-pinned to `outlineDark` #7C8DA6 (5.71/5.29/4.33 on scaffold/surface/container) and `outlineVariantDark` #64748B (4.06/3.75/3.07). New dark `errorContainer/onErrorContainer` pair #5C1A22/#FFDAD6 (10.00:1) replacing the light pair that rendered as a washed-out pink block. New `AppSemanticColors` ThemeExtension exposing brightness-aware success/warning/danger (#4ADE80/#FBBF24/#F87171 in dark — the static light constants collapse to ~2.3–3.9:1 on dark surfaces); read via `context.semanticColors`, light values unchanged.
  - **Static light-tuned color reads migrated**: every `AppColors.success/warning/danger` site (0 remain), all `AppColors.surface/onSurfaceVariant/scaffoldBackground` reads, and `AppColors.primary`-as-foreground sites (headlines/data → `colorScheme.onSurface`, links/accents/icons → `colorScheme.primary`; navy hero/banner/chip backgrounds deliberately kept as brand chrome). Shared widgets fixed at token level: `StatCard` (invisible metric values), `ThemedSectionHeader` + `ThemedEmptyState` (invisible titles), `SecondaryButton` (invisible outlined/destructive labels), `ThemedTextField` (invisible hints, scheme-aware borders).
  - **Three real 360dp overflow bugs** (all pre-existing at the base commit, surfaced by the evidence render): `kyc_document_upload_screen` status card Row +24px (Expanded+ellipsis title); `owner_configuration_screen` location row +96px (LayoutBuilder stacks the map-picker button below coordinates <420dp); `employee_jobs_screen` location-permission banner +8.2px (Expanded+ellipsis title).
  - **AppBar consistency (V-area 3)**: `service_screen` gained its AppBar title (new `myServicesTitle` l10n key en+ar); `customer_jobs_screen` and `subscription_screen` duplicate in-body page headings removed where the AppBar already carries the title (embedded-tab variants keep in-body headers — they render no AppBar). Definitive per-screen AppBar audit: all 28 screens now render chrome exclusively through `AppShell`/templates with the navy default; the only title-less screens are the deliberate full-bleed auth/update gates and embedded tab children.
  - **Typography scale audit (V-area 2)**: zero `fontSize:` outside `core/theme.dart` except two geometry-derived avatar-initial sites (`radius * 0.8` in `entity_avatar.dart`, deliberate); zero raw `TextStyle(` constructions in screens/widgets. No scale gaps found — no new roles needed.
  - **Golden baselines**: 12 regenerated full-file under the pinned environment (light-mode diffs reviewed pixel-by-pixel — only intended hint-tone/headline microshifts); 5 new dark mobile baselines + dark golden tests added (component library, login, notifications, customer jobs, reconciliation queue). `dark_theme_hex_verification_test` re-pinned; `owner_payout_test` made viewport-robust (`ensureVisible`) for the new wallet AppBar.
- **Commit SHA**: ``c4fb6cd84d86dc9bc587cd537b3fe87ccbc89839``
- **Verification**: `flutter analyze` 0 issues; full `flutter test` 462/462 (committed suite 401 = prior 396 + 5 dark goldens; remaining 61 in the deliberately-uncommitted scratch evidence harness). Evidence PNGs reviewed for every dark screen; remaining known-invisible items are harness-only artifacts (MaterialIcons/monospace/Arabic glyphs never rendered in golden env — pre-existing, identical in CI baselines; Ahem-width "Pric" dropdown truncation absent with real Poppins). Deferred: owner-dashboard silent-empty body on provider errors (A5 deferred batch), sort-dropdown label width (harness-font artifact), reconciliation order-label wrap tightness (cosmetic). Decluttering proposals (V-area 5) held for explicit approval — not implemented in this pass. ✅

## Decluttering Pass V2 — Five Densest Screens (user-approved direction)

- **Implementation Detail**: Implements the approved progressive-disclosure direction from the V1 report. Owner Dashboard: jobs preview capped at 3 + VIEW ALL JOBS (History tab), Fleet Overview + Service Reputation sections folded into the quick-access cluster (compact Fleet Live Map card + header-less RatingSummaryCard; 4 cards via a shared `_quickAccessCard` builder that stacks full-width <420dp), urgent actions collapsed to one dismissible row, plus a pre-existing 360dp hero fix (wallet badge starved the title to one glyph/line — LayoutBuilder stacks the badge) and a Flexible trend-chip ellipsis. Job Status: fare boxes -> summary row with expandable itemized breakdown (`fare_details_toggle`); negotiation matrix collapsed behind `negotiation_panel_toggle` (countdown pill retained, expired banner always visible). Marketplace: filter card 3 rows -> one quick-filter row + Filters bottom sheet (Nearby/map/radius relocated, keys preserved, redundant search icon removed), service cards trimmed to title/category/distance/rating/est-price/Book. Employee Jobs: welcome card slimmed to one row; subordinate chips behind a per-card Details toggle. Wallet: three StatCard rows folded into one slim inline breakdown row.
- **Commit SHA**: ``4cbfac1a4dd574c787e82680f4643c13267360d7``
- **Verification**: `flutter analyze` 0 issues; full `flutter test` 462/462; official golden baselines byte-identical (untouched); before/after evidence renders reviewed light+dark for all five screens (before-set captured from the pre-change tree via stash with the timed-pump harness fix that also un-blanked the home_screen capture — entrance-animation artifact, harness-only). Tests updated deliberately where controls relocated/collapsed (A8 overflow guards, negotiable-transport flows, marketplace map/nearby). New l10n keys: ownerHomeViewAllJobs, ownerHomeFleetSub, marketplaceFiltersTooltip, jobCardDetailsToggle (en+ar). ✅

## UI/UX Audit Remediation — Banner Retry l10n Leak, Close-Button Semantics & Tap Targets

- **Implementation Detail**: Re-ran the A8 audit methodology against the post-V2 tree; 3 live findings confirmed, all concentrated in shared widgets:
  - **Hardcoded English "Retry" leaked into Arabic locale** (`frontend/lib/widgets/themed_banner.dart`): constructor default `retryLabel = "Retry"` plus inline `widget.retryLabel ?? "Retry"` fallback rendered English on every retryable banner (~10+ screens) regardless of locale, despite the existing ARB key (`app_ar.arb` `"retry": "حاول تاني"`). Default removed; fallback now resolves via null-safe `context.l10n.retry`. No caller passes `retryLabel`, so no caller-by-caller review was required — this resolves one instance of the A8-deferred widget-default-parameter class at widget level.
  - **5 unlabeled icon-only close IconButtons** gained localized tooltips (`context.l10n.tooltipClose`): `create_service_dialog.dart`, `deposit_funds_dialog.dart`, `email_change_dialog.dart`, `payout_request_dialog.dart`, `themed_banner.dart`. The P7b "0 unlabeled" semantics sweep was screens/-scoped and missed these widget-side sites.
  - **Banner dismiss tap target restored to Material 48dp minimum**: removed `padding: EdgeInsets.zero` + empty `BoxConstraints()` + visual-only `splashRadius: 20` overrides (effective touch target was ~18×18px).
- **Commit SHA**: ``31a7941254a4322585c116de8c66d589a7048302``
- **Verification**: 6 new regression tests (Arabic retry label via ARB delegate; null-safe English fallback without delegate; tooltip presence ×5 dialogs/banner; ≥44dp tap-target assertion). Full suite 407/407 passed; `flutter analyze` 0 issues; golden baselines byte-identical (no regeneration needed); `dart format --set-exit-if-changed lib/` clean. Verified via local execution only. ✅

## Global Per-IP Rate Bucket Exhausted by SSE Reconnect Churn (Full API Lockout)

**Date**: 2026-08-26
**Category**: Bug Fix / Availability
**Related Commit SHA**: ``70def3268ee14d087977e72698e7ebd882b1b613``

- **Observed live on quickdelivery-vm**: after the day's stack force-recreates killed open SSE streams, one mobile client's EventSource reconnect loop drove 438 `GET /api/v1/notifications/stream` 429s in ~6 minutes — and because the gateway enforced ONE global 100 req/min per-client-IP bucket across ALL routes, every unrelated endpoint for that user (auth/user, ratings, employees) locked out with exponential backoff up to 300s. Steady-state single-user load measured at 39/min: uncomfortably near the shared ceiling even without churn.
- **Root cause**: connect attempts of a long-lived/reconnecting endpoint drew from the same per-IP budget as ordinary REST traffic; aggressive client reconnect behavior (multiple concurrent streams per tenant observed in notification-service hub logs) turned any network blip or deploy into a full-API lockout cascade.
- **Fix**: route-aware rate limiting via `middleware.RateLimitWithOverrides` — `/api/v1/notifications/stream` now draws from its own isolated Redis bucket (`gateway-sse`, same 100/min budget) so stream churn can no longer starve general API access; all other routes keep the original bucket and budgets unchanged.
- **Regression tests**: SSE-bucket exhaustion leaves the general bucket untouched and vice versa; nil-overrides path reproduces legacy shared-bucket semantics. Full api-gateway suite green locally.
