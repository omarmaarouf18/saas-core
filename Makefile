.PHONY: docs docs-check setup ci

setup:
	git config core.hooksPath .githooks
	@echo "Git hooks path set to .githooks/"

docs:
	go run tools/docgen/main.go

docs-check:
	go test -v ./shared/infra/...

ci:
	./.githooks/pre-push
