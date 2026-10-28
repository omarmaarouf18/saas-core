# SaaS Platform — Production Deployment Guide

This guide provides step-by-step instructions for deploying the Quick Delivery SaaS platform on any generic cloud Virtual Private Server (VPS) or Linux host running Docker and Docker Compose (e.g. Hetzner, DigitalOcean, Linode, AWS EC2).

---

## 1. Architecture Overview (Four-Repo Multi-Artifact Pipeline)

The SaaS platform uses a decoupled four-repository architecture to isolate source code development from production cloud deployment, mobile application distribution, and static marketing website publishing:

1. **Monorepo / Source Repository (`omarmaarouf18/saas-core`)**:
   - Primary monorepo containing all Go microservice source code, Flutter mobile app source code (`frontend/`), database migrations, test suites, and core CI/CD workflows.
   - Merging changes into the `main` branch automatically triggers GitHub Actions to:
     - Build production Docker images for all 5 microservices (`ghcr.io`) and update `saas-core-deploy`.
     - Extract `frontend/` via `git subtree split` and force-push to `quick-delivery-mobile`.

2. **Backend VPS Deployment Repository (`omarmaarouf18/saas-core-deploy`)**:
   - Deploy-only repository containing production `docker-compose.yml`, `.env.example`, `Caddyfile`, and certificate generation tooling.
   - The production cloud host **only pulls from this repository**. No application source code, Go compilers, or Flutter SDKs are present or required on the production VPS host.

3. **Mobile Application Repository (`omarmaarouf18/quick-delivery-mobile`)**:
   - Standalone repository containing the extracted Flutter mobile codebase and APK release workflow (`build-apk.yml`).
   - Receives automatic subtree sync pushes from `saas-core`. Pushing to `main` triggers automated Flutter release APK builds and GitHub Release creation.

4. **Marketing Web Site Repository (`omarmaarouf18/logiclinc`)**:
   - Company website repository deployed on Vercel (`logiclinkeg.tech`).
   - Automatically receives release metadata updates (`app-release.json`) from `quick-delivery-mobile`'s APK release pipeline to present live download links to end users.

---

## 2. Prerequisites & Minimum Specs

### Software Requirements
* **OS**: Linux host (Ubuntu 22.04 LTS, Debian 12, RHEL 9, or similar)
* **Docker Engine**: 24.0+
* **Docker Compose**: v2.20+ (`docker compose` v2 plugin)

### Minimum Hardware Specifications
* **CPU**: 2 vCPUs minimum (4 vCPUs recommended for production traffic)
* **RAM**: 4GB RAM minimum (8GB recommended to comfortably run MongoDB, Redis, and all 5 Go microservices under load)
* **Disk**: 20GB+ SSD storage for Docker images, service logs, and persistent database volumes

---

## 3. Cloud-Specific Provisioning: Microsoft Azure

When deploying to Microsoft Azure Virtual Machines, specific SKU selections, Network Security Group (NSG) configurations, and subscription policy considerations apply.

### 3.1 Recommended Azure VM SKU & Hardware Requirements
* **Production SKU**: `Standard_B2s_v2` (2 vCPU, 8 GB RAM) is the recommended VM size for production deployments.
* **Free-Tier SKU Undersizing**: Azure free-tier or entry-level SKUs (such as `Standard_B2ats_v2` or `Standard_B2pts_v2` with 1 GiB RAM) are severely undersized for this architecture. The full production stack (MongoDB 7.0, Redis 7.2, and all 5 Go microservices) requires at least 4 GB of RAM. Attempting to deploy on 1 GiB RAM instances results in immediate Out-Of-Memory (OOM) process termination, MongoDB engine initialization failures, and container eviction during stack startup.

### 3.2 Azure Network Security Group (NSG) Inbound Rules
Configure inbound security rules on the VM's Network Security Group (NSG) to permit required public and administrative traffic:

| Priority | Name | Port / Protocol | Source | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| 1000 | `Allow-SSH` | `22 / TCP` | Administrator IP | Remote SSH server administration |
| 1010 | `Allow-HTTP` | `80 / TCP` | Any (`*`) | HTTP web traffic & Let's Encrypt ACME challenges |
| 1020 | `Allow-HTTPS` | `443 / TCP` | Any (`*`) | Secure production web and API traffic |

> [!WARNING]
> The API Gateway (port 8080) has no published host port binding. All public ingress routes through Caddy (ports 80/443). Internal microservice ports (`3001`–`3004`), database ports (`27017` for MongoDB, `6379` for Redis), and internal mTLS communication are strictly bound to internal container network interfaces (`127.0.0.1` / `saas-net`) and MUST NOT be exposed in Azure NSG inbound rules.

### 3.3 Azure Subscription Region Policy Restrictions
Constrained Azure subscriptions (such as Azure for Students or restricted enterprise subscriptions) enforce policy definitions restricting resource deployment to specific geographic regions.

> [!NOTE]
> Attempting to create a Resource Group or VM in an unpermitted region triggers a `RequestDisallowedByPolicy` error during deployment.

To discover your subscription's allowed deployment regions:
1. Open the Azure Portal and navigate to **Policy** -> **Assignments**.
2. Select the **Allowed resource deployment locations** policy assignment.
3. Review the **Parameters** tab to view the exact list of permitted Azure region codes (e.g. `eastus`, `westeurope`, `northeurope`).
4. Specify one of these approved locations when creating your Resource Group and Virtual Machine.

---

## 4. GHCR Image Registry Authentication & Package Visibility

By default, Docker images published to GitHub Container Registry (`ghcr.io`) from a private repository inherit private visibility.

### Option A (RECOMMENDED): Make GHCR Packages Public
Because compiled production binaries contain **zero baked-in secrets** (all database URIs, passwords, JWT secrets, and mTLS certificates are supplied dynamically at runtime via `.env` and volume mounts), changing package visibility to **Public** is the simplest and recommended approach for single-operator deployments:

1. **Benefit**: Eliminates token rotation and host-side authentication on the production VPS.
2. **Setup**: After the initial image publishing workflow runs on `main`, navigate to GitHub Package Settings for each package (`https://github.com/users/omarmaarouf18/packages?repo_name=saas-core`), click **Package Settings** -> **Change Visibility** -> set to **Public**.
3. **CLI Alternative**:
   ```bash
   for pkg in saas-core-api-gateway saas-core-auth-service saas-core-chat-service saas-core-notification-service saas-core-user-service; do
     gh api -X PATCH /user/packages/container/$pkg/visibility -f visibility=public
   done
   ```

### Option B: Keep Packages Private (Requires Host Authentication)
If package visibility remains Private, the production server must authenticate to `ghcr.io` before pulling:

1. **Create Host Read PAT**: In GitHub Settings -> Developer Settings -> Personal Access Tokens, generate a token with the `read:packages` scope (e.g. `GHCR_READ_TOKEN`).
   > [!NOTE]
   > `DEPLOY_REPO_PAT` (used by GitHub Actions with `repo` scope to update `saas-core-deploy`) is distinct from `GHCR_READ_TOKEN`. While a single PAT with both `repo` and `read:packages` scopes *can* be reused, using a dedicated read-only PAT on the production host is best security practice.
2. **Authenticate on Host**:
   ```bash
   echo "<GHCR_READ_TOKEN>" | docker login ghcr.io -u <github-username> --password-stdin
   ```

---

## 5. Server Provisioning & Initial Deployment

### Step 5.1: Clone Deployment Repository
On the production VPS host, clone the dedicated deployment repository:
```bash
git clone https://github.com/omarmaarouf18/saas-core-deploy.git /opt/saas-platform
cd /opt/saas-platform
```

### Step 5.2: Configure Environment Variables & Secrets
Copy the template environment file:
```bash
cp .env.example .env
```

Edit `.env` using `nano` or `vim`. Every parameter marked as a production secret **MUST** be set to a strong, unique, randomly-generated string (never reuse local dev values):

```env
# -----------------------------------------------------------------------------
# Database Credentials & URIs (Database-per-Service Isolation)
# -----------------------------------------------------------------------------
MONGO_INITDB_DATABASE=saas_platform
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD=<GENERATE_STRONG_SECRET> # e.g. `openssl rand -hex 24`

# Service-Specific Database Isolation
AUTH_MONGO_DATABASE=auth_db
USER_MONGO_DATABASE=user_db
CHAT_MONGO_DATABASE=chat_db

# MongoDB URI used by microservices over internal Docker network (saas-net)
MONGO_URI=mongodb://root:<MONGO_INITDB_ROOT_PASSWORD>@mongo:27017/?authSource=admin

> [!IMPORTANT]
> **Database-per-Service Isolation & Fresh Deployment Reset**:
> `auth-service` (`auth_db`), `user-service` (`user_db`), and `chat-service` (`chat_db`) use distinct logical databases to enforce microservice data isolation. Any existing deployment running against the old unified `saas_platform` database must be reset (drop `saas_platform` or allow services to boot against fresh empty `auth_db` and `user_db` databases). This destructive reset is safe only because current environment data is test/throwaway data. Any FUTURE database-naming change once real production data exists would require a proper `mongodump`/`mongorestore` data migration script.

REDIS_PASSWORD=<GENERATE_STRONG_SECRET> # e.g. `openssl rand -hex 24`
REDIS_URI=redis://:<REDIS_PASSWORD>@redis:6379

# Optional Redis Sentinel High Availability Configuration (Overrides REDIS_URI if set)
# REDIS_SENTINEL_ADDRS=sentinel1:26379,sentinel2:26379,sentinel3:26379
# REDIS_SENTINEL_MASTER_NAME=mymaster
# REDIS_SENTINEL_PASSWORD=<SENTINEL_AUTH_PASSWORD>

# -----------------------------------------------------------------------------
# Service Ports & Internal Routing
# -----------------------------------------------------------------------------
API_GATEWAY_PORT=8080
AUTH_SERVICE_PORT=3002
USER_SERVICE_PORT=3003
CHAT_SERVICE_PORT=3001
NOTIFICATION_SERVICE_PORT=3004

AUTH_SERVICE_URL=https://auth-service:3002
USER_SERVICE_URL=https://user-service:3003
CHAT_SERVICE_URL=https://chat-service:3001
NOTIFICATION_SERVICE_URL=https://notification-service:3004

# Reviewer console image pin (saas-core ADR-0021). Pin an exact SHA tag
# published by kyc-reviewer-console (NO 'latest' fallback; deploy preflight fails if unset).
KYC_CONSOLE_IMAGE_TAG=<commit-sha>

# Second gate for reviewer console: Caddy basic_auth on kyc.logiclinkeg.tech.
# If either variable is empty, Caddy fails closed with HTTP 503.
# Generate hash via: `caddy hash-password` (see step 8.1.3). Never print the password.
KYC_CONSOLE_BASIC_AUTH_USER=<username>
KYC_CONSOLE_BASIC_AUTH_HASH=<bcrypt-hash>

# -----------------------------------------------------------------------------
# Production Environment & Security Secrets
# -----------------------------------------------------------------------------
APP_ENV=production
LOG_LEVEL=info
ALLOWED_ORIGIN=https://yourdomain.com

# Cryptographic tokens (Generate via `openssl rand -base64 48`)
JWT_SECRET=<GENERATE_STRONG_SECRET>
DOCUMENT_SIGNING_SECRET=<GENERATE_STRONG_SECRET>
GATEWAY_SECRET=<GENERATE_STRONG_SECRET>
INTERNAL_SERVICE_TOKEN=<GENERATE_STRONG_SECRET>

# AES-256 Key for OTP encryption at rest (64 hex chars / 32 bytes via `openssl rand -hex 32`)
OTP_AES_KEY=<GENERATE_64_HEX_CHARS>

# AES-256 Key for KYB/KYE documents, chat attachments and service photos at rest
# (64 hex chars / 32 bytes via `openssl rand -hex 32`). user-service refuses to start in
# production without a valid one (PROD-PHOTO-STORAGE). Never change it while data exists.
DOCUMENT_ENCRYPTION_KEY=<GENERATE_64_HEX_CHARS>

# Optional Third-Party Services
RESEND_API_KEY=re_your_live_key_here
RESEND_FROM_EMAIL=Quick Delivery <noreply@yourdomain.com>
# FCM push: base64 of the Firebase service-account key. Never paste it here by hand:
# install it with the commands in step 9.4.
FCM_SERVICE_ACCOUNT_JSON_B64=
FCM_PROJECT_ID=<firebase project id>
```

### Step 5.3: Generate Internal mTLS Certificates
Inter-service communications inside `saas-net` are secured via mutual TLS (mTLS). Generate fresh production certificates on the target host prior to startup:

```bash
mkdir -p certs
cd certs
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=SaaS-Platform-Prod-Root-CA"

SERVICES=("api-gateway" "auth-service" "chat-service" "notification-service" "user-service" "reviewer-console")
for service in "${SERVICES[@]}"; do
  openssl genrsa -out "${service}.key" 2048
  openssl req -new -key "${service}.key" -out "${service}.csr" -subj "/CN=${service}" -addext "subjectAltName = DNS:${service}, DNS:localhost, IP:127.0.0.1"
  cat <<EOF > "${service}.ext"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:${service}, DNS:localhost, IP:127.0.0.1
EOF
  openssl x509 -req -in "${service}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${service}.crt" -days 3650 -sha256 -extfile "${service}.ext" -copy_extensions copy
  rm -f "${service}.csr" "${service}.ext"
done

openssl req -x509 -newkey rsa:2048 -nodes -keyout api-gateway-external.key -out api-gateway-external.crt -days 3650 -subj "/CN=localhost" -addext "subjectAltName = DNS:localhost, IP:127.0.0.1"
chmod 600 *.key
chmod 644 *.crt
cd ..
```

> [!IMPORTANT]
> **Key file permissions must match the containers' runtime UID (deployed reality)**
> All production containers run as non-root users (`appuser` UID 100, console user UID 1000), while files in
> `certs/` are owned by the host service account (e.g. `deploybot`, UID 1001). A `600` key is therefore
> unreadable inside the container and the service crash-loops with
> `failed to load TLS keypair: ... permission denied` (observed live with `reviewer-console.key`). The
> deployed stack runs all private keys at mode `644` (world-readable but only reachable on the VM's local
> disk). When generating certs per this section on `quickdelivery-vm`, use:
> ```bash
> chmod 644 *.key *.crt
> ```
> Tightening this (e.g. group-based access mapped into the containers via `group_add`) is tracked as hardening follow-up work; until then `644` is required for services to boot.

---

## 6. Running the Production Stack

### Step 6.1: Pull Images
If using Option B (private packages), perform `docker login ghcr.io` first. Then pull pre-built images:
```bash
docker compose pull
```

### Step 6.2: Start Stack in Detached Mode
```bash
docker compose up -d
```

### Step 6.3: Verify Health
Check container status (confirm MongoDB and Redis report `healthy`):
```bash
docker compose ps
```

Test internal gateway health endpoint (gateway has no host port; query inside container):
```bash
docker exec saas-api-gateway curl -sk https://localhost:8080/health
```
Output: `{"status":"ok"}`

Test reviewer console health (saas-core ADR-0021; loopback only):
```bash
curl http://127.0.0.1:8090/healthz
```
Output: `ok`. The console fails fast at startup if `INTERNAL_SERVICE_TOKEN` is unset, and its document/review proxies require a valid reviewer token — an unauthenticated `curl /api/queue` must return 401.

### Step 6.4: Non-Root Container Execution & Docker Native HEALTHCHECK Directives
All 5 production microservice Dockerfiles (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, `user-service`) enforce non-root runtime execution and container-level liveness monitoring:
* **Non-Root Execution (`USER appuser`)**: Production container stages create a dedicated `appgroup` (GID 101) and `appuser` (UID 100). All binary execution runs as `appuser`. Write directories (such as `auth-service`'s `/app/data`) are explicitly created and assigned `appuser:appgroup` ownership during image build.
* **Native Docker HEALTHCHECK Directives**: Each production image incorporates a native `HEALTHCHECK` directive (running every 10s with 5s timeout, 5s start-period, and 3 retries) using `curl -f -s -k` pointing to its respective `/health` endpoint over HTTPS/mTLS with fallback options:
  - `api-gateway`: `HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 CMD curl -f -s -k https://localhost:8080/health ...`
  - `auth-service`: `HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 CMD curl -f -s -k --cert /app/certs/auth-service.crt --key /app/certs/auth-service.key https://localhost:3002/health ...`
  - `chat-service`: `HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 CMD curl -f -s -k --cert /app/certs/chat-service.crt --key /app/certs/chat-service.key https://localhost:3001/health ...`
  - `notification-service`: `HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 CMD curl -f -s -k --cert /app/certs/notification-service.crt --key /app/certs/notification-service.key https://localhost:3004/health ...`
  - `user-service`: `HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 CMD curl -f -s -k --cert /app/certs/user-service.crt --key /app/certs/user-service.key https://localhost:3003/health ...`
* **Unprivileged Port Verification**: All 5 services bind to unprivileged ports above 1024 (`8080`, `3002`, `3001`, `3004`, `3003`), allowing non-root `appuser` to bind network sockets without requiring `CAP_NET_BIND_SERVICE` or root privileges.

---

## 7. Automated Upgrades & Continuous Deployment (Self-Hosted Runner CD)

Production deployments on `omarmaarouf18/saas-core-deploy` are automatically executed via a repository-scoped GitHub Actions self-hosted runner (`[self-hosted, saas-vm]`) running on the production VM under the low-privilege `deploybot` system user.

### 7.1 Automated Deployment Flow
1. When developer changes are pushed to `main` in `saas-core`, `build-and-publish.yml` builds microservice images, pushes them to GHCR, and updates image tag SHAs in `saas-core-deploy`'s `docker-compose.yml`.
2. The push to `saas-core-deploy`'s `main` branch automatically triggers `.github/workflows/deploy.yml` on the self-hosted runner.
3. The runner executes `docker compose config --quiet` to validate syntax, `docker compose pull` to download new images, `docker compose up -d --remove-orphans` to apply updates, and performs a 12-attempt health check against `http://localhost:8080/health`.

### 7.2 Security Boundary & Privilege Model
> [!NOTE]
> **`docker` Group Security Tradeoff**:
> The `deploybot` user has no `sudo` privileges and no interactive SSH shell access. However, `deploybot` is a member of the `docker` group to permit `docker compose` execution. On Linux hosts, access to `/var/run/docker.sock` is effectively root-equivalent. This is a known, explicit architecture tradeoff accepted for this single-VM setup to avoid SSH-from-GitHub security risks or long-lived SSH key storage in GitHub.

### 7.3 Manual Deployment & Emergency Fallback
If the self-hosted runner is offline or undergoing maintenance, operator deployment can be executed manually on the VM host:
```bash
cd /opt/saas-platform
git pull origin main
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
docker exec saas-api-gateway curl -sk https://localhost:8080/health
```

### 7.4 Rollback Procedures (Automated & Manual)

#### Automated Health-Failure Rollback (Continuous Deployment)
When `.github/workflows/deploy.yml` detects a health check failure across any of the 5 microservices during deployment, it triggers the automated `Rollback on Health Failure` step:
1. **Strict Shell Failure Mode (`set -euo pipefail`)**: Halts execution on any sub-command error, preventing silent masking of failed restore steps.
2. **Compose Manifest Checkout**: Restores the previous working `docker-compose.yml` directly from Git history (`git checkout HEAD~1 -- docker-compose.yml`).
3. **Container Recreation**: Forces recreation of running containers with the previous image tags (`docker compose up -d --force-recreate --remove-orphans`).
4. **Post-Rollback Health Verification (`verify_service_health`)**: Re-runs the full 5-service health retry loop against restored containers to verify recovery before exiting. If rollback containers also fail health checks, exits with code 1 and outputs `::error::CRITICAL: ROLLBACK FAILED HEALTH CHECK TOO`.

#### Emergency Manual Rollback Procedure
If automated deployment is interrupted, or if an issue requires manual operator intervention:
1. SSH into the production VM:
   ```bash
   cd /opt/saas-platform
   git revert HEAD -m "revert: rollback failed deployment"
   git push origin main
   ```
2. Or manually checkout the previous working image tags and redeploy:
   ```bash
   git checkout HEAD~1 -- docker-compose.yml
   docker compose up -d --force-recreate --remove-orphans
   docker compose ps
   docker exec saas-api-gateway curl -sk https://localhost:8080/health
   ```

### 7.5 Graceful Shutdown & Signal Handling Across All 5 Microservices
All 5 microservices (`api-gateway`, `auth-service`, `chat-service`, `notification-service`, and `user-service`) implement a standardized, non-disruptive graceful shutdown protocol on receiving `SIGINT` or `SIGTERM` signals (such as during `docker compose stop`, `docker compose down`, or rolling deployments):
- **Signal Handling & Timeout**: Each service intercepts `SIGINT`/`SIGTERM` via `signal.Notify` and logs `[<SERVICE_TAG>] Shutting down...` before executing `http.Server.Shutdown()` with a 10-second context timeout (`context.WithTimeout(10*time.Second)`), allowing in-flight HTTP requests to complete.
- **WebSocket Connection Teardown (`chat-service`)**: `chat-service`'s `Hub.Close()` iterates over all connected WebSocket clients, closing their outbound `Send` channels. This causes each client's `writePump` loop to transmit a clean WebSocket close frame (`1000 CloseNormalClosure`) to active clients before closing socket descriptors, avoiding abrupt TCP resets.
- **SSE Stream Cleanup (`notification-service`)**: `notification-service` cancels `r.Context()` on `http.Server.Shutdown()` and `SSEHub.Close()` closes active `Send` channels across `SSEHub.clients`, prompting active `/notifications/stream` loops to exit cleanly.

---

## 8. Public Reverse Proxy (Caddy), Custom Domain & Firewall

Production HTTPS traffic should be terminated via Caddy, which automatically obtains and renews TLS certificates via Let's Encrypt / ACME HTTP-01 challenges.

### Step 8.1: Reverse Proxy (Caddy) Architecture

Caddy is integrated directly into `docker-compose.yml` as a first-class service (`saas-caddy`, `caddy:2.11.4-alpine`). It runs on the internal `saas-net` Docker network alongside `api-gateway` and `kyc-reviewer-console`, exposing public ports 80 and 443 (and 443/udp for HTTP/3).

#### 1. Deployment `Caddyfile` Configuration
The source of truth for the production reverse proxy is `infrastructure/deploy/Caddyfile` (mirrored to `saas-core-deploy/Caddyfile`), mounted read-only into `saas-caddy` at `/etc/caddy/Caddyfile`:

```caddy
api.logiclinkeg.tech {
    # The admin API (/api/v1/admin/*, today only version-config) is used from
    # the VM only, by exec-ing into the gateway container (see
    # docs/runbooks/OPS-HARDEN-cutover.md). It is not served publicly: the
    # token check stays in the gateway, this is defence in depth.
    @admin path /api/v1/admin /api/v1/admin/*
    respond @admin 404

    reverse_proxy https://api-gateway:8080 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}

kyc.logiclinkeg.tech {
    reverse_proxy kyc-reviewer-console:8090
}
```

> [!IMPORTANT]
> **Internal Service Name Resolution & Port Isolation**:
> - The `reverse_proxy` target is `https://api-gateway:8080` over the internal `saas-net` bridge network. `api-gateway` does NOT publish port 8080 on the host interface.
> - The admin API path (`/api/v1/admin/*`) returns `404` at Caddy for `api.logiclinkeg.tech`. It can only be called locally from the VM via `docker exec saas-api-gateway` using the `X-Admin-Token` header.

> [!NOTE]
> **Trusted Proxy IP Configuration (`TRUSTED_PROXY_IPS`)**:
> The `api-gateway` service uses `TRUSTED_PROXY_IPS` (comma-separated IP addresses or CIDR subnets, defaulting to `127.0.0.1,::1`) to determine which upstream connections are authorized reverse proxies. `api-gateway` only trusts incoming `X-Forwarded-For` headers when the immediate connection IP (`r.RemoteAddr`) matches an entry in `TRUSTED_PROXY_IPS`. For trusted proxies, the original client IP in the `X-Forwarded-For` chain is preserved and forwarded downstream to `auth-service` and other services. Direct untrusted connections have their `X-Forwarded-For` header overwritten with `r.RemoteAddr` to prevent IP spoofing attacks. Ensure `TRUSTED_PROXY_IPS` includes whatever IP or CIDR range the reverse proxy connects from in your deployment topology (e.g. `127.0.0.1,::1,172.16.0.0/12` for Docker bridge or host mode).

#### 2. Automatic Lifecycle Management & Certificate Persistence
Caddy is fully managed by Docker Compose under the `saas-core-deploy` project. Running `docker compose up -d` handles container creation, networking, port binding, and automatic restart (`restart: unless-stopped`). Caddy must not be started manually outside compose.

ACME TLS certificates issued by Let's Encrypt are persisted across container recreations and deployments using the pre-existing external volume:
```yaml
volumes:
  caddy_data:
    external: true
```

#### 3. Reviewer Console Route (saas-core ADR-0021 & Two-Gate Security Model)
The KYC/KYB/KYE reviewer console (`kyc-reviewer-console` service) is kept off the public API surface: it holds `INTERNAL_SERVICE_TOKEN` and exists precisely because reviewer endpoints cannot be reached through the public gateway. It is exposed on its own subdomain (`kyc.logiclinkeg.tech`) so remote reviewers can reach it over HTTPS.

To protect the console against automated scanning and unauthorized access, access is gated by **two independent layers**:
1. **Edge Gate (Caddy `basic_auth` & Edge Security Headers)**: Caddy terminates TLS on `kyc.logiclinkeg.tech` and enforces HTTP Basic Authentication before any request reaches the console container. Caddy also injects edge security headers (`Strict-Transport-Security`, `Content-Security-Policy: frame-ancestors 'none'`, and `X-Frame-Options: DENY`). If either `KYC_CONSOLE_BASIC_AUTH_HASH` or `KYC_CONSOLE_BASIC_AUTH_USER` is empty or unset, Caddy fails closed with `HTTP 503 Service Unavailable`.
2. **Application Gate (`X-Reviewer-Token`)**: The console UI and its API proxies require a valid cryptographic reviewer token verified upstream by `auth-service` via `/auth/reviewer/verify`.

##### Owner Steps: Reviewer Console Edge Gate Setup
Follow these steps on the production VM to configure or rotate the console edge gate:

1. **Generate Bcrypt Password Hash** (never write or echo the plaintext password):
   Run Caddy's password hasher. The interactive prompt reads the password directly without echoing it to terminal or shell history:
   ```bash
   docker run --rm -it caddy:2.11.4-alpine caddy hash-password
   ```
   Copy the output bcrypt string (e.g. `$2a$14$...`).

2. **Configure Environment in `/home/deploybot/.env`**:
   Set the operator username, bcrypt hash, and the pinned console image tag:
   ```bash
   sudo nano /home/deploybot/.env
   # Ensure the following keys are populated:
   # KYC_CONSOLE_IMAGE_TAG=<pinned-sha-from-kyc-reviewer-console-ci>
   # KYC_CONSOLE_BASIC_AUTH_USER=<operator-username>
   # KYC_CONSOLE_BASIC_AUTH_HASH='<bcrypt-hash-from-step-1>'
   ```
   > [!IMPORTANT]
   > Do NOT use `latest` for `KYC_CONSOLE_IMAGE_TAG`. Docker Compose configuration strictly requires `KYC_CONSOLE_IMAGE_TAG` to be set; deploy preflight fails if unset.

3. **Apply Changes and Redeploy**:
   ```bash
   cd /opt/saas-platform
   docker compose --env-file /home/deploybot/.env up -d caddy kyc-reviewer-console
   ```

4. **Verify Dual Gates**:
   - Without credentials: `curl -i https://kyc.logiclinkeg.tech/` returns `401 Unauthorized` with `Www-Authenticate: Basic realm="restricted"`.
   - Edge security headers present: verify `Strict-Transport-Security`, `Content-Security-Policy: frame-ancestors 'none'`, `X-Frame-Options: DENY`.
   - With valid HTTP basic auth: browser opens the Reviewer Console login screen prompting for `X-Reviewer-Token`.
   - If `KYC_CONSOLE_BASIC_AUTH_HASH` is blanked or unset: Caddy answers `503 Service Unavailable` immediately (fail-closed).

DNS: create an additional `A` record for the `kyc` subdomain pointing at the same VM public IP, using the same registrar guidance as Step 8.2 (delegated-nameserver warning applies).

---

### Step 8.2: Custom Domain & DNS Configuration

To route public API traffic to Caddy and enable automated Let's Encrypt TLS certificate issuance:

1. **Create DNS A Record**:
   In your domain registrar or DNS management dashboard, create an `A` record mapping your API subdomain (e.g., `api.yourdomain.com`) to the public IP address of your Azure VM:
   - **Type**: `A`
   - **Name**: `api` (or fully qualified `api.yourdomain.com`)
   - **Value**: `<AZURE_VM_PUBLIC_IP>` (e.g., `20.12.34.56`)
   - **TTL**: `300` (or Automatic)

> [!WARNING]
> **Delegated Nameservers (e.g. Vercel, Cloudflare, Netlify)**:
> If your root domain's DNS is delegated to an external hosting platform like Vercel (for example, if an unrelated frontend web project is hosted on `yourdomain.com`), new DNS records for subdomains (e.g. `api.yourdomain.com`) MUST be created from that platform's actual **"DNS Records"** management panel (`Domains` -> `dns.yourdomain.com` -> `Add Record`).
> Do NOT use the platform's "Domain Assignment" / "Connect to an environment" panel for API subdomains — that panel is intended exclusively for attaching web deployments hosted directly on that platform and will not create standard external DNS `A` records.

> [!NOTE]
> **DNS Propagation Verification**:
> Global DNS propagation for a newly created or updated `A` record can take anywhere from a few minutes up to 1–2 hours, even with a low TTL. Before troubleshooting Caddy or ACME certificate issuance, verify that public resolvers return your VM's public IP address:
> ```bash
> # Query Google Public DNS
> nslookup api.yourdomain.com 8.8.8.8
> 
> # Query Cloudflare DNS
> nslookup api.yourdomain.com 1.1.1.1
> ```
> Alternatively, check global propagation across worldwide edge resolvers using [dnschecker.org](https://dnschecker.org). Do not attempt to debug Let's Encrypt TLS challenges until global DNS resolution is verified.

---

### Step 8.3: Firewall Rules (UFW & Azure NSG)
Ensure host-level firewall rules permit HTTP, HTTPS, and SSH traffic:
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

> [!WARNING]
> Database ports (`27017`, `6379`) and internal microservice ports (`3001`–`3004`, `8080`) are bound to internal networks (`127.0.0.1` / `saas-net`) and MUST NOT be opened in UFW or Azure NSG rules.

---

## 9. Logging & Database Backups

### Step 9.1: Live Logs
```bash
docker compose logs -f
docker compose logs -f auth-service
```

### Step 9.2: Manual MongoDB Backup (`mongodump`)
```bash
docker compose exec mongo mongodump \
  -u root -p "<MONGO_INITDB_ROOT_PASSWORD>" \
  --authenticationDatabase admin \
  --archive=/data/db/backup_$(date +%F).archive --gzip

docker cp saas-mongo:/data/db/backup_$(date +%F).archive /opt/backups/
```

### Step 9.3: Service photos (PROD-PHOTO-STORAGE)

Owner service photos are stored AES-256-GCM encrypted by `user-service` in the
named volume `saas_platform_service_photos_data`, mounted at
`/app/data/service_photos` (`STORAGE_BASE_DIR`). The key is the same
`DOCUMENT_ENCRYPTION_KEY` that auth-service (documents) and chat-service
(attachments) use. With an empty or invalid key `user-service` fails its
`--check-env` pre-flight and refuses to start in production; outside
production it starts and photo upload/read answer
`503 photo_storage_unavailable`. A photo is never stored unencrypted.

**Before the release** (on the VM, `/home/deploybot/.env`):

```bash
# Prints "64 hex" for a usable key; never prints the key itself.
sudo awk 'index($0,"DOCUMENT_ENCRYPTION_KEY=")==1 { v=substr($0,25); gsub(/^["\x27]|["\x27]$/,"",v); print length(v), (v ~ /^[0-9A-Fa-f]+$/ ? "hex" : "NOT hex") }' /home/deploybot/.env
sudo grep -c '^APP_ENV=production$' /home/deploybot/.env   # expect 1
```

If the first line is not `64 hex`, stop: do **not** generate a new key, the
existing documents and attachments are encrypted with the current one. Find
the right value in your password manager copy of `.env` (see
[runbooks/BACKUP-RESTORE.md](runbooks/BACKUP-RESTORE.md)). Nothing else is
needed in `.env`: the compose file sets `STORAGE_BASE_DIR` itself.

Optional pre-flight with the new image (the CD pipeline runs the same check):

```bash
docker run --rm --env-file /home/deploybot/.env -e TLS_CERT_PATH=/x -e TLS_KEY_PATH=/x -e TLS_CA_PATH=/x \
  ghcr.io/omarmaarouf18/saas-core-user-service:<new tag> --check-env
# expect: PREFLIGHT OK: user-service config validated (and no PREFLIGHT WARNING line)
```

**After the deploy**, check the volume, then that a photo survives a redeploy:

```bash
docker volume inspect saas_platform_service_photos_data --format '{{.Name}} {{.Mountpoint}}'
docker exec saas-user-service sh -c 'id; ls -ldn /app/data/service_photos'   # uid 100 owns the dir
```

1. In the app, as an owner on a paid plan, upload a test photo for a service
   and open it (the service card shows it).
2. List the stored objects (encrypted bytes, nothing readable):
   `docker run --rm --network none -v saas_platform_service_photos_data:/p:ro --entrypoint find mongo:7 /p -type f`
3. Recreate the container: `cd /opt/saas-platform && docker compose up -d --force-recreate user-service`.
4. Open the service again: the photo is still there, and step 2 lists the same file.
5. Remove the test photo in the app (its object is deleted from the volume).

**Backup and restore**: the daily backup includes this volume; deploy the
release before updating the backup scripts on the VM. Restore steps:
[runbooks/BACKUP-RESTORE.md](runbooks/BACKUP-RESTORE.md), "Service photos
volume" and "Restore into production", step 5.

### Step 9.4: FCM push credentials

`notification-service` sends push notifications with a Firebase
service-account key, passed as `FCM_SERVICE_ACCOUNT_JSON_B64` (the key file,
base64-encoded on one line) plus `FCM_PROJECT_ID` (optional: it defaults to
the key's `project_id`). The compose file passes both from
`/home/deploybot/.env`. A missing or broken key never stops the service: push
is disabled and the reason is logged. The older raw-JSON variables
`FCM_SERVICE_ACCOUNT_JSON` / `FCM_CREDENTIALS_JSON` are still read when set in
the container, but the compose file does not pass them.

At startup (and in the CD pre-flight `--check-env`) the service mints one
OAuth2 access token from the key (it sends no push) and logs the result. Every
send then carries a cached access token (`Authorization: Bearer`, refreshed
5 minutes before it expires and once on a `401`). Android pushes use the
notification channel `qd_default`, which the app creates.

1. In the Firebase console: Project settings → Service accounts → Generate new
   private key. It downloads `<project>-firebase-adminsdk-<id>.json`. Keep the
   original in your password manager, not in a synced folder.
2. Copy it to the VM (`<you>@<vm>` is your SSH login):

   ```bash
   scp ~/Downloads/<project>-firebase-adminsdk-<id>.json <you>@<vm>:/tmp/fcm.json
   ```

3. On the VM, append it to `.env` without it ever reaching the screen, the
   shell history or a command line (`ps`), then destroy the copy:

   ```bash
   chmod 600 /tmp/fcm.json
   sudo grep -c '^FCM_SERVICE_ACCOUNT_JSON_B64=' /home/deploybot/.env   # must print 0; else delete that line first (sudoedit)
   { printf 'FCM_SERVICE_ACCOUNT_JSON_B64='; base64 -w0 /tmp/fcm.json; echo; } | sudo tee -a /home/deploybot/.env >/dev/null
   echo 'FCM_PROJECT_ID=<firebase project id>' | sudo tee -a /home/deploybot/.env >/dev/null
   shred -u /tmp/fcm.json
   sudo stat -c '%U %a' /home/deploybot/.env   # still: deploybot 600
   sudo awk -F= '$1=="FCM_SERVICE_ACCOUNT_JSON_B64" { print "key length:", length($0) - length($1) - 1 }' /home/deploybot/.env
   ```

   The last line prints only a length (a few thousand characters), never the
   key. Delete the downloaded file on your machine too once your password
   manager holds the original.
4. Redeploy (re-run the deploy workflow, or step 7.3 by hand). The CD
   pre-flight (`--check-env`) and the container log both print the push status.
5. Verify from the log line, never from the key:

   ```bash
   docker logs saas-notification-service 2>&1 | grep -E 'push (enabled|disabled|key loaded)' | tail -n 2
   ```

   Expected, in this order:

   ```text
   [CONFIG] push key loaded (project <firebase project id>)
   [FCM] push enabled (project <firebase project id>, token ok)
   ```

   `token ok` means Google accepted the key and issued an access token. Other
   lines and what to do:
   - `[CONFIG] push disabled: <reason>`: the key itself (`not valid base64`,
     `not valid JSON`, `not a service-account key`, `no FCM_PROJECT_ID and no
     project_id`, or no key at all): fix `.env` and redeploy.
   - `[FCM] push disabled: token mint failed: token endpoint returned HTTP 400:
     invalid_grant ...`: Google rejected the key (deleted or disabled in the
     Firebase/Google Cloud console, or the VM clock is far off: check
     `timedatectl`). Generate a new key (steps 1 to 4).
   - `[FCM] push enabled (project X, token mint failed: ...; retried on every
     send)`: a network or Google-side error at startup. Push stays on and every
     send retries the token; if it persists, check outbound HTTPS from the VM to
     `oauth2.googleapis.com` and `fcm.googleapis.com`.
6. Send a test push to your own account. Sign in to the app (2.0.0 or later,
   built with Firebase) on a phone and allow notifications, so its device token
   is registered; take your user ID and tenant ID from the admin tools or the
   database. Then, on the VM (`<user id>` / `<tenant id>` are yours; the internal
   token is read from `.env` straight into curl, never onto the screen or a
   command line):

   ```bash
   cd /opt/saas-platform
   NOTIF_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' saas-notification-service)
   NOTIF_PORT=$(sudo awk -F= '$1=="NOTIFICATION_SERVICE_PORT" { print $2 }' /home/deploybot/.env)
   curl -sS --cacert certs/ca.crt --cert certs/user-service.crt --key certs/user-service.key \
     --resolve "notification-service:${NOTIF_PORT}:${NOTIF_IP}" \
     -H @<(sudo awk -F= '$1=="INTERNAL_SERVICE_TOKEN" { print "X-Internal-Token: " substr($0, length($1) + 2) }' /home/deploybot/.env) \
     -H 'Content-Type: application/json' \
     -d '{"type":"popup","tenant_id":"<tenant id>","user_id":"<user id>","title":"Test push","body":"FCM check"}' \
     "https://notification-service:${NOTIF_PORT}/notifications/send"
   docker logs --since 2m saas-notification-service 2>&1 | grep '\[FCM-PUSH\]'
   ```

   (If `INTERNAL_SERVICE_TOKEN` is quoted in `.env`, the quotes end up in the
   header and the call answers `401`: remove them from the header with
   `gsub(/^["\x27]|["\x27]$/, "", v)` as in step 9.3, or unquote the value.)

   The curl answers `200`. The log shows one of:
   - `Push delivered successfully to token <first chars>...`: FCM accepted it;
     the phone shows "Test push".
   - `user <id> has no registered device tokens`: the app never registered a
     token for that user (Firebase not set up in that build, notifications
     denied, or a different account).
   - `Stale/unregistered token detected ...`: FCM no longer knows that token; it
     is removed from the user. Reopen the app to register a new one.
   - `FCM request failed with status 403 PERMISSION_DENIED` (or
     `SENDER_ID_MISMATCH`): the key belongs to a different Firebase project
     than the app's `google-services.json`.
   - `access token unavailable ... token endpoint returned HTTP 400`: see the
     `invalid_grant` line above.

---

## 10. Troubleshooting

### 10.1 `Conflict. The container name "/x" is already in use`
* **Symptom**: `docker compose up -d` fails with `Error response from daemon: Conflict. The container name "/saas-auth-service" is already in use by container "...".`
* **Cause**: Stale or stopped containers from a prior failed deployment attempt or manual container execution still exist with identical container names.
* **Resolution**: Stop and remove the existing conflicting containers before running Compose:
  ```bash
  docker stop <container_name> && docker rm <container_name>
  # Or remove all stopped stack containers cleanly:
  docker compose down
  docker compose up -d
  ```

### 10.2 `no port specified: :<empty>` on `docker compose ps` / `logs`
* **Symptom**: Running `docker compose ps` or `docker compose logs` outputs error `no port specified: :<empty>` or fails to resolve port environment variables.
* **Cause**: Forgetting to pass `--env-file .env` (or having an environment file named something other than the default `.env`) on subsequent `docker compose` subcommands. Compose attempts to substitute environment variables declared in `docker-compose.yml` (such as `${API_GATEWAY_PORT}`) with empty strings when `.env` is omitted.
* **Resolution**: Always supply `--env-file .env` on every `docker compose` invocation (not just during `up`):
  ```bash
  docker compose --env-file .env ps
  docker compose --env-file .env logs -f api-gateway
  docker compose --env-file .env down
  ```

### 10.3 Transient Connection Resets or Startup Delays During Service Initialization
* **Symptom**: Executing `curl -k https://localhost:8080/health` immediately after `docker compose up -d` returns `curl: (35) OpenSSL SSL_connect: Connection reset by peer` or `Connection refused`.
* **Cause**: Production containers run static precompiled Go binaries (`/bin/service` compiled during multi-stage Docker builds from `golang:1.26-alpine`). Initial connection resets or startup delays occur because microservices wait for database container healthchecks (`saas-mongo` and `saas-redis`) or internal mTLS certificate initialization and TCP listener setup, not runtime binary compilation (which is used only in local development mode via `air`).
* **Resolution**: Inspect container startup logs to confirm database connection establishment and TLS listener readiness:
  ```bash
  docker compose logs -f api-gateway
  ```
  Look for log lines indicating successful MongoDB/Redis initialization and server startup (`Server listening on port 8080`).

### 10.4 MongoDB Authentication Failure (`storedKey mismatch`) After Password Change
* **Symptom**: Executing `docker compose up -d` fails with `dependency failed to start: container saas-mongo is unhealthy`, and container logs (`docker compose logs mongo`) display error `AuthenticationFailed: SCRAM authentication failed, storedKey mismatch`.
* **Cause**: MongoDB processes environment variables `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` exclusively during initial database initialization when the volume is created. Modifying `MONGO_INITDB_ROOT_PASSWORD` in `.env` after the persistent volume (`mongo_data`) already exists does not update the internal credentials stored inside MongoDB's `admin` database.
* **Resolution**: Select one of the following remediation options depending on whether existing data must be preserved:
  * **Option A: Re-initialize Volume (Non-Production / Dev Environments Only)**:
    > [!WARNING]
    > This operation permanently deletes all persistent database records stored in `mongo_data`.
    ```bash
    docker compose down -v
    docker compose up -d
    ```
  * **Option B: In-Place Password Update via `mongosh` (Recommended for Existing Data)**:
    1. Temporarily revert `MONGO_INITDB_ROOT_PASSWORD` in `.env` to the old working password.
    2. Start the MongoDB container:
       ```bash
       docker compose up -d mongo
       ```
    3. Update the root password directly inside MongoDB using `mongosh`:
       ```bash
       docker compose exec mongo mongosh -u root -p "<OLD_PASSWORD>" --authenticationDatabase admin --eval 'db.getSiblingDB("admin").changeUserPassword("root", "<NEW_PASSWORD>")'
       ```
    4. Update `MONGO_INITDB_ROOT_PASSWORD` (and dependent `MONGO_URI` strings) in `.env` to `<NEW_PASSWORD>` and restart the application stack:
       ```bash
       docker compose up -d
       ```

### 10.5 Missing or Orphaned `saas-caddy` Container Causing Public Domain Outage
* **Symptom**: Requests to the public domain (e.g. `curl https://api.logiclinkeg.tech/`) fail with `Could not connect to server` or `Connection refused`, even though internal health checks within the API Gateway (`docker exec saas-api-gateway curl -sk https://localhost:8080/health`) succeed. `docker compose ps` shows no `saas-caddy` container running or running without published port bindings (`80`/`443`).
* **Cause**: Caddy was historically executed outside Docker Compose via an un-orchestrated `docker run` command (see ADR-0011). Manual containers are orphaned by `docker compose down` and are not automatically managed or recreated by Docker Compose commands if removed or stopped.
* **Resolution**: Caddy is now fully integrated as a first-class service (`caddy`) in `docker-compose.yml` (per ADR-0011). Re-align the stack by executing:
  ```bash
  cd /opt/saas-platform
  docker compose ps caddy
  docker compose up -d --remove-orphans
  ```
  Confirm `saas-caddy` status shows `Up` with published ports `0.0.0.0:80->80/tcp` and `0.0.0.0:443->443/tcp`.

### 10.6 Legacy Common Name mTLS Certificate Error (`x509: certificate relies on legacy Common Name field`)
* **Symptom**: `[PROXY ERROR] POST /auth/signup → https://auth-service:3002: tls: failed to verify certificate: x509: certificate relies on legacy Common Name field, use SANs instead` followed by `502 Bad Gateway` on any api-gateway route that proxies to an internal service (auth-service, user-service, chat-service, notification-service).
* **Cause**: The mTLS certificate generation commands in Section 4.3 ("Generate Internal mTLS Certificates") sign each service's CSR using `openssl x509 -req ... -extfile "${service}.ext"` without the `-copy_extensions copy` flag. Depending on the OpenSSL version on the host, this can silently produce a signed certificate whose `subjectAltName` (SAN) extension does not make it into the final `.crt`, even though the CSR and `.ext` file both correctly specify it. Go's TLS client (used by all 5 microservices) has rejected certificates lacking a SAN — falling back to the legacy Common Name field — since Go 1.15, so any internal service-to-service call fails at the TLS handshake stage while simple health-check endpoints (`GET /`, `GET /health`) that don't proxy to another service continue to return 200, making the certificate defect easy to miss during initial smoke testing.
* **Resolution**: Regenerate all internal certificates with `-copy_extensions copy` added to the signing command:
  ```bash
  openssl x509 -req -in "${service}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${service}.crt" -days 3650 -sha256 -extfile "${service}.ext" -copy_extensions copy
  ```
  Then restart all containers so they pick up the regenerated certificate files from disk (they only read the mounted `.crt`/`.key` files at process startup, not on change):
  ```bash
  docker compose down && docker compose up -d
  ```

* **Verification**: Confirm the SAN extension is actually present in the signed certificate before restarting containers:
  ```bash
  openssl x509 -in certs/auth-service.crt -noout -text | grep -A 2 "Subject Alternative Name"
  ```
  Expected output: `DNS:auth-service, DNS:localhost, IP Address:127.0.0.1`. If this is empty, the certificate is defective regardless of what the CSR/`.ext` file specify.

> [!WARNING]
> Because `GET /` and `GET /health` do not exercise the inter-service mTLS path, a "successful" health check does NOT confirm certificates are valid. Always test at least one real cross-service route (e.g. `POST /api/v1/auth/signup`) before considering a deployment verified.

### 10.7 OTP Dispatcher Silently Reverts to MockSMS or MongoDB SCRAM Auth Fails After CD Run
* **Symptom**: The `auth-service` OTP delivery mechanism silently reverts from `Resend` (`[AUTH] OTP dispatcher: Resend`) back to `MockSMS` (or MongoDB reports `AuthenticationFailed: SCRAM authentication failed, storedKey mismatch`) whenever the automated CD pipeline runs on a push to `main`, even though an operator manually updated `.env` and restarted services via SSH earlier.
* **Cause**: Dual `.env` files on the VM host. An operator manually updated `.env` in `~/azureuser/saas-core-deploy/.env` or `/opt/saas-platform/.env`, but the self-hosted GitHub Actions runner (`saas-vm-runner`) executes under system user `deploybot` at `/home/deploybot/actions-runner/_work/saas-core-deploy/saas-core-deploy/` and restores its environment from `/home/deploybot/.env` (a cross-run persistent backup). Every automated CD execution restores `/home/deploybot/.env` into the runner workspace and runs `docker compose up -d --force-recreate`, silently overwriting any manual container overrides with `/home/deploybot/.env`'s contents (see ADR-0012).
* **Resolution**: Update `/home/deploybot/.env` directly (the canonical source of truth for production environment variables), add the missing keys (`RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `ALLOWED_ORIGIN`), delete any stale `.env` file in the runner workspace directory, and re-trigger the CD pipeline via `workflow_dispatch` or `git push`.
* **Verification**: Inspect container logs post-deployment to verify Resend activation:
  ```bash
  docker compose logs saas-auth-service --tail 15 | grep "OTP dispatcher"
  ```
  Expected output: `[AUTH] OTP dispatcher: Resend (Resend API active)`.

---

## 11. Database Migrations & Data Model Corrections

### 11.1 ADR-0017 Zero-Commission Data Model Migration (`platform_config`)

When deploying the zero-commission subscription revenue model (ADR-0017), existing production data in the `platform_config` collection must be updated to set `platform_fee_percentage` to `0.0`. `user-service` owns `platform_config` and connects to database `${USER_MONGO_DATABASE:-user_db}` (per Finding #8 database-per-service separation).

Execute the following `mongosh` script against the production MongoDB container:

```bash
docker compose exec mongo mongosh -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "${USER_MONGO_DATABASE:-user_db}" --eval '
  db.platform_config.updateOne(
    { _id: "global" },
    { $set: { platform_fee_percentage: 0.0, updated_at: new Date() } },
    { upsert: true }
  );
'
```

Verify migration result:
```bash
docker compose exec mongo mongosh -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "${USER_MONGO_DATABASE:-user_db}" --eval '
  db.platform_config.find({ _id: "global" });
'
```
Expected output: `{ _id: "global", platform_fee_percentage: 0, platform_wallet_id: "platform-central" }`.

### 11.2 KYB/KYE Document Encryption at Rest Migration (`encrypt-documents`)

When upgrading host storage to application-level AES-256-GCM document encryption at rest, any existing unencrypted plaintext identity documents stored on local disk under `STORAGE_BASE_DIR` (e.g. `./data/documents`) must be encrypted in place using `DOCUMENT_ENCRYPTION_KEY`.

Execute the one-time migration tool:

```bash
DOCUMENT_ENCRYPTION_KEY="$DOCUMENT_ENCRYPTION_KEY" go run ./services/auth-service/cmd/encrypt-documents/main.go -dir ./services/auth-service/data/documents
```

The migration command checks each file's AEAD tag header prior to encryption; files that are already encrypted are skipped, making the migration safe and idempotent.

### 11.3 App Version Management & Minimum Version Enforcement (In-Memory Version Store)

To manage supported mobile client versions and enforce minimum required version gating at the API Gateway (ADR-0018), query or update version enforcement configuration via the admin endpoint.

> [!NOTE]
> Per OPS-13 / cutover configuration, the version configuration store in `api-gateway` is currently in-memory (`version.NewStore(nil, "")`).
> Public edge requests to `/api/v1/admin/*` return HTTP 404 at Caddy. The admin API is accessible only from the VM by exec-ing into `saas-api-gateway` using the dedicated `ADMIN_API_TOKEN` (`X-Admin-Token`).

```bash
# Fetch current app version configuration (from the VM host)
docker exec saas-api-gateway sh -c 'curl -sk -H "X-Admin-Token: $ADMIN_API_TOKEN" https://localhost:8080/api/v1/admin/version-config'

# Update minimum supported version and enable enforcement
docker exec -i saas-api-gateway sh -c 'curl -sk -X PUT -H "Content-Type: application/json" -H "X-Admin-Token: $ADMIN_API_TOKEN" --data-binary @- https://localhost:8080/api/v1/admin/version-config' <<'EOF'
{
  "latest_version": "1.2.0",
  "minimum_supported_version": "1.1.0",
  "enforce_minimum_version": true,
  "download_url": "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk"
}
EOF
```




