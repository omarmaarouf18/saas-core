# Documentation Changelog

This file tracks historical entries for the primary category: **Documentation Changelog**.

---

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
