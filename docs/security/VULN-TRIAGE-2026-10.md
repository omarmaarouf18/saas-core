# Go dependency vulnerability triage — 2026-10

Task DEPS-VULN, phase 1 (triage only; no `go.mod`/`go.sum` changed).

Scanner: `govulncheck@v1.8.0` (pin from `tools/versions.env`), Go `go1.26.10`,
vuln DB updated `2026-10-21 00:27:29 +0000 UTC`. Command, in every module
directory: `govulncheck -show verbose ./...`.

## Key finding: the gate and the images see different versions

The repo root has a `go.work` that `use`s all 10 modules. Run from a module
directory, govulncheck (and `scripts/govulncheck-module.sh`, the gate step)
runs in **workspace mode**: Go picks, for each dependency, the highest version
any module in the workspace requires. That is why all 5 services and
`tests/e2e` report the same "1 imported / 5 required" result.

The service images are built **without** `go.work`: `services/*/Dockerfile`
copies only `shared/infra` and the service's own `go.mod`/`go.sum`, so the
binary is built from that module's own requirements. Those are older in
several modules. The same scan with `GOWORK=off` (module mode, what the
images ship) shows more findings, and four modules have vulnerabilities their
code **does** call:

| Module | Workspace mode (gate today) | Module mode (`GOWORK=off`, = image) |
|---|---|---|
| services/api-gateway | 0 called, 1 imported, 5 required, exit 0 | 0 called, 2 imported, 22 required, exit 0 |
| services/auth-service | 0 called, 1 imported, 5 required, exit 0 | 0 called, 0 imported, 6 required, exit 0 |
| services/chat-service | 0 called, 1 imported, 5 required, exit 0 | **1 called** (GO-2026-5327), 0 imported, 6 required, exit 3 |
| services/notification-service | 0 called, 1 imported, 5 required, exit 0 | **2 called** (GO-2026-5327, GO-2026-5970), 0 imported, 23 required, exit 3 |
| services/user-service | 0 called, 1 imported, 5 required, exit 0 | **1 called** (GO-2026-5327), 0 imported, 6 required, exit 3 |
| shared/infra | none, exit 0 | none, exit 0 |
| tests/e2e | 0 called, 1 imported, 5 required, exit 0 | **2 called** (GO-2026-5327, GO-2026-5970), 0 imported, 24 required, exit 3 (see note) |
| tests/contracts | none, exit 0 | none, exit 0 |
| tools/docgen | none, exit 0 | load error: no `replace` for `shared/infra`, only builds in the workspace |
| tools/paritycheck | none, exit 0 | load error: no `replace` for `shared/infra`, only builds in the workspace |

Note on `tests/e2e`: it has no committed `go.sum` and its `go.mod` is not tidy
(it lacks `require` lines for `go-redis` and every indirect dependency), so it
only builds inside the workspace. The module-mode numbers above come from a
scan run with `GOFLAGS=-mod=mod`, which resolved the missing requirements
through `mongo-driver/v2 v2.0.0` (`x/crypto v0.29.0`, `x/text v0.20.0`); the
`go.mod` edit that scan made was reverted. e2e is not shipped in an image, so
this view matters less for it.

The "called" traces all start at `mongo.Connect` (for example
`internal/store/mongodb.go:60:30: store.NewMongoDB calls mongo.Connect, which
eventually calls norm.Form.String` in notification-service).

## Dependency versions per module (from each `go.mod`)

| Module | mongo-driver/v2 | x/crypto | x/text | klauspost/compress |
|---|---|---|---|---|
| services/api-gateway | v2.8.0 direct | v0.33.0 indirect | v0.22.0 indirect | v1.17.6 indirect |
| services/auth-service | v2.4.2 direct | v0.54.0 **direct** (bcrypt) | v0.40.0 indirect | v1.16.7 indirect |
| services/chat-service | v2.2.1 direct | v0.54.0 indirect | v0.40.0 indirect | v1.16.7 indirect |
| services/notification-service | v2.2.1 direct | v0.33.0 indirect | v0.22.0 indirect | v1.16.7 indirect |
| services/user-service | v2.2.1 direct (+ v1 `mongo-driver v1.17.9` direct) | v0.54.0 indirect | v0.40.0 indirect | v1.16.7 indirect |
| tests/e2e | v2.0.0 direct | not listed | not listed | not listed |
| tools/docgen | — | v0.54.0 indirect | — | — |
| shared/infra, tests/contracts, tools/paritycheck | — | — | — | — |
| **Workspace build list** (what CI tests run against) | v2.8.0 | v0.54.0 | v0.40.0 | v1.17.6 |

Every one of these four modules comes in through the Mongo driver
(`mongo-driver/v2 -> x/mongo/driver -> klauspost/compress/snappy`;
`-> x/mongo/driver/auth -> xdg-go/stringprep -> x/text/unicode/norm`;
`-> scram/pbkdf2 -> x/crypto`), plus auth-service's direct use of
`x/crypto/bcrypt`. None of our code imports `x/crypto/ssh` or `x/crypto/openpgp`.

## Triage table (one row per vulnerability ID)

"Ours" lists which of our modules have the vulnerable version, in workspace
mode (W) and module/image mode (M). "Level" is the strongest govulncheck level
seen: called > imported > required. No fix needs a major-version jump; all
fixes are minor/patch bumps within the current major.

| ID | Module | Current | Fixed in | Ours (W / M) | Level | Fix? | Major? | Risk for us |
|---|---|---|---|---|---|---|---|---|
| GO-2026-5327 | go.mongodb.org/mongo-driver/v2 (heap OOB read in GSSAPI error handling) | v2.2.1 (chat, notif, user), v2.0.0 (e2e) | v2.4.2 | W: none / M: chat, notification, user, e2e | **called** | yes | no | Reachable from `mongo.Connect`, but only triggers with GSSAPI (Kerberos) auth, which we do not configure; still the top item because it is a called finding in 3 shipped images. |
| GO-2026-5970 | golang.org/x/text (infinite loop on invalid input) | v0.22.0 (api-gw, notif), v0.20.0 (e2e) | v0.39.0 | W: none / M: notification, e2e (called), api-gateway (imported) | **called** | yes | no | Reached via SCRAM `stringprep` normalising the Mongo credentials at connect; input is our own config, so a DoS needs a bad secret, but it is a called finding in the notification image. |
| GO-2026-5841 | github.com/klauspost/compress (OOB read in `s2`) | v1.17.6 (api-gw), v1.16.7 (others) | v1.18.7 | W: all 5 services + e2e (imported) / M: api-gateway imported, others required | imported | yes | no | We import `compress/snappy` via the Mongo driver, not `s2`, and configure no wire compressors; low. |
| GO-2026-6629 | golang.org/x/text (panic in `secure/precis`) | v0.40.0, v0.22.0, v0.20.0 | v0.41.0 | W: all 5 services + e2e / M: same | required | yes | no | We never import `precis`; low. |
| GO-2026-6355 | golang.org/x/crypto (`ssh`: DoS on deadlocked established channel) | v0.54.0, v0.33.0, v0.29.0 | v0.56.0 | W: all 5 + e2e / M: same | required | yes | no | No SSH code; low. |
| GO-2026-6354 | golang.org/x/crypto (`ssh`: DoS on deadlocked undecided channel) | same | v0.56.0 | W: all 5 + e2e / M: same | required | yes | no | No SSH code; low. |
| GO-2026-6303 | golang.org/x/crypto (`ssh`: source-address option not enforced) | same | v0.55.0 | W: all 5 + e2e / M: same | required | yes | no | No SSH code; low. |
| GO-2026-5932 | golang.org/x/crypto (`openpgp` unmaintained, unsafe by design) | all versions | **N/A** | W: all 5 + e2e / M: same | required | **no** | — | We never import `openpgp`; it cannot be cleared by any upgrade and stays listed while we require `x/crypto` at all. |
| GO-2026-5033 | golang.org/x/crypto (`ssh`: pathological inputs panic client) | v0.33.0 (api-gw, notif), v0.29.0 (e2e) | v0.52.0 | W: none / M: api-gateway, notification, e2e | required | yes | no | No SSH code; low. |
| GO-2026-5023 | golang.org/x/crypto (`ssh`: VerifiedPublicKeyCallback permissions skip) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5021 | golang.org/x/crypto (`ssh`: `@revoked` not enforced) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5020 | golang.org/x/crypto (`ssh`: infinite loop on large channel writes) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5019 | golang.org/x/crypto (`ssh`: FIDO/U2F physical-interaction bypass) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5018 | golang.org/x/crypto (`ssh`: pathological RSA/DSA params DoS) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5017 | golang.org/x/crypto (`ssh`: server deadlock on unexpected responses) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5016 | golang.org/x/crypto (`ssh`: memory leak rejecting channels) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5015 | golang.org/x/crypto (`ssh`: server panic in CheckHostKey/Authenticate) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5014 | golang.org/x/crypto (`ssh`: certificate restriction bypass) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5013 | golang.org/x/crypto (`ssh`: byte arithmetic underflow panic) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2026-5006 | golang.org/x/crypto (`ssh/agent`: constraints dropped when forwarding) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH agent code; low. |
| GO-2026-5005 | golang.org/x/crypto (`ssh/agent`: key constraints not enforced) | same | v0.52.0 | M only, same 3 | required | yes | no | No SSH agent code; low. |
| GO-2025-4135 | golang.org/x/crypto (`ssh/agent`: malformed constraint DoS) | same | v0.45.0 | M only, same 3 | required | yes | no | No SSH agent code; low. |
| GO-2025-4134 | golang.org/x/crypto (`ssh`: unbounded memory) | same | v0.45.0 | M only, same 3 | required | yes | no | No SSH code; low. |
| GO-2025-4116 | golang.org/x/crypto (`ssh/agent`: DoS) | same | v0.43.0 | M only, same 3 | required | yes | no | No SSH agent code; low. |
| GO-2025-3487 | golang.org/x/crypto (potential denial of service) | same | v0.35.0 | M only, same 3 | required | yes | no | No code path we know of reaches it; low. |
| GO-2024-3321 | golang.org/x/crypto (misuse of `connection.serverAuthenticate` may cause authorization bypass) | v0.29.0 (e2e) | v0.31.0 | M only, e2e | required | yes | no | Test-only module, no SSH code; low. |

Latest versions available at triage time (`go list -m -versions`):
`x/crypto v0.58.0`, `x/text v0.43.0`, `klauspost/compress v1.20.3`,
`mongo-driver/v2 v2.9.2`, `mongo-driver v1.17.10`.

## Proposed upgrade plan (phase 2, after owner approval)

Target per module: `mongo-driver/v2 v2.8.0`, `x/crypto v0.56.0`,
`x/text v0.41.0`, `klauspost/compress v1.18.7`. This is the minimum that
clears every fixable ID. `mongo-driver/v2 v2.4.2` would be enough for
GO-2026-5327, but v2.8.0 is already what the workspace build list (and so
every CI test run) uses, so aligning on it changes nothing the tests see.
`mongo-driver/v2 v2.8.0` still requires `klauspost v1.17.6`,
`x/crypto v0.33.0` and `x/text v0.22.0`, so the three explicit pins are
needed either way.

### Group 1 — patch/minor, no change to what CI already tests

Raise each module's own `go.mod` to the version the workspace already selects.
No new code in any test run; only the images change.

| Module | `go get` |
|---|---|
| services/auth-service | `go.mongodb.org/mongo-driver/v2@v2.8.0` |
| services/chat-service | `go.mongodb.org/mongo-driver/v2@v2.8.0` |
| services/notification-service | `go.mongodb.org/mongo-driver/v2@v2.8.0 golang.org/x/crypto@v0.54.0 golang.org/x/text@v0.40.0` |
| services/user-service | `go.mongodb.org/mongo-driver/v2@v2.8.0` |
| services/api-gateway | `golang.org/x/crypto@v0.54.0 golang.org/x/text@v0.40.0` |
| tests/e2e | `go.mongodb.org/mongo-driver/v2@v2.8.0` |

Clears in the images: GO-2026-5327 (all called findings), GO-2026-5970, and
every x/crypto ID fixed at or below v0.52.0. What it could break: mongo-driver
v2.2.1 -> v2.8.0 is six minor releases of the driver, but the services
already run against v2.8.0 in every workspace test; the risk is a
behaviour only seen in the image build, which CI does not test.

### Group 2 — patch/minor, new versions for everyone

| Module | `go get` |
|---|---|
| services/{api-gateway,auth-service,chat-service,notification-service,user-service}, tests/e2e | `golang.org/x/crypto@v0.56.0 golang.org/x/text@v0.41.0 github.com/klauspost/compress@v1.18.7` |
| tools/docgen | `golang.org/x/crypto@v0.56.0` (optional; keeps its stray indirect line consistent, no finding today) |

One commit per dependency (x/crypto, x/text, klauspost), `go mod tidy` in each
module, then the workspace re-resolves on its own (`go.work` lists modules,
not versions; `go.work.sum` may change). What it could break:

- `x/crypto v0.54.0 -> v0.56.0`: pre-1.0 minor; auth-service calls `bcrypt`
  directly (stable API). `v0.56.0` declares `go 1.26.0` and pulls newer
  `x/net`/`x/sys`/`x/term`, so a few more indirect lines move.
- `x/text v0.40.0 -> v0.41.0`: one minor; used only through SCRAM stringprep.
- `klauspost/compress v1.17.6 -> v1.18.7`: one minor of a v1 module; the Mongo
  driver uses its snappy/zstd code only when wire compression is configured,
  which we do not do. Not yet exercised by CI at this version.

### Majors

None are needed. Items that look like majors and are left out:

- `go.mongodb.org/mongo-driver` v1 in user-service (and imported by a
  chat-service test): removing it is a code change, not an upgrade; see
  follow-ups. It has no finding today.

### What stays after both groups

GO-2026-5932 (`x/crypto/openpgp`, no fixed version) stays as "required" in
every module that requires `x/crypto`, so "0 required" is not reachable by
upgrades; the reachable target is 0 called, 0 imported, 1 required
(GO-2026-5932) in both workspace and module mode.

## Follow-ups (out of lane, not done here)

1. **Gate blind spot:** `scripts/govulncheck-module.sh` runs in workspace mode
   and so cannot see what the images ship. Today that hides 3 called findings
   (exit 3 with `GOWORK=off`). Running it with `GOWORK=off` for the services
   would close the gap, but `tools/docgen`, `tools/paritycheck` and
   `tests/e2e` do not load in module mode today, so they would need a
   `replace` / a tidy `go.mod` + `go.sum` first, or to stay in workspace mode.
2. **tests/e2e `go.mod` is not tidy and has no `go.sum`**; it builds only
   inside the workspace.
3. **mongo-driver v1 in user-service:** `internal/handlers/ratings_handlers.go`
   calls v1 `mongo.IsDuplicateKeyError` on an error from the v2 store; the
   string-match fallback on the same line is what actually catches the
   duplicate key. `services/chat-service/internal/handlers/admin_tickets_test.go`
   imports the v1 driver while chat-service's `go.mod` does not require it
   (works only through the workspace).
