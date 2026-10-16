#!/usr/bin/env bash
#
# scripts/changed-scope.sh — which gate stages a change needs (WF-03).
#
#   scripts/changed-scope.sh                # working tree: `make check` / `make ci`
#   scripts/changed-scope.sh --push         # pre-push: ref lines on stdin
#   scripts/changed-scope.sh --paths        # explicit path list on stdin (one per line)
#
# Changed paths:
#   (default)  committed changes since the merge-base of HEAD with SCOPE_BASE
#              (default: logic-exploitation) + staged + unstaged + untracked
#              (not ignored) files.
#   --push     for every ref line git passes to pre-push
#              ("<local ref> <local sha> <remote ref> <remote sha>"): the commits
#              <remote sha>..<local sha>. A new remote ref (all-zero remote sha)
#              is diffed against its merge-base with origin/logic-exploitation
#              (or the local logic-exploitation). Delete lines are ignored.
#
# Mapping (first match wins, per path; the scope is the union over all paths):
#   CLAUDE.md                         -> FULL gate (checked before *.md)
#   *.md anywhere, docs/**            -> docs (markdown SHA check)
#                                        + shared/infra tests (changelog and
#                                        docgen validation live there)
#   go.work, go.work.sum, any go.mod / go.sum, shared/infra/**, tools/**,
#   .githooks/**, scripts/**, Makefile, .github/**, CLAUDE.md, .gitleaks.toml
#                                     -> FULL gate
#   services/<svc>/**                 -> that module (gofmt, build, vet, test,
#                                        govulncheck, gosec) + tests/contracts
#                                        + shared/infra/docgen tests
#   tests/contracts/**                -> tests/contracts
#   frontend/**                       -> frontend (dart format, composition
#                                        gate, flutter analyze, flutter test)
#                                        + shared/infra/docgen tests
#   infrastructure/staging/**         -> compose validation (staging) + docs
#   infrastructure/deploy/**          -> compose validation (prod) + docs
#   infrastructure/** (anything else) -> compose validation (all stacks) + docs
#   anything else                     -> FULL gate (fail safe)
# Additions to the WF-03 task mapping: shared/infra/docgen tests read
# services/*/internal/handlers (APPLICATION_MAP.md route sync) and frontend/**
# (STATUS.md coverage, widget counts, pubspec vs DESIGN.md, l10n), so service
# and frontend changes also run them. .gitleaks.toml is gate configuration.
#
# CI_SCOPE=full forces the full gate.
#
# stdout: shell-quoted KEY=value lines (eval them):
#   SCOPE_MODE        full | scoped | none
#   SCOPE_GO_MODULES  space-separated module dirs (full: all six)
#   SCOPE_CONTRACTS, SCOPE_DOCS, SCOPE_INFRA_TESTS, SCOPE_DOCGEN,
#   SCOPE_FRONTEND    0 | 1
#   SCOPE_COMPOSE     space-separated stacks (local staging prod)
#   SCOPE_KEY         canonical description, e.g. "go=services/x contracts docgen"
# stderr: the scope and WHY (one line per reason).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ALL_GO_MODULES="services/api-gateway services/auth-service services/chat-service services/notification-service services/user-service shared/infra"
ZERO_SHA_RE='^0+$'

say() { printf 'scope: %s\n' "$*" >&2; }

FULL_REASON=""
GO_MODULES=""
CONTRACTS=0
DOCS=0
INFRA_TESTS=0
DOCGEN=0
FRONTEND=0
COMPOSE=""

add_word() { # add_word <varname> <word>
	local cur="${!1}"
	case " $cur " in *" $2 "*) return ;; esac
	printf -v "$1" '%s' "${cur:+$cur }$2"
}

force_full() {
	[ -n "$FULL_REASON" ] || FULL_REASON="$1"
}

classify() { # classify <path>
	local p="$1"
	case "$p" in
	CLAUDE.md)
		# Before the *.md rule: agent instructions change how the gate is used.
		force_full "$p (agent instructions)"
		return
		;;
	*.md | docs/*)
		DOCS=1
		INFRA_TESTS=1
		return
		;;
	go.work | go.work.sum | */go.mod | */go.sum | go.mod | go.sum)
		force_full "$p (Go workspace/module definition)"
		return
		;;
	shared/infra/* | tools/* | .githooks/* | scripts/* | Makefile | .github/* | .gitleaks.toml)
		force_full "$p (shared code or gate configuration)"
		return
		;;
	services/*/*)
		local svc="${p#services/}"
		svc="${svc%%/*}"
		if [ -d "services/$svc" ] && [ -f "services/$svc/go.mod" ]; then
			add_word GO_MODULES "services/$svc"
			CONTRACTS=1
			DOCGEN=1
		else
			force_full "$p (services/$svc is not a known Go module)"
		fi
		return
		;;
	tests/contracts/*)
		CONTRACTS=1
		return
		;;
	frontend/*)
		FRONTEND=1
		DOCGEN=1
		return
		;;
	infrastructure/staging/*)
		add_word COMPOSE staging
		DOCS=1
		return
		;;
	infrastructure/deploy/*)
		add_word COMPOSE prod
		DOCS=1
		return
		;;
	infrastructure/*)
		add_word COMPOSE local
		add_word COMPOSE staging
		add_word COMPOSE prod
		DOCS=1
		return
		;;
	esac
	force_full "$p (unmapped path: fail safe)"
}

resolve_base_ref() { # the upstream to diff against for new refs / the working tree
	local cand
	for cand in "${SCOPE_BASE:-}" origin/logic-exploitation logic-exploitation; do
		[ -n "$cand" ] || continue
		if git rev-parse --verify --quiet "$cand^{commit}" >/dev/null; then
			echo "$cand"
			return 0
		fi
	done
	return 1
}

MODE="${1:-worktree}"
PATHS_FILE="$(mktemp)"
trap 'rm -f "$PATHS_FILE"' EXIT

case "$MODE" in
worktree)
	base_ref="${SCOPE_BASE:-logic-exploitation}"
	if ! git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
		force_full "upstream '$base_ref' not found"
	else
		mb="$(git merge-base HEAD "$base_ref")"
		say "changed paths = committed since merge-base with $base_ref ($(git rev-parse --short "$mb")) + staged + unstaged + untracked"
		{
			git diff --no-renames --name-only "$mb" HEAD
			git diff --no-renames --name-only --cached
			git diff --no-renames --name-only
			git ls-files --others --exclude-standard
		} >>"$PATHS_FILE"
	fi
	;;
--push)
	while read -r _lref lsha _rref rsha; do
		[ -n "${_lref}${lsha}" ] || continue
		if [[ "$lsha" =~ $ZERO_SHA_RE ]]; then
			continue # delete line: publishes nothing
		fi
		if [[ "$rsha" =~ $ZERO_SHA_RE ]]; then
			if base_ref="$(resolve_base_ref)"; then
				from="$(git merge-base "$lsha" "$base_ref")"
				say "$_rref is a new remote ref: pushed range = merge-base with $base_ref ($(git rev-parse --short "$from"))..$(git rev-parse --short "$lsha")"
			else
				force_full "$_rref is a new remote ref and no upstream to diff against"
				continue
			fi
		elif ! git cat-file -e "$rsha^{commit}" 2>/dev/null; then
			force_full "remote sha of $_rref is not in the local repo (fetch first)"
			continue
		else
			from="$rsha"
			say "pushed range for $_rref: $(git rev-parse --short "$from")..$(git rev-parse --short "$lsha")"
		fi
		git diff --no-renames --name-only "$from" "$lsha" >>"$PATHS_FILE"
	done
	;;
--paths)
	cat >>"$PATHS_FILE"
	;;
*)
	echo "usage: scripts/changed-scope.sh [--push | --paths]" >&2
	exit 2
	;;
esac

if [ "${CI_SCOPE:-}" = "full" ]; then
	FULL_REASON="CI_SCOPE=full"
fi

NPATHS=0
while IFS= read -r p; do
	[ -n "$p" ] || continue
	NPATHS=$((NPATHS + 1))
	classify "$p"
done < <(sort -u "$PATHS_FILE")

if [ -n "$FULL_REASON" ]; then
	MODE_OUT=full
	GO_MODULES="$ALL_GO_MODULES"
	CONTRACTS=1 DOCS=1 INFRA_TESTS=1 DOCGEN=1 FRONTEND=1
	COMPOSE="local staging prod"
	say "FULL gate: $FULL_REASON"
	KEY=full
elif [ "$NPATHS" -eq 0 ]; then
	MODE_OUT=none
	say "no changed paths: nothing to check"
	KEY=none
else
	MODE_OUT=scoped
	# Canonical module order, so the key does not depend on path order.
	ordered=""
	for m in $ALL_GO_MODULES; do
		case " $GO_MODULES " in *" $m "*) ordered="${ordered:+$ordered }$m" ;; esac
	done
	GO_MODULES="$ordered"
	ordered=""
	for s in local staging prod; do
		case " $COMPOSE " in *" $s "*) ordered="${ordered:+$ordered }$s" ;; esac
	done
	COMPOSE="$ordered"
	KEY=""
	[ -z "$GO_MODULES" ] || KEY="go=${GO_MODULES// /,}"
	[ "$CONTRACTS" -eq 0 ] || KEY="${KEY:+$KEY }contracts"
	[ "$DOCS" -eq 0 ] || KEY="${KEY:+$KEY }docs"
	[ "$INFRA_TESTS" -eq 0 ] || KEY="${KEY:+$KEY }infra-tests"
	[ "$DOCGEN" -eq 0 ] || KEY="${KEY:+$KEY }docgen"
	[ "$FRONTEND" -eq 0 ] || KEY="${KEY:+$KEY }frontend"
	[ -z "$COMPOSE" ] || KEY="${KEY:+$KEY }compose=${COMPOSE// /,}"
	say "SCOPED gate ($NPATHS changed path(s)): $KEY"
	sort -u "$PATHS_FILE" | sed '/^$/d' | head -n 20 | sed 's/^/scope:   /' >&2
	[ "$NPATHS" -le 20 ] || say "  ... and $((NPATHS - 20)) more"
fi

printf 'SCOPE_MODE=%q\n' "$MODE_OUT"
printf 'SCOPE_GO_MODULES=%q\n' "$GO_MODULES"
printf 'SCOPE_CONTRACTS=%q\n' "$CONTRACTS"
printf 'SCOPE_DOCS=%q\n' "$DOCS"
printf 'SCOPE_INFRA_TESTS=%q\n' "$INFRA_TESTS"
printf 'SCOPE_DOCGEN=%q\n' "$DOCGEN"
printf 'SCOPE_FRONTEND=%q\n' "$FRONTEND"
printf 'SCOPE_COMPOSE=%q\n' "$COMPOSE"
printf 'SCOPE_KEY=%q\n' "$KEY"
