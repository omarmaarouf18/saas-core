#!/usr/bin/env bash
#
# scripts/test_release.sh — tests for scripts/release.sh.
#
# Uses a temp git repo and a fake gh on PATH (never touches real GitHub or pushes).
#
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="${RELEASE_SCRIPT:-$ROOT/scripts/release.sh}"
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

# Set up test git repository
repo="$tmp/repo"
mkdir -p "$repo/services" "$repo/scratch"
git -C "$repo" init -b main --quiet
git -C "$repo" config user.name "Release Test"
git -C "$repo" config user.email "release-test@example.com"

echo "services code" >"$repo/services/app.go"
git -C "$repo" add services/app.go
git -C "$repo" commit -m "initial commit on main" --quiet

# Create fake origin remote
bare_origin="$tmp/origin.git"
git clone --bare "$repo" "$bare_origin" --quiet
git -C "$repo" remote add origin "$bare_origin"
git -C "$repo" fetch origin --quiet

# Create logic-exploitation with 1 commit ahead
git -C "$repo" checkout -b logic-exploitation --quiet
echo "new service feature" >>"$repo/services/app.go"
git -C "$repo" commit -am "releaseable feature commit" --quiet
# Push logic-exploitation to origin so local == origin/logic-exploitation
git -C "$repo" push origin logic-exploitation --quiet

short_sha="$(git -C "$repo" rev-parse --short HEAD)"
full_sha="$(git -C "$repo" rev-parse HEAD)"

# Fake gh executable directory
mkdir -p "$tmp/bin"
fake_gh="$tmp/bin/gh"

cat >"$fake_gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "run" ] && [ "${2:-}" = "list" ]; then
	shift 2
	has_json=0
	commit_sha=""
	while [ $# -gt 0 ]; do
		case "$1" in
			--commit) commit_sha="$2"; shift 2 ;;
			--json) has_json=1; shift 2 ;;
			*) shift ;;
		esac
	done
	if [ "$has_json" -eq 1 ]; then
		ci_status="${FAKE_CI_STATUS:-completed}"
		ci_conclusion="${FAKE_CI_CONCLUSION:-success}"
		if [ "${DYNAMIC_POLL:-0}" = "1" ]; then
			poll_file="${POLL_COUNTER_FILE}"
			count=0
			[ -f "$poll_file" ] && count=$(cat "$poll_file")
			count=$((count + 1))
			echo "$count" >"$poll_file"
			if [ "$count" -eq 1 ]; then
				ci_status="in_progress"
				ci_conclusion=""
			fi
		fi
		cat <<JSON
[
  {
    "workflowName": "CI Gate",
    "name": "CI Gate",
    "status": "${ci_status}",
    "conclusion": "${ci_conclusion}",
    "url": "https://github.com/example/saas-core/actions/runs/201"
  },
  {
    "workflowName": "Release Gate E2E",
    "name": "Release Gate E2E",
    "status": "${FAKE_E2E_STATUS:-completed}",
    "conclusion": "${FAKE_E2E_CONCLUSION:-success}",
    "url": "https://github.com/example/saas-core/actions/runs/202"
  },
  {
    "workflowName": "Build and Publish Docker Images",
    "name": "Build and Publish Docker Images",
    "status": "in_progress",
    "conclusion": "",
    "url": "https://github.com/example/saas-core/actions/runs/203"
  }
]
JSON
	else
		printf 'completed\tsuccess\tCommit msg\tCI Gate\tlogic-exploitation\tpush\t201\t1m\t2026-10-28T00:00:00Z\n'
	fi
	exit 0
fi
if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ]; then
	echo "https://github.com/example/saas-core"
	exit 0
fi
echo "unknown fake gh command: $*" >&2
exit 1
EOF
chmod +x "$fake_gh"

export PATH="$tmp/bin:$PATH"
export RELEASE_POLL_INTERVAL=0.01
export RELEASE_POLL_LIMIT=3

# 1. Refuse if not on branch logic-exploitation
(cd "$repo" && git checkout main --quiet && bash "$SCRIPT" >"$tmp/out_branch" 2>"$tmp/err_branch")
rc=$?
check "refuses when not on logic-exploitation" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "logic-exploitation" "$tmp/err_branch" "$tmp/out_branch" || grep -q "Current branch" "$tmp/err_branch" "$tmp/out_branch"
check "branch error message explains branch requirement" $? "out: $(cat "$tmp/out_branch" "$tmp/err_branch")"
git -C "$repo" checkout logic-exploitation --quiet

# 2. Refuse if working tree has modified tracked files
echo "dirty edit" >>"$repo/services/app.go"
(cd "$repo" && bash "$SCRIPT" >"$tmp/out_dirty" 2>"$tmp/err_dirty")
rc=$?
check "refuses when tracked files modified" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
git -C "$repo" checkout -- services/app.go

# 3. Refuse if untracked files are under tracked directory
echo "untracked" >"$repo/services/new.go"
(cd "$repo" && bash "$SCRIPT" >"$tmp/out_untracked" 2>"$tmp/err_untracked")
rc=$?
check "refuses when untracked files under tracked dir" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
rm "$repo/services/new.go"

# 4. Allow untracked file in scratch directory
echo "scratch file" >"$repo/scratch/temp.txt"
# With clean tree + scratch file, test dry run
(cd "$repo" && echo "release" | RELEASE_DRY_RUN=1 bash "$SCRIPT" >"$tmp/out_scratch" 2>"$tmp/err_scratch")
rc=$?
check "allows untracked files in scratch dir in dry run" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc, out: $(cat "$tmp/out_scratch" "$tmp/err_scratch")"
rm "$repo/scratch/temp.txt"

# 5. Refuse if local != origin/logic-exploitation
echo "another commit" >>"$repo/services/app.go"
git -C "$repo" commit -am "local unpushed commit" --quiet
(cd "$repo" && bash "$SCRIPT" >"$tmp/out_sync" 2>"$tmp/err_sync")
rc=$?
check "refuses when local != origin/logic-exploitation" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
git -C "$repo" reset --hard HEAD~1 --quiet

# 6. Refuse if origin/main is not an ancestor
# Advance origin/main with a divergent commit
git -C "$repo" checkout main --quiet
echo "divergent" >"$repo/services/divergent.txt"
git -C "$repo" add services/divergent.txt
git -C "$repo" commit -m "divergent commit on main" --quiet
git -C "$repo" push origin main --quiet
git -C "$repo" checkout logic-exploitation --quiet
(cd "$repo" && bash "$SCRIPT" >"$tmp/out_ancestor" 2>"$tmp/err_ancestor")
rc=$?
check "refuses when origin/main is not ancestor" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
# Reset origin/main back
git -C "$repo" checkout main --quiet
git -C "$repo" reset --hard HEAD~1 --quiet
git -C "$repo" push --force origin main --quiet
git -C "$repo" checkout logic-exploitation --quiet

# 7. Refuse when required workflow failed
export FAKE_CI_CONCLUSION="failure"
export FAKE_E2E_CONCLUSION="success"
(cd "$repo" && bash "$SCRIPT" >"$tmp/out_gate_fail" 2>"$tmp/err_gate_fail")
rc=$?
check "refuses when required workflow failed" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
export FAKE_CI_CONCLUSION="success"

# 7b. --wait flag polls and succeeds when workflow completes
export DYNAMIC_POLL=1
export POLL_COUNTER_FILE="$tmp/poll_count"
rm -f "$POLL_COUNTER_FILE"
(cd "$repo" && echo "release" | RELEASE_DRY_RUN=1 bash "$SCRIPT" --wait >"$tmp/out_wait" 2>"$tmp/err_wait")
rc=$?
check "--wait flag polls and succeeds once runs complete" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc, out: $(cat "$tmp/out_wait" "$tmp/err_wait")"
grep -q "Waiting for workflows to complete" "$tmp/out_wait"
check "--wait outputs polling message" $? "out: $(cat "$tmp/out_wait")"
export DYNAMIC_POLL=0

# 8. Confirmation refusal when confirmation != 'release'
unset RELEASE_CONFIRM || true
(cd "$repo" && echo "no" | bash "$SCRIPT" >"$tmp/out_confirm_bad" 2>"$tmp/err_confirm_bad")
rc=$?
check "refuses when typed confirmation is not 'release'" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"

# 9. Dry run mode does everything except push
(cd "$repo" && echo "release" | RELEASE_DRY_RUN=1 bash "$SCRIPT" >"$tmp/out_dry" 2>"$tmp/err_dry")
rc=$?
check "dry run exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc, out: $(cat "$tmp/out_dry" "$tmp/err_dry")"
grep -q "DRY RUN" "$tmp/out_dry"
check "dry run output mentions DRY RUN" $? "out: $(cat "$tmp/out_dry")"
# Verify origin/main was NOT moved in dry run
origin_main_sha="$(git -C "$repo" rev-parse origin/main)"
check "dry run does not push to origin/main" "$([ "$origin_main_sha" != "$full_sha" ] && echo 0 || echo 1)" "origin main was modified"

# 10. Real release pushes <sha>:main, verifies origin/main == SHA, and prints RELEASE_VERIFIED
(cd "$repo" && echo "release" | bash "$SCRIPT" >"$tmp/out_real" 2>"$tmp/err_real")
rc=$?
check "real release exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc, out: $(cat "$tmp/out_real" "$tmp/err_real")"
new_origin_main_sha="$(git -C "$repo" rev-parse origin/main)"
check "origin/main updated to exact SHA" "$([ "$new_origin_main_sha" = "$full_sha" ] && echo 0 || echo 1)" "origin main: $new_origin_main_sha, expected: $full_sha"
grep -q "RELEASE_VERIFIED: $short_sha" "$tmp/out_real"
check "prints RELEASE_VERIFIED: <short sha>" $? "out: $(cat "$tmp/out_real")"
grep -q "https://github.com/example/saas-core/actions" "$tmp/out_real"
check "prints deploy workflow run URL" $? "out: $(cat "$tmp/out_real")"
current_branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
check "leaves owner on logic-exploitation" "$([ "$current_branch" = "logic-exploitation" ] && echo 0 || echo 1)" "branch: $current_branch"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all release script checks passed"
