.PHONY: docs docs-counts docs-check setup check ci ci-full ensure-hooks commit push since-last-report report-hash backend-frontend-parity-check contract-test worktree-new worktree-list worktree-remove release-status release

# --- WF-01 parallel-agent workflow constants ---------------------------------
# The integration branch agents branch off and the owner merges into.
INTEGRATION_BRANCH := logic-exploitation
# Push-block message, shared with .githooks/pre-push (Layer B); Layer A is the
# per-worktree remote.origin.pushurl set by scripts/agent-worktree.sh.
BLOCKED_MSG = "BLOCKED: agents never push; the owner merges and pushes from the main worktree"
# The CI lock (scripts/ci-lock.sh) and the gate pass stamps
# (scripts/gate-stamp.sh) live under the COMMON git dir, shared by all
# worktrees.
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

# WF-03: the local gate is SCOPED to what changed; GitHub CI
# (.github/workflows/ci.yml) is the single full gate.
#   make check    scoped gate (scripts/changed-scope.sh prints the scope and
#                 why); a pass writes the stamp `make commit` requires.
#   make ci       same as `make check` (kept for muscle memory).
#   make ci-full  everything (CI_SCOPE=full); also writes a stamp.
# All three run .githooks/pre-push WITHOUT arguments, so the WF-01 agent push
# guard inside it (which only fires for real git push hook invocations) is
# skipped and the checks run in any worktree. The hook exports
# TEST_DB_SUFFIX=<worktree dir name>-<pid> (unless already set) and takes the
# CI lock itself.
check: ensure-hooks
	@./.githooks/pre-push

ci: check

ci-full: ensure-hooks
	@CI_SCOPE=full ./.githooks/pre-push

contract-test: ensure-hooks
	cd tests/contracts && go test -v -count=1 ./...

# WF-01: no `git add -A` — FILES is required, so untracked files (including
# .env*) can never be swept into a commit.
# WF-02: implemented in scripts/commit.sh, which reads FILES / MSG / MSG_FILE
# from the environment (make exports command-line variables), so quotes and
# multi-line messages are safe. Exactly one of MSG / MSG_FILE is required;
# staged deletions in FILES work; only FILES are committed (other staged paths
# stay staged, with a warning).
commit: ensure-hooks
	@bash scripts/commit.sh

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

# --- WF-RELEASE release commands ---------------------------------------------
release-status: ensure-hooks
	@bash scripts/release-status.sh $(if $(REF),$(REF),$(INTEGRATION_BRANCH))

release: ensure-hooks
	@bash scripts/release.sh $(if $(WAIT),--wait,) $(if $(DRY_RUN),--dry-run,)
# -----------------------------------------------------------------------------

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



