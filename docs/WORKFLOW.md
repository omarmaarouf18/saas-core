# Parallel Agent Workflow (WF-01) — Owner Guide

Several agents run in parallel, each in its own git worktree on its own
`agent/<TASK-ID>-<slug>` branch, branched off the integration branch
`logic-exploitation`. Agents never push: you review each branch, merge it
into `logic-exploitation`, and push yourself.

The push block described at the end of this file is a **guardrail, not a
security boundary** — it prevents accidents, not determined evasion.

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
4. the expectation to run `make ci` before every commit, to record work in
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
make ci        # full gate in this worktree; takes the shared CI lock
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
make ci
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
make commit FILES="AI_CONTEXT.md docs/changelog/<category>.md" MSG="docs: fold WF-XX worklog"
```

Then push and clean up:

```bash
make push
make worktree-remove TASK=<TASK-ID>
```

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
  `make ci`, then `git merge --ff-only` from the main worktree. Do not create
  merge bubbles on `logic-exploitation`.
- **Hot-path collisions** (e.g. two tasks both editing `go.work` or the
  `Makefile`): expect the second rebase to conflict. Resolve in favor of the
  combination of both changes and re-run `make ci` before merging. Avoid this
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
   git push (git passes the remote name and URL as hook arguments — `make ci`
   invokes the same script with no arguments, so the gate still runs inside
   worktrees) AND the git dir contains `/worktrees/` or the current branch
   matches `agent/*`, the hook prints
   `BLOCKED: agents never push; the owner merges and pushes from the main worktree`
   and exits 1. In the main worktree on `logic-exploitation` or `main`, the
   hook behaves exactly as before. `make push` refuses under the same
   conditions with the same message.

Layer B blocks even pushes to *other* remotes (e.g. a throwaway local bare
remote), which is exactly what Layer A cannot cover.

**This is a guardrail, not a security boundary.** An agent with full shell
access could bypass it (e.g. `--no-verify` — forbidden by CLAUDE.md, or
`git -c core.hooksPath=`), so review diffs before merging; the layers exist
so that no agent can push by following the normal paths, by accident, or out
of confusion.

### CI lock

`make ci` wraps the gate in `flock` on a lock file under the common
`.git` dir (`$(git rev-parse --git-common-dir)/ci.lock`), so two worktrees
never run integration tests against the shared local Mongo/Redis at the same
time. The second run prints `waiting for CI lock: ...` and starts only after
the first finishes.

### Stale worktrees

Worktrees whose directories were deleted outside git (e.g. after moving the
repo) show up as `prunable` in `git worktree list`. Run
`git worktree prune --dry-run -v` to review, and decide yourself whether to
prune (this also orphans their branches; `git branch -d` refuses unmerged
ones).
