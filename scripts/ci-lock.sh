#!/usr/bin/env bash
#
# scripts/ci-lock.sh — run a command under the CI lock (WF-02, narrowed in WF-03).
#
#   scripts/ci-lock.sh <cmd> [<args> ...]
#
# Takes flock on <git-common-dir>/ci.lock — one file shared by every worktree
# — so two gate runs never run integration tests against the shared local
# Mongo/Redis at the same time. Since WF-03 only the stages that use them
# (integration test packages, see scripts/go-test-module.sh) run under it;
# gofmt, vet, gosec, govulncheck, flutter and unit tests run without it.
#
# CI_LOCK_HELD=1 means a caller already holds the lock: run directly.
# Prints "waiting for CI lock: ..." while another run holds it, and
# "[timing] lock-wait <seconds>s" when it had to wait.
set -euo pipefail

[ "$#" -gt 0 ] || { echo "usage: scripts/ci-lock.sh <cmd> [<args> ...]" >&2; exit 2; }

if [ "${CI_LOCK_HELD:-}" = "1" ]; then
	exec "$@"
fi

LOCK_FILE="$(git rev-parse --path-format=absolute --git-common-dir)/ci.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
	echo "waiting for CI lock: $LOCK_FILE is held by another gate run (make check or git push)"
	t0=$EPOCHREALTIME
	flock 9
	awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN { printf "[timing] lock-wait %.1fs\n", b - a }'
fi
export CI_LOCK_HELD=1
exec "$@"
