module github.com/project/notification-service

go 1.24

require (
	github.com/alicebob/miniredis/v2 v2.38.0
	github.com/golang-jwt/jwt/v5 v5.3.1
	github.com/redis/go-redis/v9 v9.21.0
	github.com/sony/gobreaker/v2 v2.4.0
	github.com/project/shared/infra v0.0.0
)

require (
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/yuin/gopher-lua v1.1.1 // indirect
	go.uber.org/atomic v1.11.0 // indirect
)

replace github.com/project/shared/infra => ../../shared/infra
