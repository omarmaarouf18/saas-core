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

