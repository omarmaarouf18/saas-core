# Read AI_CONTEXT.md first

Before doing anything in this repo, read `AI_CONTEXT.md` at the repo root.
It has the current project state, what's done, what's deferred, what's
still open, and the immediate next task. Update it in the same commit as
any change you make — do not leave it stale.

Detailed history lives in [docs/changelog/](docs/changelog/), split by category — consult the relevant category file when investigating something specific, don't read all of them by default.

For frontend-related work, you must also consult [docs/frontend/STATUS.md](docs/frontend/STATUS.md) (the frontend state tracker) and [frontend/README.md](frontend/README.md) (developer setup guide) before starting the task.

To prevent documentation drift, any other agent-specific instruction files created in the future (e.g., CODEX.md, .cursorrules, etc.) must be created as short pointer files stating "Follow CLAUDE.md verbatim", never as copies.



## Auto-commit policy
After completing any change, immediately git add, commit with a specific
message, and push to origin/logic-exploitation. Do not batch multiple
unrelated changes into one commit, and do not wait until a whole task is
finished if it has multiple independent sub-changes.

Commit SHA in changelog files must be the real, full git hash of the commit
being documented, captured via `git rev-parse HEAD` immediately after
committing — never a placeholder.

docs/APPLICATION_MAP.md must be updated in the same commit whenever a change
adds, removes, renames, or changes the auth/permission requirements of an HTTP
endpoint, or changes an inter-service call path. The "as of Git commit" note at
the top must be refreshed to the new commit's short SHA in that same commit.

