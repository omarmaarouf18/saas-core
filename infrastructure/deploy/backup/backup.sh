#!/usr/bin/env bash
#
# infrastructure/deploy/backup/backup.sh — daily encrypted off-host backup of
# production data (OPS-BACKUP). Runbook: docs/runbooks/BACKUP-RESTORE.md.
#
# What it backs up, every run, into one directory per run under BACKUP_DIR:
#   mongo-<stamp>.archive.gz.age        mongodump --archive --gzip of every database
#   <volume>-<stamp>.tar.gz.age         tar.gz of each named volume (documents,
#                                       attachments; caddy_data when present)
#   env-<stamp>.age                     the production secrets file ENV_FILE
#                                       (holds DOCUMENT_ENCRYPTION_KEY: without
#                                       it the volume backups cannot be read)
#   SHA256SUMS                          checksums of the .age files (no secrets)
# Each artifact is streamed straight into `age` (encrypted to the public key in
# backup-recipient.pub; the private key never touches this machine), uploaded
# with curl to Azure Blob Storage using a create/write-only SAS URL read from
# SAS_FILE, and the newest KEEP_LOCAL local runs are kept.
#
# Usage:
#   backup.sh               run a backup (what the systemd service does)
#   backup.sh --post-stop   systemd ExecStopPost hook: records a failure marker
#                           when the run was killed before it could do so itself
#
# Settings (environment; systemd also reads /etc/quickdelivery-backup/backup.env).
# The defaults are production values; tests override them.
#   MONGO_CONTAINER   running mongo container                    (saas-mongo)
#   DUMP_IMAGE        image for the dump/tar sidecars   (the image of MONGO_CONTAINER)
#   DUMP_MEMORY       memory cap of the mongodump sidecar         (192m)
#   VOLUMES           named volumes that must exist  (saas_platform_documents_data
#                                                     saas_platform_attachments_data)
#   OPTIONAL_VOLUMES  named volumes backed up when present        (caddy_data)
#   ENV_FILE          production secrets file, required   (/home/deploybot/.env)
#   BACKUP_DIR        local encrypted copies          (/var/backups/quickdelivery)
#   KEEP_LOCAL        local runs to keep                          (3)
#   STATE_DIR         failure marker and last-success  (/var/lib/quickdelivery-backup)
#   SAS_FILE          one line: container SAS URL   (/etc/quickdelivery-backup/sas)
#   PING_FILE         one line: healthchecks.io ping URL (dead-man ping,
#                     OBS-MIN)                     (/etc/quickdelivery-backup/ping)
#   RECIPIENT_FILE    age recipients file        (backup-recipient.pub next to this script)
#   BLOB_PREFIX       blob name prefix                            ($(hostname -s))
#   MIN_FREE_MB       refuse to start below this much free space  (2048)
#   BACKUP_ALLOW_HTTP 1 = allow an http:// upload URL (local tests only)  (0)
#
# Why a sidecar for mongodump instead of `docker exec saas-mongo mongodump`:
# exec'd processes run inside the mongo container's 400m cgroup. Measured on a
# 140 MB test set, an exec'd mongodump took that cgroup to 391/400 MiB, and a
# cgroup OOM there kills mongod (the biggest process), not mongodump. The
# sidecar shares saas-mongo's network namespace (127.0.0.1:27017) but has its
# own memory cap: in the worst case the dump is OOM-killed and the backup fails
# loudly, while mongod is untouched. --numParallelCollections=1 keeps it under
# 128 MiB on the same test set (the default of 4 needed more than 256 MiB).
set -euo pipefail

# Refuse xtrace: it would print the SAS URL and the Mongo password.
case $- in *x*)
	echo "backup.sh: refusing to run with xtrace (set -x) enabled: it would print secrets" >&2
	exit 2
	;;
esac

umask 077
export LC_ALL=C

SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

MONGO_CONTAINER="${MONGO_CONTAINER:-saas-mongo}"
DUMP_IMAGE="${DUMP_IMAGE:-}"
DUMP_MEMORY="${DUMP_MEMORY:-192m}"
VOLUMES="${VOLUMES:-saas_platform_documents_data saas_platform_attachments_data}"
OPTIONAL_VOLUMES="${OPTIONAL_VOLUMES-caddy_data}"
ENV_FILE="${ENV_FILE:-/home/deploybot/.env}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/quickdelivery}"
KEEP_LOCAL="${KEEP_LOCAL:-3}"
STATE_DIR="${STATE_DIR:-/var/lib/quickdelivery-backup}"
SAS_FILE="${SAS_FILE:-/etc/quickdelivery-backup/sas}"
PING_FILE="${PING_FILE:-/etc/quickdelivery-backup/ping}"
RECIPIENT_FILE="${RECIPIENT_FILE:-$SELF_DIR/backup-recipient.pub}"
BLOB_PREFIX="${BLOB_PREFIX:-$(hostname -s)}"
MIN_FREE_MB="${MIN_FREE_MB:-2048}"
BACKUP_ALLOW_HTTP="${BACKUP_ALLOW_HTTP:-0}"

FAIL_MARKER="$STATE_DIR/FAILED"
RUNNING_MARKER="$STATE_DIR/running"
LAST_SUCCESS="$STATE_DIR/last-success"

STEP="init"

log() {
	# journald (systemd sets JOURNAL_STREAM) timestamps lines itself.
	if [ -n "${JOURNAL_STREAM:-}" ]; then
		printf '[%s] %s\n' "$STEP" "$*"
	else
		printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "$STEP" "$*"
	fi
}

die() {
	log "ERROR: $*"
	exit 1
}

now_ms() { date +%s%3N; }
human() { numfmt --to=iec --suffix=B "$1"; }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1fs", ms / 1000 }'; }

# --- dead-man ping (OBS-MIN) -------------------------------------------------
# healthchecks.io-style dead-man ping to the URL in PING_FILE (its first
# line): "<url>/start" when a run gets going, "<url>" when it succeeds and
# "<url>/fail" when it fails. The URL is a secret: read from a root-only file
# at run time and handed to curl on stdin (-K -, like the SAS), so it is never
# on a command line (ps) and never in a log — only the ping suffix is logged.
# Best effort everywhere: the file being absent or empty disables the feature
# with one log line, and a failed ping is a WARN, never a failure; the ping
# itself is capped at a few seconds (--connect-timeout 5 --max-time 10).
PING_URL=""
ping_url_scheme_ok() { # ping_url_scheme_ok <url>: true when the ping URL may be used
	case "$1" in
	https://*) return 0 ;;
	http://127.0.0.1:[0-9]*) [ "$BACKUP_ALLOW_HTTP" = "1" ] ;;
	*) return 1 ;;
	esac
}
read_ping_url() {
	if [ ! -f "$PING_FILE" ]; then
		log "ping: dead-man ping disabled ($PING_FILE does not exist; OBS-MIN runbook)"
		return 0
	fi
	PING_URL="$(head -n 1 "$PING_FILE" | tr -d '\r\n\t ')"
	if [ -z "$PING_URL" ]; then
		log "ping: dead-man ping disabled ($PING_FILE is empty; OBS-MIN runbook)"
		return 0
	fi
	read -r ping_mode < <(stat -c '%a' "$PING_FILE")
	if [ $((8#$ping_mode & 8#007)) -ne 0 ]; then
		log "WARN: ping: $PING_FILE has mode $ping_mode; it holds a secret URL, make it 600"
	fi
	case "$PING_URL" in */) PING_URL="${PING_URL%/}" ;; esac
	PING_URL="${PING_URL%%[[:space:]]*}"
	if ! ping_url_scheme_ok "$PING_URL"; then
		log "WARN: ping: $PING_FILE holds a URL backup.sh will not use (https only); ping disabled"
		PING_URL=""
	fi
	return 0
}
ping_hc() { # ping_hc <suffix> <body> — one best-effort healthchecks.io ping
	local suffix="$1" body="$2" t0 code
	[ -n "$PING_URL" ] || return 0
	t0="$(now_ms)"
	set +e
	code="$(printf 'url = "%s%s"\ndata-binary = "%s"\n' \
		"$PING_URL" "$suffix" "${body//\"/}" |
		curl -K - --silent --max-time 10 --connect-timeout 5 \
			--request POST --output /dev/null --write-out '%{http_code}' 2>/dev/null)"
	local rc=$?
	set -e
	if [ "$rc" -eq 0 ] && [ "$code" = "200" ]; then
		log "ok: ping$suffix in $(secs $(( $(now_ms) - t0 )))"
	else
		log "WARN: ping$suffix failed (curl exit $rc, HTTP ${code:-?}); the backup itself is unaffected"
	fi
	return 0
}
ping_fail() { # ping_fail <body> — best-effort /fail ping; reads the file itself
	# because cleanup() and --post-stop can run before read_ping_url was called.
	local url body
	[ -f "$PING_FILE" ] || return 0
	url="$(head -n 1 "$PING_FILE" | tr -d '\r\n\t ')"
	[ -n "$url" ] || return 0
	case "$url" in */) url="${url%/}" ;; esac
	if ! ping_url_scheme_ok "$url"; then
		return 0
	fi
	body="$(printf '%s' "$1" | tr '\r\n' ' ' | head -c 300 | tr -s ' ')"
	PING_URL="$url" ping_hc /fail "$body"
	return 0
}

# --- systemd ExecStopPost hook ----------------------------------------------
if [ "${1:-}" = "--post-stop" ]; then
	STEP="post-stop"
	if [ "${SERVICE_RESULT:-success}" != "success" ]; then
		mkdir -p "$STATE_DIR"
		if [ -e "$RUNNING_MARKER" ] || [ ! -e "$FAIL_MARKER" ]; then
			# The script did not reach its own exit trap (SIGKILL, MemoryMax OOM,
			# timeout), so record what systemd knows.
			printf '%s run killed or failed outside the script: result=%s code=%s status=%s\n' \
				"$(date -u +%FT%TZ)" "${SERVICE_RESULT:-?}" "${EXIT_CODE:-?}" "${EXIT_STATUS:-?}" >"$FAIL_MARKER"
			rm -f "$RUNNING_MARKER"
			# A fresh marker means the script's own cleanup did not run for this
			# failure, so this hook also sends the /fail dead-man ping (one per
			# failed run; the script's cleanup owns it otherwise).
			ping_fail "$(cat "$FAIL_MARKER")"
		fi
		log "BACKUP FAILED: $(cat "$FAIL_MARKER")"
		log "marker: $FAIL_MARKER (removed by the next successful run)"
	fi
	exit 0
fi

[ $# -eq 0 ] || {
	echo "usage: $0 [--post-stop]" >&2
	exit 2
}

# --- run state, cleanup and failure marker ----------------------------------
RUN_DIR=""
TMP_DIR=""
SIDECARS=()

cleanup() {
	local rc=$?
	trap - EXIT
	local c
	for c in "${SIDECARS[@]}"; do
		docker rm -f "$c" >/dev/null 2>&1 || true
	done
	[ -z "$RUN_DIR" ] || rm -f "$RUN_DIR"/*.partial
	[ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
	if [ "$rc" -ne 0 ] && [ "$STEP" != "lock" ]; then
		mkdir -p "$STATE_DIR"
		printf '%s backup failed at step "%s" (exit %s); see: journalctl -u quickdelivery-backup.service\n' \
			"$(date -u +%FT%TZ)" "$STEP" "$rc" >"$FAIL_MARKER"
		rm -f "$RUNNING_MARKER"
		log "BACKUP FAILED (exit $rc); marker written: $FAIL_MARKER"
		ping_fail "$(cat "$FAIL_MARKER")"
	fi
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# --- lock: two runs never overlap -------------------------------------------
STEP="lock"
mkdir -p "$BACKUP_DIR" "$STATE_DIR"
chmod 700 "$BACKUP_DIR" "$STATE_DIR"
exec 9>"$BACKUP_DIR/.lock"
if ! flock -n 9; then
	die "another backup run holds $BACKUP_DIR/.lock; not starting a second one"
fi

STEP="preflight"
RUN_START_MS="$(now_ms)"
date -u +%FT%TZ >"$RUNNING_MARKER"
read_ping_url

for tool in docker age curl flock sha256sum numfmt; do
	command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# Recipient: must hold at least one real age public key (not the placeholder).
[ -r "$RECIPIENT_FILE" ] || die "recipient file not readable: $RECIPIENT_FILE"
grep -Eq '^age1[0-9a-z]{58}$' "$RECIPIENT_FILE" ||
	die "no age public key (age1...) in $RECIPIENT_FILE: generate the key pair offline (runbook step 1)"

# SAS file: root-only (or current-user-only in tests), one line.
[ -f "$SAS_FILE" ] || die "SAS file missing: $SAS_FILE (runbook step 3)"
read -r sas_mode sas_uid < <(stat -c '%a %u' "$SAS_FILE")
[ "$sas_uid" = "$(id -u)" ] || die "$SAS_FILE must be owned by uid $(id -u) (owner uid is $sas_uid)"
[ $((8#$sas_mode & 8#077)) -eq 0 ] || die "$SAS_FILE has mode $sas_mode; it must be 600 or 400"
SAS_URL="$(head -n 1 "$SAS_FILE" | tr -d '\r\n\t ')"
[ -n "$SAS_URL" ] || die "$SAS_FILE is empty: paste the container SAS URL (runbook step 3)"
SAS_BASE="${SAS_URL%%\?*}"
SAS_TOKEN="${SAS_URL#*\?}"
if [ "$SAS_TOKEN" = "$SAS_URL" ] || [ -z "$SAS_TOKEN" ]; then
	die "$SAS_FILE holds no '?<token>' part: paste the Blob SAS URL, not the bare container URL"
fi
if [[ "$SAS_BASE" =~ ^https://[a-z0-9]{3,24}\.blob\.core\.windows\.net/[a-z0-9][a-z0-9-]{2,62}$ ]]; then
	:
elif [ "$BACKUP_ALLOW_HTTP" = "1" ] && [[ "$SAS_BASE" =~ ^http://127\.0\.0\.1:[0-9]+/[a-z0-9-]+$ ]]; then
	log "WARN: BACKUP_ALLOW_HTTP=1: uploading to a local test endpoint"
else
	die "SAS URL must look like https://<account>.blob.core.windows.net/<container>?<token>"
fi
# Permissions: refuse anything beyond create/write, so a stolen SAS cannot
# read, list or delete backups. A SAS tied to a stored access policy (si=)
# carries its permissions in the policy instead.
sas_param() { # sas_param <name>: value of a query parameter of the SAS token
	local kv
	local IFS='&'
	for kv in $SAS_TOKEN; do
		[ "${kv%%=*}" = "$1" ] && {
			printf '%s' "${kv#*=}"
			return 0
		}
	done
	return 0
}
sas_sp="$(sas_param sp)"
sas_si="$(sas_param si)"
if [ -n "$sas_sp" ]; then
	[[ "$sas_sp" =~ ^[cw]+$ ]] || die "SAS permissions are sp=$sas_sp; only c (create) and w (write) are allowed (runbook step 3)"
elif [ -n "$sas_si" ]; then
	log "SAS permissions come from stored access policy '$sas_si' (not checked here; it must be create+write only)"
else
	die "SAS token has neither sp= nor si=: cannot tell its permissions"
fi
sas_se="$(sas_param se)"
if [ -n "$sas_se" ]; then
	se_epoch="$(date -u -d "${sas_se//%3A/:}" +%s 2>/dev/null || echo 0)"
	days_left=$(((se_epoch - $(date -u +%s)) / 86400))
	[ "$se_epoch" -gt "$(date -u +%s)" ] || die "SAS expired at ${sas_se//%3A/:}: create a new one (runbook step 3)"
	if [ "$days_left" -lt 30 ]; then
		log "WARN: SAS expires in $days_left days (${sas_se//%3A/:}): renew it soon (runbook step 3)"
	fi
fi

avail_mb="$(df --output=avail -m "$BACKUP_DIR" | tail -n 1 | tr -d ' ')"
[ "$avail_mb" -ge "$MIN_FREE_MB" ] || die "only ${avail_mb} MB free under $BACKUP_DIR (need $MIN_FREE_MB)"

[ "$(docker inspect -f '{{.State.Running}}' "$MONGO_CONTAINER" 2>/dev/null || true)" = "true" ] ||
	die "container $MONGO_CONTAINER is not running"
[ -n "$DUMP_IMAGE" ] || DUMP_IMAGE="$(docker inspect -f '{{.Config.Image}}' "$MONGO_CONTAINER")"

for v in $VOLUMES; do
	docker volume inspect "$v" >/dev/null 2>&1 || die "required volume $v does not exist (docker volume ls)"
done

# Only the path is ever logged, never the contents.
if [ ! -f "$ENV_FILE" ] || [ ! -r "$ENV_FILE" ]; then
	die "secrets file not readable: $ENV_FILE (set ENV_FILE)"
fi
[ -s "$ENV_FILE" ] || die "secrets file is empty: $ENV_FILE"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$BACKUP_DIR/$STAMP"
TMP_DIR="$(mktemp -d)"
mkdir -m 700 "$RUN_DIR"
log "start run $STAMP: dir=$RUN_DIR target=$SAS_BASE/$BLOB_PREFIX/$STAMP/ image=$DUMP_IMAGE free=${avail_mb}MB"
ping_hc /start "start $STAMP on $(hostname -s)"

# --- 1. Mongo -----------------------------------------------------------------
STEP="mongodump"
t0="$(now_ms)"
mongo_user="$(docker exec "$MONGO_CONTAINER" printenv MONGO_INITDB_ROOT_USERNAME)" ||
	die "cannot read MONGO_INITDB_ROOT_USERNAME from $MONGO_CONTAINER"
mongo_pass="$(docker exec "$MONGO_CONTAINER" printenv MONGO_INITDB_ROOT_PASSWORD)" ||
	die "cannot read MONGO_INITDB_ROOT_PASSWORD from $MONGO_CONTAINER"
case "$mongo_pass" in *$'\n'*) die "the Mongo password contains a newline; unsupported" ;; esac
mongo_out="$RUN_DIR/mongo-$STAMP.archive.gz.age"
dump_name="qd-backup-dump-$$"
SIDECARS+=("$dump_name")
# The password reaches mongodump through stdin and a YAML --config file on a
# tmpfs inside the sidecar: it is never on a command line (ps) or in the
# sidecar's environment (docker inspect). printf is a bash builtin.
set +e
printf "password: '%s'\n" "${mongo_pass//\'/\'\'}" |
	docker run -i --rm --name "$dump_name" \
		--network "container:$MONGO_CONTAINER" \
		--memory "$DUMP_MEMORY" --memory-swap "$DUMP_MEMORY" \
		--tmpfs /run/qdb:size=64k,mode=0700 \
		--entrypoint sh "$DUMP_IMAGE" -c \
		'umask 077; cat >/run/qdb/cfg && exec mongodump --config /run/qdb/cfg --username "$1" --authenticationDatabase admin --host 127.0.0.1 --port 27017 --archive --gzip --quiet --numParallelCollections=1' \
		sh "$mongo_user" |
	age -R "$RECIPIENT_FILE" -o "$mongo_out.partial"
rcs=("${PIPESTATUS[@]}")
set -e
unset mongo_pass
[ "${rcs[1]}" -eq 0 ] || die "mongodump sidecar exited ${rcs[1]} (137 = OOM-killed at --memory $DUMP_MEMORY; raise DUMP_MEMORY)"
[ "${rcs[2]}" -eq 0 ] || die "age exited ${rcs[2]}"
mv "$mongo_out.partial" "$mongo_out"
log "ok: $(basename "$mongo_out") $(human "$(stat -c %s "$mongo_out")") in $(secs $(($(now_ms) - t0)))"

# --- 2. Volumes ---------------------------------------------------------------
# A read-only mount of the volume into a short-lived container (the mongo
# image, already on the host: nothing new is pulled), not the host path under
# /var/lib/docker/volumes: no dependency on the Docker data-root layout or the
# volume driver, and :ro guarantees the backup cannot modify the data.
backup_volume() { # backup_volume <volume>
	local vol="$1" out tar_name t0 rcs
	STEP="volume:$vol"
	t0="$(now_ms)"
	out="$RUN_DIR/$vol-$STAMP.tar.gz.age"
	tar_name="qd-backup-tar-$$"
	SIDECARS+=("$tar_name")
	set +e
	docker run --rm --name "$tar_name" --network none --memory 64m --memory-swap 64m \
		-v "$vol:/src:ro" --entrypoint tar "$DUMP_IMAGE" \
		-C /src --warning=no-file-changed -czf - . |
		age -R "$RECIPIENT_FILE" -o "$out.partial"
	rcs=("${PIPESTATUS[@]}")
	set -e
	# GNU tar exit 1 = a file changed while it was read (an upload in
	# progress): the archive is still valid, the file is caught tomorrow.
	if [ "${rcs[0]}" -eq 1 ]; then
		log "WARN: tar reported files changing during the read (exit 1); archive kept"
	elif [ "${rcs[0]}" -ne 0 ]; then
		die "tar sidecar exited ${rcs[0]}"
	fi
	[ "${rcs[1]}" -eq 0 ] || die "age exited ${rcs[1]}"
	mv "$out.partial" "$out"
	log "ok: $(basename "$out") $(human "$(stat -c %s "$out")") in $(secs $(($(now_ms) - t0)))"
}

for v in $VOLUMES; do
	backup_volume "$v"
done
for v in $OPTIONAL_VOLUMES; do
	if docker volume inspect "$v" >/dev/null 2>&1; then
		backup_volume "$v"
	else
		STEP="volume:$v"
		log "WARN: optional volume $v not found; skipped"
	fi
done

# --- 3. Secrets file ------------------------------------------------------------
# Encrypted to the same offline recipient as the data. The plaintext only
# flows from the file into age; nothing here reads or prints it.
STEP="env"
t0="$(now_ms)"
env_out="$RUN_DIR/env-$STAMP.age"
set +e
# shellcheck disable=SC2002 # same streaming pattern as the other artifacts
cat -- "$ENV_FILE" | age -R "$RECIPIENT_FILE" -o "$env_out.partial"
rcs=("${PIPESTATUS[@]}")
set -e
[ "${rcs[0]}" -eq 0 ] || die "cannot read $ENV_FILE (cat exited ${rcs[0]})"
[ "${rcs[1]}" -eq 0 ] || die "age exited ${rcs[1]}"
mv "$env_out.partial" "$env_out"
log "ok: $(basename "$env_out") $(human "$(stat -c %s "$env_out")") in $(secs $(($(now_ms) - t0)))"

STEP="checksums"
(cd "$RUN_DIR" && sha256sum -- *.age >SHA256SUMS)
log "ok: SHA256SUMS ($(wc -l <"$RUN_DIR/SHA256SUMS") files)"

# --- 4. Upload ----------------------------------------------------------------
# The URL (with the SAS signature) goes to curl through a config on stdin
# (-K -), never as an argument, so it is not visible in ps. Only the HTTP
# status and Azure's error code are logged, never the URL or the response body.
upload() { # upload <file>
	local f="$1" name code err t0
	name="$(basename "$f")"
	STEP="upload:$name"
	t0="$(now_ms)"
	code="$(printf 'url = "%s/%s/%s/%s?%s"\n' "$SAS_BASE" "$BLOB_PREFIX" "$STAMP" "$name" "$SAS_TOKEN" |
		curl -K - --silent --show-error --retry 3 --connect-timeout 20 --max-time 3600 \
			--upload-file "$f" \
			-H 'x-ms-blob-type: BlockBlob' -H 'Content-Type: application/octet-stream' \
			-o "$TMP_DIR/upload-body" -w '%{http_code}' 2>"$TMP_DIR/upload-err")" || {
		err="$(head -c 300 "$TMP_DIR/upload-err" | tr '\n' ' ')"
		die "curl failed: ${err%%\?*}"
	}
	if [ "$code" != "201" ]; then
		err="$(grep -o '<Code>[^<]*</Code>' "$TMP_DIR/upload-body" 2>/dev/null | head -n 1 || true)"
		die "upload rejected: HTTP $code ${err:-(no Azure error code)}"
	fi
	log "ok: uploaded $name $(human "$(stat -c %s "$f")") in $(secs $(($(now_ms) - t0)))"
}

for f in "$RUN_DIR"/*.age; do
	upload "$f"
done
# SHA256SUMS last: its presence off-host means the run's set is complete.
upload "$RUN_DIR/SHA256SUMS"

# --- 5. Local retention ---------------------------------------------------------
STEP="retention"
mapfile -t runs < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -regextype posix-extended \
	-regex '.*/[0-9]{8}T[0-9]{6}Z' -printf '%f\n' | sort)
removed=0
if [ "${#runs[@]}" -gt "$KEEP_LOCAL" ]; then
	for r in "${runs[@]:0:${#runs[@]}-KEEP_LOCAL}"; do
		rm -rf -- "${BACKUP_DIR:?}/$r"
		removed=$((removed + 1))
	done
fi
log "ok: kept $((${#runs[@]} - removed)) local runs, removed $removed (KEEP_LOCAL=$KEEP_LOCAL)"

STEP="done"
total="$(du -sb "$RUN_DIR" | cut -f1)"
rm -f "$FAIL_MARKER" "$RUNNING_MARKER"
date -u +%FT%TZ >"$LAST_SUCCESS"
log "BACKUP OK: run $STAMP, $(human "$total") encrypted, uploaded to $SAS_BASE/$BLOB_PREFIX/$STAMP/ in $(secs $(($(now_ms) - RUN_START_MS)))"
ping_hc "" "ok: run $STAMP, $(human "$total"), $(secs $(( $(now_ms) - RUN_START_MS )))"
