#!/usr/bin/env bash
#
# infrastructure/deploy/backup/test/e2e-local.sh — local end-to-end test of
# backup.sh and restore.sh (OPS-BACKUP). Needs docker, age, age-keygen, curl,
# python3. Touches nothing shared: it creates its own disposable mongo:7
# container (400m, WiredTiger cache 0.25 GB, like production), its own
# volumes, a throwaway age key pair and a local fake Blob endpoint, and
# removes them all at the end.
#
#   infrastructure/deploy/backup/test/e2e-local.sh
#
# Checks:
#   1. backup.sh succeeds; every artifact (env-<stamp>.age included) is
#      uploaded (201) before SHA256SUMS and the uploaded bytes equal the local
#      copies; nothing in the log or in `ps` during the run contains the SAS
#      signature, the Mongo password or a value from the fake .env
#   2. restore.sh of the UPLOADED copies: per-collection document counts equal
#      the source exactly; restored volume files equal the source (sha256);
#      the secrets file is decrypted to a mode-600 file, nothing of its
#      contents (not even a variable name) is printed, it is deleted without
#      -k, and with -k it is kept and equal to the source
#   3. local retention keeps 3 runs; the lock refuses an overlapping run
#   4. failures exit non-zero and write the marker; the next success clears it;
#      a rejected upload logs the HTTP status and Azure code, not the SAS
#   5. refusals: bash -x, placeholder recipient, SAS with read/list/delete
#      permissions, group/other-readable SAS file, missing secrets file
# "A && B || fail" is meant here: fail when either A or B is false.
# shellcheck disable=SC2015
set -euo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SH="$HERE/../backup.sh"
RESTORE_SH="$HERE/../restore.sh"
PLACEHOLDER_PUB="$HERE/../backup-recipient.pub"
IMAGE="${E2E_IMAGE:-mongo:7}"

for t in docker age age-keygen curl python3 flock; do
	command -v "$t" >/dev/null || {
		echo "missing tool: $t" >&2
		exit 1
	}
done

ID="qdbt-$$"
WORK="$(mktemp -d)"
MONGO="$ID-mongo"
VOL_DOCS="$ID-documents"
VOL_ATT="$ID-attachments"
FAKE_PID=""

cleanup() {
	local rc=$?
	[ -z "$FAKE_PID" ] || kill "$FAKE_PID" 2>/dev/null || true
	docker rm -f "$MONGO" >/dev/null 2>&1 || true
	docker volume rm "$VOL_DOCS" "$VOL_ATT" >/dev/null 2>&1 || true
	rm -rf "$WORK"
	if [ "$rc" -eq 0 ]; then echo "E2E RESULT: PASS"; else echo "E2E RESULT: FAIL (exit $rc)"; fi
}
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() {
	printf 'FAIL: %s\n' "$*"
	exit 1
}
section() { printf '\n### %s\n' "$*"; }

rand() { od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'; }

# --- fixtures -------------------------------------------------------------------
section "fixtures"
age-keygen -o "$WORK/key.txt" 2>/dev/null
age-keygen -y "$WORK/key.txt" >"$WORK/recipient.pub"
echo "throwaway age key pair generated (public key in $WORK/recipient.pub)"

MONGO_PW="p'w\"$(rand 8) \$x&y"
SIG="$(rand 16)"
ENV_V1="dek-$(rand 16)"
ENV_V2="jwt-$(rand 16)"
ENV_V3="pw-$(rand 8)"
docker run -d --name "$MONGO" --memory 400m \
	-e MONGO_INITDB_ROOT_USERNAME=root -e MONGO_INITDB_ROOT_PASSWORD="$MONGO_PW" \
	"$IMAGE" --quiet --wiredTigerCacheSizeGB 0.25 >/dev/null
for i in $(seq 1 60); do
	docker exec "$MONGO" mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' >/dev/null 2>&1 && break
	[ "$i" -lt 60 ] || fail "mongo did not start"
	sleep 1
done
# Wait until the init script has created the root user (auth works).
for i in $(seq 1 60); do
	"$RESTORE_SH" --counts "$MONGO" >/dev/null 2>&1 && break
	[ "$i" -lt 60 ] || fail "mongo root user not ready"
	sleep 1
done
docker exec "$MONGO" sh -c 'mongosh --quiet -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "$1"' sh '
const spec = {
  auth_db: { users: 1500, kyc_documents: 700, refresh_tokens: 0 },
  user_db: { services: 120, jobs: 4000, wallets: 1500, ledger: 9000 },
  chat_db: { messages: 12000, tickets: 333 },
  notification_db: { notifications: 7777 },
};
for (const [d, cols] of Object.entries(spec)) {
  for (const [c, n] of Object.entries(cols)) {
    const coll = db.getSiblingDB(d)[c];
    if (n === 0) { db.getSiblingDB(d).createCollection(c); continue; }
    for (let b = 0; b < n; b += 2000) {
      const docs = [];
      for (let i = b; i < Math.min(n, b + 2000); i++) {
        docs.push({ i, name: "doc-" + i, nested: { a: [i, i * 2], at: new Date(1700000000000 + i * 1000) }, pad: "x".repeat(i % 300) });
      }
      coll.insertMany(docs);
    }
    coll.createIndex({ i: 1 });
  }
}
db.getSiblingDB("user_db").services.createIndex({ loc: "2dsphere" });
' >/dev/null
echo "seeded mongo container $MONGO"

docker volume create "$VOL_DOCS" >/dev/null
docker volume create "$VOL_ATT" >/dev/null
docker run --rm -v "$VOL_DOCS:/d" -v "$VOL_ATT:/a" --entrypoint sh "$IMAGE" -c '
set -e
for u in 1 2 3; do mkdir -p /d/user-$u; for k in 1 2 3 4; do head -c $((u * k * 7000)) /dev/urandom >/d/user-$u/kyc-$k.enc; done; done
mkdir -p "/d/space dir"; echo hello >"/d/space dir/a b.txt"
for t in 1 2; do mkdir -p /a/ticket-$t; for k in 1 2 3; do head -c $((t * k * 5000)) /dev/urandom >/a/ticket-$t/att-$k.bin; done; done
chmod 600 /d/user-1/kyc-1.enc'
echo "seeded volumes $VOL_DOCS, $VOL_ATT"

mkdir -p "$WORK/blob" "$WORK/state" "$WORK/backups"
# Fake production .env: comments, blank lines, export, a quoted value.
cat >"$WORK/env" <<ENV
# production secrets (fake)
DOCUMENT_ENCRYPTION_KEY=$ENV_V1

export JWT_SECRET=$ENV_V2
MONGO_ROOT_PASSWORD="$ENV_V3 with spaces"
ENV
chmod 600 "$WORK/env"
echo "fake secrets file $WORK/env ($(wc -l <"$WORK/env") lines)"
printf '%s\n' "$SIG" >"$WORK/expected-sig"
python3 -I "$HERE/fake_blob_server.py" "$WORK/blob" "$WORK/port" "$WORK/expected-sig" >"$WORK/fake.log" 2>&1 &
FAKE_PID=$!
for _ in $(seq 1 50); do [ -s "$WORK/port" ] && break; sleep 0.1; done
PORT="$(cat "$WORK/port")"
SE="$(date -u -d '+365 days' +%Y-%m-%dT%H%%3A%M%%3A%SZ)"
write_sas() { # write_sas <sp> <sig>
	printf 'http://127.0.0.1:%s/backups?sv=2022-11-02&sp=%s&se=%s&sr=c&sig=%s\n' "$PORT" "$1" "$SE" "$2" >"$WORK/sas"
	chmod 600 "$WORK/sas"
}
write_sas cw "$SIG"
echo "fake blob endpoint on 127.0.0.1:$PORT"

export MONGO_CONTAINER="$MONGO" VOLUMES="$VOL_DOCS $VOL_ATT" OPTIONAL_VOLUMES="$ID-caddy-missing" \
	BACKUP_DIR="$WORK/backups" STATE_DIR="$WORK/state" SAS_FILE="$WORK/sas" ENV_FILE="$WORK/env" \
	RECIPIENT_FILE="$WORK/recipient.pub" BLOB_PREFIX="e2e-host" MIN_FREE_MB=100 BACKUP_ALLOW_HTTP=1

secret_hits() { # secret_hits <file>: lines containing the SAS sig, the Mongo password or an .env value
	grep -cF -e "$SIG" -e "$MONGO_PW" -e "$ENV_V1" -e "$ENV_V2" -e "$ENV_V3" "$1" || true
}
env_name_hits() { # env_name_hits <file>: lines containing a variable name from the fake .env
	grep -cF -e DOCUMENT_ENCRYPTION_KEY -e JWT_SECRET -e MONGO_ROOT_PASSWORD "$1" || true
}

# --- 1. backup -------------------------------------------------------------------
section "1. backup.sh"
: >"$WORK/ps.log"
(while :; do ps -eo args >>"$WORK/ps.log"; sleep 0.05; done) &
PS_PID=$!
set +e
"$BACKUP_SH" >"$WORK/run1.log" 2>&1
rc=$?
set -e
kill "$PS_PID"
wait "$PS_PID" 2>/dev/null || true
cat "$WORK/run1.log"
[ "$rc" -eq 0 ] || fail "backup.sh exited $rc"
pass "backup.sh exit 0"
echo "fake endpoint log:"
cat "$WORK/fake.log"
RUN1="$(find "$WORK/backups" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | head -n 1)"
n_local="$(find "$WORK/backups/$RUN1" -type f | wc -l)"
n_201="$(grep -c ' -> 201' "$WORK/fake.log")"
[ "$n_local" -eq 5 ] && [ "$n_201" -eq 5 ] || fail "expected 5 local files and 5 uploads, got $n_local / $n_201"
pass "5 artifacts (mongo, 2 volumes, env, SHA256SUMS) written locally and uploaded with 201"
[ -f "$WORK/backups/$RUN1/env-$RUN1.age" ] || fail "env-$RUN1.age missing"
grep -q "  env-$RUN1.age\$" "$WORK/backups/$RUN1/SHA256SUMS" || fail "env-$RUN1.age not in SHA256SUMS"
env_line="$(grep -n " .*/env-$RUN1.age -> 201" "$WORK/fake.log" | cut -d: -f1)"
sums_line="$(grep -n " .*/$RUN1/SHA256SUMS -> 201" "$WORK/fake.log" | cut -d: -f1)"
[ -n "$env_line" ] && [ -n "$sums_line" ] && [ "$env_line" -lt "$sums_line" ] || fail "env-$RUN1.age not uploaded before SHA256SUMS"
pass "env-$RUN1.age is in SHA256SUMS and uploaded before SHA256SUMS"
UP="$WORK/blob/backups/e2e-host/$RUN1"
for f in "$WORK/backups/$RUN1"/*; do
	cmp -s "$f" "$UP/$(basename "$f")" || fail "uploaded copy differs: $(basename "$f")"
done
pass "uploaded bytes identical to the local copies"
for f in "$WORK/backups/$RUN1"/*.age; do
	head -c 21 "$f" | grep -q '^age-encryption.org/v1' || fail "not an age file: $f"
done
pass "every artifact starts with the age header (encrypted)"
[ "$(secret_hits "$WORK/run1.log")" -eq 0 ] || fail "secret found in the backup log"
pass "backup log contains neither the SAS sig, the Mongo password nor an .env value"
ps_lines="$(wc -l <"$WORK/ps.log")"
if [ "$(secret_hits "$WORK/ps.log")" -ne 0 ]; then
	grep -F -e "$SIG" -e "$MONGO_PW" "$WORK/ps.log" | sort -u | sed -e "s/$SIG/<SIG>/g" | awk -v pw="$MONGO_PW" '{ gsub(pw, "<MONGO_PW>"); print "  ps: " $0 }' | head -n 5
	fail "secret visible in ps output during the run"
fi
pass "ps sampled every 50 ms during the run ($ps_lines lines): no SAS sig, no Mongo password on any command line"
grep -q "qd-backup-dump" "$WORK/ps.log" && pass "ps sampling caught the mongodump sidecar running (the sampler saw the run)" ||
	echo "NOTE: ps sampling did not catch the sidecar's docker run line (run too fast)"
[ ! -e "$WORK/state/FAILED" ] && [ -s "$WORK/state/last-success" ] || fail "state files wrong after success"
pass "no FAILED marker, last-success written"

# --- 2. restore ------------------------------------------------------------------
section "2. restore.sh from the uploaded copies"
"$RESTORE_SH" --counts "$MONGO" >"$WORK/counts-source.txt"
echo "source counts (restore.sh --counts on the source container):"
cat "$WORK/counts-source.txt"
"$RESTORE_SH" -i "$WORK/key.txt" "$UP/mongo-$RUN1.archive.gz.age" | tee "$WORK/restore-mongo.log"
grep -E '^[A-Za-z0-9_]+\.[^ ]+ [0-9]+$' "$WORK/restore-mongo.log" >"$WORK/counts-restored.txt"
if diff -u "$WORK/counts-source.txt" "$WORK/counts-restored.txt"; then
	pass "document counts match exactly: $(wc -l <"$WORK/counts-source.txt") collections, $(awk '{ s += $2 } END { print s }' "$WORK/counts-source.txt") documents"
else
	fail "document counts differ"
fi

mkdir -p "$WORK/restore-tmp"
RESTORE_TMP="$WORK/restore-tmp" "$RESTORE_SH" -k -i "$WORK/key.txt" "$UP/$VOL_DOCS-$RUN1.tar.gz.age" "$UP/$VOL_ATT-$RUN1.tar.gz.age" | tee "$WORK/restore-vol.log"
src_sums() { # src_sums <volume>
	docker run --rm -v "$1:/s:ro" --entrypoint sh "$IMAGE" -c 'cd /s && find . -type f -print0 | sort -z | xargs -0 sha256sum'
}
mapfile -t vdirs < <(find "$WORK/restore-tmp" -mindepth 1 -maxdepth 1 -type d | sort)
[ "${#vdirs[@]}" -eq 2 ] || fail "expected 2 extracted dirs, got ${#vdirs[@]}"
i=0
for vol in "$VOL_DOCS" "$VOL_ATT"; do
	# restore.sh extracts in argument order: documents first, then attachments.
	d="$(grep -o "$WORK/restore-tmp/qd-restore-[A-Za-z0-9]*" "$WORK/restore-vol.log" | sed -n "$((i + 1))p")"
	src_sums "$vol" >"$WORK/src-$i.sums"
	(cd "$d" && find . -type f -print0 | sort -z | xargs -0 sha256sum) >"$WORK/dst-$i.sums"
	diff -u "$WORK/src-$i.sums" "$WORK/dst-$i.sums" || fail "restored files of $vol differ from the source"
	pass "$vol: $(wc -l <"$WORK/src-$i.sums") files restored, every sha256 equal to the source"
	i=$((i + 1))
done
rm -rf "$WORK/restore-tmp"

mkdir -p "$WORK/restore-tmp"
RESTORE_TMP="$WORK/restore-tmp" "$RESTORE_SH" -i "$WORK/key.txt" "$UP/env-$RUN1.age" >"$WORK/restore-env.log" 2>&1 ||
	fail "restore.sh of env-$RUN1.age failed: $(cat "$WORK/restore-env.log")"
sed -e "s|$WORK|<WORK>|g" "$WORK/restore-env.log"
[ "$(secret_hits "$WORK/restore-env.log")" -eq 0 ] || fail "restore.sh printed a value from the .env"
[ "$(env_name_hits "$WORK/restore-env.log")" -eq 0 ] || fail "restore.sh printed a variable name from the .env"
grep -q "mode 600, $(stat -c %s "$WORK/env") bytes, $(wc -l <"$WORK/env") lines" "$WORK/restore-env.log" ||
	fail "restore.sh did not report mode 600 and the source's size and line count"
[ -z "$(find "$WORK/restore-tmp" -mindepth 1)" ] || fail "decrypted secrets file not deleted without -k"
pass "env: mode 600, size and line count of the source, no value and no variable name printed, deleted without -k"
RESTORE_TMP="$WORK/restore-tmp" "$RESTORE_SH" -k -i "$WORK/key.txt" "$UP/env-$RUN1.age" >"$WORK/restore-env-k.log" 2>&1 ||
	fail "restore.sh -k of env-$RUN1.age failed"
[ "$(secret_hits "$WORK/restore-env-k.log")" -eq 0 ] && [ "$(env_name_hits "$WORK/restore-env-k.log")" -eq 0 ] ||
	fail "restore.sh -k printed a value or a variable name from the .env"
mapfile -t kept < <(find "$WORK/restore-tmp" -mindepth 1)
[ "${#kept[@]}" -eq 1 ] && [ "$(stat -c %a "${kept[0]}")" = "600" ] && cmp -s "${kept[0]}" "$WORK/env" ||
	fail "with -k: expected one kept file, mode 600, equal to the source .env"
grep -q 'kept secrets files' "$WORK/restore-env-k.log" || fail "with -k: kept file not reported"
pass "env with -k: decrypted file kept, mode 600, byte-identical to the source .env"
rm -rf "$WORK/restore-tmp"

# --- 3. retention and lock -------------------------------------------------------
section "3. retention (KEEP_LOCAL=3) and lock"
for n in 2 3 4; do
	sleep 1.1 # one stamp per second
	"$BACKUP_SH" >"$WORK/run$n.log" 2>&1 || fail "backup run $n failed"
	grep 'retention' "$WORK/run$n.log"
done
n_runs="$(find "$WORK/backups" -mindepth 1 -maxdepth 1 -type d | wc -l)"
[ "$n_runs" -eq 3 ] || fail "expected 3 local runs after 4 backups, got $n_runs"
[ ! -d "$WORK/backups/$RUN1" ] || fail "oldest run $RUN1 was not removed"
pass "after 4 runs: $n_runs local runs kept, the oldest ($RUN1) removed; off-host copies untouched: $(find "$WORK/blob/backups/e2e-host" -mindepth 1 -maxdepth 1 -type d | wc -l) runs"

flock "$WORK/backups/.lock" sleep 4 &
LOCK_PID=$!
sleep 0.5
set +e
"$BACKUP_SH" >"$WORK/lock.log" 2>&1
rc=$?
set -e
wait "$LOCK_PID"
cat "$WORK/lock.log"
[ "$rc" -ne 0 ] && grep -q 'another backup run holds' "$WORK/lock.log" || fail "overlapping run was not refused"
[ ! -e "$WORK/state/FAILED" ] || fail "lock refusal must not write the FAILED marker"
pass "overlapping run refused by flock (exit $rc), no FAILED marker"

# --- 4. failures -----------------------------------------------------------------
section "4. failure marker, rejected upload"
set +e
MONGO_CONTAINER="$ID-nonexistent" "$BACKUP_SH" >"$WORK/fail.log" 2>&1
rc=$?
set -e
cat "$WORK/fail.log"
[ "$rc" -ne 0 ] && [ -s "$WORK/state/FAILED" ] || fail "failed run did not exit non-zero / write the marker"
echo "marker: $(cat "$WORK/state/FAILED")"
pass "failed run: exit $rc, FAILED marker written"
SERVICE_RESULT=exit-code EXIT_CODE=exited EXIT_STATUS=1 "$BACKUP_SH" --post-stop | tee "$WORK/poststop.log"
grep -q 'BACKUP FAILED' "$WORK/poststop.log" || fail "--post-stop did not print the marker"
pass "--post-stop (systemd ExecStopPost) prints the marker into the unit's log / systemctl status"

write_sas cw "wrong$(rand 8)"
WRONG_SIG="$(sed -n 's/.*sig=//p' "$WORK/sas")"
sleep 1.1
set +e
"$BACKUP_SH" >"$WORK/reject.log" 2>&1
rc=$?
set -e
cat "$WORK/reject.log"
[ "$rc" -ne 0 ] && grep -q 'HTTP 403 <Code>AuthenticationFailed</Code>' "$WORK/reject.log" || fail "rejected upload not reported"
grep -qF "$WRONG_SIG" "$WORK/reject.log" && fail "rejected-upload log contains the SAS sig"
pass "rejected upload: exit $rc, HTTP status + Azure code logged, SAS sig not logged"

write_sas cw "$SIG"
sleep 1.1
"$BACKUP_SH" >"$WORK/recover.log" 2>&1 || fail "recovery run failed"
tail -n 1 "$WORK/recover.log"
[ ! -e "$WORK/state/FAILED" ] || fail "successful run did not clear the marker"
pass "next successful run cleared the FAILED marker"

# --- 5. refusals -----------------------------------------------------------------
section "5. refusals"
expect_refusal() { # expect_refusal <label> <pattern> <command...>
	local label="$1" pat="$2" out rc
	shift 2
	set +e
	out="$("$@" 2>&1)"
	rc=$?
	set -e
	printf '%s\n' "$out" | grep -v '^\s*$' | tail -n 2
	[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "$pat" || fail "$label: not refused as expected"
	printf '%s' "$out" | grep -qF -e "$SIG" -e "$MONGO_PW" -e "$ENV_V1" -e "$ENV_V2" -e "$ENV_V3" && fail "$label: output contains a secret"
	pass "$label: refused (exit $rc), no secret in the output"
}
expect_refusal "bash -x" "refusing to run with xtrace" bash -x "$BACKUP_SH"
expect_refusal "placeholder recipient" "no age public key" env RECIPIENT_FILE="$PLACEHOLDER_PUB" "$BACKUP_SH"
write_sas rcwl "$SIG"
expect_refusal "SAS with read/list" "only c (create) and w (write)" "$BACKUP_SH"
write_sas cw "$SIG"
chmod 644 "$WORK/sas"
expect_refusal "SAS file mode 644" "it must be 600 or 400" "$BACKUP_SH"
chmod 600 "$WORK/sas"
expect_refusal "missing secrets file" "secrets file not readable" env ENV_FILE="$WORK/no-such.env" "$BACKUP_SH"
