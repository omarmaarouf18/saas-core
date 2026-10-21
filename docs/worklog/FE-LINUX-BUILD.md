# Worklog: FE-LINUX-BUILD — Linux desktop build fails on new clang

## Task and scope
- Task ID: FE-LINUX-BUILD
- Item IDs covered: 1 (CMakeLists conditional flag), 2 (CONNECTING_TO_BACKEND.md Linux section), 3 (this worklog)
- Allowed paths (lane from the task prompt): `frontend/linux/**`, `frontend/CONNECTING_TO_BACKEND.md` (one short section), `docs/worklog/FE-LINUX-BUILD.md`
- Agent branch: agent/FE-LINUX-BUILD-linux-desktop-build, created from logic-exploitation (merge commit starting "Merge branch 'agent/JOB-MODEL-V2-ADR...'")

## Environment (captured)
Toolchain used for every command in this worklog:

- `flutter 3.44.6 • channel stable` (framework revision printed by `flutter --version`: `ee80f08bbf`, 2026-07-08)
- `cmake version 4.3.0`
- `gcc (GCC) 16.2.1 20260819 (Red Hat 16.2.1-2)`
- `clang version 22.1.8 (Fedora 22.1.8-4.fc44)`
- All builds ran on Fedora; `rpm -q libsecret-devel jsoncpp-devel gtk3-devel`:

```
libsecret-devel-0.21.8.2-2.fc44.x86_64
jsoncpp-devel-1.9.6-3.fc44.x86_64
gtk3-devel-3.24.52-2.fc44.x86_64
```

## Decisions taken
- The support check uses the **positive** flag form `-Wdeprecated-literal-operator`, and only the outcome adds the **negative** `// -Wno-deprecated-literal-operator`. Reason, verified empirically on this box: clang accepts an unknown positive `-Wfoo` while emitting `warning: unknown warning option ...`, which one of `check_cxx_compiler_flag`'s built-in FAIL_REGEX patterns (`unknown [^\n]*option`, CMakeCheckCompilerFlagCommonPatterns.cmake:13) catches, so unknown-flags-yield-FALSE holds for clang and (`unrecognized command-line option`) for GCC. With the negative form, an unknown `-Wno-...` produces **no** diagnostic at all on old clang, so the check would return a false TRUE, leaving the unknown flag in the build; clang only reports unknown `-Wno-` options when another diagnostic fires, which under our `-Werror` would then break otherwise-warning-free old builds.
- The `include(CheckCXXCompilerFlag)` + `check_cxx_compiler_flag(...)` call sits once at top level (not inside APPLY_STANDARD_SETTINGS); the result cache variable is shared by the runner and every generated plugin target that calls the function from subdirectories. `-Wall -Werror` stays unconditional for our own runner code (only the one suppression flag is conditional).

## Baseline reproduction (BEFORE the fix, working tree unmodified)
`rm -rf build/linux && flutter build linux --debug` (run from `frontend/`; same as `rm -rf frontend/build/linux` from the repo root). Literal last lines (captured with `| tail -30`):

```
Got dependencies!
65 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Building Linux application...                                   
/home/omarmaarouf/CS tools/Antigravity/saas-core-wt/FE-LINUX-BUILD/frontend/linux/flutter/ephemeral/.plugin_symlinks/flutter_secure_storage_linux/linux/include/json.hpp:24392:35: error: identifier '_json' preceded by whitespace in a literal operator declaration is deprecated [-Werror,-Wdeprecated-literal-operator]
/home/omarmaarouf/CS tools/Antigravity/saas-core-wt/FE-LINUX-BUILD/frontend/linux/flutter/ephemeral/.plugin_symlinks/flutter_secure_storage_linux/linux/include/json.hpp:24400:49: error: identifier '_json_pointer' preceded by whitespace in a literal operator declaration is deprecated [-Werror,-Wdeprecated-literal-operator]
/home/omarmaarouf/CS tools/Antigravity/saas-core-wt/FE-LINUX-BUILD/frontend/linux/flutter/ephemeral/.plugin_symlinks/flutter_secure_storage_linux/linux/include/json.hpp:24464:58: error: identifier '_json' preceded by whitespace in a literal operator declaration is deprecated [-Werror,-Wdeprecated-literal-operator]
/home/omarmaarouf/CS tools/Antigravity/saas-core-wt/FE-LINUX-BUILD/frontend/linux/flutter/ephemeral/.plugin_symlinks/flutter_secure_storage_linux/linux/include/json.hpp:24465:58: error: identifier '_json_pointer' preceded by whitespace in a literal operator declaration is deprecated [-Werror,-Wdeprecated-literal-operator]
Build process failed
```

## Changes per commit (message only — NO SHAs)
1. `FE-LINUX-BUILD: suppress -Wdeprecated-literal-operator in linux CMake only when the compiler supports it`
2. `FE-LINUX-BUILD: document Linux desktop packages, run command and stale CMake cache rebuild`
3. `FE-LINUX-BUILD: task worklog`

## Verification
All commands run locally, from the FE-LINUX-BUILD worktree (`frontend/` where noted).

1. **Post-fix clean build** — `rm -rf build/linux && flutter build linux --debug` (run from `frontend/`), flutter's own exit code captured without a pipe, `echo "flutter-exit=$?"` printed `flutter-exit=0`. Literal last lines of the build log:

```
65 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Building Linux application...                                   
✓ Built build/linux/x64/debug/bundle/frontend
```

   (An identical earlier post-fix run — the first successful build after the CMake edit — ended with the same `✓ Built build/linux/x64/debug/bundle/frontend` line; for that run the printed `build-exit=0` came from `tail` of a pipeline, not flutter, so the second run above is the authoritative exit-code check.)

2. **Flag actually reached the real build targets** — `grep -n "CXX_HAS_DEPRECATED_LITERAL_OPERATOR\|CMAKE_CXX_COMPILER:" build/linux/x64/debug/CMakeCache.txt` from `frontend/` printed:

```
28:CMAKE_CXX_COMPILER:FILEPATH=/usr/bin/clang++
528://Test CXX_HAS_DEPRECATED_LITERAL_OPERATOR
529:CXX_HAS_DEPRECATED_LITERAL_OPERATOR:INTERNAL=1
```

   So the conditional branch fired for the real (clang++-based) Flutter Linux build.

3. **Detection behaves correctly for both compiler families** — a scratch CMake project (`/tmp/opencode/cmake-flag-probe/`) calling the same `check_cxx_compiler_flag("-Wdeprecated-literal-operator", ...)` plus a deliberately nonexistent flag `"-Wdeprecated-nonexistentflag"` as the "old compiler lacks the flag" simulation. `cmake -B build-clang -DCMAKE_CXX_COMPILER=clang++`:

```
-- The CXX compiler identification is Clang 22.1.8
-- nonexistent positive flag supported: 
-- deprecated-literal-operator supported: 1
```

   `cmake -B build-gcc -DCMAKE_CXX_COMPILER=g++`:

```
-- The CXX compiler identification is GNU 16.2.1
-- nonexistent positive flag supported: 
-- deprecated-literal-operator supported: 1
```

   (also confirmed on this box directly: clang+++`-Werror -Wdeprecated-nonexistentflag` → `error: unknown warning option ...`; g++ unknown flag → `error: unrecognized command-line option`; both real-flag invocations exit 0.)

4. **`make check` (scoped gate) before commit 1** — last literal lines:

```
01:33 +1019: All tests passed!
[timing] flutter-analyze-test 122.9s
[timing] total 124.9s
== pre-push gate: all checks passed (scope: docgen frontend) ==
```

5. **`make check` before commit 2** — last literal lines:

```
[timing] flutter-analyze-test 117.5s
[timing] total 335.8s
== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==
```

6. **`make check` before commit 3 (this worklog)** — captured after writing this file; result recorded below in "Verification (commit 3)".

### Verification (commit 3)

`make check` was run after this file was written (before its commit) and PASSED. Literal last two lines:

```
[timing] total 125.5s
== pre-push gate: all checks passed (scope: docs infra-tests docgen frontend) ==
```

The third output line — `gate stamp written: /home/omarmaarouf/CS tools/Antigravity/SaaS prototype/.git/gate-stamps/<40-char hex> (scope: docs infra-tests docgen frontend)` — is reproduced here with only the stamp file name redacted, because the markdown SHA scan does not allow any 40-character hex string inside a tracked `.md` (see follow-ups). `make check` was then re-run to stamp the final edited tree, and only after passing was this commit created.

## Unverified
- No actual **older** clang (< 15) or GCC (< 14) toolchain was available on this machine, so "older GCC/clang keep working" was not tested with one. Instead the same detection path was verified with a deliberately nonexistent flag through the same module (FALSE for both Clang 22.1.8 and GNU 16.2.1 probes above), which reproduces how a compiler lacking the flag is detected.
- `flutter run -d linux` (the interactive launch) was not executed; only `flutter build linux --debug`. The doc's run command is written to match the existing sections' conventions but was not itself executed.
- The Ubuntu package names (`libsecret-1-dev libjsoncpp-dev libgtk-3-dev`) are not installed/verified anywhere — no Ubuntu machine available.
- Whether GitHub CI builds any Linux desktop target was not checked in `.github/workflows/ci.yml`; no CI evidence for this change.
- The exact newest `flutter_secure_storage_linux` version that fixes the bundled json.hpp was not investigated (plugin bump = `pubspec.yaml`/lock — another agent's lane).

## Follow-ups / out-of-lane findings
- The markdown SHA scan inside the gate rejects ANY 40-character hex string in a tracked `.md`, including non-commit hashes such as the gate-stamp file names that `make check` itself prints. A worklog that quotes gate output verbatim can therefore be blocked through no writer error; this worklog had to redact that one stamp file name. Owner may want a scan carve-out for `gate-stamps/` paths or guidance to summarize stamp lines.
- During the builds `flutter pub get` reported `65 packages have newer versions incompatible with dependency constraints.` — informational only.
- An accidental `frontend/main.cpp` was created during a probe (cwd slipped) and deleted in the same session before any commit; it never appears in git history (working-tree `git status` confirmed only the CMakeLists edit at that point).

## Open questions
- none