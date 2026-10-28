#!/usr/bin/env bash
#
# scripts/test_staging_up.sh — tests for staging .env.staging provisioning (FIX-E2E-PHOTO item 1).
#
# Verifies:
#   1. When .env.staging does not exist, staging_up.sh creates it from .env.staging.example.
#   2. All CHANGE_ME_64_HEX occurrences are replaced with 64-character hex keys.
#   3. Every generated 64-hex secret is unique across keys.
#   4. All CHANGE_ME_PASSWORD occurrences are replaced with non-placeholder passwords.
#   5. Mongo URI password matches MONGO_INITDB_ROOT_PASSWORD.
#   6. Redis URI password matches REDIS_PASSWORD.
#   7. File mode of created .env.staging is 600 (-rw-------).
#   8. An existing .env.staging is never overwritten.
#
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
STAGING_UP="${STAGING_UP_SCRIPT:-$ROOT/scripts/staging_up.sh}"
fails=0

check() { # check <name> <condition result 0|1> <detail>
	if [ "$2" -eq 0 ]; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s: %s\n' "$1" "$3"
		fails=$((fails + 1))
	fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

test_staging_dir="$tmp/staging"
mkdir -p "$test_staging_dir"
cp "$ROOT/infrastructure/staging/.env.staging.example" "$test_staging_dir/.env.staging.example"
test_env_file="$test_staging_dir/.env.staging"

# 1. Run staging_up with STAGING_ENV_ONLY=1 in isolated directory where .env.staging is missing
STAGING_ENV_ONLY=1 STAGING_DIR="$test_staging_dir" ENV_FILE="$test_env_file" bash "$STAGING_UP" >"$tmp/out" 2>"$tmp/err" || true

check ".env.staging created when missing" "$([ -f "$test_env_file" ] && echo 0 || echo 1)" "file missing"

if [ -f "$test_env_file" ]; then
	# 2. Check no CHANGE_ME_64_HEX remains
	hex_placeholders=$(grep -c "CHANGE_ME_64_HEX" "$test_env_file" || true)
	check "no CHANGE_ME_64_HEX in created .env.staging" "$([ "$hex_placeholders" -eq 0 ] && echo 0 || echo 1)" "found $hex_placeholders placeholder(s)"

	# 3. Check no CHANGE_ME_PASSWORD remains
	pw_placeholders=$(grep -c "CHANGE_ME_PASSWORD" "$test_env_file" || true)
	check "no CHANGE_ME_PASSWORD in created .env.staging" "$([ "$pw_placeholders" -eq 0 ] && echo 0 || echo 1)" "found $pw_placeholders placeholder(s)"

	# 4. Check that 64-hex keys are valid 64-character lowercase hex strings
	hex_vars=(JWT_SECRET GATEWAY_SECRET INTERNAL_SERVICE_TOKEN ADMIN_API_TOKEN OTP_AES_KEY DOCUMENT_SIGNING_SECRET DOCUMENT_ENCRYPTION_KEY)
	valid_hex=0
	declare -a extracted_hexes=()
	for v in "${hex_vars[@]}"; do
		val=$(grep -E "^${v}=" "$test_env_file" | cut -d'=' -f2 | tr -d '[:space:]')
		if [[ "$val" =~ ^[0-9a-f]{64}$ ]]; then
			valid_hex=$((valid_hex + 1))
			extracted_hexes+=("$val")
		fi
	done
	check "all 7 secrets are valid 64-hex strings" "$([ "$valid_hex" -eq 7 ] && echo 0 || echo 1)" "only $valid_hex/7 valid"

	# 5. Check uniqueness of generated keys
	unique_count=$(printf '%s\n' "${extracted_hexes[@]}" | sort -u | grep -c . || true)
	check "all generated 64-hex keys are unique" "$([ "$unique_count" -eq 7 ] && echo 0 || echo 1)" "only $unique_count unique out of 7"

	# 6. Mongo URI matches MONGO_INITDB_ROOT_PASSWORD
	mongo_pw=$(grep -E "^MONGO_INITDB_ROOT_PASSWORD=" "$test_env_file" | cut -d'=' -f2- | tr -d '[:space:]')
	mongo_uri=$(grep -E "^MONGO_URI=" "$test_env_file" | cut -d'=' -f2- | tr -d '[:space:]')
	expected_mongo_uri="mongodb://staging_root:${mongo_pw}@mongo:27017/?authSource=admin"
	check "Mongo URI password matches root password" "$([ -n "$mongo_pw" ] && [ "$mongo_uri" = "$expected_mongo_uri" ] && echo 0 || echo 1)" "root: $mongo_pw, uri: $mongo_uri"

	# 7. Redis URI matches REDIS_PASSWORD
	redis_pw=$(grep -E "^REDIS_PASSWORD=" "$test_env_file" | cut -d'=' -f2- | tr -d '[:space:]')
	redis_uri=$(grep -E "^REDIS_URI=" "$test_env_file" | cut -d'=' -f2- | tr -d '[:space:]')
	expected_redis_uri="redis://:${redis_pw}@redis:6379"
	check "Redis URI password matches redis password" "$([ -n "$redis_pw" ] && [ "$redis_uri" = "$expected_redis_uri" ] && echo 0 || echo 1)" "pw: $redis_pw, uri: $redis_uri"

	# 8. File mode is 600
	file_mode=$(stat -c "%a" "$test_env_file" 2>/dev/null || stat -f "%OLp" "$test_env_file" 2>/dev/null || true)
	check ".env.staging permissions are 600" "$([ "$file_mode" = "600" ] && echo 0 || echo 1)" "mode is $file_mode"
fi

# 9. Existing .env.staging is never overwritten
sentinel_content="SENTINEL_CUSTOM_SETTING=keep_me_safe"
echo "$sentinel_content" > "$test_env_file"
chmod 600 "$test_env_file"

STAGING_ENV_ONLY=1 STAGING_DIR="$test_staging_dir" ENV_FILE="$test_env_file" bash "$STAGING_UP" >"$tmp/out2" 2>"$tmp/err2" || true
still_has_sentinel=$(grep -c "SENTINEL_CUSTOM_SETTING=keep_me_safe" "$test_env_file" || true)
check "existing .env.staging is never overwritten" "$([ "$still_has_sentinel" -eq 1 ] && echo 0 || echo 1)" "sentinel was overwritten or lost"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all staging_up environment provisioning checks passed"
