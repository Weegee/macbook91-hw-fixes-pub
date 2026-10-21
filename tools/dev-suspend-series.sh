#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Development helper for the maintainer's test machine, not packaged. Runs N suspend/resume cycles the
# way the desktop does it - `systemctl suspend`, i.e. logind, systemd-sleep and
# its hooks - with an RTC alarm as the only planned wake source, and checks the
# machine after every cycle. Stops at the first failed cycle; stops at once on
# a storage or filesystem error. Needs root.
#
#   tools/dev-suspend-series.sh MODE N [LOAD] [SLEEP] [PAUSE]
#     MODE   deep | s2idle      written to /sys/power/mem_sleep, restored at exit
#     LOAD   idle | wlan | audio | camera | all    kept running across the cycles
#     SLEEP  seconds until the RTC alarm (default 20), PAUSE between cycles (15)
#
# The run's own sleep inhibitor (who=macbook91-hw-fixes) blocks logind, so
# suspend is requested with --ignore-inhibitors - but only after checking that
# no other process holds a block-mode sleep inhibitor.
# Output: one line per cycle plus findings; TSV log in $LOGDIR (default: the invoking
# user's ~/.local/state/macbook91-hw-fixes/suspend). MACs masked. Run it with sudo: the
# invoking user (SUDO_USER) is the session whose desktop and audio the checks use.
set -uo pipefail
MODE=${1:-} N=${2:-} LOAD=${3:-idle} SLEEP=${4:-20} PAUSE=${5:-15}
OWN_INHIBITOR=macbook91-hw-fixes
IOFILE=/var/tmp/macbook91-suspend-io.bin

case $MODE in deep | s2idle) ;; *) echo "MODE must be deep or s2idle" >&2; exit 2 ;; esac
[[ $N =~ ^[0-9]+$ ]] && [ "$N" -gt 0 ] || { echo "N must be a positive number" >&2; exit 2; }
case $LOAD in idle | wlan | audio | camera | all) ;; *) echo "bad LOAD" >&2; exit 2 ;; esac
[ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 2; }
user=${SUDO_USER:-}
{ [ -n "$user" ] && [ "$user" != root ]; } || { echo "run it with sudo from the desktop user's session (SUDO_USER is empty or root)" >&2; exit 2; }
LOGDIR=${LOGDIR:-$(getent passwd "$user" | cut -d: -f6)/.local/state/macbook91-hw-fixes/suspend}

mask() { sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/MAC/g'; }
mkdir -p "$LOGDIR"
run=$(date +%Y%m%dT%H%M%S)-$MODE-$LOAD
TSV=$LOGDIR/$run.tsv
REPORT=$LOGDIR/$run.log
exec > >(tee -a "$REPORT") 2>&1
printf 'cycle\tmode\tload\tslept\tsecs\tearly\twake_irq\tio\twifi_s\taudio\tcamera\tkbd\tbacklight\tkwarn\tkerr\tresult\n' >"$TSV"

old_mem_sleep=$(sed -E 's/.*\[([a-z0-9]+)\].*/\1/' /sys/power/mem_sleep)
pids=()
cleanup() {
	for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
	echo "$old_mem_sleep" >/sys/power/mem_sleep
	rm -fv "$IOFILE"
	echo "mem_sleep restored to $old_mem_sleep"
}
trap cleanup EXIT
echo "$MODE" >/sys/power/mem_sleep

uid=$(id -u "$user")
as_user() { sudo -u "$user" XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus "$@"; }

gateway=$(ip route show default | awk '{print $3; exit}')
wifi_before=no
nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -qx 'wifi:connected' && wifi_before=yes
bl=$(ls -d /sys/class/backlight/* | head -n1)

start_loads() {
	if [ "$LOAD" = wlan ] || [ "$LOAD" = all ]; then
		[ -n "$gateway" ] || { echo "LOAD wlan: no default route" >&2; exit 2; }
		ping -q -i 0.2 "$gateway" >/dev/null 2>&1 &
		pids+=($!)
	fi
	if [ "$LOAD" = audio ] || [ "$LOAD" = all ]; then
		# Silence: an active stream through PipeWire without sound in the room.
		as_user aplay -q -D default -t raw -f S16_LE -r 48000 -c 2 /dev/zero >/dev/null 2>&1 &
		pids+=($!)
	fi
	if [ "$LOAD" = camera ] || [ "$LOAD" = all ]; then
		v4l2-ctl -d /dev/video0 --stream-mmap --stream-to=/dev/null >/dev/null 2>&1 &
		pids+=($!)
	fi
	sleep 3
}
loads_alive() {
	local p
	for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null || return 1; done
}

# Block-mode sleep inhibitors held by anyone but this run, from logind itself.
foreign_block() {
	busctl --json=short call org.freedesktop.login1 /org/freedesktop/login1 \
		org.freedesktop.login1.Manager ListInhibitors 2>/dev/null |
		jq -r --arg own "$OWN_INHIBITOR" '.data[0][] | select(.[3] == "block" and (.[0] | split(":") | index("sleep")) and .[1] != $own) | .[1]'
}

io_check() {
	local a b
	head -c 4M /dev/urandom >"$IOFILE.src" || return 1
	a=$(sha256sum <"$IOFILE.src")
	dd if="$IOFILE.src" of="$IOFILE" bs=1M oflag=direct conv=fsync status=none || return 1
	b=$(dd if="$IOFILE" bs=1M iflag=direct status=none | sha256sum)
	rm -f "$IOFILE.src"
	[ "$a" = "$b" ]
}

# Known, already analysed kernel messages that are not failures of a cycle.
# TSC ADJUST: Apple firmware writes TSC_ADJUST in S3; the kernel restores it (tsc_sync.c).
BENIGN='TSC ADJUST differs|applespi.*crc mismatch|Touch jump|clm_blob|txcap_blob|BCM.hcd|baudrate|UFW BLOCK|ACPI BIOS Error|ACPI Error|AE_ALREADY_EXISTS|AE_NOT_FOUND|wsec_key|unknown advertising'
FATAL='nvme.*(timeout|reset|error|down)|I/O error|blk_update_request|BTRFS (error|warning|critical)|EXT4-fs error|critical (medium|target) error|Buffer I/O'

btrfs_errs() { btrfs device stats / 2>/dev/null | awk '{s+=$2} END {print s+0}'; }
btrfs0=$(btrfs_errs)

start_loads
fail=0
echo "series $run: mode=$MODE n=$N load=$LOAD sleep=${SLEEP}s pause=${PAUSE}s wifi_before=$wifi_before kernel=$(uname -r)"
for i in $(seq 1 "$N"); do
	fb=$(foreign_block)
	if [ -n "$fb" ]; then
		echo "STOP: foreign block inhibitor(s): $fb"; fail=1; break
	fi
	loads_alive || { echo "STOP: a load process died before cycle $i"; fail=1; break; }
	bl0=$(cat "$bl/brightness")
	before=$(cat /sys/power/suspend_stats/success)
	fails0=$(cat /sys/power/suspend_stats/fail)
	t0=$(date +%s)
	rtcwake -m no -s "$SLEEP" >/dev/null 2>&1 || { echo "STOP: rtcwake could not set the alarm"; fail=1; break; }
	systemctl suspend --ignore-inhibitors || { echo "STOP: systemctl suspend failed"; fail=1; break; }
	slept=no
	for _ in $(seq 1 $((SLEEP + 180))); do
		[ "$(cat /sys/power/suspend_stats/success)" != "$before" ] && { slept=yes; break; }
		# fail counts since boot; only a new failure ends the wait.
		[ "$(cat /sys/power/suspend_stats/fail)" != "$fails0" ] && break
		sleep 1
	done
	sleep 2
	t1=$(date +%s)
	secs=$((t1 - t0))
	early=no; [ "$slept" = yes ] && [ "$secs" -lt $((SLEEP - 3)) ] && early=yes
	irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null || echo -)

	io=ok; io_check || io=FAIL
	w=-; if [ "$wifi_before" = yes ]; then
		w=-1
		for s in $(seq 1 60); do
			nmcli -t -f TYPE,STATE dev 2>/dev/null | grep -qx 'wifi:connected' && { w=$s; break; }
			sleep 1
		done
	fi
	audio=ok; grep -q 'HDA-Intel' /proc/asound/cards || audio=FAIL
	cam=ok; [ -e /dev/video0 ] || cam=FAIL
	kbd=ok; { [ -e /sys/bus/spi/drivers/applespi/spi-APP000D:00 ] && grep -q 'Apple SPI Keyboard' /proc/bus/input/devices; } || kbd=FAIL
	# The desktop may undim after resume, so the value may change; it must not be 0.
	bl1=$(cat "$bl/brightness" 2>/dev/null)
	blv="$bl0->$bl1"; { [ -n "$bl1" ] && { [ "$bl1" != 0 ] || [ "$bl0" = 0 ]; }; } || blv="FAIL($bl0->${bl1:-?})"

	msgs=$(journalctl -k --since "@$t0" --no-pager -q -p warning -o cat 2>/dev/null | mask)
	kwarn=$(grep -vE "$BENIGN" <<<"$msgs" | grep -c . || true)
	kerr=$(journalctl -k --since "@$t0" --no-pager -q -p err -o cat 2>/dev/null | grep -vE "$BENIGN" | grep -c . || true)
	fatal=$(grep -E "$FATAL" <<<"$msgs" | head -n 3)
	btrfs1=$(btrfs_errs)

	result=PASS
	{ [ "$slept" = yes ] && [ "$early" = no ] && [ "$io" = ok ] && [ "$audio" = ok ] && [ "$cam" = ok ] &&
		[ "$kbd" = ok ] && [[ $blv != FAIL* ]] && [ "$kerr" = 0 ] && { [ "$w" = - ] || [ "$w" -ge 0 ]; }; } || result=FAIL
	[ -n "$fatal" ] || [ "$btrfs1" != "$btrfs0" ] && result=FATAL

	printf '%d\t%s\t%s\t%s\t%d\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$i" "$MODE" "$LOAD" "$slept" "$secs" "$early" "$irq" \
		"$io" "$w" "$audio" "$cam" "$kbd" "$blv" "$kwarn" "$kerr" "$result" >>"$TSV"
	echo "cycle $i/$N $result slept=$slept secs=$secs early=$early irq=$irq io=$io wifi_s=$w audio=$audio cam=$cam kbd=$kbd backlight=$blv kwarn=$kwarn kerr=$kerr"
	if [ "$kwarn" != 0 ]; then grep -vE "$BENIGN" <<<"$msgs" | head -n 8 | sed 's/^/    /'; fi
	if [ "$result" = FATAL ]; then
		echo "STOP: storage/filesystem error - no further risky tests"; printf '    %s\n' "$fatal"; fail=2; break
	fi
	[ "$result" = PASS ] || { echo "STOP: cycle $i failed"; fail=1; break; }
	sleep "$PAUSE"
done
done_n=$(($(wc -l <"$TSV") - 1))
pass_n=$(grep -c '	PASS$' "$TSV")
echo "RESULT run=$run mode=$MODE load=$LOAD cycles=$done_n/$N pass=$pass_n status=$([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
