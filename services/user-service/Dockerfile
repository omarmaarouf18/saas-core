# ===========================================================================
# Multi-stage Dockerfile — Go Service
# ===========================================================================

# ---- Development Stage ---------------------------------------------------
FROM golang:1.26-alpine AS dev

RUN apk add --no-cache git \
    && go install github.com/air-verse/air@v1.52.2

WORKDIR /app

COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true

COPY . .

EXPOSE 3003

CMD ["air", "-c", ".air.toml"]

# ---- Build Stage ---------------------------------------------------------
FROM golang:1.26-alpine AS build

WORKDIR /app/services/user-service

COPY shared/infra /app/shared/infra
COPY services/user-service/go.mod services/user-service/go.sum* ./
RUN go mod download 2>/dev/null || true

COPY services/user-service/ .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/service ./cmd/main.go

# ---- Production Stage ----------------------------------------------------
FROM alpine:3.20 AS prod

RUN apk --no-cache add ca-certificates curl \
    && addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=build /bin/service /bin/service

EXPOSE 3003

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f -s -k --cert /app/certs/user-service.crt --key /app/certs/user-service.key https://localhost:3003/health || curl -f -s -k --cert /app/certs/server.crt --key /app/certs/server.key https://localhost:3003/health || curl -f -s -k https://localhost:3003/health || curl -f -s http://localhost:3003/health || exit 1

USER appuser

ENTRYPOINT ["/bin/service"]
