#!/usr/bin/env bash
#
# infrastructure/deploy/monitor/install.sh — one-time install of the 5-minute
# host health check on the production VM (OBS-MIN). The OWNER runs it as root
# from a copy of this directory; runbook: docs/runbooks/MONITORING.md.
#
#   sudo ./install.sh             install or update, enable the timer and run
#                                 one check now (a run without a ping file is
#                                 never a failure: feature off, one log line)
#   sudo ./install.sh --set-ping  paste the healthchecks.io ping URL of the
#                                 HOSTCHECK check (not echoed, not in shell
#                                 history) into the ping file, then exit
#
# Idempotent: re-running it updates the script and the units and keeps the
# ping file, the restart-count state and the local state.
#
# Layout:
#   /usr/local/lib/quickdelivery-monitor/hostcheck.sh        0755
#   /etc/quickdelivery-monitor/                              0700
#   /etc/quickdelivery-monitor/ping                          0600, optional (dead-man ping URL)
#   /etc/quickdelivery-monitor/hostcheck.env                 optional overrides
#   /var/lib/quickdelivery-monitor/                          0700 (restart-count state)
#   /etc/systemd/system/quickdelivery-monitor.{service,timer} 0644
set -euo pipefail
umask 077

SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB=/usr/local/lib/quickdelivery-monitor
CONF=/etc/quickdelivery-monitor
STATE=/var/lib/quickdelivery-monitor
PING_FILE="$CONF/ping"
UNIT_DIR=/etc/systemd/system

say() { printf '== %s\n' "$*"; }
die() {
	printf 'install.sh: ERROR: %s\n' "$*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0 $*"

install -d -m 0700 -o root -g root "$CONF"

if [ "${1:-}" = "--set-ping" ]; then
	printf 'Paste the healthchecks.io ping URL for the HOSTCHECK check (https://hc-ping.com/<uuid>), then Enter.\nInput is not shown.\n> '
	IFS= read -r -s ping
	printf '\n'
	ping="$(printf '%s' "$ping" | tr -d '\r\n\t ')"
	ping="${ping%/}"
	[[ "$ping" =~ ^https://[a-z0-9.-]+/[0-9a-zA-Z-]{16,}$ ]] ||
		die "that does not look like a healthchecks.io ping URL (https://hc-ping.com/<uuid>, no trailing slash); nothing written"
	printf '%s\n' "$ping" >"$PING_FILE.new"
	chown root:root "$PING_FILE.new"
	chmod 600 "$PING_FILE.new"
	mv "$PING_FILE.new" "$PING_FILE"
	unset ping
	say "ping URL written to $PING_FILE (mode 600). Now run: sudo $0"
	exit 0
fi
[ $# -eq 0 ] || die "usage: $0 [--set-ping]"

say "1/5 checks"
for f in hostcheck.sh quickdelivery-monitor.service quickdelivery-monitor.timer; do
	[ -f "$SRC/$f" ] || die "missing $SRC/$f: copy the whole infrastructure/deploy/monitor directory"
done
command -v docker >/dev/null || die "docker not found"
command -v curl >/dev/null || die "curl not found"
systemd-analyze calendar '*-*-* *:0/5' >/dev/null 2>&1 ||
	die "this systemd cannot parse 'OnCalendar=*-*-* *:0/5' (needs systemd >= 235)"

say "2/5 files under $LIB"
install -d -m 0755 -o root -g root "$LIB"
install -m 0755 -o root -g root "$SRC/hostcheck.sh" "$LIB/hostcheck.sh"

say "3/5 directories"
install -d -m 0700 -o root -g root "$STATE"
# The ping file is deliberately NOT created empty: an absent file means the
# dead-man ping is off, which must not look like a failing check.

say "4/5 systemd units"
install -m 0644 -o root -g root "$SRC/quickdelivery-monitor.service" "$UNIT_DIR/quickdelivery-monitor.service"
install -m 0644 -o root -g root "$SRC/quickdelivery-monitor.timer" "$UNIT_DIR/quickdelivery-monitor.timer"
systemctl daemon-reload
systemctl enable --now quickdelivery-monitor.timer
systemctl list-timers --no-pager quickdelivery-monitor.timer

say "5/5 first check"
if systemctl start quickdelivery-monitor.service; then
	# The check does not depend on ping being configured; show its one-line
	# outcome so the owner sees the baseline immediately.
	journalctl --no-pager -n 3 -o cat _SYSTEMD_UNIT=quickdelivery-monitor.service || true
	say "first check ran; every 5 minutes from now on. Alerts need the ping file: sudo $0 --set-ping"
else
	systemctl --no-pager status quickdelivery-monitor.service || true
	journalctl --no-pager -u quickdelivery-monitor.service -n 30 || true
	die "first health check FAILED to start: see the log above and docs/runbooks/MONITORING.md"
fi
