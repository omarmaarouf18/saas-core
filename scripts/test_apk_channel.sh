#!/usr/bin/env bash
#
# scripts/test_apk_channel.sh — the website download and the in-app update
# must hand out the same APK (FE-APK-CHANNEL).
#
#   bash scripts/test_apk_channel.sh
#   APK_WORKFLOW=<path> bash scripts/test_apk_channel.sh   # check another copy
#
# Flutter gives split-per-ABI APKs a version-code offset (arm64-v8a = 2000+n)
# while the universal app-release.apk has code n. The api-gateway default
# download_url (forced-update gate) is releases/latest/download/app-release.apk,
# so the website's default download (app-release.json `apk_url`, written by
# frontend/.github/workflows/build-apk.yml) must be that universal file too:
# a phone that installed a split could never install the gate's update.
# No `set -e`: a failing check must be reported, not abort the run.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW="${APK_WORKFLOW:-$ROOT/frontend/.github/workflows/build-apk.yml}"
GATEWAY="$ROOT/services/api-gateway/internal/version/version.go"
fails=0

check() { # check <name> <condition result 0|1> <detail>
	if [ "$2" -eq 0 ]; then
		printf 'ok   %s\n' "$1"
	else
		printf 'FAIL %s: %s\n' "$1" "$3"
		fails=$((fails + 1))
	fi
}

# The release step's apk_url output (exactly one).
apk_lines="$(grep -E '^[[:space:]]*echo "apk_url=' "$WORKFLOW" || true)"
n="$(printf '%s' "$apk_lines" | grep -c . || true)"
check "one apk_url output in build-apk.yml" "$([ "$n" -eq 1 ] && echo 0 || echo 1)" "found $n: $apk_lines"
printf '%s\n' "$apk_lines" | grep -qE '/app-release\.apk" >> "\$GITHUB_OUTPUT"$'
check "apk_url points at the universal app-release.apk" $? "got: $apk_lines"

# app-release.json takes apk_url from that output, and the universal entry
# from the same file name.
grep -qF '"apk_url": "${{ steps.release.outputs.apk_url }}"' "$WORKFLOW"
check "app-release.json apk_url comes from the release output" $? "template line missing"
grep -qE '^[[:space:]]*echo "apk_url_universal=\$\{BASE\}/app-release\.apk"' "$WORKFLOW"
check "apk_urls.universal is app-release.apk" $? "apk_url_universal line missing or changed"

# The workflow's own publish-time guard is still there.
grep -qF '(.apk_url | endswith("/app-release.apk")) and (.apk_url == .apk_urls.universal)' "$WORKFLOW"
check "workflow verifies app-release.json before publishing" $? "jq guard missing"

# The update gate links the same file.
grep -qE 'DownloadURL:[[:space:]]+"https://github\.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release\.apk"' "$GATEWAY"
check "api-gateway download_url is the universal app-release.apk" $? "$GATEWAY default DownloadURL changed"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all apk channel checks passed"
