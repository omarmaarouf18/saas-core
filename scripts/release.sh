#!/usr/bin/env bash
#
# scripts/release.sh — guarded release to production (WF-RELEASE).
#
# Preconditions:
#   1. Current branch is logic-exploitation
#   2. Clean working tree (untracked files listed; allowed only in standalone
#      scratch directories like scratch/ or tmp/, not under tracked dirs or at root)
#   3. local logic-exploitation == origin/logic-exploitation
#   4. origin/main is an ancestor of logic-exploitation (fast-forward only)
#   5. CI Gate and Release Gate E2E are completed and successful on the exact SHA
#      (no "in progress"; --wait flag polls every 30s up to a limit)
#
# Execution:
#   - Shows commit list ahead of origin/main
#   - Asks for typed confirmation ("release")
#   - Runs git push origin <sha>:main (pushing exact SHA to avoid races)
#   - Verifies origin/main == <sha>
#   - Prints RELEASE_VERIFIED: <short sha> and deploy workflow run URL
#   - Leaves the repository on logic-exploitation
#
# RELEASE_DRY_RUN=1 (or --dry-run) performs all checks and confirmation, but skips push.
#
set -euo pipefail

WAIT_FLAG=0
DRY_RUN="${RELEASE_DRY_RUN:-0}"
POLL_INTERVAL="${RELEASE_POLL_INTERVAL:-30}"
POLL_LIMIT="${RELEASE_POLL_LIMIT:-60}"

while [ $# -gt 0 ]; do
	case "$1" in
		--wait) WAIT_FLAG=1; shift ;;
		--dry-run) DRY_RUN=1; shift ;;
		*) echo "Unknown option: $1" >&2; exit 1 ;;
	esac
done

if [ "${RELEASE_WAIT:-0}" = "1" ]; then
	WAIT_FLAG=1
fi

REQUIRED_BRANCH="logic-exploitation"
REQUIRED_WORKFLOWS=("CI Gate" "Release Gate E2E")
FAILURES=()

echo "=== Guarded Production Release ==="
if [ "$DRY_RUN" = "1" ]; then
	echo "[DRY RUN MODE ENABLED]"
fi
echo

# 1. Branch check
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "$REQUIRED_BRANCH" ]; then
	FAILURES+=("Current branch is '$CURRENT_BRANCH'; release must be performed from '$REQUIRED_BRANCH'. Switch to it: git checkout $REQUIRED_BRANCH")
fi

# 2. Clean tree check
if ! git diff --quiet; then
	FAILURES+=("Working tree has unstaged modifications to tracked files")
fi
if ! git diff --cached --quiet; then
	FAILURES+=("Index has staged uncommitted changes")
fi

# Check untracked files
UNTRACKED=$(git ls-files --others --exclude-standard)
if [ -n "$UNTRACKED" ]; then
	echo "Untracked files present:"
	echo "$UNTRACKED" | sed 's/^/  /'
	FORBIDDEN_UNTRACKED=()
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		# Dedicated scratch directories like scratch/ and tmp/ are allowed
		case "$f" in
			scratch/*|tmp/*) ;;
			*)
				FORBIDDEN_UNTRACKED+=("$f")
				;;
		esac
	done <<<"$UNTRACKED"

	if [ "${#FORBIDDEN_UNTRACKED[@]}" -gt 0 ]; then
		FAILURES+=("Untracked files found outside scratch directories (allowed only in scratch/ or tmp/): ${FORBIDDEN_UNTRACKED[*]}")
	fi
fi

# 3. Synchronize with remote
git fetch origin logic-exploitation main >/dev/null 2>&1 || true

if ! LOCAL_SHA=$(git rev-parse --verify "refs/heads/${REQUIRED_BRANCH}^{commit}" 2>/dev/null); then
	FAILURES+=("Local branch '$REQUIRED_BRANCH' does not resolve to a commit")
	LOCAL_SHA=""
fi

REMOTE_LOGIC_SHA=$(git rev-parse --verify "refs/remotes/origin/${REQUIRED_BRANCH}^{commit}" 2>/dev/null || true)
if [ -z "$REMOTE_LOGIC_SHA" ]; then
	FAILURES+=("Remote branch 'origin/$REQUIRED_BRANCH' does not exist")
elif [ -n "$LOCAL_SHA" ] && [ "$LOCAL_SHA" != "$REMOTE_LOGIC_SHA" ]; then
	FAILURES+=("Local $REQUIRED_BRANCH ($LOCAL_SHA) does not match origin/$REQUIRED_BRANCH ($REMOTE_LOGIC_SHA). Run 'make push' or 'git pull' first")
fi

# 4. Fast-forward ancestry check
REMOTE_MAIN_SHA=$(git rev-parse --verify "refs/remotes/origin/main^{commit}" 2>/dev/null || true)
if [ -z "$REMOTE_MAIN_SHA" ]; then
	FAILURES+=("Remote branch 'origin/main' does not exist")
elif [ -n "$LOCAL_SHA" ]; then
	if ! git merge-base --is-ancestor "$REMOTE_MAIN_SHA" "$LOCAL_SHA"; then
		FAILURES+=("origin/main ($REMOTE_MAIN_SHA) is not an ancestor of $REQUIRED_BRANCH ($LOCAL_SHA); fast-forward merge to main is impossible")
	elif [ "$REMOTE_MAIN_SHA" = "$LOCAL_SHA" ]; then
		FAILURES+=("origin/main is already up to date with $REQUIRED_BRANCH ($LOCAL_SHA); nothing to release")
	fi
fi

# 5. Required CI status check on target SHA
if [ -n "$LOCAL_SHA" ]; then
	if ! command -v gh >/dev/null 2>&1; then
		FAILURES+=("'gh' CLI tool is required to verify workflow runs but was not found on PATH")
	else
		TARGET_SHORT_SHA=$(git rev-parse --short "$LOCAL_SHA")
		echo "Checking required workflows for $TARGET_SHORT_SHA..."

		check_workflows() {
			local json
			json=$(gh run list --commit "$LOCAL_SHA" --json workflowName,name,status,conclusion,url 2>/dev/null || true)
			if [ -z "$json" ]; then
				echo "NONE"
				return 0
			fi
			echo "$json"
		}

		poll_count=0
		while true; do
			RUNS_JSON=$(check_workflows)
			ALL_SUCCESS=1
			ANY_IN_PROGRESS=0
			ANY_FAILED=0
			FAILED_DETAILS=()

			if [ "$RUNS_JSON" = "NONE" ]; then
				ANY_IN_PROGRESS=1
				FAILED_DETAILS+=("No workflow runs found yet for commit $TARGET_SHORT_SHA")
			elif ! command -v jq >/dev/null 2>&1; then
				FAILURES+=("'jq' is required to parse GitHub workflow runs")
				break
			else
				for wf in "${REQUIRED_WORKFLOWS[@]}"; do
					WF_INFO=$(echo "$RUNS_JSON" | jq -r --arg name "$wf" '
						[.[] | select((.workflowName == $name) or (.name == $name))] | first // empty
					')
					if [ -z "$WF_INFO" ] || [ "$WF_INFO" = "null" ]; then
						ANY_IN_PROGRESS=1
						ALL_SUCCESS=0
						FAILED_DETAILS+=("$wf: run not found")
					else
						STATUS=$(echo "$WF_INFO" | jq -r '.status // "unknown"')
						CONCLUSION=$(echo "$WF_INFO" | jq -r '.conclusion // "pending"')
						URL=$(echo "$WF_INFO" | jq -r '.url // ""')
						if [ "$STATUS" = "completed" ] && [ "$CONCLUSION" = "success" ]; then
							:
						elif [ "$STATUS" = "completed" ]; then
							ALL_SUCCESS=0
							ANY_FAILED=1
							FAILED_DETAILS+=("$wf: completed with conclusion '$CONCLUSION' ($URL)")
						else
							ALL_SUCCESS=0
							ANY_IN_PROGRESS=1
							FAILED_DETAILS+=("$wf: status is '$STATUS', conclusion is '$CONCLUSION' ($URL)")
						fi
					fi
				done
			fi

			if [ "$ALL_SUCCESS" -eq 1 ]; then
				echo "All required workflows passed on $TARGET_SHORT_SHA:"
				for wf in "${REQUIRED_WORKFLOWS[@]}"; do
					echo "  ✓ $wf (completed/success)"
				done
				break
			fi

			# If in wait mode and pending/in_progress without definitive failure
			if [ "$WAIT_FLAG" -eq 1 ] && [ "$ANY_FAILED" -eq 0 ] && [ "$poll_count" -lt "$POLL_LIMIT" ]; then
				poll_count=$((poll_count + 1))
				echo "Waiting for workflows to complete (attempt $poll_count/$POLL_LIMIT, polling every ${POLL_INTERVAL}s)..."
				sleep "$POLL_INTERVAL"
				continue
			fi

			# Definite failure or wait disabled or timeout
			for detail in "${FAILED_DETAILS[@]}"; do
				FAILURES+=("Workflow gate unsatisfied: $detail")
			done
			break
		done
	fi
fi

# Print all failures and exit if any
if [ "${#FAILURES[@]}" -gt 0 ]; then
	echo
	echo "ERROR: Release preconditions failed (${#FAILURES[@]} error(s)):" >&2
	for err in "${FAILURES[@]}"; do
		echo "  - $err" >&2
	done
	exit 1
fi

echo
echo "Commits to release to production:"
git log --oneline "${REMOTE_MAIN_SHA}..${LOCAL_SHA}"
echo

# Typed confirmation
CONFIRM=""
if [ -n "${RELEASE_CONFIRM:-}" ]; then
	CONFIRM="$RELEASE_CONFIRM"
else
	read -r -p "Type 'release' to confirm release to production: " CONFIRM
fi

if [ "$CONFIRM" != "release" ]; then
	echo "Release aborted by user (input did not match 'release')." >&2
	exit 1
fi

SHORT_SHA=$(git rev-parse --short "$LOCAL_SHA")

if [ "$DRY_RUN" = "1" ]; then
	echo
	echo "[DRY RUN] All preconditions met and confirmation received."
	echo "[DRY RUN] Would execute: git push origin ${LOCAL_SHA}:main"
	echo "[DRY RUN] Release dry run completed successfully for ${SHORT_SHA}."
	exit 0
fi

echo
echo "Pushing ${LOCAL_SHA} to origin:main..."
git push origin "${LOCAL_SHA}:main"

# Post-push verification
NEW_REMOTE_MAIN=$(git ls-remote origin refs/heads/main | awk '{print $1}')
if [ "$NEW_REMOTE_MAIN" != "$LOCAL_SHA" ]; then
	echo "ERROR: origin/main verification mismatch! Expected $LOCAL_SHA, got $NEW_REMOTE_MAIN" >&2
	exit 1
fi

echo
echo "RELEASE_VERIFIED: ${SHORT_SHA}"

# Find and print deploy workflow run URL
DEPLOY_URL=""
if command -v gh >/dev/null 2>&1; then
	# Allow brief moment for GitHub to register workflow run on main
	for _ in $(seq 1 3); do
		DEPLOY_JSON=$(gh run list --commit "$LOCAL_SHA" --json workflowName,name,url 2>/dev/null || true)
		if [ -n "$DEPLOY_JSON" ]; then
			DEPLOY_URL=$(echo "$DEPLOY_JSON" | jq -r '
				[.[] | select((.workflowName | test("Build|Deploy|Publish"; "i")) or (.name | test("Build|Deploy|Publish"; "i")))] | first | .url // empty
			' 2>/dev/null || true)
			[ -n "$DEPLOY_URL" ] && break
		fi
		sleep 1
	done
fi

if [ -n "$DEPLOY_URL" ]; then
	echo "Deploy workflow run URL: $DEPLOY_URL"
else
	REPO_URL=$(gh repo view --json url -q .url 2>/dev/null || true)
	if [ -n "$REPO_URL" ]; then
		echo "Deploy workflow runs: ${REPO_URL}/actions"
	else
		echo "Deploy workflow runs: check repository GitHub Actions"
	fi
fi

# Owner remains on logic-exploitation
echo "Current branch remains: $(git rev-parse --abbrev-ref HEAD)"
