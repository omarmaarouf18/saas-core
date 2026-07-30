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

### Practical Utility of CI
In the project's history, a fabricated commit SHA was pushed on a fresh environment where the local pre-push hook had not been activated. The local push succeeded due to the unconfigured hook, but GitHub Actions CI immediately failed on the `lint-formatting` job's "Verify Markdown Commit SHAs" step, preventing unverified documentation from entering the codebase.

---

## 3. Build-and-Publish Pipeline (`.github/workflows/build-and-publish.yml`)

### Workflow Trigger
`build-and-publish.yml` triggers **only on push to `main`**. Pushes to `logic-exploitation` or other development branches do not trigger image builds or deployment repository syncs.

### Pipeline Structure
The workflow contains two sequential jobs:

1. **`build-and-publish` Job**:
   - Matrix build across all 5 microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`).
   - Logs into GitHub Container Registry (`ghcr.io`) using `GITHUB_TOKEN`.
   - Builds the production multi-stage image (`target: prod`) from root context (`.`).
   - Publishes images to `ghcr.io/omarmaarouf18/saas-core-<service>:${COMMIT_SHA}` and `:latest`.

2. **`update-deployment-repo` Job**:
   - Runs after `build-and-publish` completes.
   - Checks out the private deployment repository `omarmaarouf18/saas-core-deploy` using secret token `DEPLOY_REPO_PAT`.
   - Replaces image tag references in `saas-core-deploy`'s `docker-compose.yml` with the current commit SHA.
   - Commits and pushes the updated `docker-compose.yml` to `saas-core-deploy` `main` branch.

### Two-Repository Architecture Rationale
- **Development Repository (`saas-core`)**: Source code, tests, CI/CD, Go and Flutter toolchains.
- **Deployment Repository (`saas-core-deploy`)**: Image-based `docker-compose.yml`, production `.env.example`, `Caddyfile`, README. Production cloud hosts clone only `saas-core-deploy`. No application source code or build toolchains are stored on or required by the production VPS.

---

## 4. End-to-End Operational Lifecycle

```text
[Developer Work]
       │
       ▼
Push to 'logic-exploitation'  ──► Local Hook (.githooks/pre-push) runs (if make used)
       │                                     │
       ▼                                     ▼
GitHub Actions CI (.github/workflows/ci.yml) validates build/vet/test/lint
       │
       ▼
Pull Request / Merge to 'main'
       │
       ▼
Push to 'main'  ──► Triggers .github/workflows/build-and-publish.yml
                          │
                          ├─► Builds 'prod' Docker images for 5 services
                          ├─► Pushes images to ghcr.io (tagged by SHA & latest)
                          └─► Updates docker-compose.yml in saas-core-deploy
                                        │
                                        ▼
Production VPS Host  ──► cd /opt/saas-platform && git pull
                          docker compose pull && docker compose up -d
```

---

## 5. Known Limitations & Gotchas

1. **Local Hook Bypass Risk**: Fresh clones do not execute local hooks until `make setup`, `make ci`, or another make target invoking `ensure-hooks` is run.
2. **GHCR Package Visibility & Host Auth**: Private GHCR images require `docker login ghcr.io -u <user> -p <PAT>` with `read:packages` scope on the production host. Setting GHCR package visibility to Public eliminates host authentication requirements.
3. **Govulncheck Standard Library Warnings**: `.githooks/pre-push` prints warning messages for standard library vulnerabilities while blocking strictly on uncalled third-party package vulnerabilities.
