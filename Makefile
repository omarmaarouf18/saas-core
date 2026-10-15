.PHONY: docs docs-counts docs-check setup ci ensure-hooks commit push since-last-report report-hash backend-frontend-parity-check contract-test worktree-new worktree-list worktree-remove

# --- WF-01 parallel-agent workflow constants ---------------------------------
# The integration branch agents branch off and the owner merges into.
INTEGRATION_BRANCH := logic-exploitation
# Push-block message, shared with .githooks/pre-push (Layer B); Layer A is the
# per-worktree remote.origin.pushurl set by scripts/agent-worktree.sh.
BLOCKED_MSG = "BLOCKED: agents never push; the owner merges and pushes from the main worktree"
# CI lock lives under the COMMON git dir, so every worktree locks the same
# file and parallel worktrees never run integration tests against the shared
# local Mongo/Redis at the same time.
CI_LOCK_FILE := $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || git rev-parse --git-common-dir)/ci.lock
# -----------------------------------------------------------------------------

ensure-hooks:
	@if [ "$$(git config --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then \
		git config core.hooksPath .githooks; \
		echo "[MAKE] Configured git core.hooksPath to .githooks"; \
	fi

setup: ensure-hooks
	@echo "Git hooks path set to .githooks/"

docs: ensure-hooks
	go run tools/docgen/main.go

docs-counts: ensure-hooks
	go run tools/docgen/main.go -counts

docs-check: ensure-hooks
	go run tools/docgen/main.go -check
	go test -v -count=1 ./shared/infra/docgen ./shared/infra/handlerutil ./shared/infra/jwtutil ./shared/infra/ratelimit ./shared/infra/resilience ./shared/infra/tlsutil

backend-frontend-parity-check: ensure-hooks
	go run tools/paritycheck/main.go

# WF-01: the gate runs under flock so parallel worktrees serialize against the
# shared local Mongo/Redis. Prints a waiting line when the lock is held.
# The gate script is invoked WITHOUT arguments here, so the WF-01 agent push
# guard inside it (which only fires for real git push hook invocations) is
# skipped and the full check suite runs in any worktree.
ci: ensure-hooks
	@LOCK_FILE="$(CI_LOCK_FILE)"; \
	exec 9>"$$LOCK_FILE" || exit 1; \
	if ! flock -n 9; then \
		echo "waiting for CI lock: $$LOCK_FILE is held by another make ci"; \
		flock 9 || exit 1; \
	fi; \
	./.githooks/pre-push

contract-test: ensure-hooks
	cd tests/contracts && go test -v -count=1 ./...

# WF-01: no `git add -A` — FILES is required, so untracked files (including
# .env*) can never be swept into a commit.
commit: ensure-hooks
	@if [ -z "$${FILES:-}" ]; then \
		echo "ERROR: FILES is required and must be non-empty: make commit FILES=\"<paths>\" MSG=\"<message>\""; \
		exit 1; \
	fi; \
	if [ -z "$${MSG:-}" ]; then \
		echo "ERROR: MSG is required: make commit FILES=\"<paths>\" MSG=\"<message>\""; \
		exit 1; \
	fi; \
	git add -- $(FILES) && git commit -m "$(MSG)"

# WF-01 push block: refuses from a linked worktree or an agent/* branch; the
# owner keeps using it from the main worktree.
push: ensure-hooks
	@PUSH_GITDIR=$$(git rev-parse --git-dir); \
	PUSH_BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	case "$$PUSH_GITDIR" in */worktrees/*) \
		echo $(BLOCKED_MSG); \
		exit 1 ;; esac; \
	case "$$PUSH_BRANCH" in agent/*) \
		echo $(BLOCKED_MSG); \
		exit 1 ;; esac; \
	LOCAL=$$(git rev-parse HEAD); \
	git push origin $$PUSH_BRANCH; \
	REMOTE=$$(git ls-remote origin $$PUSH_BRANCH | awk '{print $$1}'); \
	if [ "$$LOCAL" = "$$REMOTE" ]; then \
		echo "$$LOCAL" > .last_push_verified; \
		echo "PUSH_VERIFIED: $$LOCAL"; \
	else \
		echo "PUSH_MISMATCH: local=$$LOCAL remote=$$REMOTE"; \
		exit 1; \
	fi

# --- WF-01 worktree convenience targets (scripts/agent-worktree.sh) ----------
worktree-new:
	@if [ -z "$(TASK)" ] || [ -z "$(SLUG)" ]; then \
		echo "Usage: make worktree-new TASK=<TASK-ID> SLUG=<slug> [BASE=<base-branch>]"; \
		exit 1; \
	fi
	./scripts/agent-worktree.sh new "$(TASK)" "$(SLUG)" $(BASE)

worktree-list:
	./scripts/agent-worktree.sh list

worktree-remove:
	@if [ -z "$(TASK)" ]; then \
		echo "Usage: make worktree-remove TASK=<TASK-ID> [FORCE=1]"; \
		exit 1; \
	fi
	./scripts/agent-worktree.sh remove "$(TASK)" $(if $(FORCE),--force,)
# -----------------------------------------------------------------------------

report-hash:
	@if [ ! -f .last_push_verified ]; then \
		echo "ERROR: no .last_push_verified file — run 'make push' first"; \
		exit 1; \
	fi; \
	cat .last_push_verified

since-last-report:
	@if [ -z "$(SINCE)" ]; then \
		echo "Usage: make since-last-report SINCE=<commit-sha>"; \
		exit 1; \
	fi; \
	git log --oneline $(SINCE)..HEAD --stat



