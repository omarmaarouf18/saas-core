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
| 1030 | `Allow-API-Gateway-Direct` | `8080 / TCP` | Any (`*`) | *(Optional)* Direct API Gateway access when bypassing Caddy during initial testing |

> [!WARNING]
> Internal microservice ports (`3001`–`3004`), database ports (`27017` for MongoDB, `6379` for Redis), and internal mTLS communication are bound to internal network interfaces (`127.0.0.1` / `saas-net`) and MUST NOT be exposed in Azure NSG inbound rules.

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
# Database Credentials & URIs
# -----------------------------------------------------------------------------
MONGO_INITDB_DATABASE=saas_platform
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD=<GENERATE_STRONG_SECRET> # e.g. `openssl rand -hex 24`

# MongoDB URI used by microservices over internal Docker network (saas-net)
MONGO_URI=mongodb://root:<MONGO_INITDB_ROOT_PASSWORD>@mongo:27017/saas_platform?authSource=admin

REDIS_PASSWORD=<GENERATE_STRONG_SECRET> # e.g. `openssl rand -hex 24`
REDIS_URI=redis://:<REDIS_PASSWORD>@redis:6379

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

# -----------------------------------------------------------------------------
# Production Environment & Security Secrets
# -----------------------------------------------------------------------------
APP_ENV=production
LOG_LEVEL=info
ALLOWED_ORIGIN=https://yourdomain.com

# Cryptographic tokens (Generate via `openssl rand -base64 48`)
JWT_SECRET=<GENERATE_STRONG_SECRET>
GATEWAY_SECRET=<GENERATE_STRONG_SECRET>
INTERNAL_SERVICE_TOKEN=<GENERATE_STRONG_SECRET>

# AES-256 Key for OTP encryption at rest (64 hex chars / 32 bytes via `openssl rand -hex 32`)
OTP_AES_KEY=<GENERATE_64_HEX_CHARS>

# Optional Third-Party Services
RESEND_API_KEY=re_your_live_key_here
RESEND_FROM_EMAIL=Quick Delivery <noreply@yourdomain.com>
```

### Step 5.3: Generate Internal mTLS Certificates
Inter-service communications inside `saas-net` are secured via mutual TLS (mTLS). Generate fresh production certificates on the target host prior to startup:

```bash
mkdir -p certs
cd certs
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt -subj "/CN=SaaS-Platform-Prod-Root-CA"

SERVICES=("api-gateway" "auth-service" "chat-service" "notification-service" "user-service")
for service in "${SERVICES[@]}"; do
  openssl genrsa -out "${service}.key" 2048
  openssl req -new -key "${service}.key" -out "${service}.csr" -subj "/CN=${service}" -addext "subjectAltName = DNS:${service}, DNS:localhost, IP:127.0.0.1"
  cat <<EOF > "${service}.ext"
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = DNS:${service}, DNS:localhost, IP:127.0.0.1
EOF
  openssl x509 -req -in "${service}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${service}.crt" -days 3650 -sha256 -extfile "${service}.ext"
  rm -f "${service}.csr" "${service}.ext"
done

openssl req -x509 -newkey rsa:2048 -nodes -keyout api-gateway-external.key -out api-gateway-external.crt -days 3650 -subj "/CN=localhost" -addext "subjectAltName = DNS:localhost, IP:127.0.0.1"
chmod 600 *.key
chmod 644 *.crt
cd ..
```

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

Test internal gateway health endpoint:
```bash
curl -k https://localhost:8080/health
```
Output: `{"status":"ok"}`

---

## 7. Automated Upgrades & Continuous Deployment

When developer changes are pushed to `main` in `saas-core`:
1. GitHub Actions builds and pushes updated images tagged with the commit SHA and `latest` to GHCR.
2. The workflow automatically updates `docker-compose.yml` in `saas-core-deploy` with the new commit SHA tag.
3. On the production server, update the deployment with zero downtime:
   ```bash
   cd /opt/saas-platform
   git pull
   docker compose pull
   docker compose up -d --remove-orphans
   ```

---

## 8. Public Reverse Proxy (Caddy), Custom Domain & Firewall

Production HTTPS traffic should be terminated via Caddy, which automatically obtains and renews TLS certificates via Let's Encrypt / ACME HTTP-01 challenges.

### Step 8.1: Reverse Proxy (Caddy) Architecture

Caddy is integrated directly into `docker-compose.yml` as a first-class service (`saas-caddy`). It runs on the internal `saas-net` Docker network alongside `api-gateway`, exposing public ports 80 and 443 (and 443/udp for HTTP/3).

#### 1. Deployment `Caddyfile` Configuration
Place the production `Caddyfile` in the root of the deployment directory (`/opt/saas-platform/Caddyfile`):

```caddy
api.logiclinkeg.tech {
    reverse_proxy https://api-gateway:8080 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

> [!IMPORTANT]
> **Internal Service Name Resolution**:
> The `reverse_proxy` target must be set to `https://api-gateway:8080` (not `127.0.0.1:8080`). Over the `saas-net` bridge network, `127.0.0.1` resolves to the `saas-caddy` container itself rather than the `api-gateway` container, leading to routing failures.

#### 2. Automatic Lifecycle Management
Because Caddy is defined as a service in `docker-compose.yml`, running `docker compose up -d` handles container creation, networking, port binding, and automatic restart (`restart: unless-stopped`). ACME certificates issued by Let's Encrypt are persisted across container restarts using the named volume `caddy_data:/data`.

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
  --db saas_platform \
  --archive=/data/db/backup_$(date +%F).archive --gzip

docker cp saas-mongo:/data/db/backup_$(date +%F).archive /opt/backups/
```

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

### 10.3 `curl: (35) OpenSSL SSL_connect: Connection reset by peer`
* **Symptom**: Executing `curl -k https://localhost:8080/health` immediately after `docker compose up -d` fails with `curl: (35) OpenSSL SSL_connect: Connection reset by peer` or `Connection refused`.
* **Cause**: Containers configured with `air` (Go live reload compiler) or cold startup compilation start up immediately, but the Go service binary inside is still compiling before binding to its assigned TLS port. Initial TLS handshake attempts during compilation trigger an immediate TCP reset.
* **Resolution**: Do not assume the service container has crashed. Poll process activity inside the container to monitor compilation progress:
  ```bash
  docker compose exec <service-name> ps aux
  ```
  Watch for active `compile` or `go build` processes. Once compilation finishes and `air` outputs server startup logs (`Server listening on port ...`), re-issue the health check request.

