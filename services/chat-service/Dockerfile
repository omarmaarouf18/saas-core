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

EXPOSE 3001

CMD ["air", "-c", ".air.toml"]

# ---- Build Stage ---------------------------------------------------------
FROM golang:1.26-alpine AS build

WORKDIR /app/services/chat-service

COPY shared/infra /app/shared/infra
COPY services/chat-service/go.mod services/chat-service/go.sum* ./
RUN go mod download 2>/dev/null || true

COPY services/chat-service/ .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/service ./cmd/main.go

# ---- Production Stage ----------------------------------------------------
FROM alpine:3.20 AS prod

RUN apk --no-cache add ca-certificates curl

COPY --from=build /bin/service /bin/service

EXPOSE 3001

ENTRYPOINT ["/bin/service"]
