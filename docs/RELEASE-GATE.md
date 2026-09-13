# Release Gate Specification: Quick Delivery SaaS Platform

## 1. Purpose & Scope

This specification defines the explicit, automated quality gates and release criteria that must be satisfied before promoting code to staging or deploying to production.

The policy applies to all microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`), the shared runtime modules (`shared/infra`), ops tooling (`kyc-reviewer-console`), and client applications (`frontend/`).

Release verification operates under a **zero-trust, evidence-based** policy: no release candidate may proceed on verbal assertions or partial test runs. Every stage requires deterministic, machine-verifiable exit codes.

---

## 2. CI/CD Release Pipeline Topology

Release validation is split across three distinct enforcement tiers:

```
+---------------------------------------------------------------------------------------------------+
| Tier 1: Local Pre-Push & Pre-Merge Gate                                                           |
| Hook: .githooks/pre-push | Make Target: make ci                                                   |
| - gofmt -l . (zero unformatted files)                                                             |
| - Commit SHA reachability & drift check (all 40-char SHAs exist in branch history)                |
| - Go version consistency across all go.mod, go.work, and Dockerfiles (1.26.6 / 1.26)              |
| - make docs-check (docgen AST sync, dependency version locks, status alignment)                   |
| - make contract-test (in-process AST reflection & schema contract tests: tests/contracts/)        |
| - Unit, vet, and component integration tests for all 5 services and shared/infra                 |
| - gosec static security analysis & govulncheck dependency vulnerability scan                     |
| - Flutter analyze & unit/widget test suite (frontend/)                                            |
| - Frontend composition gate (scripts/frontend_composition_gate.sh)                                |
+---------------------------------------------------------------------------------------------------+
                                                │
                                                ▼ PASS
+---------------------------------------------------------------------------------------------------+
| Tier 2: CI Automated Verification Gate                                                            |
| Workflow: .github/workflows/ci.yml                                                                |
| - Job: lint-formatting                                                                            |
| - Job: build-test (Matrix across api-gateway, auth, chat, notif, user, shared/infra)              |
| - Job: flutter-test (Flutter analyze, composition gate, and widget tests)                         |
| - Step: make backend-frontend-parity-check (zero unconsumed or rogue routes)                      |
+---------------------------------------------------------------------------------------------------+
                                                │
                                                ▼ PASS
+---------------------------------------------------------------------------------------------------+
| Tier 3: Staging Parity & End-to-End Release Gate                                                  |
| Workflow: .github/workflows/release-gate-e2e.yml | Topology: infrastructure/staging/              |
| - Automated container orchestration: Caddy edge proxy, API Gateway, 4 backend services,           |
|   KYC Reviewer Console, MongoDB 7, Redis 7 Alpine with mTLS certificates                          |
| - Suite 1: Critical User Journeys (CUJ-A through CUJ-I, 9/9 journeys pass)                        |
| - Suite 2: Systematic API Contract Suite (82/82 canonical endpoints pass)                         |
| - Suite 3: Standalone Security Regression Suite (6 attack classes, 100% pass)                     |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. Concrete Quality Gate Criteria

Before any build artifact is tagged for production deployment (`infrastructure/deploy/deploy.yml`), the following six automated gates must pass cleanly:

| # | Quality Gate Area | Verification Command / Target | Pipeline Job Name | Pass Threshold | Blocking Level |
| :-: | :--- | :--- | :--- | :---: | :---: |
| 1 | **Code Formatting & Repository Integrity** | `gofmt -l .` && `make docs-check` | `ci.yml / lint-formatting` | 0 format issues, 0 broken SHA refs, 0 doc drifts | **BLOCKING** |
| 2 | **Unit & Module Integration Suites** | `make ci` | `ci.yml / build-test` | 100% PASS across all 5 services + `shared/infra` | **BLOCKING** |
| 3 | **Route & Schema Parity Check** | `make backend-frontend-parity-check` | `ci.yml / lint-formatting` | 0 unaccounted routes (all 82 canonical routes consumed) | **BLOCKING** |
| 4 | **Inter-Service Schema Contracts** | `make contract-test` | Local pre-push & `ci.yml` | 11/11 tests across 8 REST boundaries pass (0 drift) | **BLOCKING** |
| 5 | **Staging Critical User Journeys (CUJs)** | `go test -v ./tests/e2e -run "TestCUJ_"` | `release-gate-e2e.yml / e2e-release-gate` | 9/9 Journeys Pass (CUJ-A through CUJ-I) | **BLOCKING** |
| 6 | **Systematic API Contract Suite** | `go test -v ./tests/e2e -run "TestContract_"` | `release-gate-e2e.yml / e2e-release-gate` | 82/82 Canonical Endpoints Pass (HTTP codes & schemas) | **BLOCKING** |
| 7 | **Standalone Security Regression Suite** | `go test -v ./tests/e2e -run "TestSecurity_"` | `release-gate-e2e.yml / e2e-release-gate` | 6/6 Attack Class Test Suites Pass | **BLOCKING** |
| 8 | **Static Security & Vulnerability Analysis** | `gosec ./...` && `govulncheck ./...` | `ci.yml / build-test` | 0 high/critical vulnerabilities | **BLOCKING** |
| 9 | **Client Application Gate** | `cd frontend && flutter test` | `ci.yml / flutter-test` | 100% PASS (532+ widget/unit tests, 0 analyzer errors) | **BLOCKING** |

---

## 4. Release Decision Matrix

Promotion decisions are evaluated strictly against the following state matrix:

### 🟢 GREEN: Full Release Permitted
* **Criteria**: All 9 automated gates pass without exception. No flakiness observed in staging runs.
* **Action**:
  1. Fast-forward merge `logic-exploitation` into `main`.
  2. Tag release version (e.g. `git tag -a vX.Y.Z -m "Release vX.Y.Z"`).
  3. Trigger automated container publish and production deploy via `.github/workflows/build-and-publish.yml`.
* **Required Sign-Off**: Standard engineering peer review.

### 🟡 YELLOW: Conditional Release / Staging-Only Deploy
* **Criteria**:
  - Non-functional cosmetic or documentation-only defect discovered in non-critical client UI.
  - Parity check passes, but a companion alias deprecation warning is active.
  - Minor performance degradation under non-peak staging load not impacting transactional invariants.
* **Action**: Permitted to deploy to Staging or QA testing environments for human review. **PROHIBITED** from deploying to Production.
* **Required Sign-Off**: Requires written sign-off from Platform Tech Lead AND Lead Security Engineer before progressing to GREEN.

### 🔴 RED: Release Hard Blocked
* **Criteria**: Any of the following occurs:
  - Any single failure in unit tests, integration tests, or CUJ journeys.
  - Contract testing detects schema drift or unhandled status codes on any of the 82 canonical endpoints.
  - Security regression failure (JWT tampering accepted, rate limiter bypassed, CORS misconfigured, or RBAC matrix violation).
  - Uncommitted route detected by `make backend-frontend-parity-check`.
  - Static security scan (`gosec` or `govulncheck`) surfaces an unmitigated vulnerability.
  - Git repository drift or fabricated commit SHA detected.
* **Action**: Immediate halt. Rollback candidate immediately. Pipeline automatically aborts deployment.

---

## 5. Emergency Hotfix Bypass Policy

In the event of an active P0 production incident (e.g. datastore corruption, complete authentication outage, active exploit), an accelerated hotfix release may be authorized under strict governance.

### 1. Authorization Authority
An emergency hotfix bypass can ONLY be authorized jointly by:
* **VP of Engineering / Head of Technology**
* **Principal Security Architect / Tech Lead**

### 2. Permitted Scope of Bypass
* The staging container spin-up in `release-gate-e2e.yml` may be parallelized or scoped to the affected microservice if global staging infrastructure is impaired.
* Non-blocking documentation checks may be deferred for up to 4 hours post-incident.

### 3. Absolute Non-Negotiables (Never Bypassed)
Under no circumstances may any hotfix bypass:
1. `make ci` (unit test suite, go vet, and compilation for the modified service).
2. Go security checks (`gosec`).
3. Targeted regression test verifying the fix for the specific root cause.
4. Git commit integrity rules (no force pushing, no unverifiable commits).

### 4. Post-Hoc Remediation Requirements
Within **24 hours** of hotfix deployment:
1. A post-mortem document must be committed to `docs/postmortems/`.
2. A permanent regression test reproducing the original defect must be merged into `tests/e2e/`.
3. Full staging parity must be executed via `release-gate-e2e.yml` to confirm all 9 gates are GREEN.
4. Fast-forward synchronization between `main` and `logic-exploitation` must be completed.
