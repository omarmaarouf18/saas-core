# Worklog: OPS-HARDEN — harden the production compose to match the real server

## Task and scope
- Task ID: OPS-HARDEN
- Item IDs covered: items 1–6 of the task prompt (RB-01 group OPS-COMPOSE-HARDEN:
  OPS-04, OPS-05, SEC-10, OPS-08; also the SEC-02 edge block)
- Allowed paths (lane): `infrastructure/deploy/docker-compose.prod.yml`,
  `infrastructure/deploy/Caddyfile` (new), `infrastructure/deploy/deploy.yml`,
  `.github/workflows/build-and-publish.yml` (sync step only),
  `docs/runbooks/OPS-HARDEN-cutover.md` (new), `docs/worklog/OPS-HARDEN.md`
- Agent branch: agent/OPS-HARDEN-compose, created from logic-exploitation (`540fc574`)
- No server access. Server facts used are only those in the task prompt
  (verified by the owner on 2026-10-16). Everything else is a runbook check.

## Decisions taken
- **Owner decision (2026-10-16): accept Redis `maxmemory 32mb` with `noeviction` as
  implemented.** This resolves the Redis open question below.
- Caddy image `caddy:2.11.4-alpine`. Docker Hub `tag_last_pushed` dates on
  2026-10-16: `2.11.4-alpine` 2026-09-23 (23 days), `2.11.6-alpine` 2026-10-04 and
  `2.11.7-alpine` 2026-10-06 (both under 14 days). These are image push dates from
  the Docker Hub API, not GitHub release dates.
- `caddy_data` is `external: true, name: caddy_data`. `caddy_config` is a new named
  volume `saas_platform_caddy_config` (only Caddy's autosaved JSON, nothing to keep).
- Admin block: `@admin path /api/v1/admin /api/v1/admin/*` → `respond @admin 404`.
  `tls_insecure_skip_verify` kept, with a comment and a follow-up. The gateway serves
  its *external* certificate (`ListenAndServeTLS(cfg.ExternalTLSCertPath, …)`,
  `services/api-gateway/cmd/main.go:185`), so the follow-up must pick the matching SAN.
- Gateway: `ports:` replaced by `expose: ["${API_GATEWAY_PORT}"]`. No host port is
  needed: deploy.yml health checks use `docker exec`.
- Mongo noise: `--quiet` plus healthcheck interval 10s → 30s. An unauthenticated
  `ping` healthcheck was tried and logs just as many lines, so the authenticated
  check was kept. Measurements are under Verification.
- Redis: `maxmemory 32mb`, `maxmemory-policy noeviction` (reasoning in item 4 and in
  Open questions).
- Memory limits total 728 MiB, leaving 163 MiB of the 891 MB. Go services get
  `GOMEMLIMIT` at about 80 % of the limit. The kyc console gets none, because its
  language is not verified in this repo.
- deploy.yml: plain `up -d --remove-orphans`. Forced recreate only when the cert
  step restored or regenerated certs (`CERTS_CHANGED`). Caddy-only recreate when the
  mounted Caddyfile differs from the checkout. Rollback keeps orphans when the restored
  compose has no `caddy` service.

## Changes per commit (message only — NO SHAs)
1. `OPS-HARDEN: Caddy in compose with admin-path 404 and Caddyfile sync`
2. `OPS-HARDEN: stop publishing the api-gateway port on the host`
3. `OPS-HARDEN: json-file log rotation for every service, quieter mongo`
4. `OPS-HARDEN: memory limits for the 891 MB VM, mongo cache cap, redis maxmemory noeviction`
5. `OPS-HARDEN: deploy recreates only changed services; forced recreate only after cert changes`
6. `OPS-HARDEN: cutover runbook for the owner`
7. `OPS-HARDEN: worklog`
8. `OPS-HARDEN: worklog: owner accepts redis noeviction`
9. `OPS-HARDEN: deploy removes a hand-started saas-caddy before up -d (one-time cutover)`
10. `OPS-HARDEN: worklog: cutover guard`

## Item reports (2–5)

### Item 2: gateway not published
- `api-gateway` has `expose` only. Nothing in the lane needs a host port:
  `deploy.yml:203,282` list `api-gateway:8080`, but those are `docker exec … curl
  https://localhost:8080/health` inside the container.
- Hits outside the lane that call or document :8080 from the host or outside
  (not edited, follow-ups):
  - `docs/DEPLOYMENT.md:61`: NSG rule `Allow-API-Gateway-Direct` 8080/TCP from Any.
    Must be removed from the Azure NSG and the doc.
  - `docs/DEPLOYMENT.md:261,306,331`: `curl -k https://localhost:8080/health` on
    the VM host. Will fail now; use `docker exec saas-api-gateway curl -sk …`.
  - `docs/DEPLOYMENT.md:291`: says the runner health-checks `http://localhost:8080/health`
    and uses `up -d --remove-orphans`. The first part is stale; the second is true again.
  - `docs/DEPLOYMENT.md:544`: troubleshooting assumes `https://<VM_IP>:8080/health` works.
  - `docs/DEPLOYMENT.md:631,641`: version-config via `X-Internal-Token` on host
    `localhost:8080`. Stale twice: SEC-02 token, and no host port. See runbook §4.
  - `docs/DEPLOYMENT.md:342-365`: Caddy section describes the hand-started container.
  - `docs/REPOSITORY_MAP.md:145`: `docker compose ps caddy` is now correct as written.
  - `frontend/lib/core/api_client.dart:53`: default `https://localhost:8080/api/v1`
    is the local-dev default (`String.fromEnvironment`), not production. No change needed.

### Item 3: log rotation
- One `x-logging: &default-logging` anchor (json-file, `max-size: "10m"`,
  `max-file: "3"`) on all 9 services: mongo, redis, api-gateway, chat, auth, user,
  notification, kyc-reviewer-console, caddy.
- Mongo: `command: ["--quiet", …]` and healthcheck `interval: 30s`. Why: `--quiet`
  suppresses "Connection accepted/ended" but not warnings or errors (W lines still
  appeared in the local test). The rest of the noise is the healthcheck's own
  mongosh connections (client metadata, authentication, about 12 lines per check
  under `--quiet`), so the interval change cuts it a further 3×. Cost: a freshly
  started mongo turns healthy up to about 30 s later, which delays dependants'
  start (`condition: service_healthy`) only when mongo itself is recreated.
  `start_interval` would avoid that but needs a Docker Engine version not verified
  on the server.

### Item 4: memory limits

Budget: 891 MB total. Limits sum to **728 MiB**, leaving **163 MiB** for the OS,
dockerd and the runner. Target was ≥ 150.

| service | measured RSS | mem_limit | reservation | GOMEMLIMIT | reasoning |
| :--- | ---: | ---: | ---: | ---: | :--- |
| mongo | 144 MB | 400m | 192m | — | `--wiredTigerCacheSizeGB 0.25` = 256 MiB cache at most, plus mongod overhead, plus the mongosh healthcheck process (Node) that runs in the same cgroup. Locally idle under these flags: 127.4 MiB. |
| redis | 3.4 MB | 48m | 16m | — | `maxmemory 32mb` + overhead. AOF rewrite forks; copy-on-write pages count against the limit. Fine at today's 3.4 MB, tighter near 32 MB. |
| auth-service | 12 MB | 56m | — | 45MiB | KYB/KYE uploads up to 10 MB (`ParseMultipartForm(10 << 20)`, `auth.go:1685-1687`) plus encryption copies: about 30 MB peak for one upload. |
| chat-service | 12 MB | 56m | — | 45MiB | Ticket attachments, same 10 MB cap (`chat.go:1084-1086`), plus WebSocket hub buffers. |
| user-service | 17 MB | 48m | — | 38MiB | Highest Go RSS, no uploads. About 2.8× measured. |
| caddy | 14 MB | 40m | — | 32MiB | TLS + HTTP/3. About 2.9× measured. |
| api-gateway | 6.4 MB | 32m | — | 25MiB | Streaming reverse proxy (`FlushInterval: -1`). About 5× measured. |
| notification-service | 6.5 MB | 32m | — | 25MiB | SSE connections. About 5× measured. |
| kyc-reviewer-console | 4.6 MB | 16m | — | — | About 3.5× measured. Built in another repo; runtime not verified here, so no GOMEMLIMIT. |
| **sum** | **220.3 MB** | **728 MiB** | | | 891 − 728 = 163 |

Residual risks:
- Two concurrent 10 MB uploads on auth or chat could exceed 56m (OOM kill and restart).
- Redis is close to its limit if the dataset approaches 32 MB during an AOF rewrite.
- The runbook's post-checks include an OOM watch (`docker inspect … OOMKilled`).

Redis policy, from the code:

| key family | where | TTL |
| :--- | :--- | :--- |
| `jwt:invalidated_before:<user>` | `shared/infra/jwtutil/jwt.go:309` | 8 days |
| `jwt:denylist:<jti>` | `jwt.go:363` | until token expiry + 7 days |
| rate-limit counters and lockouts | `shared/infra/ratelimit/ratelimit.go:115-131,188-197,290-297` | window / 24 h / lockout |
| idempotency | `services/user-service/internal/handlers/handlers.go:385,413,462,481` | 24 h |
| location throttle | `handlers.go:67,167`, `jobs_handlers.go:1477,1753` | 5 min / in-flight |
| pub/sub | `account:events`, job/fleet channels (`chat/hub.go:108,288`) | no keys |

Every key has a TTL, revocation keys included. So `volatile-*` policies could evict
a revocation (a revoked session would validate again), and `allkeys-*` likewise.
**No eviction policy is safe. `noeviction` is used.** When full, Redis refuses
writes ("OOM command not allowed"); the limiters and revocation then fail closed
(429/503) rather than serving revoked tokens. See Open questions.

### Item 5: deploy without needless recreation
- Deploy step: `docker compose up -d --remove-orphans`. With `CERTS_CHANGED=1` it runs
  `docker compose up -d --force-recreate --remove-orphans`. The cert step sets that flag
  whenever it restores certs from `/home/deploybot/certs` or `/opt/saas-platform/certs`,
  or generates fresh ones. Those files are bind mounts and compose cannot see their
  content change, so this is the one place where forced recreation is really needed.
- New: after `up`, if the Caddyfile inside `saas-caddy` differs (sha256) from the
  checked-out `Caddyfile`, run `docker compose up -d --force-recreate --no-deps caddy`.
  Reason: a single-file bind mount pins the old inode. Verified locally: after
  replacing the host file, the container still served the old content (output below).
- Rollback step: `docker compose up -d $ORPHANS_FLAG`, no `--force-recreate`. The
  restored file changes image tags, so the affected services are recreated anyway.
  `--remove-orphans` is dropped when the restored compose has no `caddy:` service.
  Otherwise the first rollback to a pre-OPS-HARDEN file would delete the
  compose-managed `saas-caddy` as an orphan.
- Cert-purge path: both `docker compose down --remove-orphans` calls now also stop
  Caddy. The path still ends with the deploy step's `up -d`, which starts every
  service including Caddy. The downtime (purge → deploy step, longer if the pre-flight
  fails) is in the runbook.

### Follow-up item: cutover guard (owner request, after items 1–6)
- deploy.yml runs `remove_hand_started_caddy` right before the main `docker compose up -d`
  in both the deploy step and the rollback step. The two copies are identical
  (34 lines each, between the `# >>> cutover-guard` / `# <<< cutover-guard` markers).
- It runs `docker rm -f saas-caddy` and logs `removing hand-started saas-caddy
  (one-time cutover)` only when:
  - the compose file being applied defines a `caddy` service;
  - the current project name is known (top-level `name` from
    `docker compose config --format json`; empty → warning, no removal);
  - a container named `saas-caddy` exists;
  - its `com.docker.compose.project` label is missing or differs from the project.
- A compose-managed `saas-caddy` is never removed.
- Decision beyond the request: the first condition was added. Without it, an automatic
  rollback to a pre-OPS-HARDEN compose (no `caddy` service) would delete a
  hand-started Caddy that nothing then recreates. In that case the guard does nothing.
- The rollback step runs with `set -euo pipefail`, so the guard uses readers that
  consume all input (`grep -x … >/dev/null`, `sed -n '1…p'`, no `grep -q`/`head`).
  Its two command substitutions fall back to empty on failure, so neither a closed
  pipe nor a failed inspect can abort the step or make it remove a compose-managed
  container.
- Runbook §2 rewritten: the guard is the default path, and the manual `docker rm -f` +
  `docker compose up -d --remove-orphans` is the fallback. §6 now says the next deploy
  replaces a hand-restored Caddy unless the Caddy commit is reverted.
- Test (local, Docker 29.9.1 / Compose v5.6.0). The guard block was extracted verbatim
  from deploy.yml and run with `bash -euo pipefail` in a project directory named
  `saas-core-deploy`, whose compose file has a `caddy` service with
  `container_name: saas-caddy`:

  ```
  === (a) hand-started saas-caddy
  before: id=e8fa38b2b0be label=''
  removing hand-started saas-caddy (one-time cutover)
    saas-caddy project label: '', current project: 'saas-core-deploy'
  saas-caddy
  guard exit=0
   Container saas-caddy Starting
   Container saas-caddy Started
  up exit=0
  after:  id=d25a193c771c label='saas-core-deploy'
  === (b) compose-managed saas-caddy
  guard exit=0 (no output above = untouched)
  after:  id=d25a193c771c label='saas-core-deploy' same_container=yes
   Container saas-caddy Running
  up exit=0
   Network saas-core-deploy_default Removed
  === (c) hand-started saas-caddy, compose file without caddy service (pre-OPS-HARDEN rollback)
  guard exit=0
  after: same_container=yes
  === (d) saas-caddy owned by another compose project
  removing hand-started saas-caddy (one-time cutover)
    saas-caddy project label: 'someother', current project: 'saas-core-deploy'
  saas-caddy
  guard exit=0
  after: exists=
  ```

  The lone `saas-caddy` lines are `docker rm -f` echoing the removed name.
- Not verified: the guard inside a real GitHub Actions run on the server, and the
  length of the downtime window between the `rm -f` and the new Caddy starting.

## Verification

All commands ran locally (Docker 29.9.1, Compose v5.6.0). `make ci` ran before each commit.

- `make ci` before commit 1, first run: FAIL in user-service,
  `--- FAIL: TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL (2.01s)`,
  `handlers_test.go:4527: Expected status 201 Created on instance 1, got 400. Body: {"error":"service not found"}`.
  This diff has no Go changes. It ran against the shared local Mongo/Redis right after
  the parallel TST-01 gate. Second run: PASS.
- `make ci` before commits 1 (second run), 2, 3, 4, 5, 6: each ended `All tests passed!`
  and `== pre-push gate: all checks passed ==`. Commit 7 (this worklog): see the final
  chat report.
- Compose validation with every `${VAR}` set to a dummy value (the build-and-publish.yml
  trick: PORT vars `8000`, others `dummy_val_for_ci_validation`), on the final file:
  `compose config -q exit=0`.
- `caddy validate` with the pinned image:
  `docker run --rm -v …/Caddyfile:/etc/caddy/Caddyfile:ro caddy:2.11.4-alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile`
  printed `Valid configuration`, `caddy validate exit=0`.
- Admin matcher at runtime. The matcher lines were copied verbatim into a test
  Caddyfile on `http://:8088`, proxying to a stub that echoes the path:

  ```
  /health                              200 upstream /health
  /api/v1/users/jobs/get               200 upstream /api/v1/users/jobs/get
  /api/v1/admin                        404
  /api/v1/admin/version-config         404
  /API/V1/ADMIN/version-config         404
  /api/v1/%61dmin/version-config       404
  /api/v1//admin/version-config        404
  /api/v1/adminx                       200 upstream /api/v1/adminx
  ```

- Rendered config (dummy env, PORT vars set to `8080`), per service:

  ```
  service                published ports                            logging                                mem_limit
  api-gateway            -                                          json-file {'max-file': '3', 'max-size': '10m'} 32MiB
  auth-service           -                                          json-file {'max-file': '3', 'max-size': '10m'} 56MiB
  caddy                  0.0.0.0:80->80/tcp,0.0.0.0:443->443/tcp,0.0.0.0:443->443/udp json-file {'max-file': '3', 'max-size': '10m'} 40MiB
  chat-service           -                                          json-file {'max-file': '3', 'max-size': '10m'} 56MiB
  kyc-reviewer-console   127.0.0.1:8090->8090/tcp                   json-file {'max-file': '3', 'max-size': '10m'} 16MiB
  mongo                  127.0.0.1:27017->27017/tcp                 json-file {'max-file': '3', 'max-size': '10m'} 400MiB
  notification-service   -                                          json-file {'max-file': '3', 'max-size': '10m'} 32MiB
  redis                  127.0.0.1:6380->6379/tcp                   json-file {'max-file': '3', 'max-size': '10m'} 48MiB
  user-service           -                                          json-file {'max-file': '3', 'max-size': '10m'} 48MiB
  sum mem_limit MiB: 728
  --- grep: any 0.0.0.0 publish of 8080 in the rendered config (PORT vars set to 8080)?
  none
  ```

- Mongo log noise. Five healthcheck-style `mongosh … ping` runs on `mongo:7`:
  - without `--quiet`: 100 lines (20 `Connection accepted`, 20 `client metadata`,
    20 `Connection ended`, 15 `Auth metrics report`, 15 `Successfully authenticated`,
    5 `Connection not authenticating`, 5 `Received first command…`);
  - with `--quiet`: 60 lines (the accepted/ended lines gone);
  - unauthenticated `ping` with `--quiet`: also 60 lines, so it was not adopted.
  - Warnings still logged under `--quiet` (`W CONTROL … Soft rlimits…`).
- Mongo and Redis flags at runtime (`--memory 400m` / `48m`):
  `mongo cache max bytes: 268435456`; Redis `maxmemory 33554432`, `maxmemory-policy noeviction`;
  `opsh-m 127.4MiB / 400MiB`, `opsh-r 3.477MiB / 48MiB`, both `oom=false running=true`.
- Redis full under `noeviction` (1 MB values until refused):
  `SET k23 -> OOM command not allowed when used memory > 'maxmemory'.`; the revocation
  key written first was still readable (`1`); `used_memory_human:29.79M`; container
  `30.35MiB / 48MiB`, `oom=false`.
- Name clash (compose project with a service `container_name` already taken by a
  hand-started container, which depends on another service): `up -d` printed
  `Conflict. The container name "/opsh-clash-edge" is already in use …`, `up exit=1`,
  and the other service was left `Created`, not started. After `docker rm -f` and
  `up -d edge`, both were `Up`.
- Single-file bind mount after replacing the host file (write + rename, like a checkout):
  container sha `d7ba91752e99a5ab` before and after; host `588446efe2e3406e` after;
  container still `respond "v1"`.
- `deploy.yml` parses as YAML (`python3 yaml.safe_load` → `yaml ok`).
- Full 40-character SHA check over the files of this branch: none.

## Unverified
- Runtime behaviour of the real production stack: the stack cannot be run locally
  (GHCR images with production config, real certs, real domains). Everything above
  is config validation plus isolated container tests.
- Caddy reusing the existing certificates from `caddy_data` (the runbook compares
  serial and expiry before and after).
- That the server's Docker and Compose versions behave like the local ones on the
  name clash and on `mem_limit`. The runbook avoids depending on the clash behaviour.
- deploy.yml shell changes were not executed in a GitHub runner (no workflow lint run).
- The exact spec of the temporary iptables rule. It is not in the task facts, so the
  runbook has the owner print it first and delete that exact spec.
- The kyc console's runtime language and memory behaviour (other repo).

## Follow-ups / out-of-lane findings
- Doc updates listed in item 2 (`docs/DEPLOYMENT.md`, Azure NSG rule 8080).
- Trust the internal CA in Caddy instead of `tls_insecure_skip_verify` (comment in the Caddyfile).
- `docs/README.md` has no entry for the new `docs/runbooks/` directory.
- RB-01 report, SCALE-05: user-service also has a Redis-backed location throttle
  (`checkLocationThrottleScript`, `jobs_handlers.go:1274,1638`) next to the in-memory
  maps cited there. Re-check that row.
- `TestTrackJob_RedisBackedIdempotency_MultiInstanceAndTTL` and (in RB-01)
  `TestTrackJob_EscrowRollbackFailure_ReconciliationRequired` failed once each against
  the shared local stack and passed on re-run. For TST-01, not here.

## Open questions
- **Redis `noeviction` (task stop condition, raised but not stopped on).** No eviction
  policy is safe (all keys have TTLs, revocation keys included), and the item says to
  use `noeviction` in that case. The risk: if Redis reaches 32 MB, every write fails.
  Rate-limited endpoints then answer 429/503 and revocations fail closed, an outage
  for logins and bookings until keys expire. What drives growth is distinct IPs and
  emails hitting the auth limiters (24 h counters).
  - Today's alternative is no `maxmemory` and no `mem_limit`, which means unbounded
    growth on the host.
  - I judged a bounded, fail-closed Redis better than that, and implemented it.
  - Owner: confirm, or pick a larger `maxmemory`, which needs memory taken from another service.
  - **Answered 2026-10-16:** the owner accepted `maxmemory 32mb` + `noeviction` as implemented.
- Which chain holds the temporary iptables DROP, and is it persisted? Runbook pre-check 7.
- **Stop (gate failure outside the lane), 2026-10-16.** `make ci` for commit 8 (this
  decision note, Markdown only) failed twice in user-service:
  - run 1: `service_owner_config_test.go:177: Expected 201 Created, got 402. Body: {"error":"upgrade_required","message":"Service catalog creation requires a paid subscription."}`;
  - run 2: `service_owner_config_repro_test.go:126: Expected 200 OK for UpdateService, got 402. Body: {"error":"upgrade_required","message":"Service catalog updates requires a paid subscription."}`.
  - Cause, read from the code: both tests create `context.WithTimeout(…, 2*time.Second)`
    (`service_owner_config_repro_test.go:31`, `service_owner_config_test.go:30`), spend
    it on `store.NewMongoDB` (connect, indexes, seed), then reuse it for
    `_ = s.UpsertSubscription(ctx, …)` with the error discarded
    (`service_owner_config_repro_test.go:77`, `service_owner_config_test.go:99,104`).
    When setup takes more than 2 s, the paid subscription is never written and the
    handler correctly returns 402.
  - Fix (out of lane, `services/**`): use a fresh context for the seed writes and fail
    the test on their error.
  - Commits 1–7 each passed the gate; this note is committed only once the gate passes.
