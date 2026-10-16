#!/usr/bin/env bash
#
# scripts/go-test-module.sh — `go test` for one module, test cache aware (WF-03).
#
#   scripts/go-test-module.sh <module dir> [<package pattern> ...]   # default ./...
#
# Splits the module's test packages in three groups:
#
#   integration  the test binary links a real database client
#                (go.mongodb.org/mongo-driver or github.com/redis/go-redis), so
#                it may talk to the shared local Mongo/Redis, whose state the
#                Go test cache cannot see. Always run with -count=1.
#   repo-reader  packages listed in ALWAYS_RUN below: they read files all over
#                the repository (docgen walks docs/, frontend/, services/).
#                The test cache does track opened files, but these scans are
#                too broad to trust it; always run with -count=1.
#   unit         everything else: run WITHOUT -count=1, so an unchanged
#                package comes from the Go test cache ("(cached)").
#
# The classification is by linkage, not by what a test actually does, so it
# fails safe: a package that only links a driver for a fake still runs every
# time, and a test cannot reach Mongo/Redis without linking a driver.
#
# Prints "[timing] go-test-<group>:<module> <seconds>s" per non-empty group.
set -euo pipefail

mod="${1:?usage: scripts/go-test-module.sh <module dir> [<package pattern> ...]}"
shift
[ "$#" -gt 0 ] || set -- ./...

ALWAYS_RUN="github.com/project/shared/infra/docgen"
DRIVER_RE='(^| )(go\.mongodb\.org/mongo-driver(/v2)?|github\.com/redis/go-redis/v9)(/| |$)'

cd "$mod"

timed() { # timed <label> <cmd...>
	local label="$1" t0=$EPOCHREALTIME rc=0
	shift
	"$@" || rc=$?
	awk -v a="$t0" -v b="$EPOCHREALTIME" -v n="$label" 'BEGIN { printf "[timing] %s %.1fs\n", n, b - a }'
	return "$rc"
}

integration=()
repo_reader=()
unit=()
# One line per test main package: "<import path>.test|<deps>".
declare -A linked=()
while IFS='|' read -r ip deps; do
	case "$ip" in *.test) ;; *) continue ;; esac
	if [[ " $deps " =~ $DRIVER_RE ]]; then
		linked["${ip%.test}"]=1
	fi
done < <(go list -test -f '{{.ImportPath}}|{{join .Deps " "}}' "$@")

while read -r pkg; do
	[ -n "$pkg" ] || continue
	case " $ALWAYS_RUN " in
	*" $pkg "*)
		repo_reader+=("$pkg")
		continue
		;;
	esac
	if [ -n "${linked[$pkg]:-}" ]; then
		integration+=("$pkg")
	else
		unit+=("$pkg")
	fi
done < <(go list "$@")

echo "-- go test $mod: ${#unit[@]} unit (cached), ${#repo_reader[@]} repo-reader (-count=1), ${#integration[@]} integration (-count=1) package(s) --"

if [ "${#unit[@]}" -gt 0 ]; then
	timed "go-test-unit:$mod" go test "${unit[@]}"
fi
if [ "${#repo_reader[@]}" -gt 0 ]; then
	timed "go-test-repo-reader:$mod" go test -count=1 "${repo_reader[@]}"
fi
if [ "${#integration[@]}" -gt 0 ]; then
	timed "go-test-integration:$mod" go test -count=1 "${integration[@]}"
fi
