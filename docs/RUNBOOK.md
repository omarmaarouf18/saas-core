# SaaS Platform — Release & Server Deployment Runbook

This runbook describes the exact operational sequence to take a change from a feature branch, merge it into main, let CI/CD build and publish it, and get it running on a production/testing VPS. It complements [docs/CI_CD_AND_HOOKS.md](CI_CD_AND_HOOKS.md) (which explains how the pipeline works) by focusing on what to actually do, in order.

---

## 0. Prerequisites (one-time)

* Push access to `omarmaarouf18/saas-core`.
* GitHub App `quick-delivery-automation` secrets (`APP_ID` and `APP_PRIVATE_KEY`) configured across `saas-core` and `quick-delivery-mobile` (used by workflows to generate dynamic short-lived installation tokens).
* GHCR packages set to **Public** (recommended) — see Option A in [docs/DEPLOYMENT.md](DEPLOYMENT.md) §3 — or a `GHCR_READ_TOKEN` ready for the server.
* SSH access to the target VPS (e.g. `quickdelivery-vm`, Ubuntu 22.04).
* Internal mTLS certificates generated with `-copy_extensions copy` flag during `openssl x509 -req` execution to preserve SANs (see [DEPLOYMENT.md §5.3](DEPLOYMENT.md#53-generate-internal-mtls-certificates)).

---

## 1. Prepare work on the feature branch

```bash
git checkout logic-exploitation
git pull origin logic-exploitation
# ... make changes ...
git add -A
git commit -m "feat: <description>"
git push origin logic-exploitation
```

GitHub Actions CI (`.github/workflows/ci.yml`) runs automatically on this push (lint, build, test, govulncheck, gosec, Flutter checks). Do not merge until this workflow is green. Check status at: [https://github.com/omarmaarouf18/saas-core/actions](https://github.com/omarmaarouf18/saas-core/actions)

---

## 2. Merge into main

Open a Pull Request from `logic-exploitation` into `main`, or, if working solo and CI is already green, merge directly:

```bash
git checkout main
git pull origin main
git merge --no-ff logic-exploitation
git push origin main
```

Pushes to `main` trigger `.github/workflows/build-and-publish.yml` automatically. This is the only thing that builds and publishes production images — merging alone does nothing until this workflow runs.

> [!WARNING]
> **Strict Trigger Policy**: `build-and-publish.yml` operates strictly on push-to-main triggers. `workflow_dispatch` must never be added to this workflow for ad-hoc feature branch testing (an incident occurred where dispatching on `logic-exploitation` pushed unreviewed image tags to `saas-core-deploy`, requiring an immediate rollback to `efbe55b` via commit `c0b3f6a`). All feature testing must occur via `ci.yml` and local hooks on `logic-exploitation`.

---

## 3. Let the pipeline build & publish (automatic, no action needed)

`build-and-publish.yml` does two things in order:

1. **`build-and-publish` job**: builds the `prod` target for all 5 services and pushes to `ghcr.io/omarmaarouf18/saas-core-<service>:<sha>` and `:latest`.
2. **`update-deployment-repo` job**: checks out `saas-core-deploy` and rewrites the image tags in its `docker-compose.yml` to the new commit SHA, then commits and pushes that change to `saas-core-deploy`'s `main`.

You can watch progress at [https://github.com/omarmaarouf18/saas-core/actions](https://github.com/omarmaarouf18/saas-core/actions). It's done when both jobs show green and you can see a new commit in [https://github.com/omarmaarouf18/saas-core-deploy/commits/main](https://github.com/omarmaarouf18/saas-core-deploy/commits/main).

---

## 4. Deploy saas-core-deploy onto the server

### First-time setup on a fresh VPS
```bash
ssh <user>@<server-ip>

# System prep, Docker, Caddy, UFW, swap (if RAM is low)
sudo apt-get update && sudo apt-get upgrade -y
# install Docker Engine + compose plugin (see docs/DEPLOYMENT.md §2)

sudo mkdir -p /opt/saas-platform
sudo chown $USER:$USER /opt/saas-platform
git clone https://github.com/omarmaarouf18/saas-core-deploy.git /opt/saas-platform
cd /opt/saas-platform

cp .env.example .env
nano .env   # fill in production secrets — see docs/DEPLOYMENT.md §4.2

mkdir -p certs && cd certs
# generate mTLS certs — see docs/DEPLOYMENT.md §4.3
cd ..

docker compose pull
docker compose up -d
docker compose ps      # confirm mongo & redis report "healthy"
curl -k https://localhost:8080/health   # expect {"status":"ok"}
```

### Every subsequent release (Automated via Self-Hosted Runner CD)
Once `saas-core` merges into `main` and `build-and-publish.yml` updates `saas-core-deploy:main`, deployment to production happens **automatically** via the self-hosted GitHub Actions runner (`deploy.yml`). No manual SSH command is required in the normal path.

#### Manual Fallback (if runner is offline or undergoing maintenance)
```bash
ssh <user>@<server-ip>
cd /opt/saas-platform
git pull origin main
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
```

That's the entire automated loop: branch → CI green → merge to `main` → `build-and-publish` runs → `saas-core-deploy` updates → self-hosted runner `deploy.yml` auto-deploys & verifies health on the production VM.

> **Note:** As of the CD pipeline in `saas-core-deploy/.github/workflows/deploy.yml`,
> the steps above under "Every subsequent release" now run automatically via a
> self-hosted GitHub Actions runner on the production VM — manual SSH is only needed
> for first-time server setup, disaster recovery, or manual troubleshooting. See
> `saas-core-deploy/README.md` for the automated pipeline's exact behavior and the
> volume-naming fix that prevents MongoDB re-initialization mismatches.

## 4.1 Optional: Mobile App Sync & Build (if `frontend/` changed)

If the merge into `main` touched anything under `frontend/`, a separate
pipeline handles the Flutter mobile client independently of the backend
services above:

1. `.github/workflows/sync-mobile-frontend.yml` (in `saas-core`) automatically
   extracts `frontend/` via `git subtree split` and force-pushes it to the
   standalone `omarmaarouf18/quick-delivery-mobile` repo.
2. That push triggers `build-apk.yml` (in `quick-delivery-mobile`), which
   compiles a release APK against `API_BASE_URL` and attaches it as a
   downloadable artifact on the run.

Full architecture, manual re-trigger instructions, and a troubleshooting table
for common failures (missing `MOBILE_REPO_PAT` secret, missing target repo,
permission errors) live in **[frontend/docs/CI_CD.md](../frontend/docs/CI_CD.md)**.
This stage is independent of the server deployment above — a backend release
and a mobile sync/build can succeed or fail on their own.

---

## 5. Rollback

If a release misbehaves, roll back by pinning the previous known-good SHA in `saas-core-deploy/docker-compose.yml` (each service's `image:` tag) and re-running:

```bash
cd /opt/saas-platform
git log --oneline          # find the previous good commit
git checkout <previous-sha> -- docker-compose.yml
docker compose pull
docker compose up -d --remove-orphans
```

Then investigate and fix forward on `logic-exploitation` before merging again.
