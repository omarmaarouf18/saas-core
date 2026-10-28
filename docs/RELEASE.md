# Production Release & Hotfix Guide (WF-RELEASE)

This document describes how to release changes from `logic-exploitation` to production `main`, verify release gates, perform hotfixes, and handle post-deploy verification.

Production deploys automatically when commits land on `main` (via GitHub Actions `build-and-publish.yml` triggering `saas-core-deploy`). Releases are guarded so that untested or failing commits cannot be pushed to `main`.

---

## 1. Quick Release Summary

The release flow is a single guarded command executed by the repository owner:

```bash
# 1. Inspect current status of logic-exploitation vs origin/main & required gates
make release-status

# 2. (Optional) Run a dry-run to verify all guards pass without pushing
RELEASE_DRY_RUN=1 make release

# 3. Perform the release
make release
# Or, if CI runs are currently running, wait for them to finish:
make release RELEASE_WAIT=1
```

---

## 2. Release Commands

### `make release-status`

Inspects the release readiness of `logic-exploitation` without modifying anything (read-only):
- Resolves the HEAD commit of `logic-exploitation` (short SHA).
- Lists all commits ahead of `origin/main` (one line per commit).
- Queries GitHub Actions for the exact SHA (`gh run list --commit <sha>`) to check status and conclusion of the two required release gates:
  - **CI Gate** (`ci.yml`)
  - **Release Gate E2E** (`release-gate.yml`)
- Reports whether each gate is `completed/success`, `in_progress`, or failed.
- Exits 0 in all cases (unless `gh` CLI is missing), functioning as a non-blocking diagnostic tool.

### `make release`

Executes the guarded release to production `origin/main`. Before any action is taken, `make release` enforces all of the following preconditions:

1. **Current Branch**: Must be on `logic-exploitation`. Refuses if on `main` or any feature branch.
2. **Clean Tree**:
   - No tracked file modifications, staged changes, or uncommitted deletions.
   - Untracked files under tracked project directories (e.g. `services/`, `frontend/`, `scripts/`, `docs/`) cause refusal. Untracked files are only permitted if located in dedicated scratch directories (such as `scratch/` or `tmp/`). All untracked files are listed.
3. **Synchronized with Remote**: Local `logic-exploitation` must match `origin/logic-exploitation`. Run `make push` or `git pull` if diverged.
4. **Fast-Forward Ancestry**: `origin/main` must be an ancestor of `logic-exploitation`. Pushes must be fast-forward only.
5. **Required Gate Success on Exact SHA**:
   - Both **CI Gate** and **Release Gate E2E** must report `status: completed` and `conclusion: success` on the exact HEAD commit.
   - If either gate is queued, in progress, or failed, the release is refused.
   - With `RELEASE_WAIT=1` (or `--wait`), `make release` polls `gh run list --commit` every 30 seconds (up to 30 minutes) until both gates pass.

#### Confirmation and Push Mechanics
Once all preconditions pass:
1. Displays the list of commits ahead of `origin/main` that will be released.
2. Prompts the owner for typed confirmation:
   ```text
   Type 'release' to push <short_sha> to origin/main:
   ```
3. Pushes by exact commit SHA (`git push origin <sha>:main`), guaranteeing that a concurrent push to `logic-exploitation` cannot inadvertently deploy an unverified commit.
4. Verifies remote update (`origin/main == <sha>`).
5. Prints:
   ```text
   RELEASE_VERIFIED: <short_sha>
   Deploy workflow: https://github.com/omarmaarouf18/saas-core/actions/workflows/build-and-publish.yml
   ```
6. Leaves the owner safely on `logic-exploitation` (never checking out `main`).

### `RELEASE_DRY_RUN=1 make release`

Simulates the entire release process:
- Validates all preconditions (branch, clean tree, sync, fast-forward, completed CI & Release Gate runs).
- Displays commits ahead.
- Skips the typed confirmation and remote push.
- Prints `[DRY RUN] All release checks passed. Push would update origin/main to <short_sha>`.

---

## 3. Push Guardrail & Branch Protection

To prevent accidental pushes directly to `main` (such as the incident on 2026-10-26 where an owner remained on local `main`):
1. **`make push` & `.githooks/pre-push` Guard**:
   - Refuses pushes from `main`:
     ```text
     BLOCKED: cannot push directly from 'main'.
     Releases to production must be performed from 'logic-exploitation' via 'make release'.
     Run: git checkout logic-exploitation
     ```
   - Refuses pushes from agent branches (`agent/*`):
     ```text
     BLOCKED: agents never push; the owner merges and pushes from the main worktree
     ```
   - Refuses pushes from any other branch not named `logic-exploitation`.
2. **`make release` State**:
   - After a successful release, the owner remains on `logic-exploitation`.
   - Local `main` does not need to be manually checked out or updated for everyday development.

---

## 4. What to Do When a Gate is Red

If `make release-status` or `make release` reports that a required gate is red (e.g. `failure`):

1. **Do not force or bypass**: Never use `--no-verify` or attempt to bypass branch protection.
2. **Inspect the failure**:
   ```bash
   gh run list --commit <sha>
   gh run view <run-id> --log-failed
   ```
3. **Fix forward on `logic-exploitation`**:
   - If the failure is a lint, test, or contract issue, fix it on a task branch or directly on `logic-exploitation` following standard workflow (`make check && make commit`).
   - Push the fix to `logic-exploitation` via `make push`.
   - Wait for GitHub CI Gate and Release Gate E2E to complete on the new commit SHA.
4. **Re-check status**:
   ```bash
   make release-status
   ```
   Once both gates report `completed/success`, proceed with `make release`.

---

## 5. Hotfix Workflow (`make hotfix`)

When an urgent production incident requires a fix without pulling in unreleased work from `logic-exploitation`:

```bash
make hotfix NAME=<slug>
```

### Hotfix Steps:
1. **Worktree Creation**:
   - Creates a new worktree at `../saas-core-wt/hotfix-<slug>`.
   - Branches directly from `origin/main` into `hotfix/<slug>`.
   - Installs git hooks and disables direct remote pushing in the hotfix worktree (Layer A push guard).
2. **Implement & Test Fix**:
   - Navigate to the hotfix worktree: `cd ../saas-core-wt/hotfix-<slug>`.
   - Make the minimal required fix.
   - Run scoped tests and commit: `make check && make commit FILES="..." MSG="hotfix: <slug> ..."`.
3. **Integrate into `logic-exploitation`**:
   - Production releases always go through `logic-exploitation` to keep history unified and ensure release gates run.
   - In the main worktree:
     ```bash
     cd "/path/to/repo"
     git checkout logic-exploitation
     git merge --no-ff hotfix/<slug>
     make check
     make push
     ```
4. **Release**:
   - Wait for the CI Gate and Release Gate E2E to pass on the merge commit on `logic-exploitation`.
   - Run `make release`.
5. **Clean Up**:
   ```bash
   make worktree-remove TASK=hotfix-<slug>
   # Or remove worktree directory and delete branch hotfix/<slug>
   ```

---

## 6. Post-Deploy Verification

After `make release` succeeds and `build-and-publish.yml` triggers deployment on the production VM:

1. **Monitor Deployment Workflow**:
   - Visit the printed workflow URL:
     `https://github.com/omarmaarouf18/saas-core/actions/workflows/build-and-publish.yml`
   - Confirm images build and the self-hosted deployment runner completes `deploy.yml`.
2. **Health Checks**:
   - Query gateway health:
     ```bash
     docker exec saas-api-gateway curl -sk https://localhost:8080/health
     ```
   - Check reviewer console health (saas-core ADR-0021):
     ```bash
     curl http://127.0.0.1:8090/healthz
     ```
3. **Encrypted Photo Storage Verification (PROD-PHOTO-STORAGE)**:
   - Follow the post-deploy verification procedure detailed in [docs/DEPLOYMENT.md §9.3](DEPLOYMENT.md#step-93-service-photos-prod-photo-storage):
     - Inspect the encrypted storage volume:
       ```bash
       docker volume inspect saas_platform_service_photos_data --format '{{.Name}} {{.Mountpoint}}'
       docker exec saas-user-service sh -c 'id; ls -ldn /app/data/service_photos'
       ```
     - In the application (as a business owner on a paid plan), upload a test photo for a service and verify it displays on the service card.
     - Verify raw file encryption in the volume:
       ```bash
       docker run --rm --network none -v saas_platform_service_photos_data:/p:ro --entrypoint find mongo:7 /p -type f
       ```
     - Recreate the container to verify persistence:
       ```bash
       cd /opt/saas-platform && docker compose up -d --force-recreate user-service
       ```
     - Re-open the service card in the app to confirm the photo remains accessible.
     - Delete the test photo via the application.
