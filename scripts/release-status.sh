#!/usr/bin/env bash
#
# scripts/release-status.sh — inspect release readiness for production.
#
# Read-only. Prints:
#   1. logic-exploitation HEAD (short SHA)
#   2. Commits ahead of origin/main (one line each)
#   3. Status and conclusion of required workflows (CI Gate, Release Gate E2E)
#      via gh run list --commit
#
set -euo pipefail

TARGET_REF="${1:-logic-exploitation}"
MAIN_REF="origin/main"
REQUIRED_WORKFLOWS=("CI Gate" "Release Gate E2E")

# 1. Resolve commit SHA
if ! FULL_SHA=$(git rev-parse --verify "${TARGET_REF}^{commit}" 2>/dev/null); then
	echo "ERROR: Target ref '${TARGET_REF}' does not resolve to a commit" >&2
	exit 1
fi
SHORT_SHA=$(git rev-parse --short "$FULL_SHA")

echo "=== Release Status ==="
echo "logic-exploitation HEAD: ${SHORT_SHA} (${FULL_SHA})"
echo

# 2. Commits ahead of origin/main
if git rev-parse --verify "${MAIN_REF}^{commit}" >/dev/null 2>&1; then
	AHEAD_COMMITS=$(git log --oneline "${MAIN_REF}..${FULL_SHA}")
	if [ -z "$AHEAD_COMMITS" ]; then
		echo "Commits ahead of ${MAIN_REF}: 0 (up to date or behind)"
	else
		COUNT=$(echo "$AHEAD_COMMITS" | wc -l | tr -d ' ')
		echo "Commits ahead of ${MAIN_REF} (${COUNT}):"
		echo "$AHEAD_COMMITS"
	fi
else
	echo "Notice: ${MAIN_REF} not found in repository. Recent commits on ${TARGET_REF}:"
	git log --oneline -n 5 "$FULL_SHA"
fi
echo

# 3. Check gh CLI
if ! command -v gh >/dev/null 2>&1; then
	echo "ERROR: 'gh' CLI tool is required but not found on PATH" >&2
	exit 1
fi

# 4. Check required workflow runs via gh run list --commit
echo "Required workflows for ${SHORT_SHA}:"

RUNS_JSON=$(gh run list --commit "$FULL_SHA" --json workflowName,name,status,conclusion,url 2>/dev/null || true)
if [ -n "$RUNS_JSON" ] && command -v jq >/dev/null 2>&1; then
	for wf in "${REQUIRED_WORKFLOWS[@]}"; do
		WF_INFO=$(echo "$RUNS_JSON" | jq -r --arg name "$wf" '
			[.[] | select((.workflowName == $name) or (.name == $name))] | first // empty
		')
		if [ -z "$WF_INFO" ] || [ "$WF_INFO" = "null" ]; then
			echo "  - $wf: NOT FOUND"
		else
			STATUS=$(echo "$WF_INFO" | jq -r '.status // "unknown"')
			CONCLUSION=$(echo "$WF_INFO" | jq -r '.conclusion // "in_progress"')
			URL=$(echo "$WF_INFO" | jq -r '.url // ""')
			echo "  - $wf: status=${STATUS}, conclusion=${CONCLUSION} (${URL})"
		fi
	done
else
	echo "  (Could not query JSON runs; falling back to tabular list)"
fi

echo
echo "Workflow runs (gh run list --commit ${SHORT_SHA}):"
gh run list --commit "$FULL_SHA" || true
