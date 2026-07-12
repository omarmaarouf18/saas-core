# Read AI_CONTEXT.md first

Before doing anything in this repo, read `AI_CONTEXT.md` at the repo root.
It has the current project state, what's done, what's deferred, what's
still open, and the immediate next task. Update it in the same commit as
any change you make — do not leave it stale.

Detailed history lives in [docs/changelog/](docs/changelog/), split by category — consult the relevant category file when investigating something specific, don't read all of them by default.

For frontend-related work, you must also consult [docs/frontend/STATUS.md](docs/frontend/STATUS.md) (the frontend state tracker) and [frontend/README.md](frontend/README.md) (developer setup guide) before starting the task.


## Auto-commit policy
After completing any change, immediately git add, commit with a specific
message, and push to origin/logic-exploitation. Do not batch multiple
unrelated changes into one commit, and do not wait until a whole task is
finished if it has multiple independent sub-changes.
