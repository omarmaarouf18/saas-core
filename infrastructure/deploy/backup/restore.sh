#!/usr/bin/env bash
#
# infrastructure/deploy/backup/restore.sh — test-restore downloaded backups on
# the OWNER's machine (OPS-BACKUP). Never run it against production: it only
# restores into a throwaway container / temp dir. Restoring INTO production is
# a separate, manual procedure in docs/runbooks/BACKUP-RESTORE.md.
#
# Usage:
#   restore.sh -i <age identity file> [-k] <file.age | run dir>...
#   restore.sh --counts <container>     print document counts of a running
#                                       mongo container (auth from its
#                                       MONGO_INITDB_ROOT_* env), same format;
#                                       read-only. Like the compose healthcheck,
#                                       it passes the password to mongosh as an
#                                       argument inside that container.
#
#   -i FILE  the age private key (AGE-SECRET-KEY-1..., or a passphrase-protected
#            identity file: age then asks for the passphrase)
#   -k       keep the throwaway mongo container, the extracted volume dirs and
#            the decrypted secrets file (default: remove them; they hold
#            personal data and production secrets)
#
# Per file, by name:
#   mongo-*.archive.gz.age   decrypt | mongorestore into a fresh mongo container
#                            with no published ports, then print one line per
#                            collection: "<db>.<collection> <count>"
#   *-*.tar.gz.age           decrypt | tar -x into a temp dir, then print file
#                            and directory counts and sizes
#   env-*.age                decrypt into a temp file with mode 600, then print
#                            only its path, size and line count (never any of
#                            its contents, not even variable names)
# If a SHA256SUMS file sits next to a file, its checksum is verified first.
#
# Settings (environment): RESTORE_IMAGE (mongo:7), RESTORE_TMP (${TMPDIR:-/tmp}).
set -euo pipefail
export LC_ALL=C
umask 077

RESTORE_IMAGE="${RESTORE_IMAGE:-mongo:7}"
RESTORE_TMP="${RESTORE_TMP:-${TMPDIR:-/tmp}}"

# One line per collection, sorted: "<db>.<collection> <count>". System
# databases (admin, config, local) and system.* collections are skipped;
# countDocuments() is exact (not the metadata estimate).
COUNTS_JS='
const out = [];
for (const d of db.adminCommand({ listDatabases: 1, nameOnly: true }).databases) {
  if (["admin", "config", "local"].includes(d.name)) continue;
  const sib = db.getSiblingDB(d.name);
  for (const c of sib.getCollectionInfos({ type: "collection" }, { nameOnly: true })) {
    if (c.name.startsWith("system.")) continue;
    out.push(d.name + "." + c.name + " " + sib.getCollection(c.name).countDocuments({}));
  }
}
out.sort();
print(out.join("\n"));
'

usage() {
	sed -n '/^# Usage:/,/^# Settings/p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}

say() { printf '== %s\n' "$*"; }
die() {
	printf 'restore.sh: ERROR: %s\n' "$*" >&2
	exit 1
}
human() { numfmt --to=iec --suffix=B "$1"; }

if [ "${1:-}" = "--counts" ]; then
	[ $# -eq 2 ] || usage
	# shellcheck disable=SC2016 # expanded inside the container
	docker exec "$2" sh -c 'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "$1"' sh "$COUNTS_JS"
	exit 0
fi

IDENTITY=""
KEEP=0
while getopts ':i:kh' opt; do
	case "$opt" in
	i) IDENTITY="$OPTARG" ;;
	k) KEEP=1 ;;
	*) usage ;;
	esac
done
shift $((OPTIND - 1))
if [ -z "$IDENTITY" ] || [ $# -eq 0 ]; then usage; fi
[ -r "$IDENTITY" ] || die "identity file not readable: $IDENTITY"
for tool in age docker tar sha256sum numfmt; do
	command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# Expand run directories into their .age files.
FILES=()
for a in "$@"; do
	if [ -d "$a" ]; then
		while IFS= read -r f; do FILES+=("$f"); done < <(find "$a" -maxdepth 1 -type f -name '*.age' | sort)
	elif [ -f "$a" ]; then
		FILES+=("$a")
	else
		die "not a file or directory: $a"
	fi
done
[ "${#FILES[@]}" -gt 0 ] || die "no .age files given"

CONTAINERS=()
DIRS=()
SECRETS=()
cleanup() {
	local rc=$?
	if [ "$KEEP" -eq 0 ]; then
		local c d
		for c in "${CONTAINERS[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
		for d in "${DIRS[@]}" "${SECRETS[@]}"; do rm -rf -- "$d"; done
	else
		[ "${#CONTAINERS[@]}" -eq 0 ] || say "kept containers (remove with docker rm -f): ${CONTAINERS[*]}"
		[ "${#DIRS[@]}" -eq 0 ] || say "kept dirs (personal data, delete when done): ${DIRS[*]}"
		[ "${#SECRETS[@]}" -eq 0 ] || say "kept secrets files (mode 600, production secrets, delete when done): ${SECRETS[*]}"
	fi
	exit "$rc"
}
trap cleanup EXIT

verify_checksum() { # verify_checksum <file>
	local f="$1" dir base sums
	dir="$(dirname "$f")"
	base="$(basename "$f")"
	sums="$dir/SHA256SUMS"
	if [ -f "$sums" ] && grep -q "  $base\$" "$sums"; then
		(cd "$dir" && grep "  $base\$" SHA256SUMS | sha256sum -c --quiet -) || die "checksum mismatch: $f"
		say "checksum ok: $base"
	else
		say "no SHA256SUMS entry for $base: checksum not verified"
	fi
}

restore_mongo() { # restore_mongo <file>
	local f="$1" name i
	name="qd-restore-$$-${#CONTAINERS[@]}"
	say "mongo: starting throwaway container $name ($RESTORE_IMAGE, --network none, no auth)"
	CONTAINERS+=("$name")
	docker run -d --name "$name" --network none "$RESTORE_IMAGE" --quiet >/dev/null
	for i in $(seq 1 60); do
		if docker exec "$name" mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' >/dev/null 2>&1; then
			break
		fi
		[ "$i" -lt 60 ] || die "throwaway mongo did not become ready in 60 s"
		sleep 1
	done
	say "mongo: decrypt | mongorestore $(basename "$f")"
	age -d -i "$IDENTITY" "$f" | docker exec -i "$name" mongorestore --archive --gzip --quiet
	say "mongo: document counts (<db>.<collection> <count>)"
	docker exec "$name" mongosh --quiet --eval "$COUNTS_JS"
}

restore_volume() { # restore_volume <file>
	local f="$1" dir n_files n_dirs bytes entry
	dir="$(mktemp -d "$RESTORE_TMP/qd-restore-XXXXXX")"
	DIRS+=("$dir")
	say "volume: decrypt | tar -x $(basename "$f") -> $dir"
	age -d -i "$IDENTITY" "$f" | tar --no-same-owner --no-same-permissions -xzf - -C "$dir"
	n_files="$(find "$dir" -type f | wc -l)"
	n_dirs="$(find "$dir" -mindepth 1 -type d | wc -l)"
	bytes="$(find "$dir" -type f -printf '%s\n' | awk '{ s += $1 } END { print s + 0 }')"
	say "volume: $n_files files, $n_dirs dirs, $bytes bytes ($(human "$bytes")) in total"
	while IFS= read -r entry; do
		if [ -d "$dir/$entry" ]; then
			printf '  %s/ %s files %s bytes\n' "$entry" \
				"$(find "$dir/$entry" -type f | wc -l)" \
				"$(find "$dir/$entry" -type f -printf '%s\n' | awk '{ s += $1 } END { print s + 0 }')"
		else
			printf '  %s %s bytes\n' "$entry" "$(stat -c %s "$dir/$entry")"
		fi
	done < <(find "$dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
}

restore_env() { # restore_env <file>
	local f="$1" out
	out="$(mktemp "$RESTORE_TMP/qd-restore-env-XXXXXX")"
	SECRETS+=("$out")
	chmod 600 "$out"
	say "env: decrypt $(basename "$f") -> $out"
	age -d -i "$IDENTITY" "$f" >"$out"
	# Metadata only: nothing from the file's contents is ever printed.
	say "env: $out mode $(stat -c %a "$out"), $(stat -c %s "$out") bytes, $(wc -l <"$out") lines"
}

for f in "${FILES[@]}"; do
	verify_checksum "$f"
	case "$(basename "$f")" in
	mongo-*.archive.gz.age) restore_mongo "$f" ;;
	*.tar.gz.age) restore_volume "$f" ;;
	env-*.age) restore_env "$f" ;;
	*) die "unknown artifact type (expected mongo-*.archive.gz.age, env-*.age or *.tar.gz.age): $f" ;;
	esac
done
say "restore test finished: ${#FILES[@]} file(s)"
