# Refactoring Changelog

This file tracks historical entries for the primary category: **Refactoring Changelog**.

## Owner Service Consolidation: ServiceScreen & CreateServiceDialog Removal

- **Implementation Detail**:
  - **Consolidation**: Consolidated owner service creation and editing into `OwnerConfigurationScreen` as the single source of truth, removing the redundant `ServiceScreen` (`lib/screens/service_screen.dart`, 387 lines) and `CreateServiceDialog` (`lib/widgets/create_service_dialog.dart`, 299 lines).
  - **Dashboard Entry Points (`home_screen.dart`)**: Removed the obsolete `owner_dashboard_services_card` quick-access card; balanced wide viewport grid layout for 3 cards (`cards[2]` + aligned empty spacer) maintaining 2-column symmetry; updated empty-state "manage services" CTA in the owner jobs section to navigate to `OwnerConfigurationScreen`; removed unused `ServiceScreen` import.
  - **Dead Code & Asset Removal**: Deleted `service_screen.dart`, `create_service_dialog.dart`, `test/service_screen_test.dart`, `test/create_service_dialog_test.dart`, and golden baselines `service_screen_mobile_360x800.png` and `service_screen_dark_mobile_360x800.png`.
  - **Test Modernization**: Removed ServiceScreen golden test cases from `test/golden_screens_test.dart`; updated `test/owner_home_screen_test.dart` to assert navigation to `OwnerConfigurationScreen` via `owner_dashboard_config_card`; re-homed create-service error path coverage in `test/a5_error_handling_test.dart` onto `OwnerConfigurationScreen` verifying exception mapping through `friendlyErrorMessage` without raw `Exception:` prefix.
  - **Localization Cleanup**: Removed 36 orphaned ARB keys (plus 2 metadata entries `@serviceCreateFailed`, `@serviceLocationLine`) across `app_en.arb` and `app_ar.arb` and regenerated localization classes via `flutter gen-l10n`; confirmed shared keys (`manageServicesAction`, `userProfileTitle`, `tooltipClose`, `cancel`) remain intact.
- **Commit SHA**: ``a486414e4316391bb40201415d20658222a37c48``
- **Verification**: Verified via `dart format`, `flutter analyze` (0 issues), full `flutter test` (476/476 passed, 100%), `scripts/frontend_composition_gate.sh` (pass), `make docs-check` (pass). ✅

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
- **Commit SHA**: ``4ed40007c3a3909f6794db5d98312be219adeb9c``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), targeted suites (37/37 pass across auth/forgot-password/settings/owner-config/kyc/my-account/password-toggle tests), and full suite `flutter test` (288/288 All tests passed). ✅

## DashboardScreenTemplate & Dashboard Shell Composition Migration (3 screens)

- **Implementation Detail**:
  - Created `DashboardScreenTemplate` (`frontend/lib/widgets/dashboard_screen_template.dart`) capturing the shared tabbed-dashboard shell: canonical Quick Delivery brand logo badge (`DashboardScreenTemplate.brandLogo()`, key `app_header_logo`), transparent AppBar with dynamic tab title, lazy-hydrated `IndexedStack` body, and keyed `NavigationBar` wiring.
  - Migrated `home_screen.dart` (owner 4-tab shell; non-owner branch onto `AppShell`), `customer_home_screen.dart`, and `employee_home_screen.dart`, removing three duplicated ~90-line shell implementations.
  - Refined `scripts/frontend_audit.sh`: widget-construction matching via PCRE negative lookbehind so identifier substrings (e.g. `_buildOwnerScaffold(`) no longer false-positive; home helpers renamed `_buildOwnerShell`/`_buildNonOwnerShell`.
- **Commit SHA**: ``b083789ab5b0eb23337253818ee091a513839ce2``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), `frontend/test/dashboard_screen_template_test.dart` (4/4 pass), full suite `flutter test` (292/292 All tests passed), and post-batch audit: Scaffold files 13 -> 10, AppBar files 10 -> 7. ✅

## AppShell-Only Composition Migration Batch (6 screens)

- **Implementation Detail**:
  - Migrated screens with unique layouts onto `AppShell` directly (no archetype template): `chat_screen.dart` (`titleWidget` preserving two-line title + live status indicator), `wallet_screen.dart` (chrome-less shell), `subscription_screen.dart`, `update_required_screen.dart` (PopScope non-dismissible guard preserved), `employee_screen.dart` (TabBar-only header via AppShell `bottom:` slot on surface background), and `employee_jobs_screen.dart` (embedded-tab early-return preserved).
- **Commit SHA**: ``bdeac613b23eeafc938a4d6cd91f5901e8677ec5``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), full suite `flutter test` (292/292 All tests passed), and post-batch audit: Scaffold files 10 -> 4, AppBar files 7 -> 4. ✅

## Detail & Map Screen Composition Migration Batch (P2 Completion, 4 screens)

- **Implementation Detail**:
  - Migrated the final 4 screens onto `AppShell` composition roots: `job_status_screen.dart` (refresh spinner-in-actions preserved), `rating_screen.dart` (transparent app bar preserved), `owner_fleet_map_screen.dart` and `customer_job_map_screen.dart` (navy map headers with refresh actions preserved).
  - **P2 rollout target achieved**: 0 files in `frontend/lib/screens/` construct `Scaffold(` or `AppBar(` directly — all 28 screens compose exclusively through `AppShell`/archetype templates.
- **Commit SHA**: ``5845de375511f52f6e453cc392cee4a4f4d52ed4``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), full suite `flutter test` (292/292 All tests passed), and post-fix audit: Scaffold( files 4 -> 0, AppBar( files 4 -> 0. ✅

## P3 Centralized Uppercase Typography (36 call sites eliminated)

- **Implementation Detail**:
  - Added `AppTypography.labelUppercase` (canonical TextStyle for small badges/chips/status tags) and `AppTypography.uppercaseLabel(String)` (single centralized uppercase transform) to `frontend/lib/core/theme.dart`.
  - Rewrote all 36 scattered `.toUpperCase()` usages across 16 screen files onto `uppercaseLabel` (balanced-paren backward-scanner rewrite; the single multiline chain in `owner_fleet_map_screen.dart` repaired manually and caught by analyzer).
  - Post-fix audit (`scripts/frontend_audit.sh`): `.toUpperCase()` occurrences in screens/ = **0**.
- **Commit SHA**: ``8c493c9beaee5fbed56ba676254ae2a10a1355de``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), and full suite `flutter test` (292/292 All tests passed). ✅

## P4 BoxDecoration Elimination via ThemedPanel (110 call sites eliminated)

- **Implementation Detail**:
  - Created `ThemedPanel` + `AnimatedThemedPanel` (`frontend/lib/widgets/themed_panel.dart`) as the single sanctioned decorated-container primitives for screens, internally owning all `BoxDecoration` construction.
  - Converted 109 `Container(decoration: BoxDecoration(...))` sites and 1 `AnimatedContainer` site (signup role-selector -> `AnimatedThemedPanel`) across all 23 remaining screen files; zero unsupported-argument drops during the mechanical conversion.
  - Fixed an animation repaint defect found by the dedicated test: state initially extended `ImplicitlyAnimatedWidgetState` (no per-tick rebuilds); moved to `AnimatedWidgetBaseState`.
  - Ran `dart fix --apply` (19 `prefer_const_constructors` fixes) in the same pass.
  - Post-fix audit (`scripts/frontend_audit.sh`): `BoxDecoration(` occurrences in screens/ = **0**.
- **Commit SHA**: ``13f9bc65e40d1b5337fa1e7b313ef85758db6ff9``
- **Verification**: Verified via `dart format`, `flutter analyze` (No issues found!), `frontend/test/themed_panel_test.dart` (5/5 pass), and full suite `flutter test` (297/297 All tests passed). ✅

## Dead Code & Orphaned Localization Removal (QA Audit A7)

- **Implementation Detail**:
  - **Step 1 (whole-file audit)**: All 94 `.dart` files under `frontend/lib/` reference-audited via anchored basename + `package:frontend/` path scans across `lib/` and `test/`, cross-checked against the route table (`main.dart` — only string route is the kDebugMode-gated `/component-library`; all other navigation is typed `MaterialPageRoute`), `part`/`part of`/`export` directives (only `l10n.dart` barrel and two banner re-exports, all resolving to live files), and suspect-filename patterns (none found). Verdict: 93/94 files live; `main.dart` is the tooling entrypoint (test-referenced). **Zero orphaned files.**
  - **Dead-but-imported class scan**: every public top-level class in widgets/models/services/utils/screens/providers/core word-scanned for out-of-file references. One true hit: `AppShadows` (`lib/core/theme.dart`) — a leftover "backwards-compatible" shim aliasing retired pre-Phase-20 shadow constants, zero references anywhere. Removed. (`StatusBadgeConfig`, `CustomerHomeScreenState`, `ServiceRatingWidget` flagged by the scan but verified live on manual read — internal support classes / same-file usage.)
  - **Lint enablement check**: `unused_element`, `unused_field`, and `dead_code` confirmed ACTIVE as analyzer-native diagnostics under the stock `flutter_lints` include — proven empirically with a positive-control probe project (all three fired). Project analyze being clean therefore proves zero unused private members/dead code in lib/ today. No analysis_options.yaml change required.
  - **Commented-out code**: pattern scan across lib/ found zero disabled-code blocks (single prose comment hit).
  - **Unused ARB keys**: programmatic scan of all 694 keys per locale against hand-written source (generated `lib/l10n/` excluded) proved 99 keys have zero references — string-level leftovers of superseded surfaces: 17 `kybKye*`/`doc*` keys from the ADR-0013-excluded reviewer screen/document viewer, ~40 `ownerHome*`/`step*`/`subscription*`/`wallet*` legacy copies replaced during the Phase 28 Stitch redesign, plus superseded dialog copy (`employeeJobsCashConfirm*`, `employeeFreeze*`). Removed from both `app_en.arb` and `app_ar.arb` (parity maintained) and regenerated via `flutter gen-l10n`.
  - **Process incident (caught by verification)**: an initial hand-transcribed candidate list dropped one key (`ownerHomeJobCancelledEscrowRefunded`) that IS live — its accessor is split across lines in `home_screen.dart:1254`, defeating same-line regex scans. `flutter analyze` caught it post-removal (`undefined_getter`) and it was restored before commit. Final state re-derived programmatically from the ARB files themselves with no manual lists; exactly one remaining zero-reference key (`customerJobsPrice`, a bare `"Price"` placeholder) confirmed dead by direct grep and left removed.
- **Commit SHA**: ``da03e2b9d8356dd2f3bd23961e6e7e486a1d9e73``
- **Related Commit SHA**: ``78753c3aa5e358be58ad4b8e4c9a4607125d26d8``

Primary commit removes the 99 l10n keys; the related commit removes the AppShadows shim.
- **Verification**: removal-as-proof — `flutter analyze` clean and full suite green after each batch (any live reference would have failed compilation). Post-state: `flutter analyze` No issues found; full suite `flutter test` **390 passed / 0 failed** (baseline 390 at `a88cb84`); ARB parity 595 = 595 keys en/ar. ✅
