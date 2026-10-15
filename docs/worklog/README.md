# docs/worklog/ — agent task worklogs

One worklog per agent task: `docs/worklog/<TASK-ID>.md`.

On an agent branch (`agent/<TASK-ID>-<slug>`), the agent does NOT edit
`AI_CONTEXT.md`, `docs/changelog/**`, or `docs/frontend/STATUS.md`. Instead it
creates or appends this worklog file, and the owner folds it into the shared
docs at merge time (see [docs/WORKFLOW.md](../WORKFLOW.md)).

Rules:

- Agent branches contain **no full 40-character commit SHAs anywhere** —
  worklogs included — because a rebase or merge changes them. Short SHAs
  appear in the final chat report only. The owner cites real SHAs from the
  integration branch when folding the worklog into the shared docs.
- The worklog records what was verified and, just as importantly, what was
  NOT verified, plus every open question. Never guess: an open question is
  written down and the task stops.
- Create the file with the template below and append to it as the task
  progresses; one file per task ID, even if the task spans multiple sessions.

## Template

````markdown
# Worklog: <TASK-ID> — <short title>

## Task and scope
- Task ID: <TASK-ID>
- Item IDs covered: <item IDs from the task prompt, or "none">
- Allowed paths (lane from the task prompt): <paths>
- Agent branch: agent/<TASK-ID>-<slug>, created from <base branch> (short SHA ok)

## Decisions taken
- <one decision per line; write "none" if no decisions were needed>

## Changes per commit (message only — NO SHAs)
1. `<commit message subject line>`
2. ...

## Verification
- `make ci` — <PASS/FAIL>
- <each additional gate command actually run and its result, e.g.>
- `gofmt -l .` — <empty>
- `go vet ./...` — <result>
- <acceptance/check commands from the task prompt and their results>

## Unverified
- <anything stated in the task report that was NOT verified, with the reason;
  write "none" if everything was verified>

## Follow-ups / out-of-lane findings
- <problems noticed outside the task lane, not fixed here; write "none">

## Open questions
- <questions that need an owner decision; write "none">
````
