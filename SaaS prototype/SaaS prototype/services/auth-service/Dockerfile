# ===========================================================================
# Multi-stage Dockerfile — Go Service
# ===========================================================================

# ---- Development Stage ---------------------------------------------------
FROM golang:1.23-alpine AS dev

RUN apk add --no-cache git \
    && go install github.com/air-verse/air@latest

WORKDIR /app

COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true

COPY . .

EXPOSE 3002

CMD ["air", "-c", ".air.toml"]

# ---- Build Stage ---------------------------------------------------------
FROM golang:1.23-alpine AS build

WORKDIR /app

COPY go.mod go.sum* ./
RUN go mod download 2>/dev/null || true

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bin/service ./cmd/main.go

# ---- Production Stage ----------------------------------------------------
FROM alpine:3.20 AS prod

RUN apk --no-cache add ca-certificates

COPY --from=build /bin/service /bin/service

EXPOSE 3002

ENTRYPOINT ["/bin/service"]
