# Staging Environment Architecture & Runbook

## 1. Overview & Purpose

The Quick Delivery Staging Environment provides a high-fidelity replica of the production deployment topology. Its primary objective is catching bugs that occur at the seams between components—such as proxy buffering, TLS handshake mismatches, WebSocket upgrade failures, and multi-service event cascades—which pass unit and mock integration tests undetected.

### Why Staging Parity Exists
Historical production-only incidents motivated this environment:
1. **API Gateway Reverse-Proxy SSE Buffering**: Unit and integration tests passed in isolation, yet clients received zero notifications in production because the gateway/proxy buffered Server-Sent Events without flushing.
2. **Reviewer Console Deployment Desync**: The standalone KYC reviewer console was deployed separately from the core API gateway, causing routing, TLS, and port collisions.
3. **Protocol Upgrade Incompatibilities**: WebSocket streaming proxies failing on `101 Switching Protocols` when response bodies were wrapped by resilience middlewares.

The staging stack runs identical production container build targets (`target: prod`), enforces internal mutual TLS (mTLS), routes all public traffic through a Caddy reverse-proxy edge, and operates on dedicated, isolated data stores.

---

## 2. Environment Comparison Matrix

| Dimension | Local Dev (`infrastructure/`) | Staging (`infrastructure/staging/`) | Production (`infrastructure/prod/`) |
| :--- | :--- | :--- | :--- |
| **Orchestration** | Docker Compose (`air` hot reload) | Docker Compose (`target: prod` binaries) | Docker Compose / Swarm / K8s |
| **Ingress Proxy** | Direct API Gateway port mapping (`8080`) | **Caddy** Reverse Proxy (`8088`, `8091`) | Caddy / Cloud Edge Ingress |
| **Console Edge** | Direct port mapping | Host/port routed via Caddy (`:8091`) | Domain-routed (`kyc.domain.com`) |
| **Datastores** | Dev MongoDB (`27017`), Redis (`6380`) | **Isolated** Mongo (`27018`), Redis (`6381`) | Production Cluster |
| **TLS / mTLS** | Optional / Self-signed | **Enforced mTLS** between all services | Enforced mTLS + Public CA Edge |
| **Build Target** | Debug / Hot-reload | `prod` (Multi-stage `CGO_ENABLED=0`) | `prod` (Multi-stage `CGO_ENABLED=0`) |
| **Lifecycle** | Ephemeral or long-running | Automated via `staging_up.sh` / `staging_down.sh` | Continuous deployment |

---

## 3. Architecture & Topology

```
                  +----------------------------------------------+
                  |               Client / Tests                 |
                  +----------------------------------------------+
                                  |              |
                      HTTP :8088  |              | HTTP :8091
                                  v              v
                  +----------------------------------------------+
                  |         Caddy Edge Proxy (Port 80/8090)      |
                  +----------------------------------------------+
                            |                            |
               mTLS :8080   |               HTTP :8090   |
                            v                            v
          +-----------------------------+  +---------------------------+
          |         api-gateway         |  |   kyc-reviewer-console    |
          +-----------------------------+  +---------------------------+
             |         |         |                       |
     mTLS    |  mTLS   |  mTLS   |  mTLS                 | Direct Auth DB
     :3002   |  :3001  |  :3003  |  :3004                | (Review Queue)
             v         v         v         v             v
       +----------+ +-------+ +-------+ +--------------+ |
       |   auth   | |  chat | | user  | | notification | |
       +----------+ +-------+ +-------+ +--------------+ |
             \         /         |             /         |
              \       /          |            /          |
           +---------------+     +-----------------------+
           | Redis (6381)  |     | MongoDB (Port 27018)  |
           | PubSub/Limits |     | staging_* databases   |
           +---------------+     +-----------------------+
```

### Component Details

1. **Caddy Reverse Proxy (`staging-saas-caddy`)**:
   - Listens on host port `8088` (routed to internal `api-gateway:8080`) and host port `8091` (routed to `kyc-reviewer-console:8090`).
   - Disables upstream response buffering to guarantee unblocked SSE streams and WebSocket framing.
   - Forwards client IP chains (`X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host`).
2. **API Gateway (`staging-saas-api-gateway`)**:
   - Production compiled binary running on internal port `8080`.
   - Strips routing prefixes and enforces mTLS upstream connections to backend services.
   - Applies global rate limiting, edge validation, and CORS.
3. **Reviewer Console (`staging-saas-kyc-reviewer-console`)**:
   - Runs `ghcr.io/omarmaarouf18/kyc-reviewer-console:latest`.
   - Connects directly to `staging_auth_db` for fast queue inspection and reviewer token verification.
4. **Core Services**:
   - `auth-service` (`:3002`): Tenant registration, JWT issuance, OTP, user lifecycle.
   - `chat-service` (`:3001`): WebSocket message hub, location tracking broadcasts.
   - `user-service` (`:3003`): Services directory, job cascade dispatch, escrow/pricing.
   - `notification-service` (`:3004`): SSE notification hub with Redis multi-replica fanout.
5. **Datastores**:
   - **MongoDB (`staging-saas-mongo`)**: Port `27018`, uses isolated databases `staging_auth_db`, `staging_user_db`, `staging_notification_db`.
   - **Redis (`staging-saas-redis`)**: Port `6381`, isolated rate limiters, SSE fanout, and pub/sub.

---

## 4. Operator Runbook

### Prerequisites
- Docker Engine 24.0+ and Docker Compose v2.20+
- Go 1.26.6+ (for test execution)
- OpenSSL (for certificate generation)
- Curl

### 1. Provisioning Staging
To stand up the complete staging stack with automated cert checks and health verification:
```bash
./scripts/staging_up.sh
```
What this script does automatically:
1. Copies `infrastructure/staging/.env.staging.example` to `.env.staging` if missing.
2. Checks for TLS certificates under `infrastructure/certs/` and invokes `generate-certs.sh` if needed.
3. Fixes certificate permissions (`chmod 644 infrastructure/certs/*.key`).
4. Builds and starts containers via `docker compose -f infrastructure/staging/docker-compose.staging.yml`.
5. Polls Caddy health endpoints (`http://localhost:8088/health` and `http://localhost:8091/healthz`) until ready.

### 2. Executing Critical User Journeys (CUJs)
To execute the live end-to-end test suite against staging:
```bash
go test -v -count=1 ./tests/e2e/...
```

### 3. Tearing Down Staging
To stop all containers, remove networks, and clear persistent volumes:
```bash
./scripts/staging_down.sh
```

### 4. Manual Docker Compose Controls
If manual orchestration is required without the wrapper scripts:
```bash
# Start or rebuild specific services
docker compose -f infrastructure/staging/docker-compose.staging.yml --env-file infrastructure/staging/.env.staging up -d --build

# View real-time container status
docker compose -f infrastructure/staging/docker-compose.staging.yml --env-file infrastructure/staging/.env.staging ps

# View service logs
docker compose -f infrastructure/staging/docker-compose.staging.yml --env-file infrastructure/staging/.env.staging logs -f api-gateway
```

---

## 5. Troubleshooting & Diagnostics

### Executing into Containers
To open an interactive shell inside a running staging container:
```bash
# Inspect API Gateway
docker exec -it staging-saas-api-gateway sh

# Inspect Staging MongoDB via mongosh
docker exec -it staging-saas-mongo mongosh -u staging_root -p staging_secret123 --authenticationDatabase admin

# Inspect Staging Redis
docker exec -it staging-saas-redis redis-cli -a staging_secret123
```

### Common Issues & Remedies

| Symptom | Root Cause | Remedy |
| :--- | :--- | :--- |
| `502 Bad Gateway` on `/health` | API Gateway still starting or crashed | Check `docker logs staging-saas-api-gateway`. Verify Redis and Mongo health. |
| `403 Forbidden` on WebSocket `/chat/ws` | User not seeded in `staging_auth_db.users` | Ensure the test seeds the user record via `db.SeedCustomer` before dialing. |
| `101 Switching Protocols with non-writable body` | Proxy transport wrapped response body | Ensure `resilience.RoundTripper` does not wrap `StatusSwitchingProtocols` in `cancelReadCloser`. |
| `429 Too Many Requests` on notifications | High internal dispatch volume | Verify `POST /notifications/send` rate limiter is configured for internal service throughput (300 req/min). |
| `permission denied` on `.key` files | Staging containers run as non-root | Ensure `chmod 644 infrastructure/certs/*.key` is executed prior to start. |

---

## 6. CI Pipeline Integration

The E2E Release Gate workflow is defined in `.github/workflows/release-gate-e2e.yml`. It runs automatically on pushes to `main` and on manual `workflow_dispatch`. It executes:
1. Fresh staging stack standup via `scripts/staging_up.sh`.
2. Live test execution with `go test -v -count=1 ./tests/e2e/...`.
3. Stack teardown and volume purge via `scripts/staging_down.sh`.
