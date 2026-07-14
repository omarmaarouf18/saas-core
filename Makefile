.PHONY: docs docs-check

docs:
	go run tools/docgen/main.go

docs-check:
	go test -v ./shared/infra/...
