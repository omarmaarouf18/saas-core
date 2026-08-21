# Refactoring Changelog

This file tracks historical entries for the primary category: **Refactoring Changelog**.

## KYC/KYE Document Upload Screen Structural & Presentation Refactor (`kyc_document_upload_screen.dart`)

- **Implementation Detail**:
  - **Structural Decomposition**: Decomposed the single ~400-line monolithic `build()` method in `KycDocumentUploadScreen` (`frontend/lib/screens/kyc_document_upload_screen.dart`) into clean named section helper widgets: `_buildStatusBanner`, `_buildRejectionReasonBanner`, `_buildApprovedLockedBanner`, and `_buildDocumentSlotCard`.
  - **Shared Widget Library Adoption**: Replaced raw container and hand-built elements with design-system-aligned shared widgets: `ThemedCard` for status and slot card containers, `StatusBadge` for KYC status chip, `ThemedSectionHeader` for document requirements title/subtitle, `PrimaryButton` ("Upload Document"), `SecondaryButton` ("Replace Document"), and `ThemedErrorBanner`.
  - **Consolidated Source Picker Bottom Sheet**: Consolidated two near-identical "pick image source" bottom sheet code blocks (~lines 72–103 and ~lines 144–169) into a single reusable helper method `_showSourcePickerBottomSheet(context, {required bool allowPdf})` supporting camera, gallery, and optional PDF selection.
  - **Motion & Transitions**: Wrapped slot action controls and document preview panels in `AnimatedSwitcher` (`AppMotion.durationMedium`, `AppMotion.curveStateChange`) for smooth state transitions (loading spinner, upload button, uploaded preview). Wrapped body in `RefreshIndicator` for pull-to-refresh.
- **Commit SHA**: ``6b44d027ff5c3036eb2ae76bf1837cde755cb7e6``
- **Verification**: Verified via `dart format .`, `flutter analyze` (0 issues found), `flutter test test/kyc_document_upload_screen_test.dart` (5/5 pass), full suite `flutter test` (196/196 tests pass), `make docs-check`, and pre-push hooks gate. ✅

## Modularization of Monolithic `user-service` Handlers (`handlers.go` Decomposition)

- **Implementation Detail**:
  - **Structural Decomposition**: Decomposed the monolithic 3,247-line `services/user-service/internal/handlers/handlers.go` into responsibility-scoped domain files without altering business logic, API contracts, or runtime behavior.
  - **New Responsibility-Scoped File Layout**:
    - `handlers.go` (421 lines): Base struct definition (`UserService`), dependency constructor (`NewUserService`), route registration (`RegisterRoutes`), and cross-domain shared package-level helpers (`resolveClaims`, `resolveTokenWithRole`, `writeJSON`, `generateID`, `haversineKm`, `checkKYC`, `verifyEmployeeAssignment`, `requireTier`).
    - `services_handlers.go` (278 lines): Marketplace service catalogue and platform configuration handlers (`ListServices`, `CreateService`, `UpdateService`, `GetPlatformConfig`) and coordinate bounds validation (`isValidCoordinate`).
    - `jobs_handlers.go` (1,759 lines): Core job lifecycle management, escrow reservation/settlement, live location telemetry, and transport price negotiation (`TrackJob`, `CompleteJob`, `GetJob`, `GetOwnerJobs`, `GetCustomerJobs`, `UpdateJobLocation`, `CancelJob`, `ProposePrice`, `RespondPrice`).
    - `wallet_handlers.go` (290 lines): Tenant balance inquiry, financial ledger audit trails, test payment deposit bypass, and payout withdrawal request management (`GetWallet`, `WalletDeposit`, `GetLedger`, `RequestPayout`, `GetPayoutRequests`).
    - `subscription_handlers.go` (154 lines): Tenant subscription tier status and upgrade request processing (`Subscription`).
    - `ratings_handlers.go` (204 lines): Double-blind job rating submission and aggregated rating queries (`RateJob`, `GetRatings`).
    - `reconciliation_handlers.go` (222 lines): Disputed escrow reconciliation queue retrieval and tenant resolution decision processing (`GetReconciliationQueue`, `ResolveReconciliation`).
  - **Zero Behavior Change Guarantee**: Byte-for-byte fidelity preserved across all moved handler functions; test fixtures and test suite left intact with 100% test count and pass parity.
- **Commit SHA**: ``e0747d5557f3c4c3c21325578cc94ff17dd97738``
- **Verification**: Verified via `go build ./...`, `go vet ./...`, full test suite parity across all 6 backend services and frontend, `make docs-check`, and `.githooks/pre-push` gate. ✅


## Form-Archetype Screen Composition Migration Batch (8 screens to AppShell/FormScreenTemplate)

- **Implementation Detail**:
  - Migrated the remaining form/config archetype screens off manual `Scaffold`/`AppBar` construction onto `AppShell`/`FormScreenTemplate` composition roots as part of Frontend Architecture Unification P2: `signup_screen.dart`, `forgot_password_screen.dart`, `otp_screen.dart`, `settings_screen.dart`, `owner_configuration_screen.dart`, `kyc_document_upload_screen.dart`, `service_screen.dart`, and `my_account_screen.dart`.
  - Transparent auth app bars preserved via `appBarBackgroundColor: Colors.transparent` + `appBarForegroundColor`; embedded-tab behavior (`settings_screen.dart`), full-body initialization loaders, refresh actions, pull-to-refresh, FAB placement with KYC gating (`service_screen.dart`), and responsive grids all preserved.
  - Post-batch audit (`scripts/frontend_audit.sh`): files containing `Scaffold(` in screens/ reduced 21 -> 13; files containing `AppBar(` reduced 17 -> 10.
- **Commit SHA**: ``070b7a20c9d14f8b52c89e8e7d9da77e6f3e16d3``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), targeted suites (37/37 pass across auth/forgot-password/settings/owner-config/kyc/my-account/password-toggle tests), and full suite `flutter test` (288/288 All tests passed). ✅

## DashboardScreenTemplate & Dashboard Shell Composition Migration (3 screens)

- **Implementation Detail**:
  - Created `DashboardScreenTemplate` (`frontend/lib/widgets/dashboard_screen_template.dart`) capturing the shared tabbed-dashboard shell: canonical Quick Delivery brand logo badge (`DashboardScreenTemplate.brandLogo()`, key `app_header_logo`), transparent AppBar with dynamic tab title, lazy-hydrated `IndexedStack` body, and keyed `NavigationBar` wiring.
  - Migrated `home_screen.dart` (owner 4-tab shell; non-owner branch onto `AppShell`), `customer_home_screen.dart`, and `employee_home_screen.dart`, removing three duplicated ~90-line shell implementations.
  - Refined `scripts/frontend_audit.sh`: widget-construction matching via PCRE negative lookbehind so identifier substrings (e.g. `_buildOwnerScaffold(`) no longer false-positive; home helpers renamed `_buildOwnerShell`/`_buildNonOwnerShell`.
- **Commit SHA**: ``9630064454924560c810805692c567eae9f7d2e8``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), `frontend/test/dashboard_screen_template_test.dart` (4/4 pass), full suite `flutter test` (292/292 All tests passed), and post-batch audit: Scaffold files 13 -> 10, AppBar files 10 -> 7. ✅

## AppShell-Only Composition Migration Batch (6 screens)

- **Implementation Detail**:
  - Migrated screens with unique layouts onto `AppShell` directly (no archetype template): `chat_screen.dart` (`titleWidget` preserving two-line title + live status indicator), `wallet_screen.dart` (chrome-less shell), `subscription_screen.dart`, `update_required_screen.dart` (PopScope non-dismissible guard preserved), `employee_screen.dart` (TabBar-only header via AppShell `bottom:` slot on surface background), and `employee_jobs_screen.dart` (embedded-tab early-return preserved).
- **Commit SHA**: ``8756b0ed6ee2b0269c88b53aa8cfad627a5a7b3f``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), full suite `flutter test` (292/292 All tests passed), and post-batch audit: Scaffold files 10 -> 4, AppBar files 7 -> 4. ✅

## Detail & Map Screen Composition Migration Batch (P2 Completion, 4 screens)

- **Implementation Detail**:
  - Migrated the final 4 screens onto `AppShell` composition roots: `job_status_screen.dart` (refresh spinner-in-actions preserved), `rating_screen.dart` (transparent app bar preserved), `owner_fleet_map_screen.dart` and `customer_job_map_screen.dart` (navy map headers with refresh actions preserved).
  - **P2 rollout target achieved**: 0 files in `frontend/lib/screens/` construct `Scaffold(` or `AppBar(` directly — all 28 screens compose exclusively through `AppShell`/archetype templates.
- **Commit SHA**: ``9c0dfce444162cc4672b74eb3c277da6691f4de7``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), full suite `flutter test` (292/292 All tests passed), and post-fix audit: Scaffold( files 4 -> 0, AppBar( files 4 -> 0. ✅

## P3 Centralized Uppercase Typography (36 call sites eliminated)

- **Implementation Detail**:
  - Added `AppTypography.labelUppercase` (canonical TextStyle for small badges/chips/status tags) and `AppTypography.uppercaseLabel(String)` (single centralized uppercase transform) to `frontend/lib/core/theme.dart`.
  - Rewrote all 36 scattered `.toUpperCase()` usages across 16 screen files onto `uppercaseLabel` (balanced-paren backward-scanner rewrite; the single multiline chain in `owner_fleet_map_screen.dart` repaired manually and caught by analyzer).
  - Post-fix audit (`scripts/frontend_audit.sh`): `.toUpperCase()` occurrences in screens/ = **0**.
- **Commit SHA**: ``0106e1dc0494ec75f3a6f0a9421fee6bc6fac663``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), and full suite `flutter test` (292/292 All tests passed). ✅
