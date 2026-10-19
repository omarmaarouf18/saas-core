#!/usr/bin/env bash
#
# infrastructure/deploy/monitor/hostcheck.sh — 5-minute host health check
# (OBS-MIN) for the single production VM. systemd:
# quickdelivery-monitor.service, run by quickdelivery-monitor.timer every
# 5 minutes. Install: infrastructure/deploy/monitor/install.sh. Runbook:
# docs/runbooks/MONITORING.md.
#
# What it checks; every failure is collected into one line, and the run pings
# a healthchecks.io-compatible dead-man URL (the bare URL when all checks
# pass, /fail with the reason as the body when one fails):
#   1. disk: usage of / below DISK_MAX_PCT (85% of ~8 GB)
#   2. memory: MemAvailable above MEM_MIN_MB (80 MB; only ~380 MB is free)
#   3. every container of the COMPOSE project is running, and every one of
#      them that has a Docker healthcheck reports "healthy" (all of them
#      have one except saas-caddy and saas-kyc-reviewer-console, which are
#      still required to be running)
#   4. no container is restarting in a loop: RestartCount is compared with
#      the previous run's values, kept under STATE_DIR
#   5. the last backup did not fail: /var/lib/quickdelivery-backup/FAILED
#      absent (the backup also pings its own dead-man check at each run and
#      failure, see docs/runbooks/BACKUP-RESTORE.md; this check also catches
#      a backup that never runs at all)
#
# Secrets: the ping URL is a secret. It lives in the root-only PING_FILE
# (first line) and reaches curl through a stdin config (-K -, like the SAS
# in backup.sh), never on a command line and never in a log — only the ping
# suffix is logged. A missing, empty or https-less ping file disables the
# feature with one log line; a failed ping is a WARN and never fails the
# check (best effort, capped at a few seconds by --connect-timeout /
# --max-time). The script always exits 0: it runs on a timer and an exit
# code would only add noise; the ping tells the owner how the host is.
# One short line always lands in the journal:
#   hostcheck: ok: disk 12%, mem 310MB, 9 containers, healthchecks ok, no restart loop, backup marker absent
#   hostcheck: FAIL: disk / usage 91% >= 85%; container saas-auth-service health=unhealthy
set -euo pipefail

# Refuse xtrace: it would print every command line, and arguments of the
# curl/docker calls could end up holding parts of the ping URL.
case $- in *x*)
	echo "hostcheck.sh: refusing to run with xtrace (set -x) enabled" >&2
	exit 2
	;;
esac

umask 077
export LC_ALL=C

COMPOSE_PROJECT="${COMPOSE_PROJECT:-saas-core-deploy}"
DISK_MAX_PCT="${DISK_MAX_PCT:-85}"
MEM_MIN_MB="${MEM_MIN_MB:-80}"
PING_FILE="${PING_FILE:-/etc/quickdelivery-monitor/ping}"
STATE_DIR="${STATE_DIR:-/var/lib/quickdelivery-monitor}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/var/lib/quickdelivery-backup}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-10}"

REASON=""
PING_URL=""

log() { printf 'hostcheck: %s\n' "$1"; }

fail_add() { # fail_add <one-line reason>; reasons are built only from
	# this script's own words, container- or backup-state text, never secrets
	REASON="${REASON}${REASON:+; }$1"
}

read_ping_url() { # read_ping_url: sets PING_URL, disabled branch logs one line
	[ -f "$PING_FILE" ] || {
		log "ping disabled ($PING_FILE does not exist; docs/runbooks/MONITORING.md)"
		return 0
	}
	PING_URL="$(head -n 1 "$PING_FILE" | tr -d '\r\n\t ')"
	[ -n "$PING_URL" ] || {
		log "ping disabled ($PING_FILE is empty)"
		return 0
	}
	case "$PING_URL" in */) PING_URL="${PING_URL%/}" ;; esac
	case "$PING_URL" in
	https://*) : ;;
	http://127.0.0.1:[0-9]*) : ;;
	*)
		log "ping disabled ($PING_FILE holds a URL this script will not use)"
		PING_URL=""
		;;
	esac
	return 0
}

ping_hc() { # ping_hc <suffix: ""|/fail> <body>; best effort, never fails
	[ -n "$PING_URL" ] || return 0
	# URL and body reach curl through a stdin config (-K -): nothing on a
	# command line (ps), the log only ever shows the suffix, never the URL.
	if ! printf 'url = "%s%s"\ndata-binary = "%s"\n' "$PING_URL" "$1" "$(printf '%s' "$2" | head -c 300)" |
		curl -K - --silent --max-time "$MAX_TIME" --connect-timeout "$CONNECT_TIMEOUT" \
			--request POST --output /dev/null --write-out '%{http_code}' >/dev/null 2>&1; then
		log "WARN: ping$1 failed (best effort; the check itself is unaffected)"
	fi
	return 0
}

# --- 1. disk -------------------------------------------------------------------
diskpct="$(df -P / | awk 'NR==2 { sub(/%$/, "", $5); print $5 }' 2>/dev/null || true)"
if [ -n "$diskpct" ] && [ "$diskpct" -ge 0 ] 2>/dev/null; then
	if [ "$diskpct" -ge "$DISK_MAX_PCT" ]; then
		fail_add "disk / usage $diskpct% >= $DISK_MAX_PCT%"
	fi
else
	fail_add "disk usage unknown (df failed)"
fi

# --- 2. memory -----------------------------------------------------------------
mem_mb="$(awk '$1 == "MemAvailable:" { print int($2 / 1024); exit }' /proc/meminfo 2>/dev/null || true)"
if [ -n "$mem_mb" ] && [ "$mem_mb" -ge 0 ] 2>/dev/null; then
	if [ "$mem_mb" -le "$MEM_MIN_MB" ]; then
		fail_add "MemAvailable ${mem_mb}MB <= ${MEM_MIN_MB}MB"
	fi
else
	fail_add "MemAvailable unknown (/proc/meminfo unreadable)"
fi

# --- 3+4. containers -----------------------------------------------------------
# One docker inspect over all containers; fields joined with '|', which no
# field value ever contains: <name>|<project>|<hc yes/no>|<health or "none">|
# <RestartCount>|<State.Status>. The health field is never empty, so the
# column count is stable even for containers without a healthcheck.
mapfile -t inspect_rows < <(
	docker ps -aq 2>/dev/null | xargs -r docker inspect \
		--format '{{.Name}}|{{index .Config.Labels "com.docker.compose.project"}}|{{if .Config.Healthcheck}}hc{{else}}no{{end}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.RestartCount}}|{{.State.Status}}' 2>/dev/null |
		awk -F'|' -v proj="$COMPOSE_PROJECT" '$2 == proj { sub(/^\//, "", $1); OFS=" "; print $1, $3, $4, $5, $6 }'
) || true
N_CONTAINERS=${#inspect_rows[@]}
if [ "$N_CONTAINERS" -eq 0 ]; then
	fail_add "no containers found for compose project $COMPOSE_PROJECT (docker unreachable or the stack is gone)"
else
	declare -A restart_now=()
	for row in "${inspect_rows[@]}"; do
		read -r name is_hc health restarts state_status <<<"$row"
		if [ "$state_status" != "running" ]; then
			fail_add "container $name is $state_status"
		elif [ "$is_hc" = "hc" ] && [ "$health" != "healthy" ]; then
			fail_add "container $name health=${health:-none}"
		fi
		restart_now["$name"]="$restarts"
	done
	mkdir -p "$STATE_DIR"
	prev_counts_file="$STATE_DIR/restart-counts"
	if [ -f "$prev_counts_file" ]; then
		while read -r name prev; do
			[ -n "$prev" ] || continue
			[ -n "${restart_now["$name"]+x}" ] || continue
			if [ "$prev" -lt "${restart_now[$name]}" ]; then
				fail_add "container $name RestartCount $prev -> ${restart_now[$name]} (restart loop?)"
			fi
		done <"$prev_counts_file"
	fi
	for name in "${!restart_now[@]}"; do
		printf '%s %s\n' "$name" "${restart_now[$name]}"
	done | sort >"$prev_counts_file.new"
	mv "$prev_counts_file.new" "$prev_counts_file"
fi

# --- 5. backup failure marker ---------------------------------------------------
backup_marker="$BACKUP_STATE_DIR/FAILED"
if [ -f "$backup_marker" ]; then
	fail_add "backup FAILED marker present: $(head -c 120 "$backup_marker" | tr -s ' \n' ' ')"
fi

# --- result: ping, then log the outcome (the log is neutral: ok or findings) ------
read_ping_url
if [ -z "$REASON" ]; then
	log "ok: disk ${diskpct:-?}%, mem ${mem_mb:-?}MB, $N_CONTAINERS containers of $COMPOSE_PROJECT, healthchecks ok, no restart loop, backup marker absent"
	ping_hc "" "ok: disk ${diskpct:-?}%, mem ${mem_mb:-?}MB free, $N_CONTAINERS containers healthy"
else
	log "FAIL: $REASON"
	ping_hc /fail "host not healthy: $REASON"
fi
exit 0
