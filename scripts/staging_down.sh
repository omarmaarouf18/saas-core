#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
STAGING_DIR="$REPO_ROOT/infrastructure/staging"
COMPOSE_FILE="$STAGING_DIR/docker-compose.staging.yml"
ENV_FILE="$STAGING_DIR/.env.staging"

echo "== [STAGING] Tearing down Staging Stack =="
if [ -f "$ENV_FILE" ]; then
  docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down -v --remove-orphans
else
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans
fi
echo "== [STAGING] Stack torn down and volumes cleared =="
