# ADR-0015: Strict CD Pre-Flight Validation (Pre-Flight Env Check, Health-Gated Rollback)

- **Status**: Accepted
- **Date**: 2026-08-06
- **Related Commit SHA**: `8f768a08059af871c2885ce143c7520685a84741`
- **Supersedes**: Extends ADR-0012 (§ "Recommended Follow-Up Safeguard")

## Context

On 2026-08-06, three separate production incidents reached running containers before anyone noticed, all caused by the CD pipeline (`deploy.yml`) blindly pulling and recreating containers without validating the deployment environment:

1. **`RESEND_API_KEY` missing from runner `.env`** (related to `f819ce3...`): The persistent backup at `/home/deploybot/.env` lacked `RESEND_API_KEY`, silently reverting the auth-service OTP dispatcher from Resend to MockSMS on every automated deployment.

2. **MongoDB password mismatch** (related to `f819ce3...`): Two independently-maintained `.env` files (`/home/deploybot/.env` and the operator's manual copy) contained different `MONGO_INITDB_ROOT_PASSWORD` values, causing `AuthenticationFailed: SCRAM authentication failed` after container recreation.

3. **`DOCUMENT_SIGNING_SECRET` missing from deployed docker-compose.yml** (related to `f81d978...`): The env var was added to the local reference `infrastructure/docker-compose.yml` but never propagated to `saas-core-deploy/docker-compose.yml` because the `update-deployment-repo` job only `sed`-patches image tags — it never syncs environment variable blocks, service definitions, or volumes.

### Root Cause Analysis

The CI pipeline (`ci.yml`) has hard gates — `gosec`, `govulncheck`, markdown SHA verification, Go version drift guards — that block bad code before it lands on `main`. The CD pipeline (`deploy.yml`) had **zero pre-deployment validation**. It would:

1. `docker compose pull` the new images
2. `docker compose up -d --force-recreate` — destroying the working containers
3. Only then check `/health` on api-gateway (ignoring the other 4 services)
4. If health failed, report failure but leave broken containers running

Additionally, `update-deployment-repo` in `build-and-publish.yml` only used `sed` to patch image tags in `saas-core-deploy/docker-compose.yml`, never syncing environment variable blocks. This meant any new env var added to `infrastructure/docker-compose.yml` (like `DOCUMENT_SIGNING_SECRET`) would never reach production.

## Decision

### 1. `--check-env` Pre-Flight Flag (All 5 Services)

Every Go service's `cmd/main.go` now supports a `--check-env` flag that runs `config.Load()` and exits 0/1 without starting the HTTP server, connecting to databases, or loading TLS certificates.

The CD pipeline runs `docker run --rm --env-file .env <image> --check-env` for each service **before** `docker compose up --force-recreate`. If any service fails validation, the deploy aborts with existing containers left completely untouched.

**Why approach (a) over approach (b)**:
- Two services (`api-gateway`, `auth-service`) already had this flag — proven pattern
- Uses the actual Go config loader as single source of truth — no separate manifest file to drift
- Handles conditional validation natively (e.g. `RESEND_FROM_EMAIL` required only when `RESEND_API_KEY` is set)
- `shared/infra/docgen` does AST-based endpoint extraction, not env var extraction — cannot be reused for approach (b)

**TLS cert path handling**: Config loaders validate that `TLS_CERT_PATH` etc. env vars are non-empty strings; they do NOT call `os.Stat` or `os.ReadFile` on the paths. Actual file reads happen later in `main()` via `tlsutil.LoadServerTLSConfig()`, after the `--check-env` exit point. Pre-flight passes dummy paths (`-e TLS_CERT_PATH=/dummy`) since the check only validates env var presence.

### 2. Full Structural Sync (Not Just Image Tags)

`update-deployment-repo` in `build-and-publish.yml` now copies the entire `infrastructure/deploy/docker-compose.prod.yml` to `saas-core-deploy/docker-compose.yml` (with image tag substitution) and `infrastructure/deploy/deploy.yml` to `saas-core-deploy/.github/workflows/deploy.yml`. This eliminates structural drift entirely — any env var, volume mount, or service definition change in the reference files automatically propagates on the next merge to `main`.

### 3. All-Service Health Verification with Rollback

The health check step now verifies ALL 5 services (not just `api-gateway`) using `docker exec` to reach internal service ports. If any service fails health checks after `force-recreate`, the workflow:
1. Rolls back to the previous `docker-compose.yml` from git history (`git checkout HEAD~1 -- docker-compose.yml`)
2. Runs `docker compose up -d --force-recreate` with the old image tags
3. Reports `ROLLED BACK: <service> failed health check` in the workflow output
4. Exits with failure code for operator review

### 4. `.env` Unification via Symlink

The CD workflow now symlinks the workspace `.env` to `/home/deploybot/.env` instead of copying between them. This eliminates the possibility of editing the wrong file — there is only ONE physical file. This extends ADR-0012's "single source of truth" decision with a mechanical guarantee (symlink) instead of a procedural one (documentation saying "edit this file, not that one").

## Consequences

### Positive
- **Fail-before-touching**: A missing env var now aborts the deploy with old containers still serving traffic
- **Structural sync**: Environment blocks, volumes, and service definitions propagate automatically
- **All-service health**: Every service is verified, not just the edge gateway
- **Automatic rollback**: Failed deploys attempt self-healing before requiring manual intervention
- **Single file**: Symlink eliminates dual-file drift permanently

### Negative / Accepted Tradeoffs
- **Pre-flight adds ~30s per deploy**: Running `docker run --rm --check-env` for 5 services adds startup overhead. Accepted as negligible compared to the cost of a broken production deploy.
- **Rollback is best-effort**: If the previous image tags themselves were broken, rollback won't help. This is an improvement over the current "leave broken containers running" behavior, not a complete solution.
- **`saas-core-deploy` has no CI**: Changes synced to `saas-core-deploy` have no automated gate. YAML validation occurs only when the self-hosted runner executes the workflow. The `update-deployment-repo` job validates compose syntax via `docker compose config --quiet` before pushing.

## Alternatives Considered

- **Approach (b): Static `required-env.json` manifest**: Rejected because conditional validation rules (like `RESEND_FROM_EMAIL` required only when `RESEND_API_KEY` is set) would need to be duplicated outside Go, creating a second source of truth that can drift.
- **Blue-green deployment**: Out of scope for single-VM Docker Compose architecture. Would require container orchestration (Kubernetes, Docker Swarm) not currently in use.
- **GitHub Secrets for `.env`**: Rejected per ADR-0010/0012 — single-VM deployment deliberately avoids storing long-lived production secrets in GitHub.

## Post-Audit Addendum: Strict Rollback Hardening & Post-Rollback Health Verification (2026-08-14)

### Problem Addressed
Audit of `infrastructure/deploy/deploy.yml`'s "Rollback on Health Failure" step revealed a critical silent failure gap:
1. Shell errors in the rollback step did not halt execution (no `set -euo pipefail`), permitting failing `git checkout` or `docker compose up` commands to be ignored while printing a false "ROLLED BACK" success message.
2. The rollback step did not re-verify the health of restored containers. If restored containers failed startup or health checks, the workflow masked the failure.
3. If `git show HEAD~1:docker-compose.yml` failed (e.g. no previous commit in history), the step logged an error but exited with code 0.

### Remediation
1. **Strict Shell Failure (`set -euo pipefail`)**: Added `set -euo pipefail` to the top of the step's run block so any failing command halts step execution immediately.
2. **Explicit Rollback Command Exit Check**: Checked the exit status of `docker compose up -d --force-recreate --remove-orphans`. On non-zero exit, logs `::error::ROLLBACK COMMAND ITSELF FAILED — manual intervention required immediately` and exits 1.
3. **Post-Rollback Health Verification (`verify_service_health`)**: Re-runs the full 5-service mTLS health check retry loop (12 attempts * 5s) against restored containers. Only logs `ROLLED BACK: ... successfully restored and verified healthy` if post-rollback health checks pass.
4. **Post-Rollback Double Failure Alert**: If post-rollback health checks fail, logs `::error::CRITICAL: ROLLBACK FAILED HEALTH CHECK TOO — service is down, manual intervention required NOW` and exits 1.
5. **No Previous Commit Hard Stop**: If `git show HEAD~1:docker-compose.yml` fails, logs `::error::Cannot rollback — no previous commit in git history. Manual intervention required immediately.` and exits 1.
