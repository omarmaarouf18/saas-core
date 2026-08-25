# Documentation Changelog

This file tracks historical entries for the primary category: **Documentation Changelog**.

---

## API Gateway Version Gating Collection Alignment in Docgen & Application Map

- **Implementation Detail**: Aligned the MongoDB collection target for the mobile version gating admin endpoints (`GET /api/v1/admin/version-config` and `PUT /api/v1/admin/version-config`) in `shared/infra/docgen/generator.go` and `docs/APPLICATION_MAP.md` from `version_config` to `platform_versions` to match `services/api-gateway/internal/version/version.go`, ADR-0018 §2.2, and `docs/DEPLOYMENT.md` §11.3. Updated `api-gateway`'s inventory description in Section 1 to document MongoDB `platform_versions` database persistence and minimum version gating responsibilities.
- **Commit SHA**: ``dbd3ee56aa73ea82b4aaa92d465b4e6aafc196ae``
- **Verification**: Verified via `make docs`, `make docs-check`, `gofmt -l .`, and `go test ./...` in `shared/infra/docgen`. ✅

## Full Repository Documentation Freshness Audit & Gap-Filling Pass

- **Implementation Detail**: Completed a comprehensive, repository-wide documentation freshness audit and gap-filling sweep across all architectural specifications, ADRs, application maps, deployment guides, audit logs, and changelog indices:
  1. Updated `shared/infra/docgen/generator.go` and regenerated `docs/APPLICATION_MAP.md` via `make docs`: added complete descriptions, exact caller permissions, and storage targets for 9 recently introduced or updated endpoints (`POST/DELETE /auth/device-token`, `POST /auth/email-change/request`, `POST /auth/email-change/confirm`, `POST /users/wallet/payout/request`, `GET /users/wallet/payout/requests`, `PATCH /users/services`, `GET /api/v1/admin/version-config`, `PUT /api/v1/admin/version-config`), eliminating all `<!-- TODO: verify manually -->` placeholders and default `Public` tags.
  2. Updated ADR statuses: transitioned `ADR-0007` (GPS trail settlement reconciliation) to `Accepted` reflecting complete implementation in `CompleteJob`, and transitioned `ADR-0013` (Support agent console separate app) to `Accepted (Scope Boundary Enforced)` reflecting owner confirmation and reviewer screen removal.
  3. Disambiguated duplicate Phase 15 entries in `docs/frontend/STATUS.md` into `Phase 15A` and `Phase 15B`, and clarified the subsequent re-reversion of reviewer screens per ADR-0013.
  4. Updated `docs/REPOSITORY_MAP.md`: refreshed header commit pin, documented strict CD pre-flight and health-gated rollback per ADR-0015, and replaced deprecated `DEPLOY_REPO_PAT` triage references with GitHub App credentials (`APP_ID` / `APP_PRIVATE_KEY`).
  5. Updated `docs/BUSINESS_LOGIC_AUDIT.md`: transitioned Finding 1 (COD race condition) and Finding 2 (AgreedPrice escrow refund) to `Resolved (Remediated & Verified in Code)` with citations to `mongodb.CancelJob` CAS status guard and `CancelJob` handler math.
  6. Updated `docs/FRONTEND_CONSISTENCY_AUDIT.md`: transitioned status to `COMPLETED & 100% IMPLEMENTED (All 5 Remediation Batches Landed & Verified)` citing all 5 batch commit SHAs and test pass metrics.
  7. Refreshed category entry counts across `docs/changelog/README.md` and `AI_CONTEXT.md` to reflect actual index counts (104 security fixes, 56 new features, 49 infrastructure, 55 bug fixes, 33 documentation, 4 localization, 2 refactoring).
- **Commit SHA**: ``855bcf9e8049bc14b236a6ecef60444d76914787``
- **Verification**: Verified via `make docs-check`, `go test ./...` in shared/infra, and full git commit SHA reachability check (`FAILED_SHA=0`). ✅

## Full Repository Documentation Freshness Re-Audit & Remediation

- **Implementation Detail**: Executed a comprehensive documentation freshness audit across all 55 markdown documents in the repository following significant backend, infrastructure, and architectural landings (handlers modularization, Redis Sentinel HA support, graceful shutdown across all 5 services, CD health rollback hardening, KYC document encryption at rest, rate limiter decoupling, and zero-commission model). Remediated all identified discrepancies:
  1. Updated `docs/APPLICATION_MAP.md` and `docs/REPOSITORY_MAP.md` headers with current Git commit pins.
  2. Updated `docs/DEPLOYMENT.md` §5.2 to document Redis Sentinel environment variables (`REDIS_SENTINEL_ADDRS`, `REDIS_SENTINEL_MASTER_NAME`, `REDIS_SENTINEL_PASSWORD`) and updated §7.4 to document automated health-gated CD rollback (`set -euo pipefail`, compose rollback, container recreation, `verify_service_health`).
  3. Standardized `docs/adr/0018-client-app-semantic-versioning-and-enforcement-gate.md` status line and added ADR-0018 to `docs/adr/README.md` index.
  4. Updated user-service handler citations across `docs/frontend/STATUS.md`, `docs/FRONTEND_INTEGRATION_SCOPE.md`, `docs/BUSINESS_LOGIC_AUDIT.md`, `docs/audit/shared-module-review.md`, `DESIGN.md`, and `IMPLEMENTATION.md` to reference post-refactoring domain-scoped handler files (`jobs_handlers.go`, `wallet_handlers.go`, `services_handlers.go`, `subscription_handlers.go`, `ratings_handlers.go`).
  5. Corrected Phase 2 status in `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` executive summary table to `[100% COMPLETE & VERIFIED]`.
  6. Updated database reference in `docs/local/APP_MAP.md` architecture diagram from legacy `saas_platform` to isolated `user_db`.
  7. Corrected documentation link in `frontend/CONNECTING_TO_BACKEND.md` pointing to `docs/DEPLOYMENT.md`.
- **Commit SHA**: ``01096e2ebb43ef8e9f5540fa5ff5a2951433f6d5``
- **Verification**: Verified via `make docs-check` (all commit SHAs valid, all markdown links consistent), `git cat-file -e`, and full test suite passes across all microservices and frontend. ✅

## Visual Hierarchy & Card Presentation Overhaul (Phase 4)

- **Implementation Detail**: Extended `ThemedCard` with explicit `elevation` parameter support. Standardized static/resting cards to `AppElevation.shadowLevel1List` (control panel, empty containers, job details, worker info, audit logs) and interactive/tappable cards to `AppElevation.shadowLevel2List` (marketplace service booking cards, price counter-offer card, worker registration form, worker status form, employee active job cards) across 5 target screens (`customer_marketplace_screen.dart`, `job_status_screen.dart`, `wallet_screen.dart`, `employee_screen.dart`, `employee_jobs_screen.dart`). Re-ran `scratch/audit_hierarchy.py` confirming **0** remaining findings. Updated `docs/frontend/DESIGN_SYSTEM.md`, `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` (Phase 4 evidence), `docs/frontend/STATUS.md` (Phase 23 entry), and `AI_CONTEXT.md`.
- **Commit SHA**: ``efdba37a6399564ee18a8ba336587c5e25fcaf31``
- **Verification**: Verified via `scratch/audit_hierarchy.py` (0 remaining findings), `flutter analyze` (0 issues), and `flutter test` (177/177 pass 100%). ✅

## Empty, Error & Success State Polish (Phase 3)

- **Implementation Detail**: Standardized `ThemedEmptyState` (sized icon `AppIconSize.xl`, `AppTypography.titleMd`, and contextual primary action buttons across all empty screens), `ThemedErrorBanner` (active `onRetry` callbacks wired to re-trigger failed provider calls across all error states), and introduced `ThemedSuccessBanner` / `ThemedSnackBar` helpers (floating toast notifications with `AppColors.success`/`AppColors.error`, icons, and `AppMotion.snackBarDisplay` 2s duration across 13 screens). Re-ran `scratch/audit_states.py` confirming **0** unhandled state findings. Updated `docs/frontend/DESIGN_SYSTEM.md`, `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` (Phase 3 evidence), `docs/frontend/STATUS.md` (Phase 22 entry), and `AI_CONTEXT.md`.
- **Commit SHA**: ``f31ad8251eee557ff9b0a025da9ba1a07d7c7bd0``
- **Verification**: Verified via `scratch/audit_states.py` (0 unhandled state findings), `flutter analyze` (0 issues), and `flutter test` (177/177 pass 100% including 4 new widget state test cases). ✅

## Motion, Transitions & Micro-Interactions (Phase 2)

- **Implementation Detail**: Replaced all hardcoded `Duration` and raw `Curves` instances across screen & widget files with canonical `AppMotion` tokens (`durationFast`, `durationMedium`, `durationMediumSlow`, `durationSlow`, `snackBarDisplay`, `curveEntrance`, `curveBounce`). Extended `frontend/lib/core/theme.dart` with `AppMotion.durationMediumSlow` (400ms), `AppMotion.snackBarDisplay` (2s), and `AppMotion.debounceGuard` (600ms). Added interactive `AnimatedScale` (0.96) micro-interaction tap feedback to `PrimaryButton` and `SecondaryButton` while preserving the 600ms tap-debounce logic. Re-ran `scratch/audit_motion.py` confirming **0** remaining motion findings. Updated `docs/frontend/DESIGN_SYSTEM.md`, `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` (Phase 2 evidence), `docs/frontend/STATUS.md` (Phase 21 entry), and `AI_CONTEXT.md`.
- **Commit SHA**: ``d8b0b2fe6db33ddd27944dc96701dfe74d333d18``
- **Verification**: Verified via `scratch/audit_motion.py` (0 motion findings), `flutter analyze` (0 issues), and `flutter test` (173/173 pass 100% including 2 new scale tap feedback widget test cases). ✅

## Design Token System Migration & Debt Cleanup (Phase 1)

- **Implementation Detail**: Replaced all 55 catalogued instances of hardcoded values across 16 files with canonical `AppColors`, `AppSpacing`, `AppRadius`, and `AppTypography` design tokens. Extended `frontend/lib/core/theme.dart` with clean intermediate tokens (`AppSpacing.xxs/baseSm/xxl/xxxl`, `AppRadius.xxs/smMd/lgXl`). Re-ran `scratch/audit_debt.py` confirming **0** remaining debt findings. Updated `docs/frontend/DESIGN_SYSTEM.md` (§2 tokens table, §5 debt backlog), `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` (Phase 1 completion evidence), `docs/frontend/STATUS.md` (Phase 20 tracker entry), and `AI_CONTEXT.md`.
- **Commit SHA**: ``a855699b603e3b998d2dbd2a40d219193d4aa01f``
- **Verification**: Verified via `scratch/audit_debt.py` (0 findings), `flutter analyze` (0 issues), `flutter test` (171/171 pass 100%), and RTL `ar_EG` layout validation. ✅

## Enterprise Design System & Brand Identity Specification (Phase 19)

- **Implementation Detail**: Extended `frontend/lib/core/theme.dart` with enterprise design tokens (`AppElevation`, `AppMotion`, `AppIconSize`, and expanded `AppRadius`). Authored `docs/frontend/BRAND_IDENTITY.md` establishing color rationale, logo rules, Egyptian colloquial Arabic voice guidance, and Uber/Talabat UI benchmarks. Authored `docs/frontend/DESIGN_SYSTEM.md` detailing token references, complete 18-widget component catalog, composition patterns, 55-instance design debt backlog, and RTL layout rules. Authored `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` establishing a 6-phase follow-up roadmap (Phases 1–6). Indexed all documents in `README.md` and `docs/frontend/STATUS.md` (Phase 19).
- **Commit SHA**: ``94f0425b08bd5a853f15b65475d472bcf4046556``
- **Verification**: Verified via `flutter analyze` (0 issues), `flutter test` (171/171 pass 100%), and `go test ./shared/infra/docgen/...` (pass). ✅

## Phase 18 (ADR-0017) Frontend Status Tracker Accuracy Alignment

- **Implementation Detail**: Updated `docs/frontend/STATUS.md` Phase 18 and `AI_CONTEXT.md` to align tracking status with completed ADR-0017 backend implementation. Marked sub-items (a) Fee-Splitting Removal (`aaaacc531ffe24a9aa6da3c99231844ef4fa8803`), (b) COD Pure Log Entry (`aaaacc531ffe24a9aa6da3c99231844ef4fa8803`, `431d42a8c0c426fe66037257d42878a84f74c73f`), (c) Owner Payout Request Capability (backend API endpoints `POST /users/wallet/payout/request` & `GET /users/wallet/payout/requests`, `aaaacc531ffe24a9aa6da3c99231844ef4fa8803`), and (d) Production Data Correction (`d97ef3a3ef5051be2b4adb85cc67004b35237ee4`, `255b6ec60e86fb0e287e334d0fa46749de9f2830`) as `[VERIFIED]`. Explicitly noted sub-item (c) covers backend API endpoints only (frontend UI pending under sub-item e), and retained sub-item (e) Frontend 0% Fee & Payout UI as `[PLANNED, NOT STARTED]`.
- **Commit SHA**: ``1597f118c1b448bbc5e814228eefd6d4668e5fd7``
- **Verification**: Verified via `git diff --stat` confirming 0 code changes, and passed `go test ./shared/infra/changelog_validation_test.go`. ✅

## ADR-0017 Zero-Commission Subscription-Only Revenue Model Architecture

- **Implementation Detail**: Authored `docs/adr/0017-zero-commission-subscription-only-revenue-model.md` defining the business-model pivot to a 0% platform transaction commission revenue model (monthly SaaS subscription fee as sole platform revenue source). Established 0% commission across all payment channels, pure log-entry COD collection without wallet balance mutation, centralized electronic payment credits with tenant owner withdrawal/payout request capability, and remediation removing legacy fee deduction paths. Indexed in `docs/adr/README.md`, appended root cause notes in `docs/BUSINESS_LOGIC_AUDIT.md`, registered Phase 18 tracking entry in `docs/frontend/STATUS.md`, and updated `AI_CONTEXT.md`.
- **Commit SHA**: ``a2835440a8b3795fbb3c8551c09a621bf7e78f58``
- **Verification**: Verified via `make docs-check` and git history verification. ✅

## Business Logic Audit Report (Finding 1 & Finding 2)

- **Implementation Detail**: Produced formal business logic audit report `docs/BUSINESS_LOGIC_AUDIT.md` documenting confirmed findings in `services/user-service` job lifecycle and escrow financial logic. Detailed Critical Finding 1 (COD job cancel/complete race condition in `store.CancelJob`) and Medium Finding 2 (`AgreedPrice` omitted in `CancelJob` refund calculation, trapping owner funds in escrow). Documented 4 verified-sound security controls (atomic escrow release double-complete protection, backend KYC enforcement, tenant scope isolation, and employee IDOR protection) and explicit scope limits. Updated `README.md` documentation index.
- **Commit SHA**: ``7ed7579e91d299571706b54c067604462180ea31``
- **Verification**: Verified via `make docs-check` and git history verification. ✅

## Monorepo Shared Dependency Constraint Documentation (Finding #9)

- **Implementation Detail**: Documented Finding #9 as a deliberate, accepted monorepo dependency constraint in `docs/REPOSITORY_MAP.md` §5 and `AI_CONTEXT.md`. Clarified that `shared/infra` is resolved strictly via relative paths (`replace github.com/project/shared/infra => ../../shared/infra` in `services/*/go.mod`). Explicitly documented extraction guidance (if a service is ever copied into an external application, `shared/infra` must be copied alongside it) and the associated maintenance risk (future bug fixes or security hardening in `saas-core`'s `shared/infra` will not automatically propagate to copied instances, requiring manual operator re-syncing). Identified the long-term resolution trigger (publishing `shared/infra` as a standalone versioned module should 3+ independent applications depend on copied instances).
- **Commit SHA**: ``a35ca8670818a6d1c44b5bfd21ed211bd3f38c83``
- **Verification**: Verified via `git diff --stat` (0 code or go.mod files touched, documentation files only) and `make docs-check`. ✅

## ADR-0014 Unified Account Settings & Role Home Redesign Planning

- **Implementation Detail**: Created ADR-0014 (`docs/adr/0014-unified-account-settings-and-role-home-redesign.md`) documenting the planned frontend UX restructuring initiative. Registered 4 core decisions: (1) Unified Settings screen (Account Action Center) consolidating theme, language, support, and centralized logout, (2) Deferred Owner Configuration and My Account placeholders, (3) Customer home redesign with 4 category tiles (categories TBD) and search bar, (4) Interactive `flutter_map` location picker replacing manual lat/long text inputs, and (5) Employee backend capability audit as a prerequisite to screen redesign. Updated `docs/adr/README.md`, `docs/frontend/STATUS.md` (Phase 15 `[PLANNED, NOT STARTED]`), `docs/frontend/ARCHITECTURE.md`, and `AI_CONTEXT.md`.
- **Commit SHA**: ``c3e9a005c09fd089cc3ba97588eadb7cd6378b1a``
- **Verification**: Verified via documentation checks. ✅

## Complaint Routing Stage 7: Documentation

- **Implementation Detail**: Documented complaint routing design and atomic assignment decisions in DESIGN.md and AI_CONTEXT.md.
- **Commit SHA**: ``46849ac88483819acc6069944c5b69a6cbaa213b``
- **Verification**: Verified via review. ✅

## Application Map

- **Implementation Detail**: Created a comprehensive reference document (docs/APPLICATION_MAP.md) detailing ports, databases, actor lifecycles, and connection flows.
- **Commit SHA**: ``ed34020c6be346ba39bd0c1fafdd09e95e9b87b2``
- **Verification**: Verified via document generation. ✅

## Document Client-Submitted Coordinates Pricing Risk

- **Implementation Detail**: Documented the risk associated with client-submitted coordinates for distance-based pricing and escrow calculations in AI_CONTEXT.md.
- **Commit SHA**: ``c7189a85c31edfafd5fd6b8fdf993584f7e01197``
- **Verification**: Verified via review of AI_CONTEXT.md. ✅

## Documentation Audit Correction

- **Implementation Detail**: Fixed six mismatches between documentation and implementation (corrected `/auth/documents/view` path and added missing `/auth/kye/upload` in `APPLICATION_MAP.md`, updated location update throttle constant in map, added target architecture disclaimer and corrected `flutter_client_sse` version in `DESIGN.md`, and consolidated `GEMINI.md` to point to `CLAUDE.md` to prevent drift).
- **Commit SHA**: ``39099f89c4d6f1673d46690976cce1559eaec622``
- **Verification**: Verified via visual review and shared/infra validation test suite. ✅

## Self-Enforcing Auto-Documentation System

- **Implementation Detail**: Built a Go-based AST parser and code generator to automatically maintain the HTTP endpoint table in `APPLICATION_MAP.md` based on `RegisterRoutes` handlers. Added automated structural checks verifying that all Dart frontend files are listed in `STATUS.md` and dependency version quotes in `DESIGN.md` match `pubspec.yaml`. Configured Makefile targets (`make docs` and `make docs-check`) and wired them into the shared unit test suite.
- **Commit SHA**: ``5d6411b500d0e5f094d6b956f75dbcb74c821643``
- **Verification**: Verified via test suite (`TestDocgenFreshness`, `TestDocgenDriftCatching`, `TestDartFilesMentionedInStatus`, and `TestPubspecDependenciesInDesignDoc`). ✅

## DESIGN.md Link Alignment

- **Implementation Detail**: Fixed stale/drifted code line-number references in DESIGN.md for Go source handlers and helper functions to prevent documentation drift and align with actual locations.
- **Commit SHA**: ``ab02e2e8d127edd4ce58bcc888ee032d763315c0``
- **Verification**: Verified via visual review and checked that docgen/structural checks pass cleanly. ✅

## Audit Report Refresh (2026-07-19)

- **Implementation Detail**: Refreshed the codebase audit documentation in `docs/audit/shared-module-review.md` and `AUDIT_REPORT.md` to reflect gosec fixes (unchecked errors, server timeouts, local storage directory traversal checks), pre-push hooks, flaky test mitigations, and new features like username validation and point-in-time chat snapshots. Verified all known open items and open risks against HEAD.
- **Commit SHA**: ``3dae5df21adc6bd1ea9e2644990248c17d1aea5b``
- **Verification**: Verified that docgen tests and changelog SHA validation tests pass cleanly. ✅

## Pre-Push Hook Activation & Auto-Commit Policy Hardening

- **Implementation Detail**: Corrected invalid commit SHA in `bug-fixes.md` for Resend configuration validation to reference the actual commit (`7cd13c04e407ae527d8a641193d0cb37fc2db777`). Added `commit` and `push` Makefile targets with `ensure-hooks` as an explicit prerequisite. Updated `CLAUDE.md` auto-commit policy requiring `git config core.hooksPath .githooks` as an unconditional, idempotent first command before any `git add` to prevent unhooked commits on fresh clones.
- **Commit SHA**: ``51cf0a36ccadb1cb00903009c9bba8a6ae90304b``
## Endpoint Mapping Regeneration & Role Description Alignment

- **Implementation Detail**: Regenerated `docs/APPLICATION_MAP.md` via `make docs` to update the Git commit short SHA note (`78c35ac`) and updated `KnownEndpoints` in `shared/infra/docgen/generator.go` to accurately describe enforced caller roles across all `user-service` endpoints following the Gap 1 remediation (`resolveTokenWithRole`).
- **Commit SHA**: ``78c35ac5d9a766a05502f28d233eb45584d11884``
- **Verification**: Verified via `make docs-check` passing all freshness and drift-catching tests cleanly. ✅

## ADR-0005 Realtime Hub Horizontal Scaling Design

- **Implementation Detail**: Produced ADR-0005 (`docs/adr/0005-realtime-hub-horizontal-scaling.md`) defining the Redis Pub/Sub horizontal scaling design for `notification-service` and `chat-service`. Updated `AI_CONTEXT.md` architecture section.
- **Commit SHA**: ``09263f46220a89da4b93e4805283944c3f0d954a``
- **Verification**: Verified via `make docs-check` and `go test ./shared/infra/... -run TestChangelogCommitSHAs`. ✅

## ADR-0006 Negotiable Transport Pricing Model Design

- **Implementation Detail**: Produced ADR-0006 (`docs/adr/0006-negotiable-transport-pricing.md`) defining the negotiable pricing architecture, single-shot proposal rules, 5-minute timeout stages, owner vehicle/amenity governance, pre-selected employee assignment, and deferred escrow locking for the Transport/Rides category. Added index entry in `docs/adr/README.md`.
- **Commit SHA**: ``47edf8498d1d294dc00a04845f50fb17ae423fe1``
- **Verification**: Verified via `make docs-check` and `go test ./shared/infra/... -run TestChangelogCommitSHAs`. ✅

## ADR-0007 Delivery & Shipping GPS Trail Settlement Reconciliation Design

- **Implementation Detail**: Produced ADR-0007 (`docs/adr/0007-delivery-shipping-gps-reconciliation.md`) defining the two-phase GPS trail reconciliation architecture for Delivery and Shipping categories. Phase 0 hardens `UpdateJobLocation` to evaluate cumulative speed from job start alongside per-step speed checks (closing the slow-drip coordinate drift accumulation gap while inheriting single-instance in-memory throttle state). Phase 1 defines `CompleteJob` settlement reconciliation using cumulative Haversine waypoint distance with a guaranteed payout floor ($\max(LockedEscrowAmount, ActualAmount)$) and manual review flagging via `models.JobStatusEscrowReconciliationRequired`. Added index entry in `docs/adr/README.md`.
- **Commit SHA**: ``e0c3ab014b45c2eafffd70b33b2bffd7fb2fc270``
- **Verification**: Verified via `make docs-check` and `go test ./shared/infra/... -run TestChangelogCommitSHAs`. ✅

## ADR-0008 Live Employee Map Tracking Architecture & Provider Selection

- **Implementation Detail**: Produced ADR-0008 (`docs/adr/0008-live-employee-map-tracking.md`) defining the live employee map tracking architecture. Selected `flutter_map` with OpenStreetMap / Carto raster tiles to guarantee zero financial cost and avoid GCP billing account requirements. Reused `chat-service` WebSocket channels (`job:<job_id>` and `fleet:<owner_id>`) for real-time location streaming leveraging pre-existing `location_update` payload fields in `chat/hub.go`, paired with HTTP GET initial state hydration. Defined tenant-isolated authorization boundaries (owner fleet view vs single-job customer view) and established explicit non-goals (geocoding, routing/OSRM, place search). Added index entry in `docs/adr/README.md`.
- **Commit SHA**: ``c14e7e8e82b69715ffae7b5fca4d941d3410ae43``
- **Verification**: Verified via `make docs-check` and `go test ./shared/infra/... -run TestChangelogCommitSHAs`. ✅

## Flutter Client Backend Connectivity Developer Setup Guide (CONNECTING_TO_BACKEND.md)

- **Implementation Detail**: Created `frontend/CONNECTING_TO_BACKEND.md` detailing per-platform networking setups for Android Emulators (`10.0.2.2`), physical Android devices (`adb reverse tcp:8080 tcp:8080`), iOS Simulators (`localhost`), and physical iOS devices (`192.168.x.x`). Documented backend health checks (`/health`), `API_BASE_URL` resolution via `--dart-define`, dev-mode HTTPS certificate overrides (`DevHttpOverrides` and `bypassBadCertificate`), clean rebuild steps using exact Application ID / Bundle ID (`com.saascore.frontend`), real-time log streaming commands, and a troubleshooting matrix. Added cross-references in `README.md` and `frontend/README.md`.
- **Commit SHA**: ``c054907795e113e7d47edbd4776e6a52536032f1``
- **Verification**: Verified via `make docs-check` (all docgen freshness and structural drift tests passing). ✅

## AI_CONTEXT.md Orphaned Commit SHA Prose Formatting Mitigation

- **Implementation Detail**: Updated narrative text in `docs/changelog/bug-fixes.md` explaining the `AI_CONTEXT.md` orphaned commit SHA correction. Truncated the full 40-character hex string to short ref `05b5ca7...` to prevent global CI markdown SHA validation regex (`grep -oE '[0-9a-f]{40}'`) from matching historical reflog narratives as live commit citations.
- **Commit SHA**: ``3a032f138f47d0a9b140f12518e9ee59fe4ce266``
- **Verification**: Verified via whole-repository markdown SHA scan script (0 BLOCKED lines) and `make docs-check`. ✅

## Restored Full-Coverage Markdown Commit SHA Validation & Non-Citation Truncation Rule

- **Implementation Detail**: Superseded the citation-marker narrowing and two-tier warning pass by restoring strict repo-wide 40-character hex SHA scanning (blocking with exit 1 on any unresolvable 40-char SHA) in `.githooks/pre-push` and `.github/workflows/ci.yml`. This addresses the coverage gap where non-standard citation phrasing could bypass blocking checks. In addition, added rule #7 to `CLAUDE.md` requiring non-authoritative historical or orphaned commit references in prose to be written in truncated form (`05b5ca7...`).
- **Commit SHA**: ``c14bac58208173e914b376cf0bb8c89b4f90f433``
- **Verification**: Verified via repo-wide markdown SHA check (0 BLOCKED lines), fabricated hash regression test (BLOCKED, exit 1), and `make docs-check`. ✅

## End-to-End CI/CD Pipeline & Git Hooks Technical Reference (CI_CD_AND_HOOKS.md)

- **Implementation Detail**: Authored `docs/CI_CD_AND_HOOKS.md` detailing the mechanics, execution order, and verification rules of the local pre-push hook (`.githooks/pre-push`), GitHub Actions CI (`.github/workflows/ci.yml`), build-and-publish workflow (`.github/workflows/build-and-publish.yml`), two-repo deployment architecture (`omarmaarouf18/saas-core-deploy`), and known limitations (such as pre-push hook bypass on unconfigured fresh clones and GHCR package authentication). Updated `README.md` documentation index.
- **Commit SHA**: ``4b78b2c51ce7350952c8c6a684cb83821a64fb2b``
- **Verification**: Verified via `make docs-check` and `.githooks/pre-push` gate (100% pass). ✅

## Azure VM Production Deployment & Reverse Proxy Setup (DEPLOYMENT.md)

- **Implementation Detail**: Updated `docs/DEPLOYMENT.md` to reflect real production deployment on Azure VM with a custom domain using the two-repo pipeline model. Added Microsoft Azure cloud-specific provisioning section (`Standard_B2s_v2` SKU sizing, NSG inbound rules for SSH/HTTP/HTTPS/API Gateway, Azure Policy region assignment discovery), containerized Caddy Docker Compose sibling option (`docker-compose.caddy.yml`, `network_mode: host`), Custom Domain & DNS configuration notes (Vercel DNS panel distinction vs platform domain assignment, 1-2h propagation verification with `nslookup`/dnschecker.org), and a dedicated Troubleshooting section (stale container name conflicts, missing `--env-file .env`, `curl` (35) connection resets during `air` cold compilation).
- **Commit SHA**: ``43b2d35929350b5ca17fc897c73c363921a92480``
- **Verification**: Verified via `make docs-check` passing all freshness and drift-catching tests cleanly. ✅

## Four-Repository Ecosystem Onboarding Map & Production Troubleshooting Hardening

- **Implementation Detail**: Authored `docs/REPOSITORY_MAP.md` providing a comprehensive onboarding map of the 4-repo architecture (`omarmaarouf18/saas-core`, `omarmaarouf18/saas-core-deploy`, `omarmaarouf18/quick-delivery-mobile`, `omarmaarouf18/logiclinc`) and production VM target (`quickdelivery-vm`). Includes a Mermaid pipeline trigger flowchart, PAT secret scope security matrix (`DEPLOY_REPO_PAT`, `MOBILE_REPO_PAT`, `LOGICLINC_REPO_PAT`), explicit branch deployment rules (`main` vs `logic-exploitation`), and an operator triage runbook. Updated `docs/DEPLOYMENT.md` §10 troubleshooting (correcting §10.3 to reflect static Go binary runtime, adding §10.4 MongoDB `storedKey mismatch` password change resolution, and §10.5 orphaned `saas-caddy` realign procedure). Updated `README.md` documentation index.
- **Commit SHA**: ``fd751f5dc833511329360d6411265450781807b4``
- **Verification**: Verified via `make ci` gate and `make docs-check`. ✅

## Deferred Business Owner Configuration Backlog Scope

- **Implementation Detail**: Added documented, deferred Business Owner Configuration backlog entry in `AI_CONTEXT.md` under `### 3. Not Started Yet`, detailing future scope for custom negotiable base pricing per owner, business operating hours, service coverage geographic radius boundaries, and explicitly noting their absence in `services/user-service/internal/models/models.go` (`Service` and `Job` structs).
- **Commit SHA**: ``f25b8ef8d73920f5e18c36cdf4c4d53ef89ed016``
- **Verification**: Verified via `make docs-check` and `.githooks/pre-push` gate passing all freshness and commit SHA checks cleanly. ✅

## Comprehensive Repository Documentation Freshness Sweep

- **Implementation Detail**: Resolved all documentation drift identified in the whole-repository audit. Updated `AI_CONTEXT.md`, `docs/FRONTEND_INTEGRATION_SCOPE.md`, `docs/frontend/ARCHITECTURE.md`, and `docs/frontend/DESIGN_SYSTEM.md` to annotate removed administrative reviewer components (`KybKyeReviewScreen`, `DocumentViewerDialog`, reviewer provider methods) with `[ADR-0013 REMOVED]`/`[EXCLUDED PER ADR-0013]` notes. Realigned stale file path links in `FRONTEND_INTEGRATION_SCOPE.md` to point to valid screen files (`customer_jobs_screen.dart`, `forgot_password_screen.dart`, `api_client.dart`, `my_account_screen.dart`, `employee_screen.dart`, `create_ticket_dialog.dart`). Updated `docs/APPLICATION_MAP.md` header commit SHA. Annotated cross-repo deployment SHA `c0b3f6a` with `(saas-core-deploy)` across `AI_CONTEXT.md`, `docs/CI_CD_AND_HOOKS.md`, and `docs/RUNBOOK.md`.
- **Commit SHA**: ``4e82d984df1561f9facf51278660ff577bca6b37``
- **Verification**: Verified via `make docs`, `make docs-check`, `go test ./shared/infra/docgen/...`, and repo-wide markdown freshness audit script (0 remaining drift issues). ✅


## AI_CONTEXT.md Doc-Drift Correction: TestComplaintRoutingConcurrency Retry Loop Was Never Removed

- **Implementation Detail**: The prior session's entry claimed the 3-attempt retry loop (`for attempt := 0; attempt < 3; attempt++` + `time.Sleep(10 * time.Millisecond)`) in `TestComplaintRoutingConcurrency` (`services/chat-service/internal/handlers/chat_test.go`) had been removed. Direct verification against the branch found the loop **still present** at lines 390–398. Of the originally claimed changes, only two actually landed: the `SetMaxPoolSize(100)` revert (confirmed absent from `store/mongodb.go`) and the atomic-CAS audit comment on `CreateTicketAndAssign` (confirmed at `store/mongodb.go:272`). The entry has been rewritten to state what is actually true, with the retry-loop removal flagged as a follow-up decision instead of silently performed in a documentation pass.
- **Commit SHA**: ``94fe6e43987396fb609c62185bb254db953a2a3f``
- **Verification**: Literal greps on the current working tree: retry loop present (`chat_test.go:390: for attempt := 0; attempt < 3; attempt++`; sleep at line ~396); `grep SetMaxPoolSize store/mongodb.go` → no matches; CAS comment present (`store/mongodb.go:272`). ✅

## Documentation Freshness Audit — Full Repo Sweep (60 files)

**Date**: 2026-08-22
**Category**: Documentation
**Related Commit SHA**: ``0c232c8131095066db6968c42bb164cd81f67922``

- **Scope**: every markdown file in the repo (60 found via find), audited in an isolated detached worktree at origin/logic-exploitation (`94fb813`), then text-only corrections applied to `logic-exploitation`.
- **Evidence base**: 492 unique 40-hex SHA citations across all docs — **492/492 resolve**, zero orphans (post-rebase citation drift fully healed). `make docs-check` full gate PASS. Counts re-derived from filesystem: 29 screen files (28 production + debug component_library), 32 shared widgets, 11 providers, 12 golden baselines / 7 golden tests; suite 361/361.
- **Corrections applied (batch 1)**: changelog README index + AI_CONTEXT intro entry-count syncs (security 104→125, features 56→65, infra 49→54, bug-fixes 55→69, docs 34→35, refactoring 2→8); DESIGN_SYSTEM.md + root DESIGN.md widget count 27→32 with source-of-truth note; STATUS.md Phase-29 header flipped to COMPLETE (all sub-phases closed) and coverage Known-Gap annotated as superseded by A3-P3 (75.2%, 361 tests); audit/shared-module-review WS-token flag closed RESOLVED-BY-VERIFICATION (no URL/RawQuery logging in chat.go) while the hardcoded 7×24h refresh-window flag confirmed still open at 3 sites.
- **Verified-clean highlights**: UI_UX_ENTERPRISE_ROADMAP §Corrections internally consistent (disputed phases relabeled; undisputed rows stand on their own script evidence); GEMINI.md/IMPLEMENTATION.md correctly positioned as pointer/historical docs; ARCHITECTURE.md "28 active screens" defensible (excludes debug screen).
- **Cross-cutting pattern**: hand-typed entry counts and library sizes drift on every pass. Recommendation recorded: generate counts via script into a single source snippet.
- **Process incident (disclosed)**: batch-1 commit initially landed on parallel-session branch `q5-24-fixes` (primary checkout had been re-branched mid-flight). Recovered: cherry-picked onto `logic-exploitation` as ``0c232c8…`` and reset `q5-24-fixes` to its exact prior tip `fa904ab`. No history rewritten; nothing lost.

## Full Documentation Audit — Citation Correction, Index Completion & Map Note Refresh

- **Implementation Detail**: Repo-wide documentation audit (make docs-check + manual cross-checks beyond the automated gate's scope). Three defects found and fixed:
  - **Rule-8 citation mismatch** (`docs/changelog/new-features.md`): the "Stitch Unified UI Implementation — Batch E" entry cited `e83e1fbc4ebd3b7565ec792ce5d7a3c7ae081838`, which `git show --stat` proves is the **Batch D** commit ("Batch D owner portal and fleet management screens"). Re-pointed to `53ccd0678e0289e7d9559e14677254dd41863148` ("Batch E employee experience screens and final verification"). The Batch D entry's citation was verified correct and left untouched. Existence + feature-match re-verified for sampled citations across all 6 category files.
  - **STATUS.md File Tracking Index gaps**: 6 `.dart` files under `frontend/lib/` were unindexed — `core/update_gate.dart`, `widgets/form_screen_template.dart`, and the l10n group (`l10n/l10n.dart` + 3 generated `app_localizations*` outputs, annotated as gen-l10n products). Root cause: the automated structural drift check (`shared/infra/docgen/structural_drift_test.go`) only scans `screens/providers/models`, so `widgets/core/l10n` additions drift silently against the written "every .dart under frontend/lib" rule.
  - **APPLICATION_MAP.md staleness**: the "as of Git commit" note pointed at `7f06440` while HEAD had advanced ~20 backend/frontend commits. `make docs` regenerated it; endpoint table confirmed byte-identical (no routing/auth changes since the noted commit — note-only staleness).
- **Commit SHA**: ``122f2c2dcc51d6fa49b08a73af7b0ca199bd83b7``
- **Verification**: `make docs-check` pass (exit 0); DESIGN.md dependency constraints re-checked against `frontend/pubspec.yaml` (exact match); all 40-char SHAs resolve repo-wide (pre-push validator). Verified via local execution only. ✅
