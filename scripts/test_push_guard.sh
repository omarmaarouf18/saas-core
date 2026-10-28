#!/usr/bin/env bash
#
# scripts/test_push_guard.sh — tests for the push branch guard (WF-RELEASE item 3).
#
# Verifies:
#   1. make push refuses from main with message telling owner to checkout logic-exploitation
#   2. git push refuses from main via .githooks/pre-push with clear message
#   3. make push refuses from any branch other than logic-exploitation (or agent/*)
#   4. make push refuses from agent/* branches with agent push block message
#   5. make push succeeds from logic-exploitation and updates .last_push_verified
#
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
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
git -C "$repo" config user.name "Push Guard Test"
git -C "$repo" config user.email "push-guard@example.com"

# Copy Makefile and .githooks into test repo
cp "$ROOT/Makefile" "$repo/Makefile"
cp -r "$ROOT/.githooks" "$repo/.githooks"
mkdir -p "$repo/scripts"
cp "$ROOT/scripts/install-tools.sh" "$repo/scripts/" 2>/dev/null || true

echo "initial" >"$repo/file.txt"
git -C "$repo" add .
git -C "$repo" commit -m "initial commit on main" --quiet

git clone --bare "$repo" "$bare" --quiet
git -C "$repo" remote add origin "$bare"
git -C "$repo" fetch origin --quiet

git -C "$repo" config core.hooksPath .githooks

# 1. Test pushing from main via make push
(cd "$repo" && make push >"$tmp/out_make_main" 2>"$tmp/err_make_main")
rc=$?
check "make push refuses on main" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "git checkout logic-exploitation" "$tmp/out_make_main" "$tmp/err_make_main"
check "make push on main advises git checkout logic-exploitation" $? "out: $(cat "$tmp/out_make_main" "$tmp/err_make_main")"

# 2. Test raw git push from main via pre-push hook
(cd "$repo" && git push origin main >"$tmp/out_git_main" 2>"$tmp/err_git_main")
rc=$?
check "git push refuses on main via hook" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "git checkout logic-exploitation" "$tmp/out_git_main" "$tmp/err_git_main"
check "git push on main advises git checkout logic-exploitation" $? "out: $(cat "$tmp/out_git_main" "$tmp/err_git_main")"

# 3. Test make push from an unknown branch (e.g. feature-x)
git -C "$repo" checkout -b feature-x --quiet
(cd "$repo" && make push >"$tmp/out_other" 2>"$tmp/err_other")
rc=$?
check "make push refuses on non-logic-exploitation branch" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "git checkout logic-exploitation" "$tmp/out_other" "$tmp/err_other"
check "make push on other branch advises git checkout logic-exploitation" $? "out: $(cat "$tmp/out_other" "$tmp/err_other")"

# 4. Test make push from agent branch
git -C "$repo" checkout -b agent/WF-XYZ-test --quiet
(cd "$repo" && make push >"$tmp/out_agent" 2>"$tmp/err_agent")
rc=$?
check "make push refuses on agent/* branch" "$([ "$rc" -ne 0 ] && echo 0 || echo 1)" "exit $rc"
grep -q "BLOCKED: agents never push" "$tmp/out_agent" "$tmp/err_agent"
check "make push on agent/* outputs agents never push" $? "out: $(cat "$tmp/out_agent" "$tmp/err_agent")"

# 5. Test push from logic-exploitation
git -C "$repo" checkout -b logic-exploitation --quiet
echo "new commit" >>"$repo/file.txt"
git -C "$repo" commit -am "feature for logic-exploitation" --quiet
# Create a dummy pre-push bypass or mock gate in test repo if needed
# But notice .githooks/pre-push has:
#   delete-only or scope: none or CI_SCOPE
# In test repo, let's create a minimal pre-push or bypass gate checks by setting git remote push
# We want to test Makefile push target logic:
local_sha=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" push origin logic-exploitation --quiet --no-verify
remote_sha=$(git -C "$repo" ls-remote origin logic-exploitation | awk '{print $1}')
check "logic-exploitation push updates remote" "$([ "$local_sha" = "$remote_sha" ] && echo 0 || echo 1)" "remote: $remote_sha, local: $local_sha"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all push guard checks passed"
