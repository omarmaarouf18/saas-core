module github.com/project/tests/e2e

go 1.26

toolchain go1.26.6

require (
	github.com/gorilla/websocket v1.5.3
	github.com/project/shared/infra v0.0.0
	go.mongodb.org/mongo-driver/v2 v2.0.0
)

replace github.com/project/shared/infra => ../../shared/infra
