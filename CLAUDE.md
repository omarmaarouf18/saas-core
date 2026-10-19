# Read AI_CONTEXT.md first

Before doing anything in this repo, read `AI_CONTEXT.md` at the repo root.
It has the current project state, what's done, what's deferred, what's
still open, and the immediate next task.

> [!IMPORTANT]
> **Parallel agent workflow (WF-01)**: on an agent branch, do NOT edit
> `AI_CONTEXT.md`, `docs/changelog/**`, or `docs/frontend/STATUS.md`.
> Instead, create or append one file `docs/worklog/<TASK-ID>.md`
> (template in [docs/worklog/README.md](docs/worklog/README.md)); the owner
> folds it into the shared docs at merge time. The full procedure for
> starting, reviewing, and integrating agent worktrees lives in
> [docs/WORKFLOW.md](docs/WORKFLOW.md).

Detailed history lives in [docs/changelog/](docs/changelog/), split by category — consult the relevant category file when investigating something specific, don't read all of them by default.

For frontend-related work, you must also consult [docs/frontend/STATUS.md](docs/frontend/STATUS.md) (the frontend state tracker) and [frontend/README.md](frontend/README.md) (developer setup guide) before starting the task.

To prevent documentation drift, any other agent-specific instruction files created in the future (e.g., CODEX.md, .cursorrules, etc.) must be created as short pointer files stating "Follow CLAUDE.md verbatim", never as copies.

## Branch & Push Policy (WF-01)

- Agents work ONLY on `agent/<TASK-ID>-<slug>` branches in their own git worktree, created from the main worktree with `make worktree-new TASK=<TASK-ID> SLUG=<slug>` (helper: `scripts/agent-worktree.sh`, layout and owner procedure: [docs/WORKFLOW.md](docs/WORKFLOW.md)).
- Agents NEVER push, never merge, never rebase or force-update `logic-exploitation` (the integration branch) or `main`, and never use `--no-verify`. Pushes from linked worktrees and `agent/*` branches are blocked by two independent layers (per-worktree `remote.origin.pushurl` + the pre-push hook) and `make push` refuses there too.
- The owner reviews each agent branch, merges it into `logic-exploitation`, and pushes from the main worktree via `make push`.
- Merges to `main` happen via fast-forward merge after verifying the full test suite and CI (owner action).
- **Production CD Hotfix Procedure (owner only)**: Emergency hotfixes for live production CD/deploy pipeline failures may be committed directly to `main` when necessary to unblock deployment, but MUST be synced back to `logic-exploitation` via fast-forward as the very next action afterward so the two branches remain in sync.

## Task lane rules (WF-01)

- **Lane rule**: every task prompt states its allowed paths (the lane). Editing anything outside the lane means stop and ask — never fix, refactor, or "helpfully" extend out of lane.
- **Hot paths**: `shared/infra/**`, `go.work`, any `go.mod`/`go.sum`, `infrastructure/**`, `.github/**`, `Makefile`, `.githooks/**`, `pubspec.yaml`/`pubspec.lock`. Only a task whose prompt explicitly grants ownership may touch them, and at most one running task may own each hot path at a time.
- **Stop conditions**: a needed decision, an out-of-lane change, a failing gate you cannot fix within your lane, or a conflict with the base branch. Write the question in `docs/worklog/<TASK-ID>.md` and stop — do not guess.

## Auto-commit policy
After completing any change, you must verify it before committing:

1. `gofmt -l .` must return empty (run `gofmt -w .` to format).
2. `go build ./...` and `go vet ./...` must succeed for every module touched.
3. `go test ./...` must succeed for every module touched (including running `shared/infra` tests whenever a changelog file is edited).
4. Run `make check` before every commit; `make commit` enforces it (it refuses unless a passing `make check` stamped exactly the tree being committed). `make check` runs only the checks your change needs (it prints the scope and why; `make ci` is an alias, `make ci-full` runs everything) and holds a lock under the common `.git` dir only around tests that use the shared local Mongo/Redis — never run raw `go test` against shared services instead. GitHub CI is the full gate.
5. One commit per logical change. Do not batch multiple unrelated changes into one commit, and do not wait until a whole task is finished if it has multiple independent sub-changes.

The only way to commit is `make check && make commit FILES="..." MSG="..."` (or `MSG_FILE=<path>`). Raw `git commit` is blocked by `.githooks/pre-commit` unless a passing stamp covers the exact tree being committed. `make commit` executes `ensure-hooks` as an unavoidable prerequisite and never sweeps untracked files into the commit (`FILES` is required). Agents do NOT push — the owner merges and pushes (see [docs/WORKFLOW.md](docs/WORKFLOW.md)).

### Shared Widget Changes
Any change touching a shared/reusable widget (anything in `frontend/lib/widgets/`) as a side effect of an otherwise-scoped feature task must be called out as its own explicit item in the commit message and the task report — e.g., a separate section/paragraph titled "Unrelated shared-widget fix" — rather than folded silently into the feature diff. This makes it possible to review or revert it independently of the feature it was bundled with.

## Commit SHA citation rules

- On agent branches (`agent/<TASK-ID>-<slug>`), NO full 40-character commit SHAs may appear anywhere in committed files — `docs/worklog/<TASK-ID>.md` included — because a rebase or merge changes them. Short SHAs belong in the final chat report only.
- The rules below apply to shared docs (`AI_CONTEXT.md`, `docs/changelog/**`, ADRs, etc.), which only the owner edits after merging an agent branch into `logic-exploitation`:
  1. The Commit SHA in any changelog entry must be written AFTER running `git commit` (never before), captured directly via `git rev-parse HEAD`, and then verified with `git cat-file -e <sha>^{commit}` to confirm it actually exists before the entry is considered final.
  2. Do not fabricate, guess, or approximate a commit SHA under any circumstances. If the real SHA can't be determined, mark the entry as unverified and flag it instead of writing a placeholder.
  3. Never run `git commit --amend` on a commit whose hash has already been cited elsewhere in the repo (a changelog entry, AI_CONTEXT.md, an ADR, etc.) — amending changes the hash, orphaning the cited reference and breaking CI's SHA validation. If a commit needs correcting after its hash may have been cited anywhere, create a NEW commit instead, even for a trivial fix. Only amend a commit that has not yet been pushed and is not yet referenced anywhere in committed documentation.
  4. When referring to a commit hash in explanatory prose that is NOT a live citation (e.g. describing a historical mistake, an orphaned/superseded hash, or any other non-authoritative mention), always write it truncated (e.g. the first 7-10 characters followed by ..., such as `05b5ca7...`) — never the full 40-character form — so it cannot be mistaken for, or trigger validation as, a live commit citation. Full 40-character hashes anywhere in this repo's markdown files are always treated as live citations that must resolve to a real, reachable commit; there is no legitimate reason to write one out in full for any other purpose.
  5. When citing a commit SHA for a specific feature or fix in documentation, verify with `git show --stat <sha>` that the commit's actual file changes and commit message match the feature being described — not just that the SHA exists and is reachable (existence checks alone cannot catch a valid-but-wrong hash pointing at a different feature).

## Final report contents (WF-01)

The final report of every agent task replaces the old PUSH_VERIFIED / `make report-hash` / proactive-commit-disclosure rules and must include:

- The literal output of `git log --oneline logic-exploitation..HEAD` (or against the base commit the task started from).
- The literal output of `git diff --stat` for the same range.
- Each verification/acceptance command and its literal output.
- Anything claimed but not verified, with the reason.

## No Illustrative or Reconstructed Output

When presenting command output (test results, build logs, hook output, etc.) in a chat response, you must paste the EXACT text that was actually captured from the tool call — character for character. You must NEVER write lines that "represent" or "illustrate" what output would typically look like, even if you believe the real output would have been similar or identical. This applies even to trivial, low-risk lines.

If you did not directly capture a piece of output (e.g., you're summarizing from memory, or reconstructing what a log likely said), you must say so explicitly — e.g., "I did not capture the literal text of this line; based on the script's logic, no output would print here" — rather than writing a plausible-looking log line as if it were real.

This rule exists because a fabricated-but-plausible log line is functionally indistinguishable from a hallucinated one to anyone reading the report, even when the underlying work was done correctly. "Illustrative" output defeats the entire purpose of raw-output verification.
