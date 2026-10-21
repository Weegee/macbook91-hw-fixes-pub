#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Development helper for the maintainer's test machine, not packaged: checks the native backlight
# (intel_backlight) after `acpi_backlight=native`. Needs root.
#
#   tools/dev-backlight-check.sh ramp      every level 0..max: written value
#                                          reads back, actual_brightness is
#                                          monotone; ends at the starting value
#   tools/dev-backlight-check.sh zero S    brightness 0 for S seconds (default
#                                          10), then the starting value again
#
# A transient systemd timer restores the starting value even if this script
# is killed: it is armed before the first write and disarmed at the end.
set -uo pipefail
BL=/sys/class/backlight/intel_backlight
[ "$(id -u)" = 0 ] || { echo "needs root" >&2; exit 2; }
[ -d "$BL" ] || { echo "no intel_backlight; is acpi_backlight=native active?" >&2; exit 2; }
max=$(cat "$BL/max_brightness")
start=$(cat "$BL/brightness")
[ "$start" -gt 0 ] || start=$((max / 2))
mode=${1:-}
hold=${2:-10}

arm() {
	systemctl stop mb91-backlight-restore.timer mb91-backlight-restore.service 2>/dev/null
	systemd-run --quiet --unit=mb91-backlight-restore --on-active="$1" \
		/usr/bin/bash -c "echo $start > $BL/brightness"
}
disarm() { systemctl stop mb91-backlight-restore.timer 2>/dev/null; }
trap 'echo "$start" >"$BL/brightness"; disarm' EXIT

echo "intel_backlight max=$max start=$start bl_power=$(cat "$BL/bl_power") type=$(cat "$BL/type")"
case $mode in
ramp)
	arm 120
	prev=-1 bad=0
	for v in $(seq 0 "$max"); do
		echo "$v" >"$BL/brightness"
		r=$(cat "$BL/brightness"); a=$(cat "$BL/actual_brightness")
		[ "$r" = "$v" ] || { echo "level $v read back as $r"; bad=$((bad + 1)); }
		[ "$a" -ge "$prev" ] || { echo "actual_brightness fell from $prev to $a at $v"; bad=$((bad + 1)); }
		prev=$a
	done
	echo "ramp: $((max + 1)) levels, $bad problems, actual at max=$prev"
	[ "$bad" = 0 ] ;;
zero)
	arm $((hold + 15))
	echo 0 >"$BL/brightness"
	echo "brightness 0: actual=$(cat "$BL/actual_brightness") bl_power=$(cat "$BL/bl_power"); restoring in ${hold}s"
	sleep "$hold" ;;
*) echo "usage: dev-backlight-check.sh ramp | zero [SECONDS]" >&2; exit 2 ;;
esac
