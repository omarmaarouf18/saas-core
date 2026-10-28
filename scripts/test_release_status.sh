#!/usr/bin/env bash
#
# scripts/test_release_status.sh — tests for scripts/release-status.sh.
#
# Uses a temp git repo and a fake gh on PATH (never touches real GitHub or pushes).
#
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="${RELEASE_STATUS_SCRIPT:-$ROOT/scripts/release-status.sh}"
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
mkdir -p "$repo"
git -C "$repo" init -b main --quiet
git -C "$repo" config user.name "Release Test"
git -C "$repo" config user.email "release-test@example.com"

echo "initial" >"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -m "initial commit on main" --quiet

# Create fake origin remote
bare_origin="$tmp/origin.git"
git clone --bare "$repo" "$bare_origin" --quiet
git -C "$repo" remote add origin "$bare_origin"
git -C "$repo" fetch origin --quiet

# Create logic-exploitation with 2 commits ahead
git -C "$repo" checkout -b logic-exploitation --quiet
echo "feature 1" >>"$repo/file.txt"
git -C "$repo" commit -am "feature commit 1" --quiet
echo "feature 2" >>"$repo/file.txt"
git -C "$repo" commit -am "feature commit 2" --quiet

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
		cat <<JSON
[
  {
    "workflowName": "CI Gate",
    "name": "CI Gate",
    "status": "completed",
    "conclusion": "${FAKE_CI_CONCLUSION:-success}",
    "url": "https://github.com/example/saas-core/actions/runs/101"
  },
  {
    "workflowName": "Release Gate E2E",
    "name": "Release Gate E2E",
    "status": "completed",
    "conclusion": "${FAKE_E2E_CONCLUSION:-success}",
    "url": "https://github.com/example/saas-core/actions/runs/102"
  }
]
JSON
	else
		printf 'completed\t%s\tCommit msg\tCI Gate\tlogic-exploitation\tpush\t101\t1m\t2026-10-28T00:00:00Z\n' "${FAKE_CI_CONCLUSION:-success}"
		printf 'completed\t%s\tCommit msg\tRelease Gate E2E\tlogic-exploitation\tpush\t102\t2m\t2026-10-28T00:00:00Z\n' "${FAKE_E2E_CONCLUSION:-success}"
	fi
	exit 0
fi
echo "unknown fake gh command: $*" >&2
exit 1
EOF
chmod +x "$fake_gh"

# Case 1: normal status check with green runs
export PATH="$tmp/bin:$PATH"
export FAKE_CI_CONCLUSION="success"
export FAKE_E2E_CONCLUSION="success"

(cd "$repo" && bash "$SCRIPT" logic-exploitation >"$tmp/out" 2>"$tmp/err")
rc=$?

check "release-status exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc, stderr: $(cat "$tmp/err")"
grep -q "$short_sha" "$tmp/out"
check "prints short SHA" $? "output: $(cat "$tmp/out")"
grep -q "feature commit 1" "$tmp/out" && grep -q "feature commit 2" "$tmp/out"
check "lists commits ahead of origin/main" $? "output: $(cat "$tmp/out")"
grep -q "CI Gate.*status=completed.*conclusion=success" "$tmp/out"
check "reports CI Gate status" $? "output: $(cat "$tmp/out")"
grep -q "Release Gate E2E.*status=completed.*conclusion=success" "$tmp/out"
check "reports Release Gate E2E status" $? "output: $(cat "$tmp/out")"

# Case 2: workflow failure reflected in status
export FAKE_CI_CONCLUSION="success"
export FAKE_E2E_CONCLUSION="failure"

(cd "$repo" && bash "$SCRIPT" logic-exploitation >"$tmp/out2" 2>"$tmp/err2")
rc=$?
check "release-status still exits 0 when runs failed (read-only inspect)" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "Release Gate E2E.*status=completed.*conclusion=failure" "$tmp/out2"
check "reports failing conclusion" $? "output: $(cat "$tmp/out2")"

# Case 3: missing gh binary fails with error
(cd "$repo" && PATH="/usr/bin:/bin" bash "$SCRIPT" logic-exploitation >"$tmp/out3" 2>"$tmp/err3")
rc=$?
# If /usr/bin has real gh, skip or ensure fake empty PATH
(cd "$repo" && PATH="$tmp/empty_bin" bash "$SCRIPT" logic-exploitation >"$tmp/out3" 2>"$tmp/err3") || rc=$?
check "missing gh exits non-zero" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all release-status checks passed"
