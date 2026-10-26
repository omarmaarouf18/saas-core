# Worklog: FE-APK-CHANNEL — website and in-app update hand out the same APK

## Task and scope
- Task ID: FE-APK-CHANNEL
- Item IDs covered: 1, 2, 3, 4
- Allowed paths (lane from the task prompt): frontend/.github/workflows/build-apk.yml,
  frontend/docs/CI_CD.md, scripts/test_changed_scope.sh + the gate (Makefile check
  target or .githooks/pre-push), .github/workflows/ci.yml (goldens comment), DESIGN.md,
  frontend/pubspec.yaml assets, frontend/assets/branding/qd_logo.svg. Not touched:
  infrastructure/deploy/**, services/user-service/**, docs/runbooks/** (PROD-PHOTO-STORAGE).
- Agent branch: agent/FE-APK-CHANNEL-universal-apk-channel, created from
  logic-exploitation @ 76ba59e6 (FE-CLEANUP merge)

## Decisions taken
- Item 1 guard is two layers: a jq check inside build-apk.yml that refuses to
  publish app-release.json unless `apk_url` ends in `/app-release.apk` and equals
  `apk_urls.universal` (runs in the mobile repo, where saas-core scripts do not
  exist), plus `scripts/test_apk_channel.sh`, a static check of build-apk.yml and
  the api-gateway default `download_url`, run by the gate.
- `size_mb` in app-release.json is now the universal APK's size (it described the
  arm64 file `apk_url` used to point at).
- frontend/test/core/app_version_test.dart pinned the old arm64 `apk_url`; it now
  expects the universal one and rejects the arm64 one (a third guard, in flutter test).
- Item 3: no gate path ran any `scripts/test_*` file before (Makefile `check`, `ci`,
  `ci-full` all call `.githooks/pre-push`, which had none; `.github/workflows/ci.yml`
  has none). The new "script-tests" stage is in **.githooks/pre-push**, right after
  gitleaks, on every gate run (make check, make ci-full, real pushes); both scripts
  take ~0.1 s. `scripts/test_changed_scope.sh` accepts `CHANGED_SCOPE_SCRIPT` to
  test another copy (used to prove the pre-fix failure).
- Version-code offsets in CI_CD.md (armeabi-v7a 1000+n, arm64-v8a 2000+n, x86_64
  4000+n) were read from the local Flutter SDK:
  `packages/flutter_tools/gradle/src/main/kotlin/FlutterPluginConstants.kt`
  (`ABI_VERSION` ARM32 1, ARM64 2, X86_64 4) and `FlutterPlugin.kt`
  (`versionCodeOverride = abiVersionCode * 1000 + versionCode`).
- Item 4: qd_logo.svg deleted. `docs/frontend/BRAND_IDENTITY.md` linked it, so that
  one line now says the file was removed (still in git history) instead of leaving
  a dead link. Changelog/history mentions are left alone (owner-only, historical).

## Changes per commit (message only — NO SHAs)
1. `FE-APK-CHANNEL: item 1 - website apk_url is the universal app-release.apk`
2. `FE-APK-CHANNEL: item 2 - document the version-code rule and the one APK channel`
3. `FE-APK-CHANNEL: item 3 - run the script regression tests in the gate`
4. `FE-APK-CHANNEL: item 4 - leftovers: goldens comment, DESIGN.md font, unused qd_logo.svg`
5. `FE-APK-CHANNEL: worklog` (this file)

## Verification

### Item 1: YAML parse and guard (fail on a temp bad value, then pass)

The bad value was a scratch copy of build-apk.yml with `apk_url` set back to
the arm64 split. The working tree was not changed.

```
$ python3 -c yaml.safe_load(build-apk.yml)
YAML OK, steps: 11
$ bash scripts/test_apk_channel.sh (temp bad value: apk_url=arm64 split)
102:          echo "apk_url=${BASE}/app-arm64-v8a-release.apk" >> "$GITHUB_OUTPUT"
ok   one apk_url output in build-apk.yml
FAIL apk_url points at the universal app-release.apk: got:           echo "apk_url=${BASE}/app-arm64-v8a-release.apk" >> "$GITHUB_OUTPUT"
ok   app-release.json apk_url comes from the release output
ok   apk_urls.universal is app-release.apk
ok   workflow verifies app-release.json before publishing
ok   api-gateway download_url is the universal app-release.apk
1 check(s) failed
exit=1
$ bash scripts/test_apk_channel.sh
ok   one apk_url output in build-apk.yml
ok   apk_url points at the universal app-release.apk
ok   app-release.json apk_url comes from the release output
ok   apk_urls.universal is app-release.apk
ok   workflow verifies app-release.json before publishing
ok   api-gateway download_url is the universal app-release.apk
all apk channel checks passed
exit=0
$ jq -e <guard> bad.json
false
exit=1
$ jq -e <guard> good.json
true
exit=0
```

The jq expression is the one in the workflow. bad.json has `apk_url` =
`.../app-arm64-v8a-release.apk`. good.json has `apk_url` = `.../app-release.apk`.
Both have `apk_urls.universal` = `.../app-release.apk`.

After item 2's summary edit, `yaml.safe_load` printed `YAML OK` again. After
item 4, ci.yml and pubspec.yaml also parsed: `YAML OK`.

The first `make check` for item 1 failed on one test:
`frontend/test/core/app_version_test.dart: build-apk.yml: pinned Flutter, build number, per-ABI + universal`
(it expected the arm64 `apk_url`). After updating the test:

```
00:00 +1: build-apk.yml: pinned Flutter, build number, per-ABI + universal
00:00 +2: All tests passed!
```

### Item 3: the gate fails on the pre-fix SIGPIPE behaviour

The pre-fix script is `scripts/changed-scope.sh` as of the parent of FE-CLEANUP
item 8 (`head -n 20` under pipefail).

```
254:	sort -u "$PATHS_FILE" | sed '/^$/d' | head -n 20 | sed 's/^/scope:   /' >&2
$ CHANGED_SCOPE_SCRIPT=<pre-fix copy> bash scripts/test_changed_scope.sh
FAIL exit 0 with 1500 paths: exit 141
FAIL scoped mode: stdout: 
FAIL frontend scope: stdout: 
ok   path count reported
ok   lists exactly 20 paths
FAIL reports the rest: stderr tail: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_0019.dart
scope:   frontend/lib/features/generated/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_0020.dart
4 check(s) failed
exit=1
$ make check   (scripts/changed-scope.sh temporarily = pre-fix version)
exit=2
```

The gate log lines from that run:

```
-- scripts/test_changed_scope.sh --
FAIL exit 0 with 1500 paths: exit 141
FAIL scoped mode: stdout: 
FAIL frontend scope: stdout: 
ok   path count reported
ok   lists exactly 20 paths
FAIL reports the rest: stderr tail: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_0019.dart
scope:   frontend/lib/features/generated/xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx_0020.dart
4 check(s) failed
BLOCKED: scripts/test_changed_scope.sh failed
make: *** [Makefile:48: check] Error 1
```

The fixed script was restored right after; `git status --short` showed only
`.githooks/pre-push` and `scripts/test_changed_scope.sh` modified.

### make check (the item 4 run; full scope because scripts/** changed)

```
[timing] script-tests 0.1s
Analyzing frontend...                                           
No issues found! (ran in 2.2s)
00:32 +1221: All tests passed!
[timing] flutter-analyze-test 38.4s
[timing] total 397.1s
== pre-push gate: all checks passed (scope: full) ==
```

The last line printed after that was the gate stamp path. Its 40-character
hex file name is truncated here because the md-sha gate treats 40-hex strings
as commit citations:
`gate stamp written: .../.git/gate-stamps/44701039f7... (scope: full)`.
The full gate (scope: full) also passed for items 1, 2 and 3 before each commit.

### Item 4: qd_logo.svg unused

```
$ grep -rn qd_logo frontend (excl build/.dart_tool)
frontend/pubspec.yaml:43:    - assets/branding/qd_logo.svg
exit=0
$ grep -rn "branding/" frontend/lib frontend/test frontend/android frontend/ios frontend/web
exit=1
```

## Unverified
- build-apk.yml was not run in GitHub Actions: it runs only on a push to the
  mobile repo's main. The jq guard was tested on sample JSON with the same
  expression, not on a real generated app-release.json.
- The job-summary "For the website team" note was checked by YAML parse only.
  Its rendering on a real run was not seen.

## Follow-ups / out-of-lane findings
- `.github/workflows/ci.yml` (GitHub CI, the full gate) still runs no
  `scripts/test_*` file. Adding a step there is a hot-path change that was not
  in this task's lane.
- `scripts/test_frontend_l10n_audit.py` is not run by any gate either. It was not
  hooked in here: the task named only test_changed_scope.sh.
- The website (omarmaarouf18/logiclink) may hard-code labels such as
  "arm64" next to the default button. Its repo was not inspected.

## Open questions
- none
