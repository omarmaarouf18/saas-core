# Worklog: DEPS-VULN — triage and upgrade of Go dependency vulnerabilities

## Task and scope
- Task ID: DEPS-VULN
- Item IDs covered: phase 1 (steps 1-4). Phase 2 (steps 5-7) waits for the owner's "go phase 2".
- Allowed paths (lane from the task prompt): phase 1: `docs/security/VULN-TRIAGE-2026-10.md` and this worklog; no `go.mod`/`go.sum`. Phase 2: the `go.mod`/`go.sum` of affected modules, `go.work.sum`.
- Agent branch: agent/DEPS-VULN-go-deps-triage-upgrade, created from logic-exploitation (5a2bda66)

## Decisions taken
- Scanned each module twice: in workspace mode (as the gate runs it, `go.work` at the root) and with `GOWORK=off` (as `services/*/Dockerfile` builds the images). The two views differ; the module-mode view has called findings. Both are in the triage doc.
- The `GOWORK=off` scan of `tests/e2e` needed `GOFLAGS=-mod=mod` (its `go.mod` is not tidy and it has no `go.sum`); that scan rewrote `tests/e2e/go.mod` and created `tests/e2e/go.sum`. Both were reverted (`git checkout -- tests/e2e/go.mod`, `rm tests/e2e/go.sum`) before anything was committed; no `go.mod`/`go.sum` is changed on this branch.
- Plan aligns mongo-driver/v2 on v2.8.0 (the version the workspace already selects) instead of the minimum fix v2.4.2.

## Changes per commit (message only — NO SHAs)
1. `DEPS-VULN: govulncheck triage of Go dependencies (phase 1, docs only)`
2. `DEPS-VULN: worklog (phase 1)`

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
