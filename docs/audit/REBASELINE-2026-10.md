# Re-baseline of the 2026-10-03 remediation findings (RB-01)

- Date: 2026-10-16. Base: `logic-exploitation` at `1cff9d10`.
- Input: the five untracked files under `docs/remediation/` in the main worktree (109 findings).
  They were written against `frontend-visual-fixes`, about 345 commits older. Every finding was
  treated as a claim and checked against today's code.
- Method: static read only (grep by symbol or behaviour, `git log -S/-G` for commits, and the
  committed goldens under `frontend/test/goldens/` for visual claims). Nothing was built, run or
  deployed. Goldens are the files committed at HEAD (last regenerated in `34a47dde`); I assumed
  they match what the golden tests render today and did not run the tests.
- Statuses: **Done**, **Partial**, **Open**, **Obsolete**, **Unclear** (defined in the task).
  Severity is "now": P0 critical, P1 high, P2 medium, P3 low. Effort: S < 2 h, M < 1 day, L > 1 day.
  VM-fit: **yes** fits the 1 GB / 2-core VM, **$** needs an external service or money,
  **infra** needs more infrastructure (more VMs, HA), **tight** fits but costs scarce RAM.
- Line numbers are from `1cff9d10`. Paths are repo-relative.

## 1. Summary

| Area | Findings | Done | Partial | Open | Obsolete | Unclear |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| Security (SEC) | 18 | 0 | 7 | 10 | 0 | 1 |
| Backend (BE) | 22 | 4 | 7 | 8 | 2 | 1 |
| Observability (OBS) | 18 | 1 | 3 | 13 | 0 | 1 |
| DevOps (OPS) | 15 | 1 | 1 | 11 | 1 | 1 |
| Scalability (SCALE) | 9 | 0 | 4 | 5 | 0 | 0 |
| Frontend/UX (UX) | 27 | 2 | 6 | 18 | 1 | 0 |
| **Total** | **109** | **8** | **28** | **65** | **4** | **4** |

Duplicates named by the source documents (SEC-06 = BE-12, SEC-17 = OPS-10, SEC-18 ~ OPS-11,
SCALE-09 = BE-14, SCALE-04 = UX-19, SEC-09 ~ BE-06) are counted in both areas with the same status.
Items superseded inside the source set (BE-21, OPS-07 by the OBS-* file; BE-12, UX-19 point at
their twin) are marked Obsolete where the source itself says "track the work there".

## 2. Per-area tables

### 2.1 Security

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| SEC-01 | Real secrets in public staging example; no secret scanning; `git add -A` | Partial | Placeholders `CHANGE_ME_*` in `infrastructure/staging/.env.staging.example` (commit `212cb050`); `.env.staging`, `.env.local` ignored (`.gitignore:6-7`); `make commit` needs `FILES`, no `git add -A` (`scripts/commit.sh:11`). **Remains**: no gitleaks in `.github/workflows/ci.yml` or `.githooks/pre-push` (grep empty); old values still reachable in history (pre-`212cb050` versions of the file); rotation and "prod uses none of these" are ops steps not visible in code | P1 | S (gitleaks) + M (rotation, purge) | yes |
| SEC-02 | `version-config` guarded by internal token; any `download_url` | Partial | Dedicated `X-Admin-Token` (`services/api-gateway/cmd/main.go:105,226`; `internal/config/config.go:55-57`); https + host allowlist (`internal/version/version.go:123-136`); `VERSION_CONFIG_CHANGED` event (`65cb9457`). **Remains**: endpoint still internet-reachable (staging `Caddyfile` forwards every path; prod Caddy lives in the deploy repo, unverified); client opens any URL (`frontend/lib/screens/update_required_screen.dart:37,306`, no host check) | P2 | S | yes |
| SEC-03 | No password policy | Partial | `shared/infra/passwordpolicy` (`3bac6737`) used in Signup (covers owner-created employees) `services/auth-service/internal/handlers/auth.go:215` and ResetPassword `:3175`. **Remains**: client still validates and advertises 6 chars: `frontend/lib/screens/signup_screen.dart:246`, `employee_screen.dart:532`, `reset_password_new_screen.dart:182`, `frontend/lib/l10n/app_localizations_en.dart:429,1427,1746` | P2 | S | yes |
| SEC-04 | One HS256 secret in all services; no iss/aud | Open | `jwt.NewWithClaims(jwt.SigningMethodHS256, …)` `shared/infra/jwtutil/jwt.go:150`; HMAC-only check `:161`; `JWT_SECRET` read by auth, chat, notification, user `internal/config/config.go` | P2 | L | yes |
| SEC-05 | Refresh re-mints access token up to 7 d after expiry, old token not revoked, no limit | Open | `Refresh` `auth.go:1506-1571`: accepts `ErrExpiredToken` `:1533-1537`, 7-day window `:1540`, new token `:1561`, no `RevokeToken` of the presented token, no refresh-specific limiter (only the gateway per-IP budget) | P2 | M | yes |
| SEC-06 | Tokens in URLs/bodies; no auth middleware | Partial | Bearer header accepted first (AI_CONTEXT "Tokens in query strings" decision keeps `?token=` for WS/SSE and signed URLs: `services/chat-service/internal/handlers/chat.go:330`, `notification-service/internal/handlers/handlers.go:137`, `frontend/lib/providers/chat_provider.dart:132`). **Remains**: query fallbacks on non-stream endpoints `services/user-service/internal/handlers/jobs_handlers.go:643,887`, `ratings_handlers.go:164`, `auth.go:1459,3274`, `chat.go:433-436,977-980`; no shared auth middleware (no `authmw` in `shared/infra`) | P2 | L | yes |
| SEC-07 | Freezing an employee does not revoke sessions | Partial | Freeze revokes first, fails closed (`8d563c5e`, `auth.go:928`); same-second `<=` fix in jwtutil; reset and suspension also fail closed (SEC-07b, `1da5d069` and earlier). **Remains**: `ConfirmEmailChange` `auth.go:3598-3705` issues a fresh token (`:3694`) and never calls `RevokeAllUserTokens` (fix step 2) | P2 | S | yes |
| SEC-08 | Reviewer console must hold `INTERNAL_SERVICE_TOKEN` | Unclear | Still requires `X-Internal-Token` + `X-Reviewer-Token` (`auth.go:2699`, chat `admin_tickets.go:78`, user `reconciliation_handlers.go:266`); console gets the token as a server env var (`infrastructure/deploy/docker-compose.prod.yml:275`). Whether it reaches the browser is in the `kyc-reviewer-console` repo. Settle: read the console's server/proxy code | P2 | M | yes |
| SEC-09 | Cash fraud: no proof of delivery | Open | No delivery OTP/POD field in `services/user-service/internal/models/models.go`; reported cash accepted as-is and stored (`jobs_handlers.go:795-800`), no mismatch → reconciliation | P2 | M | yes |
| SEC-10 | Gateway port published; Caddy missing from compose | Open | Reference prod compose publishes `${API_GATEWAY_PORT}:${API_GATEWAY_PORT}` on all interfaces (`docker-compose.prod.yml:65-66`) and has no `caddy` service; ADR-0011 says Caddy is in compose. The real compose in `saas-core-deploy` was not checked | P1 | S | yes |
| SEC-11 | Broad `TRUSTED_PROXY_IPS`; first XFF entry trusted | Open | Default `127.0.0.1,::1,172.16.0.0/12,10.0.0.0/8` (`docker-compose.prod.yml:92`); first entry `services/api-gateway/internal/iputil/iputil.go:62-66`; services trust XFF with no proxy check `shared/infra/handlerutil/limiter.go:27-31`, `security_logs.go:215-221`; third helper `auth.go:1617`. AI_CONTEXT: needs trusted-proxy-count ADR | P2 | M | yes |
| SEC-12 | Per-email lockout lets anyone lock a user out | Open | Email-only key `auth.go:487-494` via `auth:email` limiter (`services/auth-service/internal/handlers/limiter.go:25`) | P3 | M | yes |
| SEC-13 | Internal errors leak to clients | Partial | `WriteSafeError` (generic message + code + `request_id`, `shared/infra/handlerutil/safe_errors.go:27-40`, `bd2250c8`), 195 call sites. **Remains**: 59 sites still put `err.Error()` in a client body, e.g. `chat-service/internal/handlers/admin_tickets.go:106,281,285`, `chat.go:1057`, `user-service/internal/handlers/admin_subscription_handlers.go:132`, `api-gateway/cmd/main.go:255`; some are curated validation errors (passwordpolicy), each needs a look | P3 | M | yes |
| SEC-14 | Secret strength not validated at startup | Open | Configs check non-empty only, e.g. `services/user-service/internal/config/config.go:28-35` | P2 | S | yes |
| SEC-15 | `dev_otp` gated only by `APP_ENV` | Partial | A5 guard refuses `APP_ENV=local` + `CLOUDWATCH_LOG_GROUP` (`services/auth-service/internal/config/config.go:136-138`). **Remains**: exposure still keyed on `APP_ENV` alone (`auth.go:98,382-395`), no `EXPOSE_DEV_OTP`; staging example ships `APP_ENV=local` (see N-02) | P3 | S | yes |
| SEC-16 | Employee accounts created with any email, no verification | Open | Owner-gated (`auth.go:267-330`) but "Employee signup — immediate creation, no OTP required" `auth.go:402` | P3 | M | yes |
| SEC-17 | All services use Mongo root | Open | One root URI `infrastructure/.env.example:29`, same `MONGO_URI` for every service in `docker-compose.prod.yml`; no `createUser` init script in repo | P1 | M | yes |
| SEC-18 | CA key on VM; 10-year certs; silent CA regeneration | Open | `infrastructure/deploy/deploy.yml:75-91` generates a CA and certs with `-days 3650` when `ca.key` is missing; keeps `ca.key` under `/home/deploybot/certs` (`:76`) | P3 | S (fail on missing) / M (rotation) | yes |

### 2.2 Backend

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| BE-01 | No dispatch / courier assignment | Done | Sequential accept/decline cascade (`48b5b985`): `findNextAvailableEmployee` + 60 s offer `jobs_handlers.go:316-349`; routes `services/user-service/internal/handlers/handlers.go:306-309`; available-employee query `:322`. No manual owner reassign endpoint, not needed for the claim | — | — | — |
| BE-02 | COD jobs become `active` with no courier | Done | No courier → `pending_dispatch` or `unavailable` (`jobs_handlers.go:316-349`); the COD activation at `:513-520` runs only when the owner supplied `EmployeeID`; accepted offers go active in `AcceptJobOffer` (`:2095`) | — | — | — |
| BE-03 | Thin job lifecycle, no status history | Open | Statuses `models.go:99-106` (no assigned/picked_up/in_transit/delivered); no `StatusHistory` or `CanTransition` (grep empty); client still shows "In Transit" (golden `job_status_mobile_360x800.png`) | P1 | L | yes |
| BE-04 | A job has a single location | Partial | `Destination` + `AddressNote` added (`models.go:126-147`, `2a3712d3` era). **Remains**: no recipient name/phone, parcel, notes, scheduled time | P1 | L | yes |
| BE-05 | Pricing uses company base → customer distance | Partial | Pickup → destination (`2a3712d3`, `jobs_handlers.go:430,2081`). **Remains**: straight-line only, no quote endpoint, float money | P2 | M | yes ($ if Google Distance Matrix; OSRM self-host is **tight**) |
| BE-06 | No proof of delivery | Open | Same evidence as SEC-09 | P2 | M | yes ($ for SMS) |
| BE-07 | Circular escrow; no payment gateway | Open | Deferred by decision (AI_CONTEXT "Payments", ADR-0002): COD only in production | P3 | L | $ |
| BE-08 | Paid tier never expires, unlocks little | Partial | `requireTier` rejects past `ExpiresAt` (`handlers.go:685-709`; changelog "requireTier Subscription Expiry Fail-Open Closure"); ADR-0024 closed status; console activation endpoint with security event (`admin_subscription_handlers.go:143`). **Remains**: no grace period, `requireTier` used in 4 places only (`handlers.go:709,743,808`, `jobs_handlers.go:1374`), no pre-expiry notices | P3 | M | yes |
| BE-09 | `SimulateEmployeeAction` in production | Unclear | Still registered `auth.go:145`, handler `:978`. Awaits owner decision (see §5); not ranked | — | — | — |
| BE-10 | Demo seed data in production; wrong 15 % log | Done | Gated by `SEED_DEMO_DATA=true` (`dc7cd544`, `services/user-service/internal/store/mongodb.go:199-200`); log says 0 % (`:195`). Deleting existing `tenant_id: "seed"` rows in prod is an ops step, not verifiable here | — | — | — |
| BE-11 | Verb-based API naming | Open | `handlers.go:296-305` (`/users/jobs/track`, `/get`, `/complete`, …) | P3 | L | yes |
| BE-12 | No auth middleware | Obsolete | Source says "same as SEC-06, do it once there"; tracked as SEC-06 (Partial) | — | — | — |
| BE-13 | Two error formats, leakage | Partial | `SafeError` envelope `{error, code, request_id}` (`safe_errors.go:27-31`); 363 sites still write bare `{"error": "..."}` maps; 59 leak `err.Error()` (SEC-13) | P3 | M | yes |
| BE-14 | No real pagination | Partial | `GetJobsByEmployee` now capped (`mongodb.go:423`); owner/customer still `SetLimit(100)` with no cursor (`:443,463`); ledger/payout lists take limit/offset (`:1281,1618`) | P2 | M | yes |
| BE-15 | No OpenAPI spec | Partial | No spec file in repo; `tools/docgen` generates the route table in `docs/APPLICATION_MAP.md` with a drift check (`make docs`), so routes vs docs is covered; no schema or client generation | P3 | L | yes |
| BE-16 | Service boundaries / naming | Open | Unchanged: user-service owns jobs, wallet, subscriptions, ratings (`handlers.go:296-339`) | P3 | L | yes |
| BE-17 | God files | Open | Grew: `auth.go` 3708 lines, `jobs_handlers.go` 3953, user `store/mongodb.go` 2283 (AI_CONTEXT refactor backlog item 3) | P3 | L | yes |
| BE-18 | Money as `float64` | Open | e.g. `models.go:153` `ActualCashAmount *float64`; `Deposit/LockEscrow(… amount float64)` `mongodb.go:959,990` | P2 | L | yes |
| BE-19 | Ledger not atomic with balances | Partial | Balances now from `FindOneAndUpdate(After)` (`mongodb.go:964-978,996-1009`, Q4 fix). **Remains**: ledger insert failure only logged (`:984,1018`), no transaction (needs OPS-03), no daily ledger-vs-balance check | P2 | M | yes |
| BE-20 | `log.Fatalf` in request handlers | Done | `8880c23c`; remaining `log.Fatalf` are constructor-time TLS client init (`auth.go:108`, `chat.go:85`, notification `handlers.go:58`, user `handlers.go:190`) | — | — | — |
| BE-21 | No observability | Obsolete | Superseded by OBS-03/04/07 (source `05-observability.md`) | — | — | — |
| BE-22 | No migrations | Open | Indexes/seeds at startup (`mongodb.go:72`); no migration tool or `schema_migrations` (grep empty) | P3 | M | yes |

### 2.3 Observability

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| OBS-01 | Security events dropped when CloudWatch is off | Partial | Every event is written to stdout as slog JSON first (`7e460315`, `shared/infra/handlerutil/security_logs.go:91-130`). **Remains**: no `security_events` collection, no startup line or prod preflight saying where events go; `event_kind` attribute not set (msg is `security_event`) | P3 | M | yes |
| OBS-02 | One goroutine + API call per event, unbounded | Done | Bounded queue (1000), single FIFO worker, drop counter (`security_logs.go:32,133-160`). No batching, by decision (AI_CONTEXT "CloudWatch shipping") | — | — | — |
| OBS-03 | No structured logging; `LOG_LEVEL` unused | Open | 350 `log.Print*` calls in non-test Go; `log/slog` only in `security_logs.go`; `LOG_LEVEL` is passed by compose (`docker-compose.prod.yml:83,…`) but no Go file reads it (grep empty) | P2 | L | yes |
| OBS-04 | No request ID / correlation | Partial | A `request_id` is generated per `WriteSafeError` and logged with it (`safe_errors.go:30,40`). **Remains**: no `X-Request-ID` middleware, nothing forwarded to internal calls (grep empty) | P2 | M | yes |
| OBS-05 | Gateway access log too thin | Open | `[TRAFFIC] method path → status (duration)` only (`services/api-gateway/internal/middleware/logging.go:105`) | P2 | S | yes |
| OBS-06 | Logs wiped each deploy; no aggregation | Open | `docker compose up -d --force-recreate --remove-orphans` (`deploy.yml:184`); no log shipper service, no `logging:` block in prod compose | P1 | M | $ / tight (Alloy agent RAM) |
| OBS-07 | No metrics | Open | No `/metrics`, no prometheus client (grep empty) | P2 | M | yes (backend $) |
| OBS-08 | No alerting / on-call | Open | Nothing in repo | P2 | M | $ |
| OBS-09 | No uptime / synthetic monitoring | Unclear | No scheduled workflow (`grep schedule: .github/workflows` empty) and no monitor config in repo; an external monitor may exist. Settle: check the UptimeRobot/Better Stack account. If absent: P1, S, $ (free tier) | P1 if absent | S | $ |
| OBS-10 | Frontend: no crash reporting | Open | No Sentry/Crashlytics, no `FlutterError.onError`/`PlatformDispatcher.instance.onError` (grep empty); 99 `debugPrint`/`print` in `frontend/lib` | P2 | M | $ (free tier) |
| OBS-11 | Dependency health not observable | Open | `/health` returns static `ok` in all five `cmd/main.go` (e.g. gateway `:74-82`); breaker stats only on token-gated `/health/internal` (`:85-99`) | P2 | S | yes |
| OBS-12 | No business metrics | Open | Depends on OBS-07; nothing exists | P3 | M | yes |
| OBS-13 | No distributed tracing | Open | No OpenTelemetry (grep `otel` empty) | P3 | L | tight / $ |
| OBS-14 | PII in logs | Open | 16 `log.Printf` lines with emails, e.g. `auth.go:373,386`, `services/auth-service/internal/otp/resend_dispatcher.go:77,83`; security event details embed emails (`auth.go:279-325`); `shared/infra/redact` has no email masker | P2 | S | yes |
| OBS-15 | Manual DB edits leave no audit | Partial | Subscription activation now via console endpoint with a security event (`admin_subscription_handlers.go:143`). **Remains**: `README.md:58,99` still documents manual `updateOne`; `cmd/approve-kyc` writes no audit record (grep empty); no `audit_events` collection | P2 | M | yes |
| OBS-16 | No product analytics | Open | No analytics package in `frontend/pubspec.yaml` | P3 | M | $ |
| OBS-17 | No profiling | Open | No `pprof` (grep empty) | P3 | S | yes |
| OBS-18 | No SLOs | Open | Depends on OBS-07 | P3 | S | yes |

### 2.4 DevOps

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| OPS-01 | KYC documents wiped on every deploy | Done | `documents_data:/app/data/documents` + `STORAGE_BASE_DIR` (`docker-compose.prod.yml:152,166,300`), attachments too (`:127`), commit `27a5040f`. Recovery for users who already lost files: not verifiable here | — | — | — |
| OPS-02 | No database backups | Open | No backup job in repo or `deploy.yml`; `docs/RUNBOOK.md:162` mentions `mongodump` only for migrations. A host cron outside the repo cannot be ruled out | P1 | M | $ (off-host storage) |
| OPS-03 | Mongo without replica set | Open | `mongo:7` with no `--replSet` (`docker-compose.prod.yml:18-30`); fallback log `mongodb.go:1031` | P1 | M | yes (single-node RS) |
| OPS-04 | No log rotation | Open | No `logging:` in prod compose (grep empty) | P1 | S | yes |
| OPS-05 | No resource limits | Open | No `mem_limit`/`cpus`/`GOMEMLIMIT` in prod compose (grep empty) | P1 | S | yes (needed most on 1 GB) |
| OPS-06 | `/health` superficial | Open | Static `/health` (see OBS-11); deploy probes `/health` with `curl -k` (`deploy.yml:217-222`); Dockerfile `HEALTHCHECK` chains four curls (`services/auth-service/Dockerfile:52`) | P2 | S | yes |
| OPS-07 | No metrics/alerts/uptime | Obsolete | Superseded by OBS-07/08/09 (source `05-observability.md`) | — | — | — |
| OPS-08 | Every deploy causes downtime | Open | `--force-recreate` (`deploy.yml:184,272`); no `stop_grace_period` | P2 | S | yes |
| OPS-09 | Self-hosted runner on prod VM | Open | `runs-on: [self-hosted, saas-vm]` (`deploy.yml:22`) | P3 | M | yes |
| OPS-10 | Services connect to Mongo as root | Open | Same as SEC-17 | P1 | M | yes |
| OPS-11 | Certificate management | Open | Same as SEC-18 | P3 | S/M | yes |
| OPS-12 | Dockerfile hygiene | Open | `RUN go mod download 2>/dev/null \|\| true` (`services/*/Dockerfile:14,29`); `curl` in prod image (`auth-service/Dockerfile:38`); `alpine:3.20` not digest-pinned; no Trivy in `build-and-publish.yml` | P3 | S | yes |
| OPS-13 | Version store in-memory | Unclear | `version.NewStore(nil, "")` (`services/api-gateway/cmd/main.go:69`). Open product decision (see §5); not ranked | — | — | — |
| OPS-14 | Reference compose drifted from real one | Open | Reference has no `caddy` (see SEC-10); no drift check in CI | P2 | M | yes |
| OPS-15 | `LOG_LEVEL`/`APP_ENV` in production | Partial | A5 guard (SEC-15) catches one bad combination. **Remains**: `--check-env` preflight (`deploy.yml:118-142`) does not reject `APP_ENV!=production`, `LOG_LEVEL=debug` or `SEED_DEMO_DATA=true` in prod | P2 | S | yes |

### 2.5 Scalability

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| SCALE-01 | No service can run >1 replica | Open | Fixed `container_name` on every service (`docker-compose.prod.yml:19,40,63,103,144,186,221,262`); gateway binds a host port | P3 | L | infra |
| SCALE-02 | 100/min per IP blocks CGNAT users | Partial | Raised to 300/min (`dab71b90`, `services/api-gateway/cmd/main.go:137`), separate SSE budget (`:145`), per-action limiters in user-service (ADR-0016, `services/user-service/internal/handlers/handlers.go:199-215`), keyed by IP for booking (`jobs_handlers.go:39`) and by user for completion (`:666`). **Remains**: still per IP at the gateway; no `Retry-After`/`RateLimit-*` headers (grep empty); no CGNAT load test | P2 | S | yes |
| SCALE-03 | Location history inside the job document | Partial | Job DTO no longer returns waypoints (only `WaypointsCount`, `models.go:676`). **Remains**: unbounded `$push` (`mongodb.go:1640-1642`); speed check sums all waypoints (`jobs_handlers.go:1434`) | P2 | M | yes |
| SCALE-04 | 5 s polling on top of WebSocket | Open | `_jobStatusPollingInterval = 5 s` (`frontend/lib/screens/job_status_screen.dart:81-85`); no `job.status_changed` publish (grep empty) | P2 | M | yes |
| SCALE-05 | Location throttle state in memory | Open | `locationLastUpdate`/`locationInFlight` maps (`services/user-service/internal/handlers/handlers.go:104-160`) | P3 | S | yes (matters only with >1 replica) |
| SCALE-06 | `ListServices` unbounded, bubble sort | Partial | `limit/offset` and 50 km default for `nearBy` (`mongodb.go:301-317`). **Remains**: nested-loop sort (`:346-352`), and it runs after `SetLimit/SetSkip`, so price order is per page only (N-01) | P2 | S | yes |
| SCALE-07 | Synchronous `checkKYC`; Redis SPOF | Open | `checkKYC` HTTP call, no cache (`handlers.go:541`); Redis has AOF (`docker-compose.prod.yml:48`) but no HA | P3 | M (cache) | infra (Redis HA) |
| SCALE-08 | Documents on local disk | Open | Deferred by decision (AI_CONTEXT "Object storage"); only the `Storage` interface exists (`shared/infra/storage/storage.go:21`) | P3 | M | $ |
| SCALE-09 | Lists capped at 100, no pagination | Partial | Same as BE-14 | P2 | M | yes |

### 2.6 Frontend / UX

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| UX-01 | Booking journey: one location, no recipient | Partial | Booking sends a destination and address note (`frontend/lib/providers/marketplace_provider.dart:69-75`). **Remains**: no recipient/parcel, no quote, no confirm screen; depends on BE-03/BE-04 | P1 | L | yes |
| UX-02 | Fake search bar on home | Done | Now an `InkWell` that opens the location picker with honest copy "Tap to set your pickup location" (`frontend/lib/screens/customer_home_screen.dart:393-418`, `app_en.arb:708`) | — | — | — |
| UX-03 | No address search; lat/lon typed by hand | Partial | `create_service_dialog.dart` is gone; owner config uses the map picker (`owner_configuration_screen.dart:207-212`, `4951fe4b`). **Remains**: no geocoding package in `pubspec.yaml`; Cairo defaults (`customer_marketplace_screen.dart:48`) | P2 | M | $ (Places) or yes (Nominatim with cache) |
| UX-04 | Shipping tile shows cleaning description | Open | `description: l10n.customerHomeTileCleaningDesc` (`customer_home_screen.dart:526`; `app_en.arb:1103`) | P1 | S | yes |
| UX-05 | Fake trend numbers | Open | `l10n.balanceTrendChipMock` (`wallet_screen.dart:208`), `l10n.jobsTrendChipMock` (`home_screen.dart:675`) | P1 | S | yes |
| UX-06 | Mixed `$` and "Credits", no `NumberFormat` | Open | `"\$…"` in `customer_jobs_screen.dart:372`, `customer_home_screen.dart:769`, `job_status_screen.dart:406,1028,1033`, `employee_jobs_screen.dart:179`, `owner_configuration_screen.dart:1272,1295,1333`; "Credits" `app_en.arb:238,390,994`; no `NumberFormat` in `lib/`; 53 `toStringAsFixed` | P1 | M | yes |
| UX-07 | Raw coordinates shown to users | Open | Courier card `job.location.formatCoordinates()` (`employee_jobs_screen.dart:1178,1496`; golden `employee_jobs_mobile_360x800.png` shows "30.0444, 31.2357"); `owner_configuration_screen.dart:798`; push text `Lat: %.4f, Lon: %.4f` (`jobs_handlers.go:2688,2694`) | P2 | M | yes |
| UX-08 | Heavy copy; empty notifications | Partial | "progressing as expected" no longer in code or ARB. **Remains**: `app_en.arb:982` ("Manage your operational tier…"), `:991` ("Manage corporate finances…"), `:1190` ("System Status: Operational.") | P3 | S | yes |
| UX-09 | Plan named "Paid", badge "PRO" | Open | Hard-coded `'BASIC' : 'PRO'` (`subscription_screen.dart:226`) vs `enumTierPaid: "Paid"`, `planProfessionalPaid` (`app_en.arb:550,558`) | P3 | S | yes |
| UX-10 | Overflow in courier card and itinerary | Done | Golden `employee_jobs_mobile_360x800.png`: chips ellipsize, no overflow stripe; golden `job_status_mobile_360x800.png`: itinerary line beside the text. Fixing commit not identified | — | — | — |
| UX-11 | Settings segmented controls break text | Open | `SegmentedButton` for theme and language (`settings_screen.dart:173,237`); golden `settings_screen_mobile_360x800.png` shows "Syste/m" and "Syste m def ault" | P2 | S | yes |
| UX-12 | Courier screen wastes prime space | Open | Golden `employee_jobs_mobile_360x800.png`: "Logged in as: Employee O…" card at the top | P2 | M | yes |
| UX-13 | Contradictory status timeline | Open | `matchingCourierLabel` "Matching courier..." under Assigned, `stepPendingDeliverySub` "Pending delivery" under Completed (`app_en.arb:873,885`); visible in golden `job_status_mobile_360x800.png` | P2 | S (copy) / L (real history, BE-03) | yes |
| UX-14 | Rating screen generic, card twice | Open | Golden `rating_screen_mobile_360x800.png`: "Driver / Employee" with "D/" avatar in two cards; `app_en.arb:913` | P2 | S | yes |
| UX-15 | Inconsistent button styles (ALL CAPS) | Open | `app_en.arb:35,64,121,132,151,157,158,163` ("LOG OUT", "SIGN IN", …); golden rating "SUBMIT RATING" with trailing icon. AI_CONTEXT: sentence-case proposal awaits a go | P3 | M | yes |
| UX-16 | Owner navigation hides core features | Open | Bottom nav Home/Employees/History/Settings (`home_screen.dart:263-281`); reconciliation behind `Icons.gavel_outlined` (`:233`) | P2 | M | yes |
| UX-17 | Login flashes on launch | Open | `home: auth.isAuthenticated ? HomeScreen() : LoginScreen()` ignores `isLoading` (`frontend/lib/main.dart:138`; `auth_provider.dart:48,74-75`) | P1 | S | yes |
| UX-18 | Booking happens in a dialog | Open | `showDialog` + `_BookingDialog` (`customer_marketplace_screen.dart:697,723`) | P2 | M | yes |
| UX-19 | Polling plus WebSocket | Obsolete | Source says "same as SCALE-04"; tracked there (Open) | — | — | — |
| UX-20 | Accessibility | Open | 2 `Semantics(` in `frontend/lib`; `otp_pin_input.dart` has one mention | P2 | M | yes |
| UX-21 | RTL | Open | 40 matches of `EdgeInsets.only(left/right)`, `Alignment.centerLeft/Right`, `left:/right:` in `lib/` (coarse grep, some may be fine) | P3 | M | yes |
| UX-22 | Static colors instead of theme | Partial | Now 579 `colorScheme.` vs 426 `AppColors.` in screens/widgets (was 18 vs 989); `ThemeExtension<AppSemanticColors>` exists (`frontend/lib/core/theme.dart:563`) | P3 | L | yes |
| UX-23 | Oversized screens | Open | Grew: `employee_jobs_screen.dart` 2033, `job_status_screen.dart` 1688, `home_screen.dart` 1467, `owner_configuration_screen.dart` 1364, `customer_marketplace_screen.dart` 1283 | P3 | L | yes |
| UX-24 | Release signed with debug key; applicationId | Open | `signingConfig = signingConfigs.getByName("debug")`, `applicationId = "com.saascore.frontend"` (`frontend/android/app/build.gradle.kts:19,32`); no `google-services.json`; no `Firebase.initializeApp` (`push_notification_service.dart:20`). The mobile-release repo may override; not checked | P1 | S (+ applicationId decision) | yes |
| UX-25 | Outdated dependencies | Open | `flutter_map ^7.0.2`, `firebase_messaging ^14.9.4`, `firebase_core ^2.32.0`, `geolocator ^12.0.0`, `flutter_lints ^3.0.0` (`pubspec.yaml:18,23,24,25,34`); no `.github/dependabot.yml` | P3 | M | yes |
| UX-26 | OSM tiles in production | Partial | Build-time override `String.fromEnvironment` (`frontend/lib/core/constants.dart:24-26`); default is still `tile.openstreetmap.org`; whether release builds set it is in the mobile-release repo | P2 | S | $ (tile provider free tier) |
| UX-27 | Review process | Partial | Goldens load the Poppins text font (`frontend/test/golden_screens_test.dart:588`). **Remains**: icon font still missing (squares in every golden); no PR template; no analytics (OBS-16) | P3 | S | yes |

## 3. Open and Partial, ranked

Sorted by severity, then effort. Items that should be one task are grouped; the suggested task
name is in bold. Unranked by design: BE-09, OPS-13 (decisions, §5); BE-07, SCALE-08 (deferred by
decision, listed at the end).

### P1

| # | Task (suggested) | Items | Sev | Effort | VM-fit | What to do |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | **OPS-COMPOSE-HARDEN** | OPS-04, OPS-05, SEC-10, OPS-08 | P1 | S | yes | Prod compose: `logging:` anchor, `mem_limit`/`cpus` + `GOMEMLIMIT`, gateway `expose` or `127.0.0.1` bind, `caddy` service, `stop_grace_period`, drop `--force-recreate`. Hot paths `infrastructure/**`; one task |
| 2 | **FE-QUICKWINS-CONTENT** | UX-04, UX-05, UX-17 | P1 | S | yes | Shipping tile key, remove mock trend chips, splash while `isLoading` |
| 3 | **SEC-GITLEAKS** | SEC-01 (scanning, history) | P1 | S | yes | gitleaks in `ci.yml` + `.githooks/pre-push` (CI parity rule); decide on history purge or private repo; rotation is an owner ops step |
| 4 | **FE-RELEASE-SIGNING** | UX-24 | P1 | S | yes | Release keystore via secrets, final `applicationId` (owner decision, cannot change later), Firebase config |
| 5 | **FE-MONEY-FORMAT** | UX-06 | P1 | M | yes | One `formatMoney` with `NumberFormat`, replace `$` and "Credits"; add a grep test |
| 6 | **OPS-MONGO-RS-USERS** | OPS-03, SEC-17/OPS-10, then BE-19 | P1 | M | yes | Single-node replica set + keyfile, per-service Mongo users; then make ledger writes transactional and fail loudly |
| 7 | **OPS-BACKUPS** | OPS-02 | P1 | M | $ | Daily encrypted `mongodump` + documents volume off-host, retention, restore drill, "no backup in 26 h" alert |
| 8 | **OBS-LOG-RETENTION** | OBS-06 | P1 | M | $ / tight | Log shipping agent to an external backend; keep local rotation (row 1) |
| 9 | **JOB-MODEL-V2** | BE-03, BE-04, UX-01, UX-13 (real history), OBS-12 later | P1 | L | yes | ADR first. Status machine + history, recipient/parcel fields, then the client journey |

### P2

| # | Task (suggested) | Items | Sev | Effort | VM-fit | What to do |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| 10 | **SEC-PW-CLIENT** | SEC-03 (client) | P2 | S | yes | Client validators and ARB hints to 8 chars (already an AI_CONTEXT open item) |
| 11 | **SEC-SESSION-GAPS** | SEC-07 (email change), SEC-14 | P2 | S | yes | Revoke on `ConfirmEmailChange`; startup secret length/prefix/distinctness checks in production |
| 12 | **SEC-VERSIONCFG-EDGE** | SEC-02 (remaining) | P2 | S | yes | Block `/api/v1/admin/*` at Caddy; host allowlist in `update_required_screen.dart` |
| 13 | **HEALTH-READY** | OPS-06, OBS-11 | P2 | S | yes | `/health/live` + `/health/ready` pinging Mongo/Redis; point Docker and deploy probes at it |
| 14 | **OPS-PREFLIGHT-PROD** | OPS-15, SEC-15 | P2 | S | yes | `--check-env` rejects non-production `APP_ENV`, `LOG_LEVEL=debug`, `SEED_DEMO_DATA=true`; dev OTP behind its own flag |
| 15 | **LIST-SERVICES-SORT** | SCALE-06, N-01 | P2 | S | yes | Sort in Mongo (aggregation) before skip/limit, or drop price sort across pages |
| 16 | **RL-HEADERS** | SCALE-02 (remaining) | P2 | S | yes | `Retry-After`/`RateLimit-Remaining`; per-user limit after auth at the gateway |
| 17 | **OBS-ACCESSLOG-PII** | OBS-05, OBS-14 | P2 | S | yes | Structured access line (route template, status, duration, upstream); mask emails in logs and event details |
| 18 | **FE-SETTINGS-RATING** | UX-11, UX-14 | P2 | S | yes | Language as list tile, theme labels that fit; rating screen with the real courier name, one card |
| 19 | **FE-UPDATE-TILES** | UX-26 | P2 | S | $ | Pick a tile provider, set the define in the release build |
| 20 | **OBS-LOGGING-FOUNDATION** | OBS-03, OBS-04, (SEC-13/BE-13 later) | P2 | L | yes | `shared/infra` slog logger honouring `LOG_LEVEL`, request-ID middleware + forwarding; then migrate `log.Printf` |
| 21 | **OBS-METRICS-ALERTS** | OBS-07, OBS-08, OBS-09 (if absent) | P2 | M | $ | `/metrics` on internal port, uptime check, a few alerts |
| 22 | **OBS-FE-CRASH** | OBS-10 | P2 | M | $ | Sentry or Crashlytics with error hooks |
| 23 | **OBS-AUDIT-CLI** | OBS-15 | P2 | M | yes | Audit record from `approve-kyc`; replace README manual `updateOne` sections |
| 24 | **REALTIME-STATUS** | SCALE-04, SCALE-03 | P2 | M | yes | Publish status changes on `job:<id>`, drop 5 s polling; cap waypoints / last-two-points speed check |
| 25 | **POD-CASH** | SEC-09, BE-06 | P2 | M | yes ($ for SMS) | Delivery code, cash mismatch to reconciliation |
| 26 | **FE-COORDS-NAV** | UX-07, UX-12, UX-16, UX-18, UX-03 | P2 | M | yes ($ geocoding) | Hide raw coordinates, courier home on the current job, owner nav, booking confirm screen, address search |
| 27 | **FE-A11Y** | UX-20 | P2 | M | yes | Semantics on stars, OTP, badges; tap-target guideline tests |
| 28 | **PAGINATION** | BE-14/SCALE-09 | P2 | M | yes | Cursor on `(created_at, _id)` for owner/customer/employee job lists (also `GetAuditLog`, AI_CONTEXT open item) |
| 29 | **OPS-COMPOSE-DRIFT** | OPS-14 | P2 | M | yes | Single source for the prod compose + CI diff (needs deploy-repo access) |
| 30 | **SEC-XFF** | SEC-11 | P2 | M | yes | ADR on trusted proxy count; gateway sets one client-IP header; one shared helper |
| 31 | **PRICING-ROAD** | BE-05 | P2 | M | tight / $ | Road distance and a quote endpoint (after JOB-MODEL-V2) |
| 32 | **SEC-REFRESH** | SEC-05 | P2 | M | yes | Separate rotating refresh token, reuse detection, rate limit (with SEC-04) |
| 33 | **SEC-AUTHMW** | SEC-06/BE-12, SEC-04 | P2 | L | yes | Shared auth middleware, drop `requester_id` query fallbacks; asymmetric signing + `iss`/`aud` |
| 34 | **MONEY-MINOR-UNITS** | BE-18 | P2 | L | yes | `int64` minor units + migration (needs BE-22) |

### P3

| # | Task (suggested) | Items | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 35 | **FE-COPY-PLAN** | UX-08, UX-09 | P3 | S | yes |
| 36 | **FE-GOLDEN-ICONS** | UX-27 | P3 | S | yes |
| 37 | **OPS-DOCKERFILE** | OPS-12 | P3 | S | yes |
| 38 | **OPS-CERTS** | SEC-18/OPS-11 | P3 | S/M | yes |
| 39 | **SCALE-THROTTLE-REDIS** | SCALE-05 | P3 | S | yes |
| 40 | **OBS-PPROF-SLO** | OBS-17, OBS-18 | P3 | S | yes |
| 41 | **OBS-SECEVENTS-STORE** | OBS-01 (remaining) | P3 | M | yes |
| 42 | **SEC-ERROR-SWEEP** | SEC-13, BE-13 | P3 | M | yes |
| 43 | **SEC-LOCKOUT-PAIR** | SEC-12 | P3 | M | yes |
| 44 | **SEC-EMPLOYEE-INVITE** | SEC-16 | P3 | M | yes |
| 45 | **SUB-TIER-MATRIX** | BE-08 | P3 | M | yes |
| 46 | **KYC-CACHE** | SCALE-07 | P3 | M | yes (Redis HA: infra) |
| 47 | **MIGRATIONS** | BE-22 | P3 | M | yes |
| 48 | **OPS-RUNNER** | OPS-09 | P3 | M | yes |
| 49 | **FE-BUTTONS-RTL** | UX-15, UX-21 | P3 | M | yes |
| 50 | **FE-DEPS** | UX-25 | P3 | M | yes |
| 51 | **OBS-ANALYTICS** | OBS-16 | P3 | M | $ |
| 52 | **SPLIT-GOD-FILES** | BE-17, UX-23, UX-22 | P3 | L | yes |
| 53 | **API-V1** | BE-11, BE-15, BE-16 | P3 | L | yes |
| 54 | **OBS-TRACING** | OBS-13 | P3 | L | tight / $ |
| 55 | **SCALE-REPLICAS** | SCALE-01 | P3 | L | infra |
| — | Deferred by decision | BE-07 (payments), SCALE-08 (object storage) | P3 | L / M | $ |

## 4. New findings (not in the source set)

| ID | Claim (short) | Status | Evidence (today) | Sev | Effort | VM-fit |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| N-01 | Price sort in `ListServices` runs after pagination, so "sort by price" is per page only | Open | `SetLimit(limit).SetSkip(offset)` then `Find` (`services/user-service/internal/store/mongodb.go:317-318`), Go nested-loop sort afterwards (`:346-352`); same pattern in `ListServicesOpenOnly` (`:368`) not re-checked line by line | P2 | S | yes |
| N-02 | Staging example enables local-only behaviour | Open | `APP_ENV=local`, `ALLOWED_ORIGIN=*`, `ALLOW_TEST_PAYMENT_BYPASS=true` in `infrastructure/staging/.env.staging.example`; with `APP_ENV=local` signup responses carry `dev_otp` (`auth.go:382-395`). Acceptable only while staging is never reachable from outside (latest commit binds Caddy to 127.0.0.1) | P3 | S | yes |
| N-03 | Client opens the server-supplied update URL without a host check | Open | `update_required_screen.dart:37,306` (part of SEC-02 step 5; called out because the server allowlist is the only guard) | P2 | S | yes |
| N-04 | `ConfirmEmailChange` leaves old sessions valid | Open | `auth.go:3598-3705` mints a token for the new email, no `RevokeAllUserTokens`; an attacker session survives an email takeover recovery (part of SEC-07 step 2) | P2 | S | yes |
| N-05 | Security event details embed raw `err.Error()` and emails | Open | `UNAUTHORIZED_EMPLOYEE_PROVISION_BLOCKED` details `auth.go:279,290,297,…` include the email and the JWT parse error; these now always reach stdout (OBS-01), widening OBS-14 | P3 | S | yes |
| N-06 | Several user-visible findings marked done by earlier audits are still visible in committed goldens | Open | UX-04/05/06/11/13/14 above, against AI_CONTEXT "Frontend UX behaviour audit 2026-09 … Done". Not necessarily a contradiction (different finding sets), but the owner should not read that row as "UX content is clean" | P3 | S (docs) | yes |

## 5. Known decisions (not raised as Open)

- **BE-09** `POST /auth/employee/action` (`SimulateEmployeeAction`, `auth.go:145,978`): stopped in
  P0-SRV, awaits the owner's choice (remove with the frontend button, or a fixed action enum).
- **OPS-13** version-config store: in-memory (`version.NewStore(nil, "")`,
  `services/api-gateway/cmd/main.go:69`) by an open product decision. The token gate (SEC-02) is settled.
- **govulncheck** stdlib findings warn locally and fail in CI, by decision (no item here depends on it).
- Also by decision, from AI_CONTEXT "Deferred by decision": tokens in query strings for WS/SSE/signed
  URLs (part of SEC-06), CloudWatch without batching (OBS-02), payments COD-only (BE-07),
  local-disk object storage (SCALE-08).
