# Parallel Agent Workflow (WF-01) — Owner Guide

Several agents run in parallel, each in its own git worktree on its own
`agent/<TASK-ID>-<slug>` branch, branched off the integration branch
`logic-exploitation`. Agents never push: you review each branch, merge it
into `logic-exploitation`, and push yourself.

The push block described at the end of this file is a **guardrail, not a
security boundary** — it prevents accidents, not determined evasion.

For the gate's mechanics (check order, scope table, `tools/versions.env`,
`scripts/install-tools.sh`, the tool cache, gitleaks, how to bump a tool), see
[docs/CI_CD_AND_HOOKS.md](CI_CD_AND_HOOKS.md).

## 0. The loop (WF-03)

Local checks run only for what changed; GitHub CI is the single full gate;
production deploys only from `main`.

```text
make check  ->  make commit  ->  owner merges  ->  make push (scoped)
            ->  GitHub CI (full)  ->  merge to main only when green
```

| Command | What it runs |
|---------|--------------|
| `make check` | the **scoped** gate: `scripts/changed-scope.sh` maps the changed paths (committed since the merge-base with `logic-exploitation` + staged + unstaged + untracked) to stages, prints the scope and why, runs them, and on a pass writes the stamp `make commit` requires |
| `make ci` | alias of `make check` (muscle memory) |
| `make ci-full` | everything, exactly the pre-WF-03 gate (`CI_SCOPE=full`); also writes a stamp |
| `make commit` | refuses unless a passing stamp covers the exact tree being committed ("run make check first") |
| `git push` / `make push` | the pre-push hook, scoped by the **pushed commit range** |
| GitHub CI (`ci.yml`) | everything, on every push and pull request |

`CI_SCOPE=full` forces the full gate anywhere (e.g. `CI_SCOPE=full git push`).
A briefly red `logic-exploitation` on GitHub is acceptable: fix forward.
`main` is protected (see "Protect main" below).

---

## 1. Starting a task

From the main worktree (the repo directory itself):

```bash
make worktree-new TASK=<TASK-ID> SLUG=<slug>        # BASE=<branch> is optional
```

- Fails if the main worktree has uncommitted changes to tracked files
  (long-lived untracked scratch dirs do not block).
- Creates branch `agent/<TASK-ID>-<slug>` from the local `logic-exploitation`
  (override with `BASE=<branch-or-sha>`).
- Creates the worktree at `../saas-core-wt/<TASK-ID>` — one sibling folder
  next to the repo holds all agent worktrees. Worktrees must live OUTSIDE the
  repo directory: `gofmt -l .`, `go vet ./...` and the markdown-SHA scan in
  `.githooks/pre-push` walk the tree from the repo root, and a nested worktree
  would be scanned twice.
- Configures `extensions.worktreeConfig`, a per-worktree
  `remote.origin.pushurl` that kills `git push origin` there (Layer A), and
  `core.hooksPath .githooks`.
- Runs `flutter pub get` in the new worktree's `frontend/` (without
  `frontend/.dart_tool`, a frontend-scoped `make check` fails at the dart
  format step). If `flutter` is not on `PATH`, or `pub get` fails, it prints
  a `WARNING` and still creates the worktree; run `flutter pub get` there by
  hand before `make check`.
- Inspect all agent worktrees anytime with:

```bash
make worktree-list
```

Then launch the agent with its working directory set to the printed worktree
path. Every task prompt must state:

1. the task ID (it names the branch and the worklog file),
2. the **allowed paths (lane)** — editing anything outside the lane means the
   agent stops and asks,
3. whether any **hot path** is explicitly granted (`shared/infra/**`,
   `go.work`, any `go.mod`/`go.sum`, `infrastructure/**`, `.github/**`,
   `Makefile`, `.githooks/**`, `pubspec.yaml`/`pubspec.lock`) — at most one
   running task may own each hot path,
4. the expectation to run `make check` before every commit (`make commit`
   enforces it), to record work in
   `docs/worklog/<TASK-ID>.md` (template: `docs/worklog/README.md`), and to
   stop and ask on the defined stop conditions (a needed decision, an
   out-of-lane change, a failing gate it cannot fix in lane, or a conflict
   with the base).

---

## 2. Reviewing a task branch

From inside the task's worktree:

```bash
cd ../saas-core-wt/<TASK-ID>
git log --oneline logic-exploitation..agent/<TASK-ID>-<slug>
git diff logic-exploitation...agent/<TASK-ID>-<slug>
make check     # scoped gate for the branch's changes (prints scope + why)
make ci-full   # optional: everything, as GitHub CI will run it
```

`make worktree-list` shows each worktree's branch, ahead/behind vs
`logic-exploitation`, and dirty state.

---

## 3. Integrating a finished task

In the task's worktree (if the branch is behind `logic-exploitation`, rebase
first; never merge `logic-exploitation` into an agent branch):

```bash
cd ../saas-core-wt/<TASK-ID>
git rebase logic-exploitation     # only if behind
make check
```

In the main worktree:

```bash
cd "/path/to/repo"
git merge --ff-only agent/<TASK-ID>-<slug>
```

Fold the task's worklog into the shared docs — `AI_CONTEXT.md`,
`docs/changelog/**` (and `docs/frontend/STATUS.md` for frontend work) — using
**real SHAs from `logic-exploitation`** (capture them with
`git log --oneline` AFTER the merge; never copy SHAs from the agent branch or
the worklog). Commit the fold:

```bash
make check     # docs scope: markdown SHA check + shared/infra tests
make commit FILES="AI_CONTEXT.md docs/changelog/<category>.md" MSG="docs: fold WF-XX worklog"
```

`make commit` rules (owner and agents alike):

- `FILES` is required (no `git add -A`). Exactly one of `MSG` or
  `MSG_FILE=<path>` is required. Use `MSG_FILE` for multi-line messages,
  e.g. a body or a `Co-Authored-By:` trailer (committed with `git commit -F`).
- A path in `FILES` may be a staged deletion (`git rm`, or the old side of a
  `git mv` — list both old and new paths). A path that exists nowhere (not
  on disk, not in the index, not in HEAD) fails with
  `ERROR: path '<p>' does not exist on disk, in the index, or in HEAD`.
- Only `FILES` are committed, exactly as staged (content and mode, so
  `git update-index --chmod=+x` survives `core.fileMode=false`). Other
  staged paths stay staged and uncommitted; a `WARNING` lists them.
- Paths containing spaces are not supported in `FILES`.
- **Pass stamp (WF-03)**: it refuses with
  `ERROR: no passing gate stamp for the tree being committed: run make check first`
  unless a passing `make check` / `make ci` / `make ci-full` stamped exactly
  the tree being committed, with a scope that covers the commit's own paths
  (a docs-only commit needs the docs-scope stamp, a code commit its module's).
  Untracked files left out of `FILES` are tolerated (they were present during
  the check); any other uncommitted tracked change is not, and is listed —
  commit it too, or `git stash push -- <paths>` and `make check` again.
  Editing a file after the check means checking again. Nothing is staged on a
  refusal. Stamps: `<git-common-dir>/gate-stamps/<tree>`, shared by all
  worktrees, pruned after 14 days / beyond the newest 200
  (`scripts/gate-stamp.sh`). A raw `git commit` does not check stamps.

Then push and clean up:

```bash
make push
make worktree-remove TASK=<TASK-ID>
```

The push runs the gate scoped by the pushed commit range (plus a gitleaks
scan of that range), taking the CI lock only around integration tests (see
"CI lock" below). GitHub CI then runs the full gate. A delete-only push
(`git push origin --delete <branch>`) skips the gate and returns at once.

`make worktree-remove` refuses while the branch is not merged into
`logic-exploitation`; pass `FORCE=1` to override (e.g. to discard an abandoned
task). It removes the worktree and deletes `agent/<TASK-ID>-<slug>` with
`git branch -d` (or `-D` with `FORCE=1`).

---

## 4. Resolving conflicts between parallel branches

- **Shared docs should never conflict**: agents do not edit `AI_CONTEXT.md`,
  `docs/changelog/**`, or `docs/frontend/STATUS.md` — you fold each
  `docs/worklog/<TASK-ID>.md` yourself, one task at a time, after its merge.
  If a shared doc conflicts, an agent went out of lane: resolve by re-doing
  the fold for that task's worklog, not by merging agent-side doc edits.
- **Code conflicts**: rebase the second branch in its worktree
  (`git rebase logic-exploitation`), resolve the conflict there, run
  `make check`, then `git merge --ff-only` from the main worktree. Do not create
  merge bubbles on `logic-exploitation`.
- **Hot-path collisions** (e.g. two tasks both editing `go.work` or the
  `Makefile`): expect the second rebase to conflict. Resolve in favor of the
  combination of both changes and re-run `make check` before merging. Avoid this
  by not granting the same hot path to two running tasks.
- Prefer `git rebase` in the worktree over merging; agents never rebase
  `logic-exploitation` or `main` themselves — only their own task branch.

---

## 5. How the push block works

Two independent layers, both created by `scripts/agent-worktree.sh` /
`.githooks/pre-push`:

1. **Layer A — per-worktree pushurl.** Every agent worktree gets
   `remote.origin.pushurl = DISABLED--agent-worktrees-never-push` as a
   worktree-specific config (requires `extensions.worktreeConfig`). Any
   `git push origin ...` from that worktree fails before any network access
   (`fatal: 'DISABLED--agent-worktrees-never-push' does not appear to be a
   git repository`). The main worktree's origin is unaffected.
2. **Layer B — pre-push hook guard.** At the very top of
   `.githooks/pre-push`, before any other check: if the invocation is a real
   git push (git passes the remote name and URL as hook arguments — `make check`
   invokes the same script with no arguments, so the gate still runs inside
   worktrees) AND the git dir contains `/worktrees/` or the current branch
   matches `agent/*`, the hook prints
   `BLOCKED: agents never push; the owner merges and pushes from the main worktree`
   and exits 1. In the main worktree on `logic-exploitation` or `main`, the
   hook behaves exactly as before. `make push` refuses under the same
   conditions with the same message.

Layer B blocks even pushes to *other* remotes (e.g. a throwaway local bare
remote), which is exactly what Layer A cannot cover.

Right after Layer B, the hook skips the gate for **delete-only pushes**: when
every ref line on stdin has an all-zero local sha, it prints
`delete-only push: gate skipped` and exits 0. Because the guard runs first, a
delete from an agent worktree or `agent/*` branch is still BLOCKED.

**This is a guardrail, not a security boundary.** An agent with full shell
access could bypass it (e.g. `--no-verify` — forbidden by CLAUDE.md, or
`git -c core.hooksPath=`), so review diffs before merging; the layers exist
so that no agent can push by following the normal paths, by accident, or out
of confusion.

### CI lock

Only the stages that use the shared local Mongo/Redis run under `flock` on a
lock file under the common `.git` dir (`$(git rev-parse --git-common-dir)/ci.lock`,
`scripts/ci-lock.sh`): `go test -count=1` of the integration test packages
(those whose test binary links a Mongo or Redis client, see
`scripts/go-test-module.sh`). gofmt, vet, gosec, govulncheck, gitleaks,
compose validation, flutter and unit tests run without it, so parallel
worktrees overlap everywhere else (WF-03; before that the whole gate held it).

A run that has to wait prints
`waiting for CI lock: <file> is held by another gate run (make check or git push)`
and `[timing] lock-wait <seconds>s`. `CI_LOCK_HELD=1` tells the gate its
caller already holds the lock.

**Why the lock stays (WF-03 experiment).** Two scoped gates touching
`services/user-service`, run concurrently from two scratch worktrees with the
lock bypassed (`CI_LOCK_HELD=1`), passed once and then both failed: Mongo
client timeouts under load (`client timed out waiting for server response`
while seeding, then `job not found` / `service not found`), not data
collisions between the runs. With the lock they serialize their integration
tests and pass. Keep the lock until the integration tests tolerate a loaded
Mongo (longer test timeouts) — see docs/worklog/WF-03.md.

### TEST_DB_SUFFIX

Every gate run (`make check`, `make ci-full`, a real push) exports
`TEST_DB_SUFFIX=<worktree dir name>-<pid>` unless it is already set
(characters outside `[A-Za-z0-9_-]` become `_`, e.g. `SaaS_prototype-12345`,
`WF-02-12345`). Tests use it (via `shared/infra/testutil`) to give each run its
own Mongo databases, Redis keys, pub/sub channels and X-Real-IP addresses.
To reproduce a run, set it yourself: `TEST_DB_SUFFIX=debug make check`.

### Stale worktrees

Worktrees whose directories were deleted outside git (e.g. after moving the
repo) show up as `prunable` in `git worktree list`. Run
`git worktree prune --dry-run -v` to review, and decide yourself whether to
prune (this also orphans their branches; `git branch -d` refuses unmerged
ones).

---

## 6. Protect main

Production deploys only from `main`, so `main` must only move to commits
whose GitHub CI is green. One-time setup on GitHub (owner):

1. Open the repository on GitHub → **Settings** → **Rules** → **Rulesets**
   → **New ruleset** → **New branch ruleset** (or the classic route:
   **Settings** → **Branches** → **Add branch protection rule**, branch name
   pattern `main`).
2. Name it `protect-main`, set **Enforcement status** to **Active**.
3. **Target branches** → **Add target** → **Include by pattern** → `main`.
4. Enable **Require status checks to pass** (classic: **Require status
   checks to pass before merging**). Click **Add checks** and add every job
   of the `CI Gate` workflow, typing each name (a check only appears in the
   list after it has run once on GitHub):
   `Lint & Formatting`, `Secret Scan (gitleaks)`, `API Contract Tests`,
   `Flutter Lint & Test`, and the six `Build & Test` matrix entries —
   `Build & Test (services/api-gateway, api-gateway)`,
   `Build & Test (services/auth-service, auth-service)`,
   `Build & Test (services/chat-service, chat-service)`,
   `Build & Test (services/notification-service, notification-service)`,
   `Build & Test (services/user-service, user-service)`,
   `Build & Test (shared/infra, shared-infra)`.
   Copy the exact names from a finished run's checks list on GitHub if they
   differ.
5. Enable **Block force pushes** (classic: leave **Allow force pushes** off)
   and **Restrict deletions**.
6. Leave **Require a pull request before merging** off if you fast-forward
   `main` from your machine with `make push`; a ruleset with required status
   checks still rejects a push to `main` whose head commit has no green
   checks. The commit must therefore have been pushed (to
   `logic-exploitation`) and gone green first.
7. **Bypass list**: leave it empty. The production CD hotfix procedure in
   CLAUDE.md is then "push the fix to `logic-exploitation`, wait for green,
   fast-forward `main`"; if you ever need to skip that, add yourself to the
   bypass list temporarily and remove yourself afterwards.
8. **Create**.

Then the loop is: `make check` → `make commit` → owner merges the agent
branch → `make push` of `logic-exploitation` (scoped hook) → GitHub CI (full)
→ when that commit is green, `git checkout main && git merge --ff-only
logic-exploitation && make push`.
