# ===========================================================================
# Multi-stage Dockerfile — Go Service
# ===========================================================================

# ---- Development Stage ---------------------------------------------------
FROM golang:1.26.6-alpine AS dev

RUN apk add --no-cache git \
    && go install github.com/air-verse/air@v1.52.2

WORKDIR /app

COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true

COPY . .

EXPOSE 3002

CMD ["air", "-c", ".air.toml"]

# ---- Build Stage ---------------------------------------------------------
FROM golang:1.26.6-alpine AS build

WORKDIR /app/services/auth-service

COPY shared/infra /app/shared/infra
COPY services/auth-service/go.mod services/auth-service/go.sum* ./
RUN go mod download 2>/dev/null || true

COPY services/auth-service/ .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/service ./cmd/main.go

# ---- Production Stage ----------------------------------------------------
FROM alpine:3.20 AS prod

RUN apk --no-cache add ca-certificates curl \
    && addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app
# Pre-create the KYB/KYE document storage dir with appuser ownership so that
# a fresh staging_saas_documents_data named volume mounted at
# /app/data/documents inherits writable ownership (the service runs as
# appuser and fail-fasts/fails uploads on EACCES otherwise).
RUN mkdir -p /app/data/documents && chown -R appuser:appgroup /app

COPY --from=build /bin/service /bin/service

EXPOSE 3002

HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f -s -k --cert /app/certs/auth-service.crt --key /app/certs/auth-service.key https://localhost:3002/health || curl -f -s -k --cert /app/certs/server.crt --key /app/certs/server.key https://localhost:3002/health || curl -f -s -k https://localhost:3002/health || curl -f -s http://localhost:3002/health || exit 1

USER appuser

ENTRYPOINT ["/bin/service"]
