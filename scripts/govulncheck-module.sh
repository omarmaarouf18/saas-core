#!/usr/bin/env bash
#
# scripts/govulncheck-module.sh — govulncheck step of the local gate (WF-02).
#
#   GOVULNCHECK_BIN=<path> scripts/govulncheck-module.sh <module dir>
#
# Called by .githooks/pre-push once per Go module. Exit 0 = pass, 1 = BLOCKED.
#
# Errors are fatal. In `-format json` mode govulncheck v1.8.0 exits 0 whether
# or not it finds vulnerabilities (exit 3 "vulnerabilities found" is only used
# in text mode), 1 on errors (e.g. packages fail to load, vuln DB unreachable)
# and 2 on usage errors. 0 and 3 are accepted; anything else blocks, with
# govulncheck's stderr. The output must also be valid govulncheck JSON that
# contains a "config" message; otherwise it blocks (e.g. a binary that is not
# govulncheck). Note: on a load error govulncheck still prints the config
# message, so the exit code is the primary check.
#
# Policy (unchanged from before WF-02): only findings that are actually called
# (the trace contains a github.com/project/ package) count. Called stdlib
# findings print a loud WARNING and do not block; called third-party findings
# block. CI blocks on stdlib findings too (see docs/CI_CD_AND_HOOKS.md).
set -uo pipefail

mod="${1:?usage: GOVULNCHECK_BIN=<path> scripts/govulncheck-module.sh <module dir>}"
: "${GOVULNCHECK_BIN:?GOVULNCHECK_BIN must be set}"

echo "-- running govulncheck on $mod --"
err_file="$(mktemp)"
trap 'rm -f "$err_file"' EXIT

VULN_RC=0
VULN_OUT=$(cd "$mod" && "$GOVULNCHECK_BIN" -format json ./... 2>"$err_file") || VULN_RC=$?

VALID_JSON=0
if printf '%s\n' "$VULN_OUT" | jq -e -s 'any(.[]; type == "object" and .config != null)' >/dev/null 2>&1; then
  VALID_JSON=1
fi

if { [ "$VULN_RC" -ne 0 ] && [ "$VULN_RC" -ne 3 ]; } || [ "$VALID_JSON" -ne 1 ]; then
  if [ "$VALID_JSON" -ne 1 ]; then
    echo "BLOCKED: govulncheck error in $mod (exit code $VULN_RC; output is not govulncheck JSON with a config message)"
  else
    echo "BLOCKED: govulncheck error in $mod (exit code $VULN_RC)"
  fi
  echo "--- govulncheck stderr ---"
  cat "$err_file"
  echo "--- end govulncheck stderr ---"
  exit 1
fi

# Check for stdlib vulnerabilities to print loud warnings
STDLIB_VULNS=$(echo "$VULN_OUT" | jq -r 'select(.finding != null and (.finding.trace | any(.package != null and (.package | startswith("github.com/project/")))) and .finding.trace[0].module == "stdlib") | .finding.osv' | sort -u)
if [ -n "$STDLIB_VULNS" ]; then
  for id in $STDLIB_VULNS; do
    echo "WARNING: SKIPPED ($id) (stdlib vulnerability) — verify local Go patch version"
  done
fi

# Block on active third-party dependencies vulnerabilities
NON_STDLIB_VULNS=$(echo "$VULN_OUT" | jq -c 'select(.finding != null and (.finding.trace | any(.package != null and (.package | startswith("github.com/project/")))) and .finding.trace[0].module != "stdlib")')
if [ -n "$NON_STDLIB_VULNS" ]; then
  echo "BLOCKED: $mod failed govulncheck security scan with third-party vulnerabilities:"
  echo "$NON_STDLIB_VULNS" | jq .
  exit 1
fi
exit 0
