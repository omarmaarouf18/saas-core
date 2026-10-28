#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Quick Delivery — Staging Stack Provisioning & Health Gate
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
STAGING_DIR="${STAGING_DIR:-$REPO_ROOT/infrastructure/staging}"
COMPOSE_FILE="${COMPOSE_FILE:-$STAGING_DIR/docker-compose.staging.yml}"
ENV_FILE="${ENV_FILE:-$STAGING_DIR/.env.staging}"

echo "== [STAGING] Validating Staging Environment =="

if [ ! -f "$ENV_FILE" ]; then
  echo "[STAGING] .env.staging not found, creating from .env.staging.example..."
  # Generate random passwords for mongo and redis (URL-safe hex to avoid URI encoding issues)
  MONGO_PASS="$(openssl rand -hex 16)"
  REDIS_PASS="$(openssl rand -hex 16)"

  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *MONGO_INITDB_ROOT_PASSWORD=CHANGE_ME_PASSWORD*)
        line="${line/CHANGE_ME_PASSWORD/$MONGO_PASS}"
        ;;
      *MONGO_URI=*CHANGE_ME_PASSWORD*)
        line="${line/CHANGE_ME_PASSWORD/$MONGO_PASS}"
        ;;
      *REDIS_PASSWORD=CHANGE_ME_PASSWORD*)
        line="${line/CHANGE_ME_PASSWORD/$REDIS_PASS}"
        ;;
      *REDIS_URI=*CHANGE_ME_PASSWORD*)
        line="${line/CHANGE_ME_PASSWORD/$REDIS_PASS}"
        ;;
      *CHANGE_ME_PASSWORD*)
        extra_pw="$(openssl rand -hex 16)"
        line="${line/CHANGE_ME_PASSWORD/$extra_pw}"
        ;;
    esac

    while [[ "$line" == *"CHANGE_ME_64_HEX"* ]]; do
      hex32="$(openssl rand -hex 32)"
      line="${line/CHANGE_ME_64_HEX/$hex32}"
    done

    printf '%s\n' "$line"
  done < "$STAGING_DIR/.env.staging.example" > "$ENV_FILE"
fi

if [ "${STAGING_ENV_ONLY:-0}" = "1" ] || [ "${1:-}" = "--env-only" ]; then
  exit 0
fi

# Ensure certificates exist
if [ ! -f "$REPO_ROOT/infrastructure/certs/ca.crt" ] || [ ! -f "$REPO_ROOT/infrastructure/certs/reviewer-console.crt" ]; then
  echo "[STAGING] Generating missing certificates..."
  bash "$REPO_ROOT/infrastructure/certs/generate-certs.sh"
fi

# Ensure correct key permissions for container compatibility (DEPLOYMENT.md §5.3)
chmod 644 "$REPO_ROOT"/infrastructure/certs/*.key 2>/dev/null || true
chmod 644 "$REPO_ROOT"/infrastructure/certs/*.crt 2>/dev/null || true

echo "[STAGING] Validating docker compose syntax..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config --quiet || {
  echo "::error::Staging docker-compose.staging.yml validation failed!"
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" config
  exit 1
}

echo "[STAGING] Starting Staging Stack (Isolated Mongo/Redis, Production Images, Caddy)..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

# Read port configurations
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [ -n "${GITHUB_ENV:-}" ] && [ -f "$GITHUB_ENV" ]; then
  {
    echo "STAGING_MONGO_URI=mongodb://${MONGO_INITDB_ROOT_USERNAME:-staging_root}:${MONGO_INITDB_ROOT_PASSWORD}@localhost:${STAGING_MONGO_PORT:-27018}/?authSource=admin"
    echo "STAGING_REDIS_URI=redis://:${REDIS_PASSWORD}@localhost:${STAGING_REDIS_PORT:-6381}/0"
    echo "JWT_SECRET=$JWT_SECRET"
    echo "INTERNAL_SERVICE_TOKEN=$INTERNAL_SERVICE_TOKEN"
    echo "ADMIN_API_TOKEN=$ADMIN_API_TOKEN"
  } >> "$GITHUB_ENV"
fi

CADDY_HTTP_PORT="${STAGING_CADDY_HTTP_PORT:-8088}"
CADDY_CONSOLE_PORT="${STAGING_CADDY_CONSOLE_PORT:-8091}"

echo "[STAGING] Waiting for Staging Gateway through Caddy (http://localhost:${CADDY_HTTP_PORT}/health)..."
MAX_ATTEMPTS=45
ATTEMPT=0
GATEWAY_READY=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${CADDY_HTTP_PORT}/health" || true)
  if [ "$STATUS" = "200" ]; then
    echo "[STAGING] Gateway is UP and responding through Caddy reverse proxy! (attempt $ATTEMPT)"
    GATEWAY_READY=1
    break
  fi
  sleep 2
done

if [ "$GATEWAY_READY" -ne 1 ]; then
  echo "::error::Staging Gateway failed to become ready within deadline."
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs --tail 50
  exit 1
fi

echo "[STAGING] Waiting for Reviewer Console through Caddy (http://localhost:${CADDY_CONSOLE_PORT}/healthz)..."
ATTEMPT=0
CONSOLE_READY=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${CADDY_CONSOLE_PORT}/healthz" || true)
  if [ "$STATUS" = "200" ]; then
    echo "[STAGING] Reviewer Console is UP and responding through Caddy! (attempt $ATTEMPT)"
    CONSOLE_READY=1
    break
  fi
  sleep 2
done

if [ "$CONSOLE_READY" -ne 1 ]; then
  echo "::error::Reviewer Console failed to become ready within deadline."
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" logs kyc-reviewer-console
  exit 1
fi

echo "================================================================="
echo "STAGING STACK READY"
echo "  - Caddy API Gateway:   http://localhost:${CADDY_HTTP_PORT}"
echo "  - Caddy KYC Console:   http://localhost:${CADDY_CONSOLE_PORT}"
echo "  - Isolated Mongo Port: ${STAGING_MONGO_PORT:-27018}"
echo "  - Isolated Redis Port: ${STAGING_REDIS_PORT:-6381}"
echo "================================================================="
