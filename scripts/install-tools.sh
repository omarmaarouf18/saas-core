#!/usr/bin/env bash
#
# scripts/install-tools.sh — install the pinned security-scan tools (WF-02).
#
# Used by both .githooks/pre-push (the local gate / `make ci`) and
# .github/workflows/ci.yml, so local runs and CI scan with the same versions.
# Versions come ONLY from tools/versions.env; to bump a tool, edit that file.
#
# Each tool is built once into a versioned cache directory:
#   ${XDG_CACHE_HOME:-$HOME/.cache}/saas-core-tools/<name>-<version>[...]/<name>
# A cached binary is reused without any network access. A failed install is
# fatal: there is no fallback to @latest and no "skip the scan" path.
#
# stdout: one KEY=<absolute path> line per tool (GOSEC_BIN=..., GOVULNCHECK_BIN=...).
# stderr: progress messages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSIONS_FILE="${ROOT}/tools/versions.env"
[ -f "$VERSIONS_FILE" ] || { echo "ERROR: $VERSIONS_FILE not found" >&2; exit 1; }
# shellcheck source=../tools/versions.env
. "$VERSIONS_FILE"

for var in GO_VERSION GOSEC_VERSION GOSEC_XTOOLS_VERSION GOVULNCHECK_VERSION; do
	[ -n "${!var:-}" ] || { echo "ERROR: $var is not set in $VERSIONS_FILE" >&2; exit 1; }
done

CACHE_ROOT="${XDG_CACHE_HOME:-$HOME/.cache}/saas-core-tools"
mkdir -p "$CACHE_ROOT"

# Builds land in a temp dir and are moved into the cache only on success, so
# an interrupted or failed build never leaves a half-written cached binary.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

# Build outside any module/workspace of this repo.
export GOWORK=off

install_govulncheck() {
	local dir="${CACHE_ROOT}/govulncheck-${GOVULNCHECK_VERSION}-go${GO_VERSION}"
	local bin="${dir}/govulncheck"
	if [ ! -x "$bin" ]; then
		echo "install-tools: building govulncheck ${GOVULNCHECK_VERSION} -> $bin" >&2
		(cd "$WORK_DIR" && GOBIN="$WORK_DIR/govulncheck-bin" \
			go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}") >&2 || {
			echo "ERROR: failed to install govulncheck ${GOVULNCHECK_VERSION}" >&2
			exit 1
		}
		mkdir -p "$dir"
		mv "$WORK_DIR/govulncheck-bin/govulncheck" "$bin"
	fi
	echo "GOVULNCHECK_BIN=$bin"
}

install_gosec() {
	local dir="${CACHE_ROOT}/gosec-${GOSEC_VERSION}-xtools-${GOSEC_XTOOLS_VERSION}-go${GO_VERSION}"
	local bin="${dir}/gosec"
	if [ ! -x "$bin" ]; then
		echo "install-tools: building gosec ${GOSEC_VERSION} (x/tools ${GOSEC_XTOOLS_VERSION}) -> $bin" >&2
		# gosec v2.29.0 pins golang.org/x/tools v0.49.0, which cannot read Go 1.26
		# export data ("export data version 5 is greater than maximum supported
		# version 4"). Build it against x/tools v0.50.0, the combination that passed
		# on 2026-09-28. Remove this when a gosec release requires x/tools >= v0.50.0.
		local mod="$WORK_DIR/gosec-build"
		mkdir -p "$mod"
		(cd "$mod" && go mod init gosec-build >/dev/null 2>&1 \
			&& go get "github.com/securego/gosec/v2/cmd/gosec@${GOSEC_VERSION}" \
				"golang.org/x/tools@${GOSEC_XTOOLS_VERSION}" \
			&& go build -o "$mod/gosec" github.com/securego/gosec/v2/cmd/gosec) >&2 || {
			echo "ERROR: failed to build gosec ${GOSEC_VERSION} with x/tools ${GOSEC_XTOOLS_VERSION}" >&2
			exit 1
		}
		mkdir -p "$dir"
		mv "$mod/gosec" "$bin"
	fi
	echo "GOSEC_BIN=$bin"
}

install_govulncheck
install_gosec
