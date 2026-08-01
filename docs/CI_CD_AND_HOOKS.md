# SaaS Platform — CI/CD Pipeline & Git Hooks Reference

This document provides a factual, technical breakdown of the verification, quality gate, and production deployment mechanisms operating in this repository.

---

## 1. Local Pre-Push Hook (`.githooks/pre-push`)

### Activation & `core.hooksPath`
Git by default only executes hooks stored in `.git/hooks/`. Files in `.githooks/` inside the repository tree are **not active on a fresh clone**. 

To activate the hook, the developer must run `make setup` (or any `make` target that includes `ensure-hooks` as a prerequisite) once per clone. This executes:

```bash
git config core.hooksPath .githooks
```

### Execution Order & Checks
When active, `.githooks/pre-push` executes automatically before every `git push`. It runs the following checks in order:

1. **Environment Setup**: Exports default authenticated connection strings for host-level integration testing against local Docker containers (`MONGO_URI` and `REDIS_URI`).
2. **Go Formatting (`gofmt`)**: Runs `gofmt -l .` across the repository. Fails if any unformatted `.go` files are detected.
3. **Dart Formatting (`dart format`)**: Checks `frontend/lib/` formatting via `dart format --output=none --set-exit-if-changed lib/`.
4. **Markdown Commit SHA Verification**:
   - Scans **all `.md` files repo-wide** for 40-character hexadecimal strings and verifies each commit exists in local Git history via `git cat-file -e "$sha^{commit}"`.
   - Diffs newly added `- **Commit SHA**:` lines in `docs/changelog/*.md` against `HEAD~1`, verifying each newly cited SHA exists and is an ancestor of `HEAD`.
   - *Historical Context*: Scope was originally restricted to `docs/changelog/*.md`. It was widened repo-wide after an incident where a fabricated commit SHA located outside `docs/changelog/` went undetected by the local hook.
5. **Go Version Drift Guard**: Asserts that `CANONICAL_GO_VERSION="1.26"` matches the Go version specified in `go.work`, `services/*/go.mod`, `shared/infra/go.mod`, `tools/docgen/go.mod`, `.github/workflows/ci.yml`, and `services/*/Dockerfile`.
6. **Per-Module Go Build, Vet, Test, and Security Scans**: Iterates through 6 Go modules (`services/api-gateway`, `services/auth-service`, `services/chat-service`, `services/notification-service`, `services/user-service`, `shared/infra`):
   - `go build ./...`
   - `go vet ./...`
   - `go test ./... -count=1`
   - `govulncheck ./...` (filters out uncalled stdlib vulnerabilities with warning output, blocks on active third-party package vulnerabilities)
   - `gosec ./...`
7. **Frontend Flutter Checks**: Runs `flutter analyze` and `flutter test` inside `frontend/`.

### Makefile Wiring & Hook Bypass Limitation
The Makefile defines `ensure-hooks` as follows:

```make
ensure-hooks:
	@if [ "$$(git config --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then \
		git config core.hooksPath .githooks; \
		echo "[MAKE] Configured git core.hooksPath to .githooks"; \
	fi
```

`ensure-hooks` is listed as a prerequisite for `setup`, `docs`, `docs-check`, `ci`, `commit`, and `push`.

> [!WARNING]
> **Known Limitation**: `ensure-hooks` only executes when one of those specific `make` targets is called. On a fresh repository clone where a developer performs raw `git commit` and `git push` without ever running `make`, `core.hooksPath` remains unconfigured, and the local pre-push hook is bypassed entirely.

---

## 2. GitHub Actions CI (`.github/workflows/ci.yml`)

Unlike local Git hooks, GitHub Actions CI is **authoritative and non-bypassable**. It runs automatically on GitHub servers for every push and pull request targeting `main` or `logic-exploitation`.

### Workflow Jobs
`ci.yml` executes three parallel jobs:

1. **`lint-formatting`**:
   - `gofmt` verification.
   - Repo-wide markdown commit SHA verification.
   - Go version consistency drift guard.
2. **`build-test`**:
   - Spawns MongoDB (`mongo:7`) and Redis (`redis:7-alpine`) service containers.
   - Matrix execution across 6 Go modules (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`, `shared-infra`).
   - Executes `go mod download`, `go build ./...`, `go vet ./...`, `go test ./... -count=1`, `govulncheck`, and `gosec`.
3. **`flutter-test`**:
   - Sets up Flutter stable channel.
   - Runs `dart format --set-exit-if-changed lib/`, `flutter analyze`, and `flutter test`.

### Practical Utility of CI & Real Incident Cases
In the project's history, the "Verify Markdown Commit SHAs" guard has caught fabricated and dangling SHAs:
1. **Unconfigured Hook Bypass**: A fabricated commit SHA was pushed from an environment where the local pre-push hook had not been activated. GitHub Actions CI immediately caught it on the `lint-formatting` job's "Verify Markdown Commit SHAs" step.
2. **Dangling Loose Object / Un-Amended File Edit Incident**: During the documentation of ADR-0012, an initial commit (`15f6f28...`) was created locally before updating the file's `Related Commit SHA` field to the amended commit (`f819ce3...`). Because `15f6f28...` existed as a loose object in the local `.git/objects` directory, `git cat-file -e` passed locally during `make ci`. However, loose objects are not transferred during `git push`. When GitHub Actions ran in a clean checkout, `15f6f28...` was missing and CI failed with `BLOCKED: fabricated/non-existent SHA in ./docs/adr/0012-single-source-of-truth-for-production-env.md`. Following this incident, both `.githooks/pre-push` and `.github/workflows/ci.yml` were upgraded to enforce `git merge-base --is-ancestor "$sha" HEAD` across ALL markdown files, preventing dangling local objects from passing locally before push.

---

## 3. Build-and-Publish Pipeline (`.github/workflows/build-and-publish.yml`)

### Workflow Trigger & Security Policy
`build-and-publish.yml` triggers **only on push to `main`**. Pushes to `logic-exploitation` or other development branches do not trigger image builds or deployment repository syncs.

> [!CAUTION]
> **Strict Trigger Policy & Incident Record**:
> `workflow_dispatch` is strictly prohibited on `build-and-publish.yml` to prevent un-reviewed dev branch commits from overwriting production deployment tags. During GitHub App token testing, `workflow_dispatch` was temporarily added to `build-and-publish.yml` and dispatched on `logic-exploitation` (Run ID `30684940738`), causing `update-deployment-repo` to push out-of-policy image tags (`375a017`) to `saas-core-deploy:main`. The deployment repo was immediately rolled back to `main` HEAD (`efbe55b` via commit `c0b3f6a`), and `workflow_dispatch` was permanently removed from `build-and-publish.yml` to enforce push-to-main-only governance.

### Pipeline Structure
The workflow contains two sequential jobs:

1. **`build-and-publish` Job**:
   - Matrix build across all 5 microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`).
   - Logs into GitHub Container Registry (`ghcr.io`) using `GITHUB_TOKEN`.
   - Builds the production multi-stage image (`target: prod`) from root context (`.`).
   - Publishes images to `ghcr.io/omarmaarouf18/saas-core-<service>:${COMMIT_SHA}` and `:latest`.

2. **`update-deployment-repo` Job**:
   - Runs after `build-and-publish` completes.
   - Generates a short-lived GitHub App installation token via `actions/create-github-app-token@v1` (using secrets `APP_ID` and `APP_PRIVATE_KEY`) scoped strictly to `saas-core-deploy`.
   - Checks out the private deployment repository `omarmaarouf18/saas-core-deploy` using the generated installation token.
   - Replaces image tag references in `saas-core-deploy`'s `docker-compose.yml` with the current commit SHA.
   - Commits and pushes the updated `docker-compose.yml` to `saas-core-deploy` `main` branch.

### Deployment Repository CD Pipeline (`saas-core-deploy/.github/workflows/deploy.yml`)
When `build-and-publish.yml` pushes an updated `docker-compose.yml` to `saas-core-deploy:main`:
1. **Trigger**: `.github/workflows/deploy.yml` fires automatically on push to `main` in `omarmaarouf18/saas-core-deploy`.
2. **Runner Execution**: Runs on a dedicated repository-scoped GitHub Actions self-hosted runner (`[self-hosted, saas-vm]`) installed on the production VM under low-privilege system user `deploybot`.
3. **Execution Steps**:
   - `docker compose config --quiet`: Validates compose file syntax (fails job immediately if malformed).
   - `docker compose pull`: Downloads updated production container images from GHCR.
   - `docker compose up -d --remove-orphans`: Applies container updates in detached mode.
   - Health Check: Performs a 12-attempt loop (5 seconds apart) calling `http://localhost:8080/health`. Fails job if non-200.
   - Failure Diagnostics: On failure, prints the last 50 lines of logs (`docker compose logs --tail=50`) directly into GitHub Actions run output.

### Security Model & Privilege Boundary
- **Outbound Polling Only**: The self-hosted runner polls GitHub via HTTPS outbound; zero inbound network ports are opened on the VM for CD.
- **`docker` Group Access**: The `deploybot` user has no `sudo` privileges or interactive SSH shell, but belongs to the `docker` group to interact with `/var/run/docker.sock`. On Linux systems, Docker socket access is effectively root-equivalent. This is an explicit, accepted tradeoff for single-VM deployments to eliminate SSH credential sharing.

> [!IMPORTANT]
> **Known Limitation — Single-VM Scope**:
> This self-hosted runner CD pipeline is strictly designed and scoped for single-VM deployments. Multi-node clusters, auto-scaling groups, or Kubernetes orchestrators are out of scope for this architecture and will require a distinct deployment design decision if ever revisited.

---

## 4. Mobile Frontend Subtree Sync (`.github/workflows/sync-mobile-frontend.yml`)

### Workflow Overview & Purpose
`sync-mobile-frontend.yml` decouples the Flutter mobile application from the primary Go monorepo (`omarmaarouf18/saas-core`) by extracting the `frontend/` directory into a standalone repository (`omarmaarouf18/quick-delivery-mobile`).

### Execution & Triggering
- **Automatic Trigger**: Fires on `push` to `main` whenever changes touch `frontend/**` paths.
- **Manual Trigger**: Can be manually executed anytime via `workflow_dispatch` on `main` or `logic-exploitation`.

### Subtree Split Mechanism & Authentication
1. **Checkout Repository**: Checks out `saas-core` with `fetch-depth: 0` (full history required for subtree splitting) and explicit `persist-credentials: false`.
2. **Subtree Split**: Runs `git subtree split --prefix=frontend` to isolate `frontend/` history into a clean commit SHA.
3. **App Token Generation & Remote Force-Push**: Generates a short-lived GitHub App installation token via `actions/create-github-app-token@v1` scoped strictly to `quick-delivery-mobile`, and force-pushes the split SHA to `omarmaarouf18/quick-delivery-mobile:main` using:
   ```bash
   git push "https://x-access-token:${APP_TOKEN}@github.com/omarmaarouf18/quick-delivery-mobile.git" "${SPLIT_SHA}:refs/heads/main" --force
   ```

### Consumed Secrets & Required Scopes
- **Primary Secrets**: `APP_ID` and `APP_PRIVATE_KEY` (GitHub App `quick-delivery-automation`).
- **Repository Location**: Stored in `omarmaarouf18/saas-core` Actions secrets.
- **Required App Installation Permissions**:
  - **`Contents: Read and write`**: Required to force-push repository commits and branches to `quick-delivery-mobile`.
  - **`Workflows: Read and write`**: **CRITICAL**. Required because `frontend/` contains `.github/workflows/build-apk.yml`. Pushing changes that modify files under `.github/workflows/` is rejected by GitHub API if the installation token lacks explicit workflow permissions.

---

## 5. Standalone Mobile Build & Release Pipeline (`build-apk.yml`)

### Workflow Location & Synchronization
- **Source Location**: [frontend/.github/workflows/build-apk.yml](file:///mnt/windows_data/CS%20tools/Antigravity/SaaS%20prototype/frontend/.github/workflows/build-apk.yml) in `saas-core`.
- **Target Location**: Root `.github/workflows/build-apk.yml` in `omarmaarouf18/quick-delivery-mobile` (propagated automatically via `sync-mobile-frontend.yml`).

### Pipeline Execution Steps
1. **Trigger**: Fires on `push` to `main` (or `workflow_dispatch`) inside `quick-delivery-mobile`.
2. **Toolchain Setup**: Configures Java JDK 17 (Temurin) and Flutter stable channel.
3. **Build Release APK**: Executes `flutter build apk --release --dart-define=API_BASE_URL="${API_BASE_URL}"`.
4. **Artifact Upload**: Uploads built APK as a run artifact (`app-release-<short_sha>`).
5. **Create GitHub Release**: Uses `gh release create` to publish tag `app-release-<short_sha>` attached to `quick-delivery-mobile` with `app-release.apk`. Requires job permission `permissions: contents: write`.
6. **Publish Release Info to Website**: Generates a short-lived GitHub App installation token via `actions/create-github-app-token@v1` (scoped to `logiclinc`), clones `omarmaarouf18/logiclinc` marketing website, updates `app-release.json` with version, live release URL, timestamp, and size in MB, then commits and pushes to `logiclinc:main`.

### Consumed Secrets
- **Primary Secrets**: `APP_ID` and `APP_PRIVATE_KEY` (GitHub App `quick-delivery-automation`).
- **Repository Location**: Stored in `omarmaarouf18/quick-delivery-mobile` Actions secrets (and `saas-core`).
- **Required App Installation Scope**: `Contents: Read and write` on `omarmaarouf18/logiclinc`.

---

## 6. Secrets Inventory

The platform uses GitHub App installation tokens generated on-the-fly via `actions/create-github-app-token@v1` using App ID and Private Key secrets across repositories:

| Secret Name | Repository Stored In | Consuming Workflows | Purpose & Scopes | Status |
| :--- | :--- | :--- | :--- | :--- |
| `APP_ID` | `omarmaarouf18/saas-core`<br>`omarmaarouf18/quick-delivery-mobile` | All workflows (`build-and-publish`, `sync-mobile-frontend`, `build-apk`) | GitHub App ID for `quick-delivery-automation`. Used to mint short-lived installation tokens. | **Active (Primary)** |
| `APP_PRIVATE_KEY` | `omarmaarouf18/saas-core`<br>`omarmaarouf18/quick-delivery-mobile` | All workflows (`build-and-publish`, `sync-mobile-frontend`, `build-apk`) | RSA Private Key for `quick-delivery-automation`. Used to mint short-lived installation tokens. | **Active (Primary)** |
| `DEPLOY_REPO_PAT` | `omarmaarouf18/saas-core` | None | Formerly `Contents: Read and write` on `saas-core-deploy` | **Decommissioned & Revoked** |
| `MOBILE_REPO_PAT` | `omarmaarouf18/saas-core` | None | Formerly `Contents: Read and write`, `Workflows: Read and write` on `quick-delivery-mobile` | **Decommissioned & Revoked** |
| `LOGICLINC_REPO_PAT` | `omarmaarouf18/quick-delivery-mobile` | None | Formerly `Contents: Read and write` on `logiclinc` | **Decommissioned & Revoked** |

---

## 7. End-to-End Operational Lifecycle

The entire 4-repository trigger and data flow operates as follows:

```text
                     [ Developer Work ]
                             │
                             ▼
              Push to 'logic-exploitation'
                             │
            (Local Pre-Push Hook: .githooks/pre-push)
                             │
                             ▼
       GitHub Actions CI (.github/workflows/ci.yml)
           (Lint, Go Mod Build/Test/Sec, Flutter)
                             │
                             ▼
               Pull Request / Merge to 'main'
                             │
           ┌─────────────────┴─────────────────┐
           ▼                                   ▼
.github/workflows/build-and-publish.yml    .github/workflows/sync-mobile-frontend.yml
  ├─► Build 5 GHCR Docker Images             ├─► `git subtree split --prefix=frontend`
  └─► Update `docker-compose.yml`            └─► Force-push to `quick-delivery-mobile:main`
      in `saas-core-deploy`                       (using MOBILE_REPO_PAT)
           │                                           │
           ▼                                           ▼
   Production VPS Host                    .github/workflows/build-apk.yml
   `git pull` &&                          (in `quick-delivery-mobile`)
   `docker compose up -d`                             │
                                                      ├─► Flutter Release APK Build
                                                      ├─► `gh release create app-release-<sha>`
                                                      └─► Push `app-release.json` update
                                                          to `logiclinc:main`
                                                          (using LOGICLINC_REPO_PAT)
                                                               │
                                                               ▼
                                                      Vercel Production Web Site
                                                      (logiclinkeg.tech auto-deploy)
```

---

## 8. Known Limitations, Failure Modes & Gotchas

1. **Local Hook Bypass Risk**: Fresh clones do not execute local hooks until `make setup`, `make ci`, or another make target invoking `ensure-hooks` is run.
2. **GHCR Package Visibility & Host Auth**: Private GHCR images require `docker login ghcr.io -u <user> -p <PAT>` with `read:packages` scope on the production host. Setting GHCR package visibility to Public eliminates host authentication requirements.
3. **Govulncheck Standard Library Warnings**: `.githooks/pre-push` prints warning messages for standard library vulnerabilities while blocking strictly on uncalled third-party package vulnerabilities.
4. **Git Checkout Persisted Credentials Override (`sync-mobile-frontend.yml`)**:
   - *Failure Mode*: `actions/checkout@v4` defaults to `persist-credentials: true`, injecting `GITHUB_TOKEN` into global git config (`http.extraheader`). This silently overrides embedded PAT credentials in `git push` URLs, resulting in `Permission denied to github-actions[bot]`.
   - *Resolution*: Always include `persist-credentials: false` in `actions/checkout@v4` steps when performing cross-repo PAT authentication, and format push URLs as `https://x-access-token:${PAT}@github.com/owner/repo.git`.
5. **Workflow Scope Rejection on Subtree Push (`MOBILE_REPO_PAT`)**:
   - *Failure Mode*: Subtree pushing `frontend/` to `quick-delivery-mobile` updates `.github/workflows/build-apk.yml`. GitHub API rejects the push with `refusing to allow a Personal Access Token to create or update workflow ... without workflow scope` if `MOBILE_REPO_PAT` lacks `Workflows: Read and write` scope.
   - *Resolution*: `MOBILE_REPO_PAT` must explicitly include both **`Contents: Read and write`** AND **`Workflows: Read and write`** scopes.
6. **GitHub Release Creation Permission (`build-apk.yml`)**:
   - *Failure Mode*: `gh release create` fails with `HTTP 403: Resource not accessible by integration` if the workflow job lacks write permissions for repository releases.
   - *Resolution*: Include `permissions: contents: write` in the `build-apk` job definition.
