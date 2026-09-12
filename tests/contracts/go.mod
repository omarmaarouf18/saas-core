module github.com/project/tests/contracts

go 1.26

toolchain go1.26.6

require (
	github.com/project/shared/infra v0.0.0
)

replace github.com/project/shared/infra => ../../shared/infra
