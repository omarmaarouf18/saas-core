# Worklog: TST-01 — unique IDs for tests that use the real Redis

## Task and scope
- Task ID: TST-01
- Item IDs covered: 1 (testutil package), 2 (replace fixed IDs/keys/channels), 3 (concurrent isolation proof)
- Allowed paths (lane from the task prompt): the five real-Redis test files
  (`services/user-service/internal/handlers/adr0006_e2e_integration_test.go`,
  `adr0007_e2e_integration_test.go`, `adr0008_e2e_integration_test.go`,
  `services/chat-service/internal/chat/chat_docker_integration_test.go`,
  `services/notification-service/internal/hub/notification_docker_integration_test.go`),
  `shared/infra/testutil/**` (new), `docs/worklog/TST-01.md`.
- Agent branch: `agent/TST-01-test-isolation`, created from `logic-exploitation`
  (worktree was 2 commits behind at start; rebased onto current `logic-exploitation`
  before any change, so the branch diff contains only TST-01 work).
- Not touched: `tests/e2e` (staging, out of scope), `AI_CONTEXT.md`,
  `docs/changelog/**`, `docs/frontend/STATUS.md`, any `go.mod`/`go.sum`, `Makefile`.
- No `go.mod`/`go.sum` changes were needed: all three services already require
  `github.com/project/shared/infra` with `replace github.com/project/shared/infra => ../../shared/infra`,
  so a new package inside that module resolves without any dependency edit. The
  per-package fallback helper alternative was therefore not needed.

## Decisions taken
- `Suffix()` is computed once per process (`sync.Once`): `TEST_DB_SUFFIX` when set
  (the value `make ci`/the hook exports, e.g. `TST-01-12345`), else `<pid>-<UnixNano>`.
  Both the env value and every `ID()` result are sanitized to `[A-Za-z0-9_-]`.
- `ID(prefix)` = sanitized `prefix + "-" + Suffix()`.
- adr0006/0007: the sequential `X-Real-IP` values were replaced as well, because they
  double as Redis rate-limiter keys (`ratelimit:<prefix>:count:<ip>`); they now derive
  from `testutil.ID("rate-ip-e2e-adr000N")` plus a per-request counter.
- adr0008: `jobID` was suffixed too; it names the `job:<jobID>` pub/sub channel and the
  `loc:inflight:<jobID>` / `loc:lastupdate:<jobID>` Redis keys.
- Channel prefixes were kept (only the varying part is suffixed):
  `"job:" + testutil.ID(...)`, `"fleet:" + ownerID`, tenant ID suffixed
  (channel becomes `notify:tenant:<tenantID>`).
- Left unchanged: Mongo-only document IDs (service seeds `svc-*`, subscription
  `sub-e2e-adr0007`, `service-1`) — they live in the per-run Mongo database whose name
  already ends in `time.Now().UnixNano()` and are never used as Redis keys; JWT secrets,
  emails, `test-internal-token`, usernames, request paths, JSON field names — not Redis
  keys/channels. `tests/e2e` untouched (not in the gate).
- Keep prefix + suffix under 64 bytes if ever used in a Mongo DB name: current IDs are
  far below that (`owner-e2e-adr0006-TST-01-12345` is 33 bytes); no current Mongo DB
  name uses `testutil.ID`.

## Fixed literals per file (grep audit, item 2)
`adr0006_e2e_integration_test.go`:
- `"owner-e2e-adr0006"`, `"emp-e2e-adr0006"`, `"cust-e2e-adr0006"`, `"cust2-e2e"`,
  `"cust3-e2e"`, `"cust4-e2e"` — **changed** to `testutil.ID(...)` (owner/user/tenant IDs;
  `empID` names `loc:*:emp:<empID>` keys on the real-Redis fallback path).
- `"192.168.200.%d"` (X-Real-IP) — **changed** (`ratelimit:<prefix>:count:<ip>` Redis keys).
- `"svc-e2e-trans-80"`, `"svc-e2e-deliv-40"` — left, because Mongo document IDs in the
  per-run database; never used in Redis keys.
- `"saas_platform_e2e_adr0006_%d"` — left, because already unique per run (UnixNano).
- JWT secret, emails, `"test-internal-token"`, `"localhost:6379"`,
  `"mongodb://localhost:27017"`, `/users/jobs/*` — left, not keys/channels.

`adr0007_e2e_integration_test.go`: same pattern.
- `"owner-e2e-adr0007"`, `"emp-e2e-adr0007"`, `"cust-e2e-adr0007"`, `"cust2-adr0007"`,
  `"cust3-adr0007"` — **changed**.
- `"192.168.210.%d"` (X-Real-IP) — **changed** (same rate-limiter reason).
- `"sub-e2e-adr0007"`, `"svc-e2e-deliv-long"`, `"svc-e2e-deliv-std"` — left, Mongo-only
  in the per-run database.

`adr0008_e2e_integration_test.go`:
- `"owner-e2e-adr0008"`, `"emp-e2e-adr0008"`, `"cust-e2e-adr0008"` — **changed**.
- `"job-e2e-adr0008"` — **changed**: names the `job:<jobID>` channel and the
  `loc:*:<jobID>` keys.
- `"service-1"` — left, Mongo-only job field in the per-run database.

`chat_docker_integration_test.go`:
- `"job:real-cross-test"` — **changed** to `"job:" + testutil.ID("real-cross-test")`;
  the Redis topic becomes `chat:channel:job:real-cross-test-<suffix>`.
- `"client-instance-1"`, `"client-instance-2"`, `"Alice"`, `"Bob"`, message content —
  left, in-process only (no Redis key/channel).

`notification_docker_integration_test.go`:
- `"tenant-docker-cross"` — **changed** to `testutil.ID("tenant-docker-cross")`; it names
  the Redis channel `notify:tenant:<tenantID>`.
- `"sse-client-instance-1"`, `"sse-client-instance-2"`, titles/bodies — left, in-process.
- `notify:*` appears only in a comment; the production `PSubscribe("notify:*")` lives in
  `hub.go` and is not a test literal.

## Changes per commit (message only — NO SHAs)
1. `TST-01: add shared/infra/testutil for per-run test IDs` — new
   `shared/infra/testutil` package (`Suffix`, `ID`, `sanitize`) + unit tests
   (env wins; sanitization; stable within process; fallback without env; two env
   values give different IDs).
2. `TST-01: use per-run IDs/channels in real-Redis integration tests` — the five files.
3. `TST-01: worklog` — this file.

## Verification
- `gofmt -l .` (repo root) — empty.
- `go build ./...` + `go vet ./...` in `services/user-service`, `services/chat-service`,
  `services/notification-service`, `shared/infra` — PASS.
- `go test -count=1 ./...` in each touched module — PASS (user-service handlers 53.1s,
  chat handlers 32.9s, notification hub 0.5s, shared/infra incl. testutil — all `ok`).
- `make ci` before each commit — PASS, `== pre-push gate: all checks passed ==`.
- Item 3 proof: concurrent runs with `TEST_DB_SUFFIX=a` / `=b` (next section), plus a
  run with `TEST_DB_SUFFIX` unset showing the in-process fallback works.

## Item 3 proof — concurrent runs (literal)
Run outside the CI lock on purpose. Local services used, not started or reconfigured
here: compose Redis at `localhost:6380` (password `devpassword123`, AUTH probed +OK) and
Mongo at `localhost:27017`; `localhost:6379` is NOT running.

### a) user-service ADR tests (real Redis via REDIS_URI, per-run Mongo DBs), two suffixes concurrently
```
$ export MONGO_URI='mongodb://root:devpassword123@localhost:27017/saas_platform?authSource=admin'; export REDIS_URI='redis://:devpassword123@localhost:6380'
$ ( TEST_DB_SUFFIX=a go test -count=1 -v -run 'TestADR0006_E2E|TestADR0007_E2E|TestADR0008_E2E' ./... > /tmp/opencode/tst01-proof-us-a.log 2>&1; echo "A rc=$?" ) &
$ ( TEST_DB_SUFFIX=b go test -count=1 -v -run 'TestADR0006_E2E|TestADR0007_E2E|TestADR0008_E2E' ./... > /tmp/opencode/tst01-proof-us-b.log 2>&1; echo "B rc=$?" ) &
$ wait; echo "wait done"
B rc=0
A rc=0
wait done
```
Run A, complete `grep -E "^(--- PASS|--- FAIL|--- SKIP|PASS|FAIL|ok )"` output (literal):
```
PASS
ok  	github.com/project/user-service/internal/config	0.002s [no tests to run]
--- PASS: TestADR0006_E2E_NegotiableTransportPricing (1.41s)
--- PASS: TestADR0007_E2E_DeliveryGPSReconciliation (1.42s)
--- PASS: TestADR0008_E2E_LiveEmployeeMapTracking (1.25s)
PASS
ok  	github.com/project/user-service/internal/handlers	4.090s
PASS
ok  	github.com/project/user-service/internal/models	0.001s [no tests to run]
PASS
ok  	github.com/project/user-service/internal/store	0.003s [no tests to run]
```
Run A used suffix `a` (literal evidence from its log):
```
owner-e2e-adr0006-a
```
Run B, complete `grep -E "^(--- PASS|--- FAIL|--- SKIP|PASS|FAIL|ok )"` output (literal):
```
PASS
ok  	github.com/project/user-service/internal/config	0.003s [no tests to run]
--- PASS: TestADR0006_E2E_NegotiableTransportPricing (1.38s)
--- PASS: TestADR0007_E2E_DeliveryGPSReconciliation (1.42s)
--- PASS: TestADR0008_E2E_LiveEmployeeMapTracking (1.27s)
PASS
ok  	github.com/project/user-service/internal/handlers	4.082s
PASS
ok  	github.com/project/user-service/internal/models	0.001s [no tests to run]
PASS
ok  	github.com/project/user-service/internal/store	0.003s [no tests to run]
```
Run B used suffix `b` (literal evidence from its log):
```
owner-e2e-adr0006-b
```

### b) chat-service docker integration package, two suffixes concurrently
```
$ ( TEST_DB_SUFFIX=a go test -count=1 -v -run 'TestRealDockerRedis_MultiInstanceChatHub' ./internal/chat/ > /tmp/opencode/tst01-proof-chat-a.log 2>&1; echo "A rc=$?" ) &
$ ( TEST_DB_SUFFIX=b go test -count=1 -v -run 'TestRealDockerRedis_MultiInstanceChatHub' ./internal/chat/ > /tmp/opencode/tst01-proof-chat-b.log 2>&1; echo "B rc=$?" ) &
$ wait; echo "wait done"
A rc=0
B rc=0
wait done
```
Run A literal output (the test skips because its client never sends the Redis password —
pre-existing, unchanged by this task; `NOAUTH Authentication required.`):
```
=== RUN   TestRealDockerRedis_MultiInstanceChatHub
    chat_docker_integration_test.go:29: Skipping real Docker Redis integration test: Redis not reachable at localhost:6380 (NOAUTH Authentication required.)
--- SKIP: TestRealDockerRedis_MultiInstanceChatHub (0.00s)
PASS
ok  	github.com/project/chat-service/internal/chat	0.003s
```
Run B literal output:
```
=== RUN   TestRealDockerRedis_MultiInstanceChatHub
    chat_docker_integration_test.go:29: Skipping real Docker Redis integration test: Redis not reachable at localhost:6380 (NOAUTH Authentication required.)
--- SKIP: TestRealDockerRedis_MultiInstanceChatHub (0.00s)
PASS
ok  	github.com/project/chat-service/internal/chat	0.003s
```
The channel rename in this file is not exercised against this environment's real Redis;
see Unverified.

### c) notification-service docker integration package, two suffixes concurrently
```
$ ( TEST_DB_SUFFIX=a go test -count=1 -v -run 'TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution' ./internal/hub/ > /tmp/opencode/tst01-proof-notif-a.log 2>&1; echo "A rc=$?" ) &
$ ( TEST_DB_SUFFIX=b go test -count=1 -v -run 'TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution' ./internal/hub/ > /tmp/opencode/tst01-proof-notif-b.log 2>&1; echo "B rc=$?" ) &
$ wait; echo "wait done"
B rc=0
A rc=0
wait done
```
Run A, complete `grep -E "Client registered|→ [01] local clients|--- PASS|^PASS$|^ok "` output
(literal). Each hub's `PSubscribe("notify:*")` demonstrably received the other run's
messages (`tenant-docker-cross-b`) and delivered 0 local clients, while A's own messages
hit 1 client (duplicate `→ 1 local clients` lines are real: both hubs log the delivery):
```
2026/10/16 16:46:16 [SSE-HUB] Client registered: id=sse-client-instance-1 tenant=tenant-docker-cross-a role=owner (total: 1)
2026/10/16 16:46:16 [SSE-HUB] Client registered: id=sse-client-instance-2 tenant=tenant-docker-cross-a role=owner (total: 1)
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-a → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-a → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-b → 0 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-b → 0 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=status_update tenant=tenant-docker-cross-a → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=status_update tenant=tenant-docker-cross-a → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=status_update tenant=tenant-docker-cross-b → 0 local clients
--- PASS: TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution (0.00s)
    --- PASS: TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution/Q18_Resolution:_Local_delivery_succeeds_immediately_even_if_subscriber_loop_closes (0.00s)
PASS
ok  	github.com/project/notification-service/internal/hub	0.004s
```
Run B, complete same grep output (literal), mirrored:
```
2026/10/16 16:46:16 [SSE-HUB] Client registered: id=sse-client-instance-1 tenant=tenant-docker-cross-b role=owner (total: 1)
2026/10/16 16:46:16 [SSE-HUB] Client registered: id=sse-client-instance-2 tenant=tenant-docker-cross-b role=owner (total: 1)
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-b → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-a → 0 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-a → 0 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=job_alert tenant=tenant-docker-cross-b → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=status_update tenant=tenant-docker-cross-b → 1 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=status_update tenant=tenant-docker-cross-a → 0 local clients
2026/10/16 16:46:16 [SSE-HUB] Broadcast: type=status_update tenant=tenant-docker-cross-b → 1 local clients
--- PASS: TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution (0.00s)
    --- PASS: TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution/Q18_Resolution:_Local_delivery_succeeds_immediately_even_if_subscriber_loop_closes (0.00s)
PASS
ok  	github.com/project/notification-service/internal/hub	0.004s
```

### d) fallback without TEST_DB_SUFFIX (item 3, last sentence)
user-service (in `services/user-service`; MONGO_URI/REDIS_URI exported as above):
```
$ env -u TEST_DB_SUFFIX go test -count=1 -v -run 'TestADR0006_E2E|TestADR0007_E2E|TestADR0008_E2E' ./internal/handlers/ > /tmp/opencode/tst01-proof-us-fallback.log 2>&1
$ echo "fallback rc=$?"
fallback rc=0
$ grep -E "^(--- PASS|--- FAIL|--- SKIP|PASS|FAIL|ok )" /tmp/opencode/tst01-proof-us-fallback.log
--- PASS: TestADR0006_E2E_NegotiableTransportPricing (1.95s)
--- PASS: TestADR0007_E2E_DeliveryGPSReconciliation (0.94s)
--- PASS: TestADR0008_E2E_LiveEmployeeMapTracking (0.79s)
PASS
ok  	github.com/project/user-service/internal/handlers	3.686s
$ grep -o "owner-e2e-adr0006-[0-9]*-[0-9]*" /tmp/opencode/tst01-proof-us-fallback.log | sort -u | head -2
owner-e2e-adr0006-435490-1792158393009298045
```
The suffix above is the in-process fallback `<pid>-<UnixNano>`.
notification-service (in `services/notification-service`):
```
$ env -u TEST_DB_SUFFIX go test -count=1 -v -run 'TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution' ./internal/hub/ > /tmp/opencode/tst01-proof-notif-fallback.log 2>&1
$ echo "fallback rc=$?"
fallback rc=0
$ grep -E "^(--- PASS|--- FAIL|--- SKIP|PASS|FAIL|ok )" /tmp/opencode/tst01-proof-notif-fallback.log
--- PASS: TestRealDockerRedis_MultiInstanceSSEHubAndQ18Resolution (0.00s)
PASS
ok  	github.com/project/notification-service/internal/hub	0.005s
$ grep -o "tenant-docker-cross-[0-9]*-[0-9]*" /tmp/opencode/tst01-proof-notif-fallback.log | sort -u | head -2
tenant-docker-cross-436757-1792158400293139176
```

## Final report evidence (task items 2–5)
Item 2 — `git log --oneline logic-exploitation..HEAD` (literal; short SHAs, per the
no-full-SHA rule):
```
224d0d96 TST-01: use per-run IDs/channels in real-Redis integration tests
e91b40a8 TST-01: add shared/infra/testutil for per-run test IDs
```
Item 3 — `git diff --stat logic-exploitation..HEAD` (literal; taken before the worklog
commit, so this file is not listed yet):
```
 .../internal/chat/chat_docker_integration_test.go  |  11 ++-
 .../hub/notification_docker_integration_test.go    |  16 +++-
 .../handlers/adr0006_e2e_integration_test.go       |  18 ++--
 .../handlers/adr0007_e2e_integration_test.go       |  16 ++--
 .../handlers/adr0008_e2e_integration_test.go       |   9 +-
 shared/infra/testutil/testutil.go                  |  56 +++++++++++
 shared/infra/testutil/testutil_test.go             | 102 +++++++++++++++++++++
 7 files changed, 204 insertions(+), 24 deletions(-)
```
Item 4 — the concurrent run output: section "Item 3 proof" above.
Item 5 — last lines of the `make ci` run immediately before the code commit at the time
this file was written (the worklog-commit gate run is the true final one and its tail is
in the chat report; this file was frozen before that run):
```
00:32 +781: /home/omarmaarouf/CS tools/Antigravity/saas-core-wt/TST-01/frontend/test/golden_screens_test.dart: (tearDownAll)
00:32 +781: All tests passed!
== pre-push gate: all checks passed ==
```

## Unverified
- The chat-service docker integration test never ran against real Redis in this
  environment (it skips: its `redis.NewClient` sends no password while the local Redis
  requires AUTH — pre-existing, unrelated to this change). So its new per-run channel
  name is compile-verified and mirrors the notification hub path that IS proven above,
  but not observed end-to-end against a real Redis. It also skips in `make ci` here.
- The two concurrent ADR runs overlapped in time (both logs start 16:46:16), but the
  overlap window is short (~1.5-4 s of test time); the proof is the two literal runs
  with different IDs and both PASS, not a long fuzz-style soak.
- No experiment with two *full concurrent* `make ci` gates (the CI lock serializes
  them by design; relaxing it is an owner decision, see Open questions).

## Follow-ups / out-of-lane findings
- `chat_docker_integration_test.go` cannot run against the local compose Redis because
  it never passes `REDIS_PASSWORD` (the notification twin does, default
  `devpassword123`). A one-line option change would let it run locally; left alone here
  to keep the diff scoped to unique IDs. Worth a separate small task.
- `tests/e2e` still uses fixed staging DBs (`staging_auth_db`, `staging_user_db`) and
  Redis `:6381`; out of scope per the task prompt (not in the gate).
- Mongo DB names built from `testutil.ID(...)` would need prefix+suffix < 64 bytes;
  current longest ID in play is ~33 bytes, so no risk yet (noted for future use).

## Open questions
1. Can the CI lock be relaxed now? Evidence from this task: the only gate-run tests
   that touch shared real Redis were these five files (WF-01 §4 audit); they now use
   per-run Mongo DB names, Redis keys, rate-limit keys and pub/sub channels. The chat
   docker test skips here; the notification docker test demonstrably isolates by tenant.
   Remaining shared state: Mongo/Redis load itself, and `tests/e2e` (not in the gate).
   Recommendation: keep the lock until a dedicated two-concurrent-`make ci` experiment
   passes deliberately (currently impossible from a worktree by design).
2. Should the chat docker test get the same `REDIS_PASSWORD` handling as the
   notification one, so it actually runs against the dev compose Redis?
3. Is the X-Real-IP replacement (rate-limit keys now suffix-derived, not IP-shaped)
   acceptable, or do you want IP-shaped values kept with a different uniqueness scheme?
