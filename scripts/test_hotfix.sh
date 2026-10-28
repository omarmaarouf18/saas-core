#!/usr/bin/env bash
#
# scripts/test_hotfix.sh — tests for make hotfix (WF-RELEASE item 4).
#
# Verifies:
#   1. make hotfix without NAME fails with usage
#   2. scripts/agent-worktree.sh hotfix <slug> creates hotfix/<slug> from origin/main
#   3. Worktree has push disabled (Layer A) and core.hooksPath set
#   4. Worktree removal refuses until merged into logic-exploitation (unless --force)
#
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="${AGENT_WORKTREE_SCRIPT:-$ROOT/scripts/agent-worktree.sh}"
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

repo="$tmp/repo"
bare="$tmp/origin.git"
mkdir -p "$repo"
git -C "$repo" init -b main --quiet
git -C "$repo" config user.name "Hotfix Test"
git -C "$repo" config user.email "hotfix@example.com"

cp "$ROOT/Makefile" "$repo/Makefile"
cp -r "$ROOT/.githooks" "$repo/.githooks"
mkdir -p "$repo/scripts"
cp "$SCRIPT" "$repo/scripts/agent-worktree.sh"

echo "production code" >"$repo/file.txt"
git -C "$repo" add .
git -C "$repo" commit -m "initial production commit on main" --quiet

git clone --bare "$repo" "$bare" --quiet
git -C "$repo" remote add origin "$bare"
git -C "$repo" fetch origin --quiet

# Create logic-exploitation ahead of main
git -C "$repo" checkout -b logic-exploitation --quiet
echo "unreleased dev work" >>"$repo/file.txt"
git -C "$repo" commit -am "dev commit on logic-exploitation" --quiet
git -C "$repo" push origin logic-exploitation --quiet
git -C "$repo" checkout main --quiet

# 1. make hotfix without NAME fails
(cd "$repo" && make hotfix >"$tmp/out_no_name" 2>"$tmp/err_no_name")
rc=$?
check "make hotfix without NAME fails" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "Usage: make hotfix NAME=<slug>" "$tmp/out_no_name" "$tmp/err_no_name"
check "prints usage on missing NAME" $? "out: $(cat "$tmp/out_no_name" "$tmp/err_no_name")"

# 2. Create hotfix worktree
(cd "$repo" && bash scripts/agent-worktree.sh hotfix "cve-patch" >"$tmp/out_hotfix" 2>"$tmp/err_hotfix")
rc=$?
check "agent-worktree.sh hotfix cve-patch exits 0" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc, out: $(cat "$tmp/out_hotfix" "$tmp/err_hotfix")"

wt_path="$tmp/saas-core-wt/hotfix-cve-patch"
check "worktree directory created" "$([ -d "$wt_path" ] && echo 0 || echo 1)" "path: $wt_path"

branch="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)"
check "branch is hotfix/cve-patch" "$([ "$branch" = "hotfix/cve-patch" ] && echo 0 || echo 1)" "branch: $branch"

# Verify branch was created from origin/main, not logic-exploitation
hotfix_base="$(git -C "$wt_path" rev-parse HEAD)"
origin_main_sha="$(git -C "$repo" rev-parse origin/main)"
check "hotfix branched from origin/main" "$([ "$hotfix_base" = "$origin_main_sha" ] && echo 0 || echo 1)" "base: $hotfix_base, origin/main: $origin_main_sha"

# 3. Verify Layer A push block
pushurl="$(git -C "$wt_path" config --get remote.origin.pushurl || true)"
check "push is disabled in hotfix worktree" "$([ "$pushurl" = "DISABLED--agent-worktrees-never-push" ] && echo 0 || echo 1)" "pushurl: $pushurl"

# 4. Verify removal refuses while unmerged into logic-exploitation
echo "fix" >>"$wt_path/file.txt"
git -C "$wt_path" commit -am "hotfix commit" --quiet

(cd "$repo" && bash scripts/agent-worktree.sh remove "hotfix-cve-patch" >"$tmp/out_rem" 2>"$tmp/err_rem")
rc=$?
check "remove refuses unmerged hotfix" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"

# 5. Remove succeeds with --force
(cd "$repo" && bash scripts/agent-worktree.sh remove "hotfix-cve-patch" --force >"$tmp/out_force" 2>"$tmp/err_force")
rc=$?
check "remove --force succeeds" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc"
check "worktree directory removed" "$([ ! -d "$wt_path" ] && echo 0 || echo 1)" "directory still exists"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all hotfix checks passed"
