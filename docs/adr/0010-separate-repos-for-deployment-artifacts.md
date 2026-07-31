# ADR-0010: Separate Repositories vs. Branches for Deployment Artifacts

- **Status**: Accepted
- **Date**: 2026-07-31
- **Related Commit SHA**: c5999f178e071f1651cb2a296d386e8cfcd0c9a4
- **Related audit finding**: Multi-Repository Release Pipeline Architecture & Security Audit

## Context

The Quick Delivery SaaS platform is authored as a monorepo (`omarmaarouf18/saas-core`) containing 5 Go microservices, shared infrastructure libraries, Flutter mobile application source code (`frontend/`), system documentation, and CI quality gates.

During initial release planning, we evaluated two architectural strategies for distributing deployment configuration, standalone mobile source code, and static marketing website release metadata:

1. **Orphan Branches within Monorepo**: Storing deployment files, mobile code snapshots, and website metadata on orphan branches (`deploy`, `mobile`, `website`) inside `saas-core` itself.
2. **Dedicated Separate Repositories**: Provisioning standalone GitHub repositories (`omarmaarouf18/saas-core-deploy`, `omarmaarouf18/quick-delivery-mobile`, and `omarmaarouf18/logiclinc`) linked via automated GitHub Actions push pipelines.

### Architectural Rationale for Separate Repositories
Production VPS cloud hosts, mobile CI runners (`flutter build apk`), and static marketing websites (deployed on Vercel) should never require access to primary monorepo source code, Go compilers, Flutter SDKs, internal test suites, or development commit history. Dedicated separate repositories provide isolated, least-privilege pull surfaces with zero application source code exposure on consumer platforms.

### Real Friction & Failure Modes Paid
Adopting a multi-repository model introduced cross-repository authentication and scope management friction that produced real operational failures during initial setup:

1. **Checkout Credential Persistence Override (`403 Forbidden`)**:
   In `.github/workflows/sync-mobile-frontend.yml`, `actions/checkout@v4` defaulted to `persist-credentials: true`, which injected `GITHUB_TOKEN` into the runner's global git config (`http.extraheader`). During the downstream `git push` step, Git prioritized the global `GITHUB_TOKEN` header over the embedded `MOBILE_REPO_PAT` in the push URL, resulting in `Permission to ... denied to github-actions[bot]`.
   *Resolution*: Added `persist-credentials: false` to `actions/checkout@v4` and formatted push URLs as `https://x-access-token:${MOBILE_REPO_PAT}@github.com/owner/repo.git`.

2. **Workflow Scope Rejection on Subtree Push**:
   `sync-mobile-frontend.yml` extracts `frontend/` using `git subtree split` and force-pushes to `quick-delivery-mobile:main`. Because `frontend/` contains `.github/workflows/build-apk.yml`, the push modified files under `.github/workflows/`. The GitHub API rejected the push with `refusing to allow a Personal Access Token to create or update workflow ... without workflow scope` because `MOBILE_REPO_PAT` was initially created with `Contents: Read and write` permission only.
   *Resolution*: Regenerated `MOBILE_REPO_PAT` with both **`Contents: Read and write`** AND **`Workflows: Read and write`** scopes.

3. **Secret Exposure Incident & Handling Discipline**:
   During initial manual secret setup, a Personal Access Token value was accidentally pasted into chat context. The exposed token was immediately revoked and regenerated. To prevent future credential leakage, we established strict secret handling discipline: tokens are read strictly from local shell environment variables (`$MOBILE_TOKEN`/`$SITE_TOKEN`) by automated tooling, and raw token values are never typed, printed, logged, or echoed back in agent responses or repository files.

## Decision

We formally adopted a decoupled **Four-Repository Multi-Artifact Deployment Architecture**:

1. **`omarmaarouf18/saas-core`** (Monorepo): Primary source repository containing Go microservices, Flutter frontend, docs, and core CI gates.
2. **`omarmaarouf18/saas-core-deploy`** (Backend VPS Deployment): Lightweight, deploy-only repo containing `docker-compose.yml`, `.env.example`, and `Caddyfile`. Updated automatically via `.github/workflows/build-and-publish.yml` using `DEPLOY_REPO_PAT`.
3. **`omarmaarouf18/quick-delivery-mobile`** (Mobile App): Standalone Flutter mobile repo. Updated automatically via `.github/workflows/sync-mobile-frontend.yml` using `MOBILE_REPO_PAT` (with `Contents` and `Workflows` write permissions). Triggers `build-apk.yml` to compile release APKs and publish GitHub Releases.
4. **`omarmaarouf18/logiclinc`** (Marketing Website): Static marketing website deployed on Vercel (`logiclinkeg.tech`). Receives live `app-release.json` updates from `quick-delivery-mobile`'s `build-apk.yml` using `LOGICLINC_REPO_PAT`.

## Consequences

### Positive
- **Clean Attack Surface Isolation**: Production VPS hosts, mobile release runners, and static website hosts clone only their respective minimal repositories. Zero application source code, Go/Flutter build tools, or dev history are exposed on production surfaces.
- **Minimal Pull Footprint**: Production VPS hosts pull lightweight Docker image tag updates (~few KB) rather than full repository trees.
- **Independent Target Lifecycles**: Backend deployments, mobile APK compilation, and website release metadata updates trigger independently without coupling runner environments.

### Negative / Tradeoffs
- **Increased Credential Management Overhead**: Requires managing and periodically rotating 3 separate Personal Access Tokens (`DEPLOY_REPO_PAT`, `MOBILE_REPO_PAT`, `LOGICLINC_REPO_PAT`) across 4 repositories.
- **Risk of Silent Workflow Drift**: Upstream sync workflows can silently fail or drift out of date if PAT permissions expire or fail silently, leaving consumer repositories running stale workflow definitions until audited.
- **Increased Debugging Complexity**: Tracing cross-repository deployment failures requires inspecting logs across multiple GitHub Actions runners across distinct repositories.
