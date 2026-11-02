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

# =============================================================================
# Secret masking (BE-HARDEN item 6)
# =============================================================================
# GitHub Actions redacts a value from the workflow log only after it has been
# registered with the `::add-mask::` workflow command. The staging secrets have
# to be registered BEFORE anything can print them:
#   * `docker compose config` interpolates the env file into the compose model
#     and dumps it — the validation fallback below prints the whole model,
#   * the passwords and tokens travel into the container environment.
# Outside GitHub Actions the helper is a no-op, so a local run never prints a
# secret and never writes a `::add-mask::` line into the terminal.
MASK_SECRETS_ENABLED=0
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  MASK_SECRETS_ENABLED=1
fi

# The values that were already registered. GitHub accepts the same mask twice,
# but every secret should be announced exactly once.
MASKED_VALUES=""

# The env file is written by a loop whose stdout is redirected to the file, so
# the mask commands have to go to the original stdout instead.
exec 3>&1

# mask_secret <value> — register <value> as a secret in the GitHub Actions log.
mask_secret() {
  local value="${1:-}"
  [ "$MASK_SECRETS_ENABLED" -eq 1 ] || return 0
  # An empty value is not a secret: GitHub rejects an empty mask, and masking
  # the empty string would blank out unrelated output.
  [ -n "$value" ] || return 0
  # A placeholder that was never replaced is not a secret either — masking it
  # would redact the placeholder text wherever it shows up.
  case "$value" in
    *CHANGE_ME*) return 0 ;;
  esac
  if printf '%s\n' "$MASKED_VALUES" | grep -Fxq -- "$value"; then
    return 0
  fi
  MASKED_VALUES="${MASKED_VALUES}${value}"$'\n'
  printf '::add-mask::%s\n' "$value" >&3
}

# The keys of the staging env file that hold a secret. Everything else in the
# file (ports, service URLs, feature flags) is not a secret and has to stay
# readable in the log.
STAGING_SECRET_KEYS=(
  MONGO_INITDB_ROOT_PASSWORD
  MONGO_URI
  REDIS_PASSWORD
  REDIS_URI
  JWT_SECRET
  GATEWAY_SECRET
  INTERNAL_SERVICE_TOKEN
  ADMIN_API_TOKEN
  OTP_AES_KEY
  DOCUMENT_SIGNING_SECRET
  DOCUMENT_ENCRYPTION_KEY
  RESEND_API_KEY
  FCM_SERVICE_ACCOUNT_JSON_B64
)

# env_file_value <KEY> — print the value of KEY from the staging env file.
# The file is read line by line instead of being sourced, so a value is never
# expanded or evaluated.
env_file_value() {
  local key="$1" line value=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$key="*) value="${line#*=}" ;;
    esac
  done < "$ENV_FILE"
  # An inline comment (`KEY=value # comment`) is not part of the value — strip
  # it the way the compose env-file parser does, then trim the whitespace.
  case "$value" in
    *" #"*) value="${value%% #*}" ;;
  esac
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

# mask_env_secrets — register every secret of the staging env file as a
# GitHub Actions log mask.
mask_env_secrets() {
  local key value
  for key in "${STAGING_SECRET_KEYS[@]}"; do
    value="$(env_file_value "$key")"
    mask_secret "$value"
  done
}

echo "== [STAGING] Validating Staging Environment =="

if [ ! -f "$ENV_FILE" ]; then
  echo "[STAGING] .env.staging not found, creating from .env.staging.example..."
  # Generate random passwords for mongo and redis (URL-safe hex to avoid URI encoding issues)
  MONGO_PASS="$(openssl rand -hex 16)"
  REDIS_PASS="$(openssl rand -hex 16)"
  # Register the fresh secrets before they can reach the log.
  mask_secret "$MONGO_PASS"
  mask_secret "$REDIS_PASS"

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
        mask_secret "$extra_pw"
        line="${line/CHANGE_ME_PASSWORD/$extra_pw}"
        ;;
    esac

    while [[ "$line" == *"CHANGE_ME_64_HEX"* ]]; do
      hex32="$(openssl rand -hex 32)"
      mask_secret "$hex32"
      line="${line/CHANGE_ME_64_HEX/$hex32}"
    done

    printf '%s\n' "$line"
  done < "$STAGING_DIR/.env.staging.example" > "$ENV_FILE"
fi

# Register the secrets of the (freshly created or pre-existing) env file before
# the compose validation below can print them.
mask_env_secrets

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
