# SaaS Platform — CI/CD Pipeline & Git Hooks Reference

This document provides a factual, technical breakdown of the verification, quality gate, and production deployment mechanisms operating in this repository.

For the owner/agent process around the gate (worktrees, the CI lock, `make commit`, who pushes), see [docs/WORKFLOW.md](WORKFLOW.md).

---

## 1. Local Pre-Push Hook (`.githooks/pre-push`)

### Activation & `core.hooksPath`
Git by default only executes hooks stored in `.git/hooks/`. Files in `.githooks/` inside the repository tree are **not active on a fresh clone**. 

To activate the hook, the developer must run `make setup` (or any `make` target that includes `ensure-hooks` as a prerequisite) once per clone. This executes:

```bash
git config core.hooksPath .githooks
```

### Local gate vs GitHub CI (WF-03)

- **Locally** (agents and owner), checks run **only for what changed**:
  `make check` (and its alias `make ci`) before every commit, the pre-push
  hook on every push. `make ci-full` / `CI_SCOPE=full` runs everything.
- **GitHub CI** (`.github/workflows/ci.yml`) is the single **full** gate, on
  every push and pull request; `main` is protected so it requires green CI
  (see [docs/WORKFLOW.md](WORKFLOW.md) → "Protect main").

### Execution Order & Checks
When active, `.githooks/pre-push` executes automatically before every `git push`; `make check` / `make ci` / `make ci-full` run the same script without arguments. Before any check it runs, in order:

- **Agent push guard (WF-01, Layer B)**: on a real push (git passes the remote as `$1`) from a linked worktree or an `agent/*` branch, prints `BLOCKED: agents never push; ...` and exits 1.
- **Delete-only push skip (WF-02)**: on a real push where every ref line on stdin has an all-zero local sha (`git push <remote> --delete <ref>`), prints `delete-only push: gate skipped` and exits 0. Runs after the guard, so agents still cannot delete remote refs.
- **Scope (WF-03)**: `scripts/changed-scope.sh` computes the changed paths and maps them to stages (table below), printing `scope: ...` lines with the scope and why. A real push uses the pushed range (`<remote sha>..<local sha>` per ref line; a new remote ref is diffed from its merge-base with `origin/logic-exploitation`); a run without arguments uses committed changes since the merge-base with `logic-exploitation` (`SCOPE_BASE=<ref>` overrides) + staged + unstaged + untracked files. No changed paths: `nothing changed, no checks to run`. Without arguments the gate also records the tree it checks, for the pass stamp.
- **`TEST_DB_SUFFIX`**: exported as `<worktree dir name>-<pid>` unless already set. Characters outside `[A-Za-z0-9_-]` become `_` (Mongo DB names cannot contain spaces: `SaaS prototype` → `SaaS_prototype-<pid>`). Tests use it (`shared/infra/testutil`) to name per-run databases, Redis keys, channels and X-Real-IP addresses.
- **Go toolchain pin (WF-02)**: sources `tools/versions.env` and exports `GOTOOLCHAIN=go$GO_VERSION`. A local Go that differs — including a distro build such as Fedora's `go1.26.9-X:nodwarf5` — makes the `go` command download and use the official toolchain.
- **Tools**: `scripts/install-tools.sh` resolves the pinned gosec, govulncheck and gitleaks (cached; see below).

Every stage prints `[timing] <stage> <seconds>s`, and the run ends with `[timing] total <seconds>s`.

#### Scope table (`scripts/changed-scope.sh`)

The scope is the union over all changed paths; for each path the first matching row wins.

| Changed path | Stages |
|--------------|--------|
| `*.md` anywhere, `docs/**` | markdown SHA check + `shared/infra` tests (changelog and docgen validation live there) |
| `go.work`, `go.work.sum`, any `go.mod`/`go.sum`, `shared/infra/**`, `tools/**`, `.githooks/**`, `scripts/**`, `Makefile`, `.github/**`, `CLAUDE.md`, `.gitleaks.toml` | **FULL** gate |
| `services/<svc>/**` | that module: gofmt, build, vet, test, govulncheck, gosec (+ Go drift guard) + `tests/contracts` + `shared/infra/docgen` tests |
| `tests/contracts/**` | gofmt + `tests/contracts` |
| `frontend/**` | dart format, composition gate, flutter analyze, flutter test + `shared/infra/docgen` tests |
| `infrastructure/staging/**` | compose validation (staging) + markdown SHA check |
| `infrastructure/deploy/**` | compose validation (prod) + markdown SHA check |
| other `infrastructure/**` | compose validation (all stacks) + markdown SHA check |
| anything else | **FULL** gate (fail safe) |

`shared/infra/docgen` tests read `services/*/internal/handlers` (APPLICATION_MAP.md route sync) and `frontend/**` (STATUS.md coverage, widget counts, pubspec vs DESIGN.md, l10n), which is why service and frontend changes run them. gitleaks runs in every scope.

#### Stages

0. **Secret scan (gitleaks, WF-03)** via `scripts/gitleaks-scan.sh`, always with `--redact` and `.gitleaks.toml`: on a push, each pushed range; otherwise merge-base..HEAD plus staged, unstaged and untracked files. Prints `BLOCKED: gitleaks found secrets in <what> (values redacted):` with rule, file, line and commit — never a value. See "Secret scanning" below.
1. **Environment Setup**: Exports default authenticated connection strings for host-level integration testing against local Docker containers (`MONGO_URI` and `REDIS_URI`).
2. **Go Formatting (`gofmt`)**: `gofmt -l .` on a full run, otherwise `gofmt -l` on the scoped module directories (and `tests/contracts`).
3. **Dart Formatting (`dart format`)** (frontend scope): `dart format --output=none --set-exit-if-changed lib/` in `frontend/`.
4. **Markdown Commit SHA Verification** (docs scope):
   - Scans **all `.md` files repo-wide** for 40-character hexadecimal strings and verifies each commit exists (`git cat-file -e "$sha^{commit}"`) and is an ancestor of `HEAD`.
   - *Historical Context*: Scope was originally restricted to `docs/changelog/*.md`. It was widened repo-wide after an incident where a fabricated commit SHA located outside `docs/changelog/` went undetected by the local hook.
5. **Go Version Drift Guard** (`scripts/check-go-version.sh`, also run by CI; whenever a Go module is in scope): reads `GO_VERSION` from `tools/versions.env` (nothing is hard-coded) and asserts that `go.work` and every `services/*`, `shared/infra`, `tools/*`, `tests/*` `go.mod` have `go <major.minor>` and `toolchain go<GO_VERSION>`, that every `go-version:` line in `.github/workflows/ci.yml` (at least one, any quoting) equals `GO_VERSION`, and that every `FROM golang:x.y.z` in `services/*/Dockerfile` equals it.
6. **Per-Module Go Build, Vet, Test, and Security Scans** for each module in scope (all 6 on a full run: `services/api-gateway`, `services/auth-service`, `services/chat-service`, `services/notification-service`, `services/user-service`, `shared/infra`):
   - `go build ./...`, `go vet ./...`
   - tests via `scripts/go-test-module.sh` (WF-03), which splits the module's test packages:
     - **integration** — the test binary links `go.mongodb.org/mongo-driver` or `github.com/redis/go-redis`: `go test -count=1`, always run, under the CI lock;
     - **repo-reader** — `shared/infra/docgen` (walks docs/, frontend/, services/): `go test -count=1`, no lock;
     - **unit** — everything else: plain `go test`, so an unchanged package is served from the Go test cache (`(cached)`), no lock.
     The split is by linkage, so it fails safe: a test cannot reach Mongo/Redis without linking a driver, and a package that links one only for a fake still runs every time. Timing lines: `go-test-unit:<mod>`, `go-test-repo-reader:<mod>`, `go-test-integration:<mod>`.
   - `govulncheck -format json ./...` via `scripts/govulncheck-module.sh` (warns on called stdlib vulnerabilities, blocks on called third-party vulnerabilities; see [Pinned tool versions](#pinned-tool-versions-toolsversionsenv) for the CI difference). A govulncheck error blocks too, printing `BLOCKED: govulncheck error in <mod>` and govulncheck's stderr: an exit code other than 0 or 3, or output with no JSON `config` message. In `-format json` mode govulncheck v1.8.0 exits 0 even when it finds vulnerabilities (3 is text mode only), 1 on errors such as packages that fail to load, and 2 on usage errors. Setting `GOVULNCHECK_BIN` in the environment overrides the pinned binary, with a `NOTE:` line (used to test this path, e.g. `GOVULNCHECK_BIN=/bin/false make ci-full`).
   - `gosec ./...`
   - The binaries come from `scripts/install-tools.sh` (pinned, cached; see below). There is no `@latest` fallback and no skip.
7. **`shared/infra` tests** (docs scope, when `shared/infra` is not already a scoped module) and **`shared/infra/docgen` tests** (service/frontend scope), through `scripts/go-test-module.sh`.
8. **API contract tests** (`tests/contracts`, `go test -v -count=1`).
9. **Compose validation** (`scripts/compose-validate.sh <stacks>`): `docker compose config -q` per stack, with the committed `*.example` env file and the placeholder `CHANGE_ME_compose_validation` for every referenced variable that would otherwise be empty — no secrets needed.
10. **Frontend Flutter Checks** (frontend scope): composition gate (`scripts/frontend_composition_gate.sh`), then `flutter analyze` and `flutter test` (goldens included) inside `frontend/`.

After a pass, a run without arguments writes the **pass stamp** (below), unless the tree changed while it ran (`WARNING: files changed while the gate ran; no stamp written`).

#### CI lock (narrowed in WF-03)

Only `go test -count=1` of integration packages runs under `flock` on `$(git rev-parse --git-common-dir)/ci.lock` (`scripts/ci-lock.sh`), printing `waiting for CI lock: <file> is held by another gate run (make check or git push)` and `[timing] lock-wait <s>s` when it had to wait. `CI_LOCK_HELD=1` means the caller already holds it. Why the lock is kept: [docs/WORKFLOW.md](WORKFLOW.md) → "CI lock".

#### Pass stamps (WF-03)

`scripts/gate-stamp.sh`. A passing run without arguments writes `<git-common-dir>/gate-stamps/<tree>` (`scope=<SCOPE_KEY>`, HEAD, date), where `<tree>` is the tree hash of a copy of the index with every tracked change and every untracked, not ignored file added from disk (so modes staged with `git update-index --chmod` count). `make commit` (`scripts/commit.sh`) builds the exact tree it will commit in a scratch index — before touching the real index — adds the untracked files it leaves out, and refuses unless a stamp exists for that tree whose scope covers the scope of the commit's own paths (`scripts/changed-scope.sh --paths`; a `full` stamp covers everything). Stamps older than 14 days, and beyond the newest 200, are pruned on each write.

#### Secret scanning (gitleaks, WF-03)

- Pinned as `GITLEAKS_VERSION` in `tools/versions.env`, built by `scripts/install-tools.sh` (`go install github.com/zricethezav/gitleaks/v8@<version>`, cached like the other tools).
- `.gitleaks.toml` extends the default rules. Allowlists: the placeholder `CHANGE_ME*`; the noisy `generic-api-key` rule only in `*_test.go`, `*_test.dart` and `testdata/` (every specific rule — AWS, GitHub, private keys, ... — still applies to tests); `frontend/build/`.
- **Ranges only, never all history.** Commit `212cb050` removed real staging credentials (`infrastructure/staging/.env.staging.example`, `tests/e2e/e2e_helpers.go`); the owner verified they are not used in production. They remain in older history, so a full-history scan would fail forever; scanning only new ranges (locally and in CI) never reaches them. No baseline file is committed.
- Values are always redacted (`--redact`); `scripts/gitleaks-scan.sh` prints only rule, file, line and commit.

### Pinned tool versions (`tools/versions.env`)

`tools/versions.env` is the single source of truth for gate tool versions. It is plain `KEY=value` (no quotes, no shell logic):

| Key | Used for |
|-----|----------|
| `GO_VERSION` | `GOTOOLCHAIN` in the hook; the drift guard's expected value for go.work / go.mod / ci.yml / Dockerfiles; part of the tool cache key |
| `GOSEC_VERSION` | gosec version built by `scripts/install-tools.sh` |
| `GOSEC_XTOOLS_VERSION` | `golang.org/x/tools` version gosec is built against (gosec v2.29.0 pins x/tools v0.49.0, which cannot read Go 1.26 export data) |
| `GOVULNCHECK_VERSION` | govulncheck version (`golang.org/x/vuln`) |
| `GITLEAKS_VERSION` | gitleaks version (`github.com/zricethezav/gitleaks/v8`); pin a release at least 14 days old |

Readers: `scripts/install-tools.sh`, `scripts/check-go-version.sh`, `.githooks/pre-push`, and `.github/workflows/ci.yml` (through the two scripts).

**`scripts/install-tools.sh`** sources `tools/versions.env` and builds each tool once into a versioned cache:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/saas-core-tools/govulncheck-<GOVULNCHECK_VERSION>-go<GO_VERSION>/govulncheck
${XDG_CACHE_HOME:-$HOME/.cache}/saas-core-tools/gosec-<GOSEC_VERSION>-xtools-<GOSEC_XTOOLS_VERSION>-go<GO_VERSION>/gosec
${XDG_CACHE_HOME:-$HOME/.cache}/saas-core-tools/gitleaks-<GITLEAKS_VERSION>-go<GO_VERSION>/gitleaks
```

- govulncheck: `go install golang.org/x/vuln/cmd/govulncheck@$GOVULNCHECK_VERSION`.
- gosec: built in a temporary module with `go get github.com/securego/gosec/v2/cmd/gosec@$GOSEC_VERSION golang.org/x/tools@$GOSEC_XTOOLS_VERSION`, then `go build`.
- A cached binary is reused with no network access. Builds land in a temp dir and are moved into the cache only on success. A failed install exits non-zero and the gate blocks; there is no `@latest` fallback.
- gitleaks: `go install` with `-X .../version.Version=<GITLEAKS_VERSION>` so `gitleaks version` prints the pin.
- stdout is `GOSEC_BIN=<path>`, `GOVULNCHECK_BIN=<path>` and `GITLEAKS_BIN=<path>` lines (progress goes to stderr). The hook parses them; CI appends them to `$GITHUB_OUTPUT`.

**How to bump a tool**: edit `tools/versions.env` only. The new version gets a new cache directory, so the next gate run builds it (old directories can be deleted by hand). For `GO_VERSION`, the drift guard then lists every `go.mod`, `ci.yml` `go-version:` line and Dockerfile that still has the old version; update those in the same change (`go.mod`/`go.sum` and `.github/**` are hot paths). Point Renovate regex managers at `tools/versions.env` (not yet configured).

**Open question: govulncheck policy differs between local and CI.** The local hook runs `govulncheck -format json` and filters with `jq`: findings whose trace starts in `stdlib` only print `WARNING: SKIPPED (<GO-ID>) (stdlib vulnerability)`, and only called third-party findings block. CI runs plain `govulncheck ./...`, which fails on any called finding, stdlib included. Since WF-02, both use the same govulncheck binary and the same Go (`GO_VERSION`). Before WF-02, CI used `golang/govulncheck-action@v1`, which installs `govulncheck@latest` and sets up Go `stable` (latest), so CI scanned against a newer standard library than the pinned toolchain. Now a stdlib vulnerability fixed in a newer Go patch fails CI until `GO_VERSION` is bumped, while locally it only warns. The policy was deliberately not changed; the owner should decide whether local should also block on stdlib findings, or CI should also filter them.

### Makefile Wiring & Hook Bypass Limitation
The Makefile defines `ensure-hooks` as follows:

```make
ensure-hooks:
	@if [ "$$(git config --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then \
		git config core.hooksPath .githooks; \
		echo "[MAKE] Configured git core.hooksPath to .githooks"; \
	fi
```

`ensure-hooks` is listed as a prerequisite for `setup`, `docs`, `docs-check`, `check` (and so `ci`), `ci-full`, `commit`, and `push`.

> [!WARNING]
> **Known Limitation**: `ensure-hooks` only executes when one of those specific `make` targets is called. On a fresh repository clone where a developer performs raw `git commit` and `git push` without ever running `make`, `core.hooksPath` remains unconfigured, and the local pre-push hook is bypassed entirely.

---

## 2. GitHub Actions CI (`.github/workflows/ci.yml`)

Unlike local Git hooks, GitHub Actions CI is **authoritative and non-bypassable**, and since WF-03 it is the **only full gate**: the local gate is scoped. It runs automatically on GitHub servers for every push and pull request targeting `main` or `logic-exploitation`.

### Workflow Jobs
`ci.yml` executes five parallel jobs:

1. **`lint-formatting`**:
   - `gofmt` verification.
   - Repo-wide markdown commit SHA verification.
   - Go version consistency drift guard (`bash scripts/check-go-version.sh`, against `tools/versions.env`).
   - Compose validation of all stacks (`bash scripts/compose-validate.sh`, WF-03).
   - Backend-frontend parity check (informational, `continue-on-error`; not run locally).
2. **`build-test`**:
   - Spawns MongoDB (`mongo:7`) and Redis (`redis:7-alpine`) service containers.
   - Matrix execution across 6 Go modules (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`, `shared-infra`).
   - Executes `go mod download`, `go build ./...`, `go vet ./...`, `go test ./... -count=1`, then `bash scripts/install-tools.sh` (same pinned versions as the local hook) and the resulting `govulncheck ./...` and `gosec ./...` binaries.
3. **`secret-scan`** (WF-03): installs the pinned gitleaks with `scripts/install-tools.sh` and runs `scripts/gitleaks-scan.sh range` on `github.event.before..github.sha` for a push (an all-zero or unknown `before` scans the head commit only) or base..head for a pull request.
4. **`contracts-test`** (WF-03): `go test -v -count=1 ./...` in `tests/contracts` — the local gate always ran it; CI did not before WF-03.
5. **`flutter-test`**:
   - Sets up Flutter (pinned `3.44.6`).
   - Runs `dart format --set-exit-if-changed lib/`, the frontend composition gate, `flutter analyze`, and `flutter test` (goldens included).

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
> `workflow_dispatch` is strictly prohibited on `build-and-publish.yml` to prevent un-reviewed dev branch commits from overwriting production deployment tags. During GitHub App token testing, `workflow_dispatch` was temporarily added to `build-and-publish.yml` and dispatched on `logic-exploitation` (Run ID `30684940738`), causing `update-deployment-repo` to push out-of-policy image tags (`375a017`) to `saas-core-deploy:main`. The deployment repo was immediately rolled back to `main` HEAD (`efbe55b` via commit `c0b3f6a` (saas-core-deploy)), and `workflow_dispatch` was permanently removed from `build-and-publish.yml` to enforce push-to-main-only governance.

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

1. **Local Hook Bypass Risk**: Fresh clones do not execute local hooks until `make setup`, `make check`, or another make target invoking `ensure-hooks` is run. Since WF-03 the local gate is scoped anyway; GitHub CI is the full gate.
2. **GHCR Package Visibility & Host Auth**: Private GHCR images require `docker login ghcr.io -u <user> -p <PAT>` with `read:packages` scope on the production host. Setting GHCR package visibility to Public eliminates host authentication requirements.
3. **Govulncheck Standard Library Warnings**: `.githooks/pre-push` prints warning messages for called standard library vulnerabilities while blocking on called third-party package vulnerabilities. CI blocks on both (open question, see [Pinned tool versions](#pinned-tool-versions-toolsversionsenv)).
4. **Git Checkout Persisted Credentials Override (`sync-mobile-frontend.yml`)**:
   - *Failure Mode*: `actions/checkout@v4` defaults to `persist-credentials: true`, injecting `GITHUB_TOKEN` into global git config (`http.extraheader`). This silently overrides embedded PAT credentials in `git push` URLs, resulting in `Permission denied to github-actions[bot]`.
   - *Resolution*: Always include `persist-credentials: false` in `actions/checkout@v4` steps when performing cross-repo PAT authentication, and format push URLs as `https://x-access-token:${PAT}@github.com/owner/repo.git`.
5. **Workflow Scope Rejection on Subtree Push (`MOBILE_REPO_PAT`)**:
   - *Failure Mode*: Subtree pushing `frontend/` to `quick-delivery-mobile` updates `.github/workflows/build-apk.yml`. GitHub API rejects the push with `refusing to allow a Personal Access Token to create or update workflow ... without workflow scope` if `MOBILE_REPO_PAT` lacks `Workflows: Read and write` scope.
   - *Resolution*: `MOBILE_REPO_PAT` must explicitly include both **`Contents: Read and write`** AND **`Workflows: Read and write`** scopes.
6. **GitHub Release Creation Permission (`build-apk.yml`)**:
   - *Failure Mode*: `gh release create` fails with `HTTP 403: Resource not accessible by integration` if the workflow job lacks write permissions for repository releases.
   - *Resolution*: Include `permissions: contents: write` in the `build-apk` job definition.
