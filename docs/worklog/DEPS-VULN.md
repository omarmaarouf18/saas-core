# Worklog: DEPS-VULN — triage and upgrade of Go dependency vulnerabilities

## Task and scope
- Task ID: DEPS-VULN
- Item IDs covered: phase 1 (steps 1-4) and phase 2 (steps 5-7), except x/crypto v0.56.0 (see Open questions).
- Allowed paths (lane from the task prompt): phase 1: `docs/security/VULN-TRIAGE-2026-10.md` and this worklog; no `go.mod`/`go.sum`. Phase 2: the `go.mod`/`go.sum` of affected modules, `go.work.sum`.
- Agent branch: agent/DEPS-VULN-go-deps-triage-upgrade, created from logic-exploitation (5a2bda66)

## Decisions taken
- Scanned each module twice: in workspace mode (as the gate runs it, `go.work` at the root) and with `GOWORK=off` (as `services/*/Dockerfile` builds the images). The two views differ; the module-mode view has called findings. Both are in the triage doc.
- The `GOWORK=off` scan of `tests/e2e` needed `GOFLAGS=-mod=mod` (its `go.mod` is not tidy and it has no `go.sum`); that scan rewrote `tests/e2e/go.mod` and created `tests/e2e/go.sum`. Both were reverted (`git checkout -- tests/e2e/go.mod`, `rm tests/e2e/go.sum`) before anything was committed; no `go.mod`/`go.sum` is changed on this branch.
- Plan aligns mongo-driver/v2 on v2.8.0 (the version the workspace already selects) instead of the minimum fix v2.4.2.

## Changes per commit (message only — NO SHAs)
1. `DEPS-VULN: govulncheck triage of Go dependencies (phase 1, docs only)`
2. `DEPS-VULN: worklog (phase 1)`
3. `DEPS-VULN: worklog: phase 2 blocked on JOB-V2-BE`
4. `DEPS-VULN: tidy tests/e2e go.mod and commit its go.sum`
5. `DEPS-VULN: align mongo-driver/v2 on v2.8.0 in every module (group 1)`
6. `DEPS-VULN: align x/crypto v0.54.0 and x/text v0.40.0 with the workspace (group 1)`
7. `DEPS-VULN: x/crypto v0.54.0 -> v0.55.0 and x/text v0.40.0 -> v0.41.0 (group 2)`
8. `DEPS-VULN: klauspost/compress v1.17.6 -> v1.18.7 (group 2)`
9. `DEPS-VULN: worklog (phase 2)`

## Verification

Scanner, `govulncheck -version` (cached v1.8.0 binary, `GOTOOLCHAIN=go1.26.10`):

```text
Go: go1.26.9-X:nodwarf5
Scanner: govulncheck@v1.8.0
DB: https://vuln.go.dev
DB updated: 2026-10-21 00:27:29 +0000 UTC
```

Summary lines of `govulncheck -show verbose ./...` per module, workspace mode (the gate's view). The `=== <module>` headers and the `exit=<code>` lines were added by the capture loop (`echo`); every other line is govulncheck's own output, filtered with `grep`:

```text
=== services_api-gateway
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 1 vulnerability in packages you import and 5
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== services_auth-service
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 1 vulnerability in packages you import and 5
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== services_chat-service
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 1 vulnerability in packages you import and 5
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== services_notification-service
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 1 vulnerability in packages you import and 5
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== services_user-service
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 1 vulnerability in packages you import and 5
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== shared_infra
No vulnerabilities found.
exit=0
=== tests_e2e
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 1 vulnerability in packages you import and 5
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== tests_contracts
No vulnerabilities found.
exit=0
=== tools_docgen
No vulnerabilities found.
exit=0
=== tools_paritycheck
No vulnerabilities found.
exit=0
```

Same scan with `GOWORK=off` (the image's view; `GOFLAGS=-mod=mod` set, see Decisions):

```text
=== services_api-gateway
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 2 vulnerabilities in packages you import and 22
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== services_auth-service
No vulnerabilities found.
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 6
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
=== services_chat-service
Your code is affected by 1 vulnerability from 1 module.
This scan also found 0 vulnerabilities in packages you import and 6
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=3
=== services_notification-service
Your code is affected by 2 vulnerabilities from 2 modules.
This scan also found 0 vulnerabilities in packages you import and 23
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=3
=== services_user-service
Your code is affected by 1 vulnerability from 1 module.
This scan also found 0 vulnerabilities in packages you import and 6
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=3
=== shared_infra
No vulnerabilities found.
exit=0
=== tests_e2e
Your code is affected by 2 vulnerabilities from 2 modules.
This scan also found 0 vulnerabilities in packages you import and 24
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=3
=== tests_contracts
No vulnerabilities found.
exit=0
=== tools_docgen
There are errors with the provided package patterns:
exit=1
=== tools_paritycheck
There are errors with the provided package patterns:
exit=1
```

`make check` before the triage-doc commit (last lines):

```text
[timing] total 20.4s
== pre-push gate: all checks passed (scope: docs infra-tests) ==
```

## Unverified
- The risk lines in the triage table ("we do not configure GSSAPI", "no wire compressors") rest on a grep of `*.go`, `*.yml`, `*.yaml`, `*.env*`, `*.tf` for `authMechanism|GSSAPI|compressors` (no hits). Connection strings held only in deployed secrets were not inspected.
- The module-mode numbers for `tests/e2e` depend on how `-mod=mod` resolved its untidy `go.mod`; they are not what any committed build uses.
- No image was built or scanned; the "image view" is `GOWORK=off` on the module source, matching what the Dockerfile copies.

## Follow-ups / out-of-lane findings
- `scripts/govulncheck-module.sh` scans in workspace mode, so the gate does not see the image's versions (today 3 called findings in module mode). See the triage doc, follow-up 1.
- `tests/e2e/go.mod` is not tidy and has no `go.sum`; `tools/docgen` and `tools/paritycheck` do not load with `GOWORK=off`.
- user-service uses mongo-driver v1 `mongo.IsDuplicateKeyError` on v2 errors; a chat-service test imports v1 without a `require`.

## Open questions
- Phase 2 needs the owner's "go phase 2"; no majors are proposed.
- Mongo target: v2.8.0 everywhere (proposed) or the minimum v2.4.2?
- tests/e2e: should phase 2 make it tidy and commit a `tests/e2e/go.sum` (needed for `go get`/`go mod tidy` to work in module mode), or only bump the `mongo-driver/v2` line?
- Gate follow-up 1 (`GOWORK=off` for services in `scripts/govulncheck-module.sh`): separate task, or in this lane?

## Phase 2 — blocker (lifted)
- Owner decisions on phase 1: go phase 2; mongo-driver/v2 target v2.8.0; tidy `tests/e2e` and commit its `go.sum` in its own commit before the upgrades; gate fix is a separate task (WF-GOWORK-OFF), `scripts/` not touched here; group 1 before group 2; no majors.
- Step 5 precondition failed: the branch is not behind logic-exploitation (local and origin tip are both the GO-1-26-10 merge, `git rev-list --count HEAD..logic-exploitation` = 0), but no JOB-V2-BE commit exists on any branch (`git log --all --oneline | grep -i JOB-V2-BE` prints nothing).
- Owner first chose "Stop and wait".
- **Lifted by owner decision:** JOB-V2-BE has not started and starts only after DEPS-VULN is merged, so there is no `go.mod` conflict. The branch stays on the tip of logic-exploitation (the GO-1-26-10 merge), no worktree recreation. Phase 2 ran on that base.

## Phase 2 — upgrades

### Decisions taken
- Order as agreed: tidy `tests/e2e` (own commit), group 1 (align each `go.mod` with the workspace build list), group 2 (new versions).
- chat-service: `go mod tidy` adds `go.mongodb.org/mongo-driver` v1 (imported by `internal/handlers/admin_tickets_test.go` without a `require`) and picked v1.17.10; pinned to v1.17.9, the version user-service and the workspace already use, so group 1 adds no version CI had not tested.
- Group 1 also moved `xdg-go/scram` v1.1.2 -> v1.2.0 and `x/sync` v0.11.0 -> v0.22.0 in the affected modules; both were already the workspace versions.
- **x/crypto stopped at v0.55.0, not v0.56.0.** v0.56.0 declares `go 1.26.0`; `go get` then rewrites the `go 1.26` line of every touched `go.mod` and `go.work` to `go 1.26.0` (and reorders `go.work`'s `use` block), and `bash scripts/check-go-version.sh` fails with `BLOCKED: Go language version drift in go.work: expected 1.26, found '1.26.0'` (same line for the 5 services and tests/e2e). Fixing that needs `scripts/` (out of lane, owner said do not touch) or a repo-wide `go` directive change, so the attempt was reverted and v0.55.0 (`go 1.25.0`, fixes GO-2026-6303) applied instead. GO-2026-6354/6355 (fixed in v0.56.0) stay as required-only findings.
- x/crypto v0.55.0 requires x/text v0.41.0, so those two are one commit.
- `tools/docgen` keeps its stray `golang.org/x/crypto v0.54.0 // indirect` line: it cannot run `go get`/`go mod tidy` outside the workspace (no `replace` for `shared/infra`), nothing in it imports x/crypto, and govulncheck reports nothing for it.
- `go.work` unchanged; `go.work.sum` gained 3 `/go.mod` hash lines (x/mod v0.38.0, x/net v0.57.0, x/tools v0.48.0), pulled by x/text v0.41.0 / x/crypto v0.55.0.

### Verification

Every touched module, after each `go get` + `go mod tidy`: `go build ./... && go vet ./...` in workspace mode and with `GOWORK=off`, printed `build+vet OK (workspace and GOWORK=off)` for api-gateway, auth-service, chat-service, notification-service, user-service and tests/e2e (the loop's own `echo`, printed only when all four commands succeeded).

Drift guard after the last bump, `bash scripts/check-go-version.sh`:

```text
Go version consistency: OK (GO_VERSION=1.26.10 from tools/versions.env)
```

`go test` per changed module, from the last `make check` (scope full, after the klauspost commit's tree; `grep` of its log):

```text
-- go test services/api-gateway: 2 unit (cached), 0 repo-reader (-count=1), 4 integration (-count=1) package(s) --
ok  	github.com/project/gateway/internal/config	(cached)
ok  	github.com/project/gateway/internal/iputil	(cached)
ok  	github.com/project/gateway/cmd	1.008s
ok  	github.com/project/gateway/internal/middleware	0.010s
ok  	github.com/project/gateway/internal/proxy	2.078s
ok  	github.com/project/gateway/internal/version	0.044s
-- go test services/auth-service: 6 unit (cached), 0 repo-reader (-count=1), 5 integration (-count=1) package(s) --
ok  	github.com/project/auth-service/internal/config	(cached)
ok  	github.com/project/auth-service/internal/models	(cached)
ok  	github.com/project/auth-service/internal/otp	(cached)
ok  	github.com/project/auth-service/internal/otpcrypto	(cached)
ok  	github.com/project/auth-service/internal/storage	(cached)
ok  	github.com/project/auth-service/cmd	0.003s
ok  	github.com/project/auth-service/cmd/approve-kyc	0.845s
ok  	github.com/project/auth-service/cmd/onboard-reviewer	0.892s
ok  	github.com/project/auth-service/internal/handlers	52.994s
ok  	github.com/project/auth-service/internal/store	7.533s
-- go test services/chat-service: 2 unit (cached), 0 repo-reader (-count=1), 4 integration (-count=1) package(s) --
ok  	github.com/project/chat-service/internal/config	(cached)
ok  	github.com/project/chat-service/cmd/onboard-agent	0.489s
ok  	github.com/project/chat-service/internal/chat	0.449s
ok  	github.com/project/chat-service/internal/handlers	27.873s
ok  	github.com/project/chat-service/internal/store	3.563s
-- go test services/notification-service: 3 unit (cached), 0 repo-reader (-count=1), 3 integration (-count=1) package(s) --
ok  	github.com/project/notification-service/internal/config	(cached)
ok  	github.com/project/notification-service/internal/fcm	(cached)
ok  	github.com/project/notification-service/internal/handlers	0.764s
ok  	github.com/project/notification-service/internal/hub	0.515s
ok  	github.com/project/notification-service/internal/store	2.819s
-- go test services/user-service: 3 unit (cached), 0 repo-reader (-count=1), 2 integration (-count=1) package(s) --
ok  	github.com/project/user-service/internal/config	(cached)
ok  	github.com/project/user-service/internal/models	(cached)
ok  	github.com/project/user-service/internal/handlers	181.734s
ok  	github.com/project/user-service/internal/store	30.623s
ok  	github.com/project/tests/contracts	0.035s
```

`make check` before each phase-2 commit passed with `scope: full` (every one touched a `go.mod`/`go.sum`/`go.work.sum`). Last lines of the final one (klauspost commit):

```text
[timing] flutter-analyze-test 49.5s
[timing] total 358.3s
== pre-push gate: all checks passed (scope: full) ==
```

govulncheck, before/after counts (called / imported / required):

| Module | Before, workspace | Before, GOWORK=off | After, workspace | After, GOWORK=off |
|---|---|---|---|---|
| services/api-gateway | 0 / 1 / 5 | 0 / 2 / 22 | 0 / 0 / 3 | 0 / 0 / 3 |
| services/auth-service | 0 / 1 / 5 | 0 / 0 / 6 | 0 / 0 / 3 | 0 / 0 / 3 |
| services/chat-service | 0 / 1 / 5 | 1 / 0 / 6 | 0 / 0 / 3 | 0 / 0 / 3 |
| services/notification-service | 0 / 1 / 5 | 2 / 0 / 23 | 0 / 0 / 3 | 0 / 0 / 3 |
| services/user-service | 0 / 1 / 5 | 1 / 0 / 6 | 0 / 0 / 3 | 0 / 0 / 3 |
| tests/e2e | 0 / 1 / 5 | 2 / 0 / 24 | 0 / 0 / 3 | 0 / 0 / 3 |
| shared/infra, tests/contracts | none | none | none | none |
| tools/docgen, tools/paritycheck | none | load error | none | load error (unchanged, no `replace`) |

The 3 remaining required IDs in every row: GO-2026-6355, GO-2026-6354 (fixed in x/crypto v0.56.0, see Open questions), GO-2026-5932 (no fix exists).

Final scan, literal summary per module (`govulncheck -show verbose ./...`; the `=== <mode> <module>` headers, `exit=<code>` and `IDs:` lines were added by the capture script, `ws` = workspace mode, `mod` = `GOWORK=off`; the rest is govulncheck output filtered with `grep`):

```text
=== ws services_api-gateway
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== ws services_auth-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== ws services_chat-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== ws services_notification-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== ws services_user-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== ws shared_infra
exit=0
No vulnerabilities found.
IDs: 
=== ws tests_contracts
exit=0
No vulnerabilities found.
IDs: 
=== ws tests_e2e
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== ws tools_docgen
exit=0
No vulnerabilities found.
IDs: 
=== ws tools_paritycheck
exit=0
No vulnerabilities found.
IDs: 
=== mod services_api-gateway
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== mod services_auth-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== mod services_chat-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== mod services_notification-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== mod services_user-service
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== mod shared_infra
exit=0
No vulnerabilities found.
IDs: 
=== mod tests_contracts
exit=0
No vulnerabilities found.
IDs: 
=== mod tests_e2e
Your code is affected by 0 vulnerabilities.
This scan also found 0 vulnerabilities in packages you import and 3
vulnerabilities in modules you require, but your code doesn't appear to call
these vulnerabilities.
exit=0
IDs: GO-2026-6355 GO-2026-6354 GO-2026-5932 
=== mod tools_docgen
There are errors with the provided package patterns:
exit=1
IDs: 
=== mod tools_paritycheck
There are errors with the provided package patterns:
exit=1
IDs: 
```

### Unverified
- tests/e2e tests were not run (they need the running stack; `make check` does not run them); for tests/e2e only build + vet in both modes were verified.
- Unit/integration tests ran in workspace mode only (`make check`); with `GOWORK=off` only `go build` + `go vet` ran, because raw `go test` against the shared Mongo/Redis is not allowed outside `make check`.
- No Docker image was built.

### Follow-ups
- x/crypto v0.56.0 (GO-2026-6354/6355), see Open questions.
- WF-GOWORK-OFF (owner-scheduled): run the gate's govulncheck with `GOWORK=off`; `tools/docgen`/`tools/paritycheck` still do not load in module mode.
- The phase-1 follow-up on mongo-driver v1 in user-service still stands; chat-service now requires v1 v1.17.9 explicitly for its test.

### Open questions (phase 2)
- x/crypto v0.56.0 needs `go 1.26.0` in every requiring `go.mod` and in `go.work`, which `scripts/check-go-version.sh` rejects (it requires exactly `go 1.26`). Options: (a) a separate task that changes the drift guard and the `go` directive repo-wide to `1.26.0`, then bumps x/crypto; (b) wait for a later x/crypto that the guard accepts (unlikely: x/ modules now track the newest Go release); (c) accept GO-2026-6354/6355 as required-only (no `x/crypto/ssh` import anywhere) until (a).
