# Read AI_CONTEXT.md first

Before doing anything in this repo, read `AI_CONTEXT.md` at the repo root.
It has the current project state, what's done, what's deferred, what's
still open, and the immediate next task. Update it in the same commit as
any change you make — do not leave it stale.

Detailed history lives in [docs/changelog/](docs/changelog/), split by category — consult the relevant category file when investigating something specific, don't read all of them by default.

For frontend-related work, you must also consult [docs/frontend/STATUS.md](docs/frontend/STATUS.md) (the frontend state tracker) and [frontend/README.md](frontend/README.md) (developer setup guide) before starting the task.

To prevent documentation drift, any other agent-specific instruction files created in the future (e.g., CODEX.md, .cursorrules, etc.) must be created as short pointer files stating "Follow CLAUDE.md verbatim", never as copies.



## Auto-commit policy
After completing any change, you must verify it before committing or pushing:

1. `gofmt -l .` must return empty (run `gofmt -w .` to format).
2. `go build ./...` and `go vet ./...` must succeed for every module touched.
3. `go test ./...` must succeed for every module touched (including running `shared/infra` tests whenever a changelog file is edited).
4. The Commit SHA in any changelog entry must be written AFTER running `git commit` (never before), captured directly via `git rev-parse HEAD`, and then verified with `git cat-file -e <sha>^{commit}` to confirm it actually exists before the entry is considered final.
5. Do not fabricate, guess, or approximate a commit SHA under any circumstances. If the real SHA can't be determined, mark the entry as unverified and flag it instead of writing a placeholder.

Do not batch multiple unrelated changes into one commit, and do not wait until a whole task is finished if it has multiple independent sub-changes. Once verified, git add, commit with a specific message, and push to origin/logic-exploitation.

docs/APPLICATION_MAP.md must be updated in the same commit whenever a change adds, removes, renames, or changes the auth/permission requirements of an HTTP endpoint, or changes an inter-service call path. The "as of Git commit" note at the top must be refreshed to the new commit's short SHA in that same commit.

