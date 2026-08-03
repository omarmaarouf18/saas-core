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
6. Never run `git commit --amend` on a commit whose hash has already been cited elsewhere in the repo (a changelog entry, AI_CONTEXT.md, an ADR, etc.) — amending changes the hash, orphaning the cited reference and breaking CI's SHA validation. If a commit needs correcting after its hash may have been cited anywhere, create a NEW commit instead, even for a trivial fix. Only amend a commit that has not yet been pushed and is not yet referenced anywhere in committed documentation.
7. When referring to a commit hash in explanatory prose that is NOT a live citation (e.g. describing a historical mistake, an orphaned/superseded hash, or any other non-authoritative mention), always write it truncated (e.g. the first 7-10 characters followed by ..., such as `05b5ca7...`) — never the full 40-character form — so it cannot be mistaken for, or trigger validation as, a live commit citation. Full 40-character hashes anywhere in this repo's markdown files are always treated as live citations that must resolve to a real, reachable commit; there is no legitimate reason to write one out in full for any other purpose.

Before performing `git add`, every commit and push sequence must explicitly execute:
```bash
git config core.hooksPath .githooks
```
as the literal first command in the sequence, unconditionally and idempotently. This line must NEVER be skipped or assumed to be already done, even mid-session, and even if it was run earlier in the same session. (Alternatively, use `make commit MSG="..."` and `make push` which execute `ensure-hooks` as an unavoidable prerequisite).

Do not batch multiple unrelated changes into one commit, and do not wait until a whole task is finished if it has multiple independent sub-changes. Once verified, run `git config core.hooksPath .githooks`, `git add`, `git commit` with a specific message, and push to origin/logic-exploitation via `make push`.

### Shared Widget Changes
Any change touching a shared/reusable widget (anything in `frontend/lib/widgets/`) as a side effect of an otherwise-scoped feature task must be called out as its own explicit item in the commit message and the task report — e.g., a separate section/paragraph titled "Unrelated shared-widget fix" — rather than folded silently into the feature diff. This makes it possible to review or revert it independently of the feature it was bundled with.

### Reporting Push Verification
- The agent MUST run `make push` (not raw `git push`) for the final push of any task.
- The agent's final report MUST include the literal, unedited output of `make push` (the `PUSH_VERIFIED: <hash>` line) pasted as-is.
- The agent must NOT write a sentence re-stating, re-typing, or "confirming" the hash separately anywhere else in its response (e.g. no "Local HEAD Hash: X / Remote Hash: X, both match" section). The `PUSH_VERIFIED` line from the script IS the mechanical confirmation — retyping it in prose is prohibited to prevent manual transcription drift. If `make push` prints `PUSH_VERIFIED`, the agent may state "push verified" in prose without retyping the hash itself; if it needs to reference the hash for a changelog entry, it must copy it from that same pasted output block.
- Whenever reporting a PUSH_VERIFIED hash in a chat response, the exact string MUST come from running `make report-hash` immediately before writing the report — copy its raw output character-for-character. Never write a commit hash from memory or from an earlier line in the conversation, even if it was seen moments ago.

### Proactive Commit Disclosure Rule
At the start of EVERY response to the user (not just when asked), if any commits exist that were not already reported in a previous response, the agent MUST proactively list them before doing anything else — run `git log --oneline <last-reported-SHA>..HEAD` (or `make since-last-report SINCE=<last-reported-SHA>`) and paste the full list, even if the user's current message is about something unrelated. The agent must track (e.g., in a comment or scratch note) which SHA was last reported to the user, so this check is always relative to the true last-disclosed state, not just 'since I last checked.' Silence about intervening commits is not acceptable, even if the work was correct and tests passed — the user must always have visibility into everything that changed, not just what they asked about.

## No Illustrative or Reconstructed Output

When presenting command output (test results, build logs, hook output, etc.) in a chat response, you must paste the EXACT text that was actually captured from the tool call — character for character. You must NEVER write lines that "represent" or "illustrate" what output would typically look like, even if you believe the real output would have been similar or identical. This applies even to trivial, low-risk lines.

If you did not directly capture a piece of output (e.g., you're summarizing from memory, or reconstructing what a log likely said), you must say so explicitly — e.g., "I did not capture the literal text of this line; based on the script's logic, no output would print here" — rather than writing a plausible-looking log line as if it were real.

This rule exists because a fabricated-but-plausible log line is functionally indistinguishable from a hallucinated one to anyone reading the report, even when the underlying work was done correctly. "Illustrative" output defeats the entire purpose of raw-output verification.



