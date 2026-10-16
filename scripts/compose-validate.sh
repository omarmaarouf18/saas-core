#!/usr/bin/env bash
#
# scripts/compose-validate.sh — structural validation of the compose stacks (WF-03).
#
#   scripts/compose-validate.sh [<stack> ...]      # stacks: local staging prod (default: all)
#
# Runs `docker compose -f <file> config -q` for each stack. Needs no secrets:
# the stack's committed *.example env file is used when there is one, and every
# variable the compose file marks as required (`${NAME:?...}`) that is still
# unset gets the placeholder value CHANGE_ME_compose_validation. This checks
# YAML syntax, schema and interpolation, not the real values. Every other
# referenced variable that is neither set in the environment nor given a
# non-empty value by the example file gets the same placeholder (an empty
# value can make a command line invalid, e.g. `--requirepass ${REDIS_PASSWORD}`).
#
# Used by the scoped local gate (.githooks/pre-push, infrastructure/** scope)
# and by .github/workflows/ci.yml (all stacks).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

stack_file() {
	case "$1" in
	local) echo "infrastructure/docker-compose.yml" ;;
	staging) echo "infrastructure/staging/docker-compose.staging.yml" ;;
	prod) echo "infrastructure/deploy/docker-compose.prod.yml" ;;
	*) return 1 ;;
	esac
}

stack_env_example() {
	case "$1" in
	local | prod) echo "infrastructure/.env.example" ;;
	staging) echo "infrastructure/staging/.env.staging.example" ;;
	esac
}

if [ "$#" -eq 0 ]; then
	set -- local staging prod
fi

command -v docker >/dev/null 2>&1 || {
	echo "BLOCKED: docker is not installed; compose validation needs 'docker compose'"
	exit 1
}

FAILED=0
for stack in "$@"; do
	file="$(stack_file "$stack")" || {
		echo "BLOCKED: unknown compose stack '$stack' (known: local staging prod)"
		exit 1
	}
	env_args=()
	env_file="$(stack_env_example "$stack")"
	if [ -n "$env_file" ] && [ -f "$env_file" ]; then
		env_args=(--env-file "$env_file")
	fi
	# Placeholders, in a subshell so nothing leaks.
	if (
		for name in $(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' "$file" | sed -E 's/^\$\{//' | sort -u); do
			[ -z "${!name:-}" ] || continue
			if [ -n "$env_file" ] && [ -f "$env_file" ] &&
				grep -qE "^${name}=[^[:space:]#]" "$env_file"; then
				continue
			fi
			export "$name=CHANGE_ME_compose_validation"
		done
		rc=0
		out="$(docker compose -f "$file" "${env_args[@]}" config -q 2>&1)" || rc=$?
		printf '%s\n' "$out" | grep -v -e 'level=warning' -e '^$' || true
		exit "$rc"
	); then
		echo "compose config OK: $stack ($file)"
	else
		echo "BLOCKED: docker compose config failed for $stack ($file)"
		FAILED=1
	fi
done
exit "$FAILED"
