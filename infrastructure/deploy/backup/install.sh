#!/usr/bin/env bash
#
# infrastructure/deploy/backup/install.sh — one-time install of the daily
# backup on the production VM (OPS-BACKUP). The OWNER runs it as root from a
# copy of this directory; runbook: docs/runbooks/BACKUP-RESTORE.md.
#
#   sudo ./install.sh             install or update, enable the timer and, when
#                                 the SAS file is filled in, run one backup now
#   sudo ./install.sh --set-sas   paste the container SAS URL (not echoed, not
#                                 in shell history) into the SAS file, then exit
#   sudo ./install.sh --set-ping  paste the healthchecks.io ping URL (not
#                                 echoed) into the ping file, then exit; see
#                                 docs/runbooks/MONITORING.md (OBS-MIN)
#
# Idempotent: re-running it updates the script, the key and the units and
# keeps the SAS file, the local backups and the state.
#
# Layout:
#   /usr/local/lib/quickdelivery-backup/backup.sh             0755
#   /usr/local/lib/quickdelivery-backup/backup-recipient.pub  0644 (public key)
#   /etc/quickdelivery-backup/                                0700
#   /etc/quickdelivery-backup/sas                             0600 (container SAS URL)
#   /etc/quickdelivery-backup/ping                            0600, optional (dead-man ping URL)
#   /etc/quickdelivery-backup/backup.env                      optional overrides
#   /var/backups/quickdelivery/                               0700 (last 3 runs)
#   /var/lib/quickdelivery-backup/                            0700 (FAILED, last-success)
#   /etc/systemd/system/quickdelivery-backup.{service,timer}  0644
set -euo pipefail
umask 077

SRC="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LIB=/usr/local/lib/quickdelivery-backup
CONF=/etc/quickdelivery-backup
SAS_FILE="$CONF/sas"
PING_FILE="$CONF/ping"
BACKUP_DIR=/var/backups/quickdelivery
STATE_DIR=/var/lib/quickdelivery-backup
UNIT_DIR=/etc/systemd/system

say() { printf '== %s\n' "$*"; }
die() {
	printf 'install.sh: ERROR: %s\n' "$*" >&2
	exit 1
}

[ "$(id -u)" -eq 0 ] || die "run as root: sudo $0 $*"

install -d -m 0700 -o root -g root "$CONF"

if [ "${1:-}" = "--set-sas" ]; then
	printf 'Paste the Blob SAS URL (https://<account>.blob.core.windows.net/<container>?sp=...), then Enter.\nInput is not shown.\n> '
	IFS= read -r -s sas
	printf '\n'
	sas="$(printf '%s' "$sas" | tr -d '\r\n\t ')"
	[[ "$sas" =~ ^https://[a-z0-9]{3,24}\.blob\.core\.windows\.net/[a-z0-9][a-z0-9-]{2,62}\?.+ ]] ||
		die "that does not look like a container SAS URL (https://<account>.blob.core.windows.net/<container>?<token>); nothing written"
	printf '%s\n' "$sas" >"$SAS_FILE.new"
	chown root:root "$SAS_FILE.new"
	chmod 600 "$SAS_FILE.new"
	mv "$SAS_FILE.new" "$SAS_FILE"
	unset sas
	say "SAS URL written to $SAS_FILE (mode 600). Now run: sudo $0"
	exit 0
fi

if [ "${1:-}" = "--set-ping" ]; then
	printf 'Paste the healthchecks.io ping URL for the BACKUP check (https://hc-ping.com/<uuid>), then Enter.\nInput is not shown.\n> '
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
[ $# -eq 0 ] || die "usage: $0 [--set-sas | --set-ping]"

say "1/6 checks"
grep -Eq '^age1[0-9a-z]{58}$' "$SRC/backup-recipient.pub" ||
	die "$SRC/backup-recipient.pub holds no age public key yet (placeholder): do runbook step 1 first"
for f in backup.sh quickdelivery-backup.service quickdelivery-backup.timer; do
	[ -f "$SRC/$f" ] || die "missing $SRC/$f: copy the whole infrastructure/deploy/backup directory"
done
command -v docker >/dev/null || die "docker not found"
systemd-analyze calendar '*-*-* 03:30:00 Africa/Cairo' >/dev/null 2>&1 ||
	die "this systemd cannot parse 'OnCalendar=... Africa/Cairo' (needs tzdata and systemd >= 235)"

say "2/6 tools (age, curl, flock)"
missing=()
command -v age >/dev/null || missing+=(age)
command -v curl >/dev/null || missing+=(curl)
command -v flock >/dev/null || missing+=(util-linux)
if [ "${#missing[@]}" -gt 0 ]; then
	command -v apt-get >/dev/null || die "missing ${missing[*]} and no apt-get: install them by hand"
	say "installing with apt-get: ${missing[*]}"
	apt-get update -qq
	DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}"
fi
say "age $(age --version)"

say "3/6 files under $LIB"
install -d -m 0755 -o root -g root "$LIB"
install -m 0755 -o root -g root "$SRC/backup.sh" "$LIB/backup.sh"
install -m 0644 -o root -g root "$SRC/backup-recipient.pub" "$LIB/backup-recipient.pub"

say "4/6 directories and the SAS file"
install -d -m 0700 -o root -g root "$BACKUP_DIR" "$STATE_DIR"
if [ ! -e "$SAS_FILE" ]; then
	install -m 0600 -o root -g root /dev/null "$SAS_FILE"
	say "created an empty $SAS_FILE (fill it with: sudo $0 --set-sas)"
fi
chown root:root "$SAS_FILE"
chmod 600 "$SAS_FILE"

say "5/6 systemd units"
install -m 0644 -o root -g root "$SRC/quickdelivery-backup.service" "$UNIT_DIR/quickdelivery-backup.service"
install -m 0644 -o root -g root "$SRC/quickdelivery-backup.timer" "$UNIT_DIR/quickdelivery-backup.timer"
systemctl daemon-reload
systemctl enable --now quickdelivery-backup.timer
systemctl list-timers --no-pager quickdelivery-backup.timer

say "6/6 first backup"
if [ ! -s "$SAS_FILE" ]; then
	say "SKIPPED: $SAS_FILE is empty. Run: sudo $0 --set-sas, then: sudo $0"
	exit 0
fi
if systemctl start quickdelivery-backup.service; then
	systemctl --no-pager status quickdelivery-backup.service || true
	say "first backup OK; daily runs are scheduled (systemctl list-timers quickdelivery-backup.timer)"
else
	systemctl --no-pager status quickdelivery-backup.service || true
	journalctl --no-pager -u quickdelivery-backup.service -n 30 || true
	die "first backup FAILED: see the log above and the runbook section 'When a backup fails'"
fi
