# SaaS Platform — Production Deployment Guide

This guide provides step-by-step instructions for deploying the Quick Delivery SaaS platform on any generic cloud Virtual Private Server (VPS) or Linux host running Docker and Docker Compose (e.g. Hetzner, DigitalOcean, Linode, AWS EC2).

---

## 1. Architecture Overview (Two-Repo Pipeline)

The SaaS platform uses a clean two-repository deployment model to separate source code development from production cloud host execution:

1. **Development Repository (`omarmaarouf18/saas-core`)**:
   - Contains all microservice source code, tests, database migrations, and CI workflows.
   - Merging changes into the `main` branch automatically triggers GitHub Actions to build production Docker images (`prod` stage) for all 5 microservices, publish them to GitHub Container Registry (`ghcr.io`), and update the deployment repository with new image tags.

2. **Deployment Repository (`omarmaarouf18/saas-core-deploy`)**:
   - Lightweight, deploy-only repository containing production `docker-compose.yml`, `.env.example`, `Caddyfile`, and certificate generation tooling.
   - The production cloud host **only pulls from this repository**. No source code, Go compilers, or Flutter SDKs are present or required on the production host.

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

## 3. GHCR Image Registry Authentication & Package Visibility

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

## 4. Server Provisioning & Initial Deployment

### Step 4.1: Clone Deployment Repository
On the production VPS host, clone the dedicated deployment repository:
```bash
git clone https://github.com/omarmaarouf18/saas-core-deploy.git /opt/saas-platform
cd /opt/saas-platform
```

### Step 4.2: Configure Environment Variables & Secrets
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

### Step 4.3: Generate Internal mTLS Certificates
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

## 5. Running the Production Stack

### Step 5.1: Pull Images
If using Option B (private packages), perform `docker login ghcr.io` first. Then pull pre-built images:
```bash
docker compose pull
```

### Step 5.2: Start Stack in Detached Mode
```bash
docker compose up -d
```

### Step 5.3: Verify Health
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

## 6. Automated Upgrades & Continuous Deployment

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

## 7. Public Reverse Proxy (Caddy) & Firewall (UFW)

### Step 7.1: Caddy Reverse Proxy
Install Caddy to terminate public HTTPS (Let's Encrypt ACME) on ports 80/443:
```bash
sudo apt update && sudo apt install -y caddy
```

Edit `/etc/caddy/Caddyfile`:
```caddy
api.yourdomain.com {
    reverse_proxy https://127.0.0.1:8080 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```
Reload Caddy: `sudo systemctl reload caddy`

### Step 7.2: Firewall Rules (UFW)
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

> [!WARNING]
> Database ports (`27017`, `6380`) and internal microservice ports (`3001`-`3004`, `8080`) are bound to `127.0.0.1` and MUST NOT be opened in UFW.

---

## 8. Logging & Database Backups

### Live Logs
```bash
docker compose logs -f
docker compose logs -f auth-service
```

### Manual MongoDB Backup (`mongodump`)
```bash
docker compose exec mongo mongodump \
  -u root -p "<MONGO_INITDB_ROOT_PASSWORD>" \
  --authenticationDatabase admin \
  --db saas_platform \
  --archive=/data/db/backup_$(date +%F).archive --gzip

docker cp saas-mongo:/data/db/backup_$(date +%F).archive /opt/backups/
```
