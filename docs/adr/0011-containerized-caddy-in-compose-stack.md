# ADR-0011: Containerized Caddy Reverse Proxy in Docker Compose Stack

- **Status**: Accepted
- **Date**: 2026-07-31
- **Related Commit SHA**: ef4bd21b7a0c2d1e721027c5d1852b77cf7b42c7
- **Related audit finding**: Production Caddy Orphan Container Incident

## Context

During a production incident on the production VM (`quickdelivery-vm`), `api.logiclinkeg.tech` became completely unreachable (connection refused on HTTP 80 / HTTPS 443).

Investigation revealed two interrelated root causes:

1. **Orphan Container Lifecycle Outside Compose**: Caddy had been executed manually via a standalone `docker run` command directly on the host VM instead of being integrated into `docker-compose.yml`. Because it was not declared in the compose stack, any `docker compose down` or host maintenance resulted in the container being orphaned, removed (likely started with `--rm`), or left out during stack recreations.
2. **Bridge Network Name Resolution vs. Loopback Target**: The original `Caddyfile` configuration targeted `https://127.0.0.1:8080`. When running inside a container attached to the `saas-net` bridge network, `127.0.0.1` resolves to the `caddy` container's own network namespace rather than the `api-gateway` container, preventing successful reverse proxying.

To restore service, Caddy was temporarily recreated manually using `-p 80:80 -p 443:443 -v ./Caddyfile:/etc/caddy/Caddyfile:ro -v caddy_data:/data --network saas-core-deploy_saas-net caddy:2-alpine`. To prevent future outages, Caddy must be formally integrated as a first-class service inside `docker-compose.yml`.

## Decision

We formally integrated Caddy into the primary `docker-compose.yml` stack definition:

1. **Service Definition**: Added service block `caddy` using image `caddy:2-alpine`, named `saas-caddy`, configured with `restart: unless-stopped`.
2. **Port Mappings**: Exposed host ports `80:80`, `443:443`, and `443:443/udp` (supporting HTTP/3).
3. **Volume Mounts**: Mounted `./Caddyfile:/etc/caddy/Caddyfile:ro` for proxy routing configuration, `caddy_data:/data` for Let's Encrypt / ACME TLS certificate persistence across container restarts, and `caddy_config:/config` for state management.
4. **Network & Inter-Service Proxying**: Attached `caddy` to `saas-net` network and configured `Caddyfile` to target `https://api-gateway:8080` (enabling DNS resolution over `saas-net` bridge network). Transport retains `tls_insecure_skip_verify` to permit proxying to `api-gateway`'s internal mTLS certificate.
5. **Dependency Declaration**: Declared `depends_on: api-gateway` with `condition: service_started`.

## Consequences

### Positive
- **Unified Lifecycle Management**: Running `docker compose up -d` automatically provisions, starts, and monitors Caddy alongside all 5 microservices.
- **ACME Certificate Persistence**: Mounting named volume `caddy_data:/data` ensures TLS certificates issued by Let's Encrypt persist across restarts, avoiding ACME rate-limit exhaustion.
- **Reliable Inter-Container Routing**: Using `api-gateway:8080` as the upstream target resolves over `saas-net` bridge DNS, eliminating loopback resolution errors.

### Negative / Flagged Gaps
- **`api-gateway` Healthcheck Gap**: The `depends_on` condition for `api-gateway` is currently set to `service_started` because `api-gateway` does not yet define a Docker compose `healthcheck`. Adding a container healthcheck for `api-gateway` is flagged for future remediation to enable `condition: service_healthy`.

## Alternatives Considered

- **Host-Native Caddy Package (`apt install caddy`)**: Rejected because system-native packages introduce manual host dependencies and bypass container orchestration.
- **Standalone `docker-compose.caddy.yml` Sibling File**: Rejected because multi-file compose flags (`-f docker-compose.yml -f docker-compose.caddy.yml`) increase operational friction and risk partial deployments.
