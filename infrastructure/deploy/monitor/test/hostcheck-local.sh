#!/usr/bin/env bash
#
# infrastructure/deploy/monitor/test/hostcheck-local.sh — local test of
# hostcheck.sh against a throwaway dockerized mini-stack and a fake
# healthchecks.io endpoint (OBS-MIN). Needs docker, curl, python3. Touches
# nothing shared: its containers are labelled with a random compose project
# that the real one does not use, and everything is removed at the end.
#
#   infrastructure/deploy/monitor/test/hostcheck-local.sh
#
# Checks:
#   1. a healthy mini-stack logs the ok line and pings the plain URL
#   2. a missing ping file: still exit 0, one "ping disabled" line, no ping
#   3. a container that restarted since the previous run (RestartCount
#      increased, the restart-loop signal) fails the check with a /fail ping
#   4. MemAvailable and disk thresholds breach via env overrides (hostcheck
#      cannot create disk pressure locally) and ping /fail with the reason
#   5. a container with a failing healthcheck ("unhealthy" while running)
#      fails the check with a /fail ping
#   6. a stopped container fails the check
#   7. a present backup FAILED marker fails the check
#   8. all clear again: ok line and a plain success ping
#   9. the ping URL never appears in the logs or in ps during a run, and
#      bash -x is refused
# shellcheck disable=SC2015 # "A && B || fail" is meant here: fail when either is false
set -euo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HC="$HERE/../hostcheck.sh"
PING_SERVER_PY="$HERE/fake_ping_server.py"

for t in docker curl python3; do
	command -v "$t" >/dev/null || {
		echo "missing tool: $t" >&2
		exit 1
	}
done

ID="qdhct-$$"
WORK="$(mktemp -d)"
PROJ="$ID-proj"
HC_A="$ID-a"       # healthy healthcheck
HC_R="$ID-restart" # restarts between two runs (docker restart)
HC_U="$ID-unheal"  # failing healthcheck
PING_PID=""
PING_SECRET=""

cleanup() {
	local rc=$?
	[ -z "$PING_PID" ] || kill "$PING_PID" 2>/dev/null || true
	docker rm -f "$HC_A" "$HC_R" "$HC_U" >/dev/null 2>&1 || true
	rm -rf "$WORK"
	if [ "$rc" -eq 0 ]; then echo "HOSTCHECK RESULT: PASS"; else echo "HOSTCHECK RESULT: FAIL (exit $rc)"; fi
}
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$*"; }
fail() {
	printf 'FAIL: %s\n' "$*"
	exit 1
}
section() { printf '\n### %s\n' "$*"; }

# --- fake ping endpoint ----------------------------------------------------------
: >"$WORK/pinglog"
PING_PORT_FILE="$WORK/pingport"
python3 -I "$PING_SERVER_PY" "$WORK/pinglog" "$PING_PORT_FILE" >"$WORK/ping-fake.log" 2>&1 &
PING_PID=$!
for _ in $(seq 1 50); do [ -s "$PING_PORT_FILE" ] && break; sleep 0.1; done
[ -s "$PING_PORT_FILE" ] || fail "fake ping server did not start"
PPORT="$(cat "$PING_PORT_FILE")"
PING_SECRET="qdhc-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
printf '%s\n' "http://127.0.0.1:$PPORT/$PING_SECRET" >"$WORK/ping"
chmod 600 "$WORK/ping"
echo "fake ping endpoint on 127.0.0.1:$PPORT (path kept in $WORK/ping, never echoed here)"

export COMPOSE_PROJECT="$PROJ" STATE_DIR="$WORK/state" BACKUP_STATE_DIR="$WORK/backupstate" \
	PING_FILE="$WORK/ping" DISK_MAX_PCT=85 MEM_MIN_MB=80

run_hc() { # run_hc <label> [extra env via the caller's command prefix]
	local label="$1"
	# shellcheck disable=SC2174 # -m only needs to apply to the final dir
	mkdir -m 700 -p "$STATE_DIR" "$BACKUP_STATE_DIR"
	set +e
	bash "$HC" >"$WORK/log-$label" 2>&1
	local rc=$?
	set -e
	cat "$WORK/log-$label"
	[ "$rc" -eq 0 ] || fail "hostcheck exited $rc (never acceptable: the script always exits 0)"
	printf '%s\n' "$rc" >"$WORK/rc-$label"
}

ping_lines() { grep -cE "^PING /$PING_SECRET(:?/fail|/start)?( |\$)" "$WORK/pinglog" 2>/dev/null || true; }

# --- 1. healthy mini-stack -------------------------------------------------------
section "1. healthy mini-stack: ok line + plain success ping"
docker run -d --name "$HC_A" --label com.docker.compose.project="$PROJ" \
	--health-cmd 'exit 0' --health-interval 1s --health-retries 1 \
	busybox sleep 3600 >/dev/null
docker run -d --name "$HC_R" --label com.docker.compose.project="$PROJ" --restart on-failure:1 \
	busybox sh -c 'sleep 20; exit 1' >/dev/null
for i in $(seq 1 30); do
	[ "$(docker inspect -f '{{.State.Health.Status}}' "$HC_A")" = "healthy" ] && break
	[ "$i" -lt 30 ] || fail "container $HC_A did not get healthy"
	sleep 1
done
run_hc 1-ok
grep -q 'hostcheck: ok:' "$WORK/log-1-ok" || fail "healthy host did not log the ok line"
tail -n 1 "$WORK/pinglog" | grep -qE "^PING /$PING_SECRET ok: " || fail "success ping missing"
[ "$(ping_lines)" -eq 1 ] || fail "expected exactly 1 ping"
pass "ok line logged, one plain success ping"

# --- 2. ping disabled -----------------------------------------------------------
section "2. missing ping file: silent run, no ping, feature off"
PING_FILE="$WORK/no-such-ping" run_hc 2-noping
grep -q 'ping disabled (.*no-such-ping does not exist' "$WORK/log-2-noping" || fail "missing ping file not reported"
[ "$(ping_lines)" -eq 1 ] || fail "a ping was sent although the ping file is missing"
grep -q 'hostcheck: ok:' "$WORK/log-2-noping" || fail "healthy host without ping should still log ok"
pass "missing ping file: one 'ping disabled' line, ok line still logged, no ping sent"

# --- 3. restart between runs ------------------------------------------------------
section "3. container restarted since the previous run: RestartCount check"
# The engine, not `docker restart`, increments RestartCount: HC_R was started
# with a 20 s sleep and exit 1 under --restart on-failure:1, so its first
# crash restarts it (count 0 -> 1) while it stays alive (sleep long enough
# that every phase below happens between the first and second crash).
for i in $(seq 1 40); do
	[ "$(docker inspect -f '{{.RestartCount}}' "$HC_R")" -ge 1 ] &&
		[ "$(docker inspect -f '{{.State.Status}}' "$HC_R")" = "running" ] && break
	[ "$i" -lt 40 ] || fail "container $HC_R never restarted into a running state"
	sleep 1
done
run_hc 3-restart
grep -q "$HC_R RestartCount 0 -> 1 (restart loop?)" "$WORK/log-3-restart" || fail "restart not detected / not worded as expected"
[ "$(grep -cE "^PING /$PING_SECRET/fail" "$WORK/pinglog")" -eq 1 ] || fail "expected one /fail ping"
grep -qF "container $HC_R RestartCount 0 -> 1" "$WORK/pinglog" || fail "/fail body lacks the restart reason"
pass "RestartCount increase detected, /fail ping carries the container name and counts"

# --- 4. memory and disk thresholds (env overrides) --------------------------------
section "4. threshold breaches via env overrides"
MEM_MIN_MB=100000 run_hc 4-mem
grep -q 'MemAvailable.*MB <= 100000MB' "$WORK/log-4-mem" || fail "memory breach not detected"
tail -n 1 "$WORK/pinglog" | grep -qF "MemAvailable" || fail "/fail body lacks the memory reason"
pass "MemAvailable breach detected, /fail reason in the ping body"

DISK_MAX_PCT=0 run_hc 4-disk
grep -q 'disk / usage' "$WORK/log-4-disk" && grep -q '>= 0%' "$WORK/log-4-disk" || fail "disk breach not detected"
tail -n 1 "$WORK/pinglog" | grep -qF "disk / usage" || fail "/fail body lacks the disk reason"
pass "disk breach detected, /fail reason in the ping body"

# --- 5. unhealthy healthcheck while running --------------------------------------
section "5. running container with a failing healthcheck"
docker run -d --name "$HC_U" --label com.docker.compose.project="$PROJ" \
	--health-cmd 'exit 1' --health-interval 1s --health-retries 1 \
	busybox sleep 3600 >/dev/null
for i in $(seq 1 30); do
	[ "$(docker inspect -f '{{.State.Health.Status}}' "$HC_U")" = "unhealthy" ] &&
		[ "$(docker inspect -f '{{.State.Status}}' "$HC_U")" = "running" ] && break
	[ "$i" -lt 30 ] || fail "container $HC_U never became unhealthy while running"
	sleep 1
done
run_hc 5-unhealthy
grep -q "container $HC_U health=unhealthy" "$WORK/log-5-unhealthy" || fail "unhealthy container not detected"
tail -n 1 "$WORK/pinglog" | grep -qF "health=unhealthy" || fail "/fail body lacks the health reason"
pass "unhealthy (but running) container detected, /fail reason in the ping body"

# --- 6. stopped container ---------------------------------------------------------
section "6. stopped container"
docker stop "$HC_A" >/dev/null
run_hc 6-stopped
grep -q "container $HC_A is exited" "$WORK/log-6-stopped" || fail "stopped container not detected"
tail -n 1 "$WORK/pinglog" | grep -qF "$HC_A is exited" || fail "/fail body lacks the stopped-container reason"
pass "stopped container detected, /fail reason in the ping body"

# --- 7. backup FAILED marker ------------------------------------------------------
section "7. backup FAILED marker present"
# shellcheck disable=SC2174 # -m only needs to apply to the final dir
mkdir -m 700 -p "$WORK/backupstate"
printf '2026-01-01T00:00:00Z backup failed at step "upload" (exit 22)\n' >"$WORK/backupstate/FAILED"
run_hc 7-marker
grep -q 'backup FAILED marker present' "$WORK/log-7-marker" || fail "backup marker not detected"
tail -n 1 "$WORK/pinglog" | grep -qF "backup FAILED marker" || fail "/fail body lacks the backup reason"
rm -f "$WORK/backupstate/FAILED"
pass "backup FAILED marker detected, /fail reason in the ping body, marker removed"

# --- 8. all clear again ------------------------------------------------------------
section "8. back to healthy"
docker rm -f "$HC_R" "$HC_U" >/dev/null
docker start "$HC_A" >/dev/null
for i in $(seq 1 30); do
	[ "$(docker inspect -f '{{.State.Health.Status}}' "$HC_A")" = "healthy" ] && break
	[ "$i" -lt 30 ] || fail "container $HC_A did not get healthy again"
	sleep 1
done
run_hc 8-clear
grep -q 'hostcheck: ok:' "$WORK/log-8-clear" || fail "hosts did not recover to ok"
tail -n 1 "$WORK/pinglog" | grep -qE "^PING /$PING_SECRET ok: " || fail "recovery success ping missing"
pass "all clear: ok line and recovery success ping"
grep -q 'ping disabled' "$WORK/log-8-clear" && fail "ping file present but reported disabled"
# restart state must have been refreshed (a run that survived a restart of a
# still-living container must not re-alarm forever):
[ "$(wc -l <"$WORK/state/restart-counts")" -ge 1 ] || fail "restart-count state file not written"

# --- 9. secrets: ping URL in no log, no ps; xtrace refused ------------------------
section "9. no secrets in logs or ps; bash -x refused"
if grep -rF "$PING_SECRET" "$WORK"/log-* /dev/null 2>/dev/null | grep -qv '/dev/null'; then
	fail "ping URL or its path printed in a hostcheck log"
fi
: >"$WORK/ps.log"
(while true; do ps -eo args >>"$WORK/ps.log"; sleep 0.05; done) &
RIPMID=$!
bash "$HC" >/dev/null 2>&1
kill "$RIPMID" 2>/dev/null || true
wait "$RIPMID" 2>/dev/null || true
if grep -qF "$PING_SECRET" "$WORK/ps.log"; then
	fail "ping URL visible on a command line during the run"
fi
pass "no ping URL in any hostcheck log line or in ps during a run"
set +e
bash -x "$HC" >"$WORK/log-x" 2>&1
xrc=$?
set -e
tail -n 2 "$WORK/log-x" | grep -v '^\s*$' || true
[ "$xrc" -eq 2 ] && grep -q 'refusing to run with xtrace' "$WORK/log-x" || fail "bash -x not refused"
grep -qF "$PING_SECRET" "$WORK/log-x" && fail "xtrace printed the ping URL"
pass "bash -x refused (exit $xrc), no URL printed"
