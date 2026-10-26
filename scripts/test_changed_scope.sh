#!/usr/bin/env bash
#
# scripts/test_changed_scope.sh — regression tests for scripts/changed-scope.sh.
#
#   bash scripts/test_changed_scope.sh
#   CHANGED_SCOPE_SCRIPT=<path> bash scripts/test_changed_scope.sh  # test another copy
#
# Run by every gate run (.githooks/pre-push "script-tests" stage, so
# `make check`, `make ci-full` and real pushes).
#
# FE-CLEANUP: with many changed paths the scope listing (first 20 paths on
# stderr) used `... | head -n 20 | ...` under `set -o pipefail`. head exits
# after 20 lines, the writer upstream gets SIGPIPE, and the script died with
# exit 141 before printing its result, so `make check` and `make commit`
# failed on any branch with a long diff. The paths here are long enough that
# the listing is far larger than a pipe buffer, which made the old code fail
# every time.
# No `set -e`: a failing check must be reported, not abort the run.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SCRIPT="${CHANGED_SCOPE_SCRIPT:-$ROOT/scripts/changed-scope.sh}"
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

# 1500 frontend paths, about 120 bytes each (~180 KB of listing).
pad="$(printf 'x%.0s' $(seq 1 90))"
for i in $(seq 1 1500); do
	printf 'frontend/lib/features/generated/%s_%04d.dart\n' "$pad" "$i"
done >"$tmp/paths"

bash "$SCRIPT" --paths <"$tmp/paths" >"$tmp/out" 2>"$tmp/err"
rc=$?

check "exit 0 with 1500 paths" "$([ "$rc" -eq 0 ] && echo 0 || echo 1)" "exit $rc"
grep -qx "SCOPE_MODE=scoped" "$tmp/out"
check "scoped mode" $? "stdout: $(head -c 300 "$tmp/out")"
grep -qx "SCOPE_FRONTEND=1" "$tmp/out"
check "frontend scope" $? "stdout: $(head -c 300 "$tmp/out")"
grep -q "SCOPED gate (1500 changed path(s))" "$tmp/err"
check "path count reported" $? "stderr: $(head -c 300 "$tmp/err")"
n="$(grep -c '^scope:   frontend/' "$tmp/err" || true)"
check "lists exactly 20 paths" "$([ "$n" -eq 20 ] && echo 0 || echo 1)" "listed $n"
grep -q "\.\.\. and 1480 more" "$tmp/err"
check "reports the rest" $? "stderr tail: $(tail -c 200 "$tmp/err")"

if [ "$fails" -ne 0 ]; then
	printf '%d check(s) failed\n' "$fails"
	exit 1
fi
echo "all changed-scope checks passed"
