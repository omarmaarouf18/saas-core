.PHONY: docs docs-check setup ci ensure-hooks commit push

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
	git push origin logic-exploitation
