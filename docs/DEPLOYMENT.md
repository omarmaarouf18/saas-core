# SaaS Platform — Production Deployment Guide

This guide provides step-by-step instructions for deploying the Quick Delivery SaaS platform on any generic cloud Virtual Private Server (VPS) or Linux host running Docker and Docker Compose (e.g. Hetzner, DigitalOcean, Linode, AWS EC2).

---

## 1. Prerequisites & Minimum Specs

### Software Requirements
* **OS**: Linux host (Ubuntu 22.04 LTS, Debian 12, RHEL 9, or similar)
* **Docker Engine**: 24.0+
* **Docker Compose**: v2.20+ (`docker compose` v2 plugin)

### Minimum Hardware Specifications
* **CPU**: 2 vCPUs minimum (4 vCPUs recommended for production traffic)
* **RAM**: 4GB RAM minimum (8GB recommended to comfortably run MongoDB, Redis, and all 5 Go microservices under load)
* **Disk**: 20GB+ SSD storage for Docker images, service logs, and persistent database volumes

---

## 2. Security Hardening & Pre-Flight Configuration

### Step 2.1: Clone Repository
```bash
git clone https://github.com/omarmaarouf18/saas-core.git /opt/saas-platform
cd /opt/saas-platform
```

### Step 2.2: Configure Environment Variables & Production Secrets
Copy the template configuration file:
```bash
cp infrastructure/.env.example infrastructure/.env
```

Edit `infrastructure/.env` using your preferred editor (`nano` or `vim`). Every parameter marked as a production secret **MUST** be generated using a cryptographically secure random generator (never reuse development values):

```env
# -----------------------------------------------------------------------------
# Database Credentials & URIs (Phase 1 Security Hardening)
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

### Step 2.3: Generate Fresh Internal mTLS Certificates
Inter-service communications inside the Docker network (`saas-net`) are secured via mutual TLS (mTLS). Generate fresh production certificates on the target host prior to startup:

```bash
cd /opt/saas-platform/infrastructure/certs
chmod +x generate-certs.sh
./generate-certs.sh
cd /opt/saas-platform
```

> [!IMPORTANT]
> The default certificates in `infrastructure/certs/` are for development purposes only. Running `./generate-certs.sh` ensures your production deployment operates on fresh, uncompromised keys.

---

## 3. Running the Stack & Health Verification

### Step 3.1: Start Containers
Run Docker Compose in detached mode:
```bash
docker compose -f infrastructure/docker-compose.yml --env-file infrastructure/.env up -d --build
```

### Step 3.2: Verify Container Health
Check the container status to ensure MongoDB and Redis health checks report `healthy`:
```bash
docker compose -f infrastructure/docker-compose.yml ps
```

Expected output snippet:
```text
NAME                           STATUS                   PORTS
saas-api-gateway               Up 30 seconds            127.0.0.1:8080->8080/tcp
saas-auth-service              Up 30 seconds            3002/tcp
saas-chat-service              Up 30 seconds            3001/tcp
saas-mongo                     Up 30 seconds (healthy)  127.0.0.1:27017->27017/tcp
saas-notification-service      Up 30 seconds            3004/tcp
saas-redis                      Up 30 seconds (healthy)  127.0.0.1:6380->6379/tcp
saas-user-service              Up 30 seconds            3003/tcp
```

Test the internal API Gateway health check endpoint:
```bash
curl -k https://localhost:8080/health
```
Output: `{"status":"ok"}`

---

## 4. Public Reverse Proxy & TLS Termination (Caddy)

Do **NOT** expose `api-gateway` port 8080 directly to the public internet. Instead, run a reverse proxy (e.g. Caddy) on the host machine to terminate public TLS (Let's Encrypt / ACME) on standard ports 80/443 and proxy traffic internally to `api-gateway`.

### Step 4.1: Install Caddy
On Ubuntu / Debian:
```bash
sudo apt update
sudo apt install -y caddy
```

### Step 4.2: Configure Caddyfile
Create or edit `/etc/caddy/Caddyfile`:

```caddy
api.yourdomain.com {
    reverse_proxy https://127.0.0.1:8080 {
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

> [!NOTE]
> `tls_insecure_skip_verify` tells Caddy to accept the internal gateway self-signed certificate while serving a valid public Let's Encrypt certificate to external users.

### Step 4.3: Start & Reload Caddy
```bash
sudo systemctl enable --now caddy
sudo systemctl reload caddy
```

---

## 5. Host Firewall Configuration (UFW)

Enforce strict host-level firewall rules using UFW (Uncomplicated Firewall) to block external access to internal service ports, MongoDB, and Redis.

```bash
# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH management
sudo ufw allow 22/tcp

# Allow public web traffic (Caddy reverse proxy)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable
```

> [!WARNING]
> Database ports (`27017`, `6380`), internal microservice ports (`3001`-`3004`), and the gateway port (`8080`) are bound only to `127.0.0.1` and protected by UFW. They MUST NOT be exposed to `0.0.0.0/0`.

---

## 6. Maintenance, Logging & Troubleshooting

### View Live Container Logs
```bash
# View logs across all services
docker compose -f infrastructure/docker-compose.yml logs -f

# View logs for a specific service (e.g. auth-service)
docker compose -f infrastructure/docker-compose.yml logs -f auth-service
```

### Restart a Specific Microservice
```bash
docker compose -f infrastructure/docker-compose.yml restart user-service
```

### Graceful Full Stack Shutdown
```bash
docker compose -f infrastructure/docker-compose.yml down
```

---

## 7. Database Backup & Disaster Recovery

### Manual MongoDB Backup (`mongodump`)
Execute `mongodump` directly within the `mongo` container to create a compressed backup archive:

```bash
docker compose -f infrastructure/docker-compose.yml exec mongo mongodump \
  -u root -p "<MONGO_INITDB_ROOT_PASSWORD>" \
  --authenticationDatabase admin \
  --db saas_platform \
  --archive=/data/db/backup_$(date +%F).archive --gzip
```

Copy the backup archive out of the container to host storage or offsite backup location:
```bash
docker cp saas-mongo:/data/db/backup_$(date +%F).archive /opt/backups/
```

### Manual MongoDB Restore (`mongorestore`)
```bash
docker compose -f infrastructure/docker-compose.yml exec -T mongo mongorestore \
  -u root -p "<MONGO_INITDB_ROOT_PASSWORD>" \
  --authenticationDatabase admin \
  --archive=/data/db/backup_2026-07-30.archive --gzip
```
