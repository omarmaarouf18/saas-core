.PHONY: docs docs-check setup ci ensure-hooks commit push since-last-report

ensure-hooks:
	@if [ "$$(git config --get core.hooksPath 2>/dev/null)" != ".githooks" ]; then \
		git config core.hooksPath .githooks; \
		echo "[MAKE] Configured git core.hooksPath to .githooks"; \
	fi

setup: ensure-hooks
	@echo "Git hooks path set to .githooks/"

docs: ensure-hooks
	go run tools/docgen/main.go

docs-check: ensure-hooks
	go test -v ./shared/infra/...

ci: ensure-hooks
	./.githooks/pre-push

commit: ensure-hooks
	git add -A && git commit -m "$(MSG)"

push: ensure-hooks
	@BRANCH=$$(git rev-parse --abbrev-ref HEAD); \
	LOCAL=$$(git rev-parse HEAD); \
	git push origin $$BRANCH; \
	REMOTE=$$(git ls-remote origin $$BRANCH | awk '{print $$1}'); \
	if [ "$$LOCAL" = "$$REMOTE" ]; then \
		echo "PUSH_VERIFIED: $$LOCAL"; \
	else \
		echo "PUSH_MISMATCH: local=$$LOCAL remote=$$REMOTE"; \
		exit 1; \
	fi

since-last-report:
	@if [ -z "$(SINCE)" ]; then \
		echo "Usage: make since-last-report SINCE=<commit-sha>"; \
		exit 1; \
	fi; \
	git log --oneline $(SINCE)..HEAD --stat


