# Worklog: WF-RELEASE — make releasing to production one guarded command

## Task and scope
- Task ID: WF-RELEASE
- Item IDs covered: 1, 2, 3, 4, 5, 6
- Allowed paths: `Makefile`, `scripts/**`, `.githooks/**`, `.github/workflows/ci.yml`, `docs/RELEASE.md`, `docs/WORKFLOW.md`, `docs/worklog/WF-RELEASE.md`
- Agent branch: agent/WF-RELEASE-guarded-release-ci-scripts, created from logic-exploitation (short SHA: bca961e7)

## Decisions taken
- Untracked files handling in `make release`: Untracked files under tracked project directories (e.g. `services/`, `frontend/`, `scripts/`, `docs/`) cause refusal to prevent uncommitted changes from being left behind. Untracked files in scratch or temporary directories (e.g. `scratch/`, `tmp/`) are permitted and reported.
- Push target semantics in `make release`: Release pushes by exact commit SHA (`git push origin <sha>:main`) rather than branch name to prevent race conditions where a newer commit on `logic-exploitation` could be deployed without gate verification.
- Push guard on `main`: Added guard in both `Makefile` (`push:` target) and `.githooks/pre-push` that unconditionally refuses pushes when on `main` or non-`logic-exploitation`/non-`agent/*` branches with advice to checkout `logic-exploitation`.
- Single source script test runner: Consolidated script tests into `scripts/run_script_tests.sh` invoked identically by `.githooks/pre-push` ("script-tests" stage) and GitHub CI `ci.yml` (`lint-formatting` job).

## Changes per commit (message only — NO SHAs)
1. WF-RELEASE: item 1 - make release-status read-only status command
2. WF-RELEASE: item 2 - make release guarded release command
3. WF-RELEASE: item 3 - branch guard refusing pushes from main and other branches
4. WF-RELEASE: item 4 - make hotfix worktree creation from origin/main
5. WF-RELEASE: item 5 - run script tests in CI and pre-push via single source runner
6. WF-RELEASE: item 6 - release and hotfix documentation and workflow link

## Verification
- `scripts/test_release_status.sh` failing before / passing after:
  - Failing before:
```text
bash: scripts/release-status.sh: No such file or directory
```
  - Passing after:
```text
ok   release-status exits 0
ok   prints short SHA
ok   lists commits ahead of origin/main
ok   reports CI Gate status
ok   reports Release Gate E2E status
ok   release-status still exits 0 when runs failed (read-only inspect)
ok   reports failing conclusion
ok   missing gh exits non-zero
all release-status checks passed
```

- `scripts/test_release.sh` failing before / passing after:
  - Failing before:
```text
bash: scripts/release.sh: No such file or directory
```
  - Passing after:
```text
ok   refuses when not on logic-exploitation
ok   branch error message explains branch requirement
ok   refuses when tracked files modified
ok   refuses when untracked files under tracked dir
ok   allows untracked files in scratch dir in dry run
ok   refuses when local != origin/logic-exploitation
ok   refuses when origin/main is not ancestor
ok   refuses when required workflow failed
ok   --wait flag polls and succeeds once runs complete
ok   --wait outputs polling message
ok   refuses when typed confirmation is not 'release'
ok   dry run exits 0
ok   dry run output mentions DRY RUN
ok   dry run does not push to origin/main
ok   real release exits 0
ok   origin/main updated to exact SHA
ok   prints RELEASE_VERIFIED: <short sha>
ok   prints deploy workflow run URL
ok   leaves owner on logic-exploitation
all release script checks passed
```

- `scripts/test_push_guard.sh` failing before / passing after:
  - Failing before:
```text
Push from main was allowed without guard check (failed: make push on main advises git checkout logic-exploitation)
```
  - Passing after:
```text
ok   make push refuses on main
ok   make push on main advises git checkout logic-exploitation
ok   git push refuses on main via hook
ok   git push on main advises git checkout logic-exploitation
ok   make push refuses on non-logic-exploitation branch
ok   make push on other branch advises git checkout logic-exploitation
ok   make push refuses on agent/* branch
ok   make push on agent/* outputs agents never push
ok   logic-exploitation push updates remote
all push guard checks passed
```

- `scripts/test_hotfix.sh` failing before / passing after:
  - Failing before:
```text
ERROR: unknown command 'hotfix'
Usage: scripts/agent-worktree.sh <new|list|remove|hotfix> ...
```
  - Passing after:
```text
ok   make hotfix without NAME fails
ok   prints usage on missing NAME
ok   agent-worktree.sh hotfix cve-patch exits 0
ok   worktree directory created
ok   branch is hotfix/cve-patch
ok   hotfix branched from origin/main
ok   push is disabled in hotfix worktree
ok   remove refuses unmerged hotfix
ok   remove --force succeeds
ok   worktree directory removed
all hotfix checks passed
```

- Item 5 `scripts/run_script_tests.sh` failing before / passing after (deliberately broken test script `scripts/test_deliberate_failure.sh` in temp branch `temp/probe-failing-script`):
  - Failing before:
```text
-- scripts/test_deliberate_failure.sh --
intentional failure for item 5 verification
BLOCKED: scripts/test_deliberate_failure.sh failed
...
ERROR: 1 script regression test suite(s) failed
Runner exited with: 1
```
  - Passing after:
```text
Ran 5 tests in 0.001s

OK
all script regression tests passed
```

- `RELEASE_DRY_RUN=1 make release` literal output on real repo:
```text
=== Guarded Production Release ===
[DRY RUN MODE ENABLED]

Checking required workflows for ccdee0ab...

ERROR: Release preconditions failed (2 error(s)):
  - Current branch is 'agent/WF-RELEASE-guarded-release-ci-scripts'; release must be performed from 'logic-exploitation'. Switch to it: git checkout logic-exploitation
  - Workflow gate unsatisfied: Release Gate E2E: completed with conclusion 'failure' (https://github.com/omarmaarouf18/saas-core/actions/runs/40642987581)
make: *** [Makefile:102: release] Error 1
```

- `make check` last lines:
```text
[timing] flutter-analyze-test 49.0s
[timing] total 363.0s
== pre-push gate: all checks passed (scope: full) ==
gate stamp written: <git-common-dir>/gate-stamps/<tree:5f162599> (scope: full)
```

## Unverified
- Real push to `origin/main`: agents never push to remote and must not deploy to production. Push to `origin/main` is verified via unit and regression test harnesses (`scripts/test_release.sh`).

## Follow-ups / out-of-lane findings
- Release Gate E2E run on GitHub for HEAD of `logic-exploitation` (`ccdee0ab`) is currently failing (`https://github.com/omarmaarouf18/saas-core/actions/runs/40642987581`). The release guard correctly blocks production deployment until this workflow passes.

## Open questions
- none
