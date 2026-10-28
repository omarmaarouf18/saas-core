#!/usr/bin/env bash
#
# scripts/run_script_tests.sh — single source runner for script regression tests (WF-RELEASE item 5).
#
# Used by:
#   1. .githooks/pre-push ("script-tests" stage)
#   2. .github/workflows/ci.yml ("Run Script Regression Tests" step in lint-formatting)
#
# Runs:
#   - Every scripts/test_*.sh script
#   - scripts/test_frontend_l10n_audit.py
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fails=0

# Run shell tests (scripts/test_*.sh)
for t in $(find scripts -maxdepth 1 -name "test_*.sh" | sort); do
	echo "-- $t --"
	if ! bash "$t"; then
		echo "BLOCKED: $t failed" >&2
		fails=$((fails + 1))
	fi
done

# Run Python tests (scripts/test_frontend_l10n_audit.py)
py_test="scripts/test_frontend_l10n_audit.py"
if [ -f "$py_test" ]; then
	echo "-- $py_test --"
	if ! python3 "$py_test"; then
		echo "BLOCKED: $py_test failed" >&2
		fails=$((fails + 1))
	fi
fi

if [ "$fails" -ne 0 ]; then
	echo "ERROR: $fails script regression test suite(s) failed" >&2
	exit 1
fi

echo "all script regression tests passed"
