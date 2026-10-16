#!/usr/bin/env bash
#
# scripts/commit.sh — implementation of `make commit` (WF-01, WF-02).
#
#   make commit FILES="<paths>" MSG="<message>"
#   make commit FILES="<paths>" MSG_FILE=<path>     # multi-line messages
#
# Inputs come from the environment (make exports command-line variables), never
# from make text substitution, so quotes, backquotes and newlines in MSG are safe.
#
# - FILES is required: no `git add -A`, so untracked files (including .env*)
#   are never swept into a commit. Paths are whitespace-separated (paths that
#   contain spaces are not supported).
# - Exactly one of MSG / MSG_FILE is required.
# - A path in FILES may be a staged deletion (already `git rm`ed, or the old
#   side of a `git mv`). A path that exists nowhere — not on disk, not in the
#   index, not in HEAD — is an error.
# - ONLY the FILES paths are committed (`git commit --only`). Other paths that
#   were already staged stay staged and uncommitted; a warning lists them.
set -euo pipefail

die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}

USAGE='make commit FILES="<paths>" MSG="<message>"  (or MSG_FILE=<path> instead of MSG)'

[ -n "${FILES:-}" ] || die "FILES is required and must be non-empty: $USAGE"
if [ -n "${MSG:-}" ] && [ -n "${MSG_FILE:-}" ]; then
	die "MSG and MSG_FILE are mutually exclusive; pass exactly one: $USAGE"
fi
if [ -z "${MSG:-}" ] && [ -z "${MSG_FILE:-}" ]; then
	die "MSG or MSG_FILE is required: $USAGE"
fi
if [ -n "${MSG_FILE:-}" ] && [ ! -r "$MSG_FILE" ]; then
	die "MSG_FILE '$MSG_FILE' does not exist or is not readable"
fi

read -r -a paths <<<"$FILES"
[ "${#paths[@]}" -gt 0 ] || die "FILES is required and must be non-empty: $USAGE"

has_head=0
if git rev-parse --verify --quiet HEAD >/dev/null; then
	has_head=1
fi

to_add=()
for p in "${paths[@]}"; do
	if [ -e "$p" ] || [ -L "$p" ]; then
		# On disk: new or modified content.
		to_add+=("$p")
	elif [ -n "$(git ls-files --cached -- "$p")" ]; then
		# In the index but gone from disk: `git add` stages the deletion.
		to_add+=("$p")
	elif [ "$has_head" -eq 1 ] && git cat-file -e "HEAD:$p" 2>/dev/null; then
		# Only in HEAD: an already-staged deletion (git rm / old side of git mv).
		# Nothing to add; it is still part of the commit pathspec below.
		:
	else
		die "path '$p' does not exist on disk, in the index, or in HEAD (typo?)"
	fi
done

if [ "${#to_add[@]}" -gt 0 ]; then
	git add -- "${to_add[@]}"
fi

# Staged paths that are NOT covered by FILES: they stay staged, uncommitted.
all_staged="$(git diff --cached --no-renames --name-only)"
ours_staged="$(git diff --cached --no-renames --name-only -- "${paths[@]}")"
others="$(comm -23 <(printf '%s\n' "$all_staged" | sed '/^$/d' | sort -u) \
	<(printf '%s\n' "$ours_staged" | sed '/^$/d' | sort -u))"
if [ -n "$others" ]; then
	echo "WARNING: these staged paths are NOT in FILES; they stay staged and are NOT committed:" >&2
	printf '%s\n' "$others" | sed 's/^/  /' >&2
fi

if [ -n "${MSG_FILE:-}" ]; then
	git commit --only -F "$MSG_FILE" -- "${paths[@]}"
else
	git commit --only -m "$MSG" -- "${paths[@]}"
fi
