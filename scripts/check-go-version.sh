#!/usr/bin/env bash
#
# scripts/check-go-version.sh — Go version drift guard (WF-02).
#
# The canonical Go version is GO_VERSION in tools/versions.env; nothing here is
# hard-coded. Every file below must agree with it:
#   - go.work and every go.mod: `go <major.minor>` and `toolchain go<GO_VERSION>`
#   - .github/workflows/ci.yml: every `go-version:` line (at least one)
#   - services/*/Dockerfile: every `FROM golang:<x.y.z>`
# Run by .githooks/pre-push (local gate / `make ci`) and by the
# "Verify Go Version Consistency" step in .github/workflows/ci.yml.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# shellcheck source=../tools/versions.env
. tools/versions.env
[ -n "${GO_VERSION:-}" ] || { echo "BLOCKED: GO_VERSION is not set in tools/versions.env"; exit 1; }

CANONICAL_GO_PATCH_VERSION="$GO_VERSION"
CANONICAL_GO_VERSION="${GO_VERSION%.*}"
CANONICAL_GO_TOOLCHAIN="go${GO_VERSION}"
DRIFT_FAILED=0

for f in go.work services/*/go.mod shared/infra/go.mod tools/*/go.mod tests/*/go.mod; do
  if [ -f "$f" ]; then
    v=$(grep -E '^go [0-9]+\.[0-9]+' "$f" | head -n 1 | awk '{print $2}' || true)
    if [ "$v" != "$CANONICAL_GO_VERSION" ]; then
      echo "BLOCKED: Go language version drift in $f: expected $CANONICAL_GO_VERSION, found '${v:-NONE}'"
      DRIFT_FAILED=1
    fi
    tc=$(grep -E '^toolchain go[0-9]+\.[0-9]+\.[0-9]+' "$f" | head -n 1 | awk '{print $2}' || true)
    if [ "$tc" != "$CANONICAL_GO_TOOLCHAIN" ]; then
      echo "BLOCKED: Go toolchain version drift in $f: expected $CANONICAL_GO_TOOLCHAIN, found '${tc:-NONE}'"
      DRIFT_FAILED=1
    fi
  fi
done

CI_YML=".github/workflows/ci.yml"
if [ -f "$CI_YML" ]; then
  # Accept any quoting style ('x', "x" or bare) so a reformatted line cannot
  # silently escape the check.
  CI_VERSIONS=$(grep -oE "go-version:[[:space:]]*['\"]?[0-9][0-9.]*['\"]?" "$CI_YML" | grep -oE "[0-9][0-9.]*" || true)
  if [ -z "$CI_VERSIONS" ]; then
    echo "BLOCKED: no go-version line found in $CI_YML (expected $CANONICAL_GO_PATCH_VERSION)"
    DRIFT_FAILED=1
  fi
  for v in $CI_VERSIONS; do
    if [ "$v" != "$CANONICAL_GO_PATCH_VERSION" ]; then
      echo "BLOCKED: Go version drift in $CI_YML: expected $CANONICAL_GO_PATCH_VERSION, found '$v'"
      DRIFT_FAILED=1
    fi
  done
fi

for d in services/*/Dockerfile; do
  if [ -f "$d" ]; then
    for v in $(grep -oE "FROM golang:[0-9]+\.[0-9]+\.[0-9]+" "$d" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || true); do
      if [ "$v" != "$CANONICAL_GO_PATCH_VERSION" ]; then
        echo "BLOCKED: Go version drift in $d: expected $CANONICAL_GO_PATCH_VERSION, found '$v'"
        DRIFT_FAILED=1
      fi
    done
  fi
done

if [ "$DRIFT_FAILED" -eq 1 ]; then
  exit 1
fi
echo "Go version consistency: OK (GO_VERSION=$GO_VERSION from tools/versions.env)"
