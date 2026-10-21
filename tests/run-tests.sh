#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2120 # ver is called with --bogus inside an eval'd check
# shellcheck disable=SC2034 # variables are read inside the eval'd checks
# Hermetic tests: no root, no hardware, no network. Both tools run against a
# fake system root (MACBOOK91_SYSROOT) and stub commands on PATH.
# Hardware checks are not here; they are recorded in docs/test-status.json.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
MIG=$REPO/src/macbook91-hw-migrate
VER=$REPO/src/macbook91-hw-verify
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'PASS %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
sha() { sha256sum "$1" | cut -d' ' -f1; }

# --- repository hygiene
cd "$REPO" || exit 1
check "shellcheck clean" 'shellcheck -S warning packaging/promote-release.sh src/macbook91-hw-migrate src/macbook91-hw-verify sleep/macbook91-lid-wake tests/run-tests.sh tools/*.sh kernel/applesmc/add-series.sh >/dev/null'
check "VERSION is YYYYMMDD.NN" 'grep -qxE "[0-9]{8}\.[0-9]{2}" VERSION'
check "PKGBUILD pkgver equals VERSION" '[ "$(sed -n "s/^pkgver=//p" packaging/arch/PKGBUILD)" = "$(cat VERSION)" ]'
check ".SRCINFO pkgver equals VERSION" 'grep -qx "	pkgver = $(cat VERSION)" packaging/arch/.SRCINFO'
check "no MAC address, serial or LUKS UUID tracked" '! git grep -nIE "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}|C02[A-Z0-9]{8}|luks(-|\.uuid=|\.name=)[0-9a-f]{8}-" -- . ":!tests/run-tests.sh" ":!private" >/dev/null'
check "no shipped file names the removed predecessor files or steps" '[ -z "$(git grep -nIE "ai_o[p]t|legacy-(d3cold|sleep)" -- src sleep udev kernel Makefile README.md docs/FINDINGS.md packaging/arch)" ]'
check "no local-only caches tracked" '[ -z "$(git ls-files | grep -E "^(\\.conte[x]t|gra[f]t/\\.graph)(/|\$)")" ]'

# --- licenses: SPDX lines, PKGBUILD license, texts, GPLv2 for what builds the modules
spdx=$(git grep -h -o "SPDX-License-Identifier: [A-Za-z0-9.+-]*" -- src sleep udev kernel Makefile | sed "s/.*: //" | sort -u)
lic=$(sed -n 's/^license=(\(.*\))$/\1/p' packaging/arch/PKGBUILD | tr -d "'" | tr ' ' '\n' | sort -u)
check "license: every packaged source names its license (SPDX line)" '[ -z "$(git grep -L SPDX-License-Identifier -- src sleep udev kernel Makefile ":!*.patch")" ]'
check "license: PKGBUILD and .SRCINFO list exactly the packaged SPDX IDs" '[ -n "$spdx" ] && [ "$spdx" = "$lic" ] && [ "$(sed -n "s/^\tlicense = //p" packaging/arch/.SRCINFO | sort -u)" = "$lic" ]'
check "license: GPL-3.0 in LICENSE and LICENSES/ (identical), every SPDX ID has a text in LICENSES/ and the tarball" 'grep -q "^Version 3, 29 June 2007" LICENSE && cmp -s LICENSE LICENSES/GPL-3.0-or-later.txt && (for id in $spdx; do { [ -s "LICENSES/$id.txt" ] && grep -qF "\"LICENSES/$id.txt\"" packaging/mkdist.py; } || exit 1; done)'
check "license: module sources and build files GPLv2-compatible, pwm_bl.c credited" '[ "$(git grep -l "SPDX-License-Identifier: GPL-3" -- kernel)" = "$(printf "%s\n" kernel/applesmc/UPSTREAM.lock kernel/applesmc/add-series.sh)" ] && head -1 kernel/macbook91_backlight.c | grep -qx "// SPDX-License-Identifier: GPL-2.0-only" && grep -q "follows cie1931() in drivers/video/backlight/pwm_bl.c" kernel/macbook91_backlight.c'

# --- applesmc replacement: pinned upstream copies, one patch for every series
AS=$REPO/kernel/applesmc
check "applesmc: UPSTREAM.lock matches the upstream copies" '(cd "$AS" && grep -v "^#" UPSTREAM.lock | awk "{print \$3\"  \"\$4}" | sha256sum --quiet -c)'
check "applesmc: every upstream series is in UPSTREAM.lock and dkms.conf" '(for d in "$AS"/upstream/*/; do s=$(basename "$d"); grep -q "^$s " "$AS/UPSTREAM.lock" && grep -q "${s//./\\\\.}" "$AS/dkms.conf" || exit 1; done)'
check "applesmc: patch applies with fuzz 0 to every series" '(for f in "$AS"/upstream/*/applesmc.c; do patch -s --dry-run --fuzz=0 -o /dev/null "$f" "$AS"/0001-applesmc-charge-limit-through-BCLM.patch || exit 1; done)'
# add-series.sh against a copy of kernel/applesmc, with a local source instead of the network.
mkdir -p "$T/asx" && cp -r "$AS"/add-series.sh "$AS"/0001-applesmc-charge-limit-through-BCLM.patch "$AS"/UPSTREAM.lock "$AS"/dkms.conf "$AS"/upstream "$T/asx/"
MACBOOK91_APPLESMC_SRC="$AS/upstream/7.2/applesmc.c" "$T/asx/add-series.sh" v9.9.1 >/dev/null 2>&1; rc=$?
check "add-series: pins a new series in UPSTREAM.lock and dkms.conf" '[ $rc = 0 ] && (cd "$T/asx" && grep -v "^#" UPSTREAM.lock | awk "{print \$3\"  \"\$4}" | sha256sum --quiet -c) && grep -q "^9\.9 v9\.9\.1 " "$T/asx/UPSTREAM.lock" && grep -qxF "BUILD_EXCLUSIVE_KERNEL=\"^(6\\.18|7\\.2|9\\.9)\\.\"" "$T/asx/dkms.conf"'
check "add-series: refuses a series that is already pinned" '! MACBOOK91_APPLESMC_SRC="$AS/upstream/7.2/applesmc.c" "$T/asx/add-series.sh" v7.2.10 >/dev/null 2>&1'

# --- fake MacBook9,1 system
mkroot() {
	R=$T/root$1
	rm -rf "$R"
	mkdir -p "$R"/sys/class/dmi/id "$R"/etc/udev/rules.d "$R"/usr/lib/systemd/system-sleep \
		"$R"/etc/default "$R"/proc/acpi
	echo "Apple Inc." >"$R"/sys/class/dmi/id/sys_vendor
	echo "MacBook9,1" >"$R"/sys/class/dmi/id/product_name
	printf 'ESP_PATH="/boot"\nKERNEL_CMDLINE[default]+="quiet rw cpuidle.governor=teo pcie_aspm=force"\nBOOT_ORDER="*, *lts"\n' >"$R"/etc/default/limine
	printf 'LID0\t  S4\t*enabled   platform:PNP0C0D:00\n' >"$R"/proc/acpi/wakeup
	printf '/dev/mapper/luks-test / btrfs subvol=/@,noatime 0 0\n/dev/mapper/luks-test /home btrfs subvol=/@home 0 0\n' >"$R"/etc/fstab
	printf 'HOOKS=(base systemd autodetect microcode kms modconf block keyboard sd-vconsole sd-encrypt filesystems)\n' >"$R"/etc/mkinitcpio.conf
	printf 'MemTotal:        7980000 kB\n' >"$R"/proc/meminfo
	mkdir -p "$R"/usr/lib/udev/rules.d "$R"/sys/bus/pci/devices/0000:01:00.0
	cp "$REPO"/udev/60-macbook91-nvme-d3cold.rules "$R"/usr/lib/udev/rules.d/
	install -m755 "$REPO"/sleep/macbook91-lid-wake "$R"/usr/lib/systemd/system-sleep/
	echo 0x106b >"$R"/sys/bus/pci/devices/0000:01:00.0/vendor
	echo 0x2003 >"$R"/sys/bus/pci/devices/0000:01:00.0/device
	echo 1 >"$R"/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed
}
mig() { MACBOOK91_SYSROOT=$R MACBOOK91_REGEN="$T/regen" "$MIG" "$@"; }
printf '#!/usr/bin/bash\necho regen >>"%s/regen.log"\n' "$T" >"$T/regen"; chmod +x "$T/regen"

mkroot 1
st=$(mig status)
check "status: the default step is pending on a fresh system" '[ "$(grep -c " pending " <<<"$st")" = 1 ] && grep -q "^backlight-native *pending" <<<"$st"'
check "status: lists exactly the default step and the two optional ones" '[ "$(awk "{print \$1}" <<<"$st" | paste -sd" ")" = "backlight-native keyboard-iso hibernate" ]'
check "status: hibernate is optional" 'grep -q "^hibernate *optional" <<<"$st"'
before_limine=$(sha "$R/etc/default/limine")
check "plan lists one step and changes nothing" '[ "$(mig plan | grep -c "^would apply")" = 1 ] && [ "$(sha "$R/etc/default/limine")" = "$before_limine" ]'
out=$(mig apply 2>&1); rc=$?
check "apply exits 0" '[ $rc = 0 ]'
check "apply: cmdline gains acpi_backlight=native once, rest unchanged" 'grep -qx "KERNEL_CMDLINE\[default\]+=\"quiet rw cpuidle.governor=teo pcie_aspm=force acpi_backlight=native\"" "$R/etc/default/limine" && [ "$(grep -c acpi_backlight "$R/etc/default/limine")" = 1 ] && grep -qx "BOOT_ORDER=\"\*, \*lts\"" "$R/etc/default/limine"'
check "apply: boot entries regenerated once" '[ "$(wc -l <"$T/regen.log")" = 1 ]'
check "apply: verbose file operations" 'grep -q " -> " <<<"$out"'
check "status after apply: the default step is applied" '[ "$(mig status | grep -c " applied ")" = 1 ]'
check "apply without names leaves hibernate alone" '! grep -q swap "$R/etc/fstab" && [ ! -e "$R/var/lib/macbook91-hw-fixes/run.log" ]'
before_fstab=$(sha "$R/etc/fstab")
limine_after_backlight=$(sha "$R/etc/default/limine")
mig apply hibernate >/dev/null 2>&1; rc=$?
check "hibernate: apply exits 0" '[ $rc = 0 ]'
check "hibernate: fstab gains marker, subvolume mount and low-priority swap" '[ "$(grep -c . "$R/etc/fstab")" = 5 ] && grep -qx "/dev/mapper/luks-test /swap btrfs subvol=/@swap,defaults,noatime 0 0" "$R/etc/fstab" && grep -qx "/swap/swapfile none swap defaults,pri=-2 0 0" "$R/etc/fstab"'
check "hibernate: cmdline gains resume and offset after the existing parameters" 'grep -qx "KERNEL_CMDLINE\[default\]+=\"quiet rw cpuidle.governor=teo pcie_aspm=force acpi_backlight=native resume=/dev/mapper/luks-test resume_offset=533760\"" "$R/etc/default/limine"'
check "hibernate: swap file sized to RAM, created on @swap, activated" 'grep -q "^btrfs subvolume create .*/@swap$" "$R/var/lib/macbook91-hw-fixes/run.log" && grep -qx "btrfs filesystem mkswapfile --size 8g /swap/swapfile" "$R/var/lib/macbook91-hw-fixes/run.log" && grep -qx "swapon /swap/swapfile" "$R/var/lib/macbook91-hw-fixes/run.log"'
check "hibernate: status applied, second apply is a no-op" 'mig status | grep -q "^hibernate *applied" && [ -z "$(mig apply hibernate 2>&1 | grep "^apply")" ]'
mig rollback hibernate >/dev/null 2>&1; rc=$?
check "hibernate: rollback restores fstab and cmdline byte-identical" '[ $rc = 0 ] && [ "$(sha "$R/etc/fstab")" = "$before_fstab" ] && [ "$(sha "$R/etc/default/limine")" = "$limine_after_backlight" ] && [ ! -e "$R/swap" ]'
check "hibernate: rollback switches swap off and deletes the subvolume" 'grep -qx "swapoff /swap/swapfile" "$R/var/lib/macbook91-hw-fixes/run.log" && grep -q "^btrfs subvolume delete .*/@swap$" "$R/var/lib/macbook91-hw-fixes/run.log"'
mig apply hibernate >/dev/null 2>&1
nregen=$(wc -l <"$T/regen.log")
out=$(mig apply 2>&1)
check "second apply changes nothing" '[ -z "$(grep -E "^apply " <<<"$out")" ] && [ "$(wc -l <"$T/regen.log")" = "$nregen" ]'
mig rollback >/dev/null 2>&1; rc=$?
check "rollback exits 0" '[ $rc = 0 ]'
check "rollback of everything also undoes hibernate" '! grep -q swap "$R/etc/fstab" && ! grep -q resume= "$R/etc/default/limine"'
check "rollback restores the command line byte-identical" '[ "$(sha "$R/etc/default/limine")" = "$before_limine" ]'
check "rollback regenerates boot entries" '[ "$(wc -l <"$T/regen.log")" = 6 ]'
check "status after rollback: pending again" '[ "$(mig status | grep -c " pending ")" = 1 ]'

# User edits after apply survive rollback.
mkroot 2; : >"$T/regen.log"
mig apply backlight-native keyboard-iso >/dev/null 2>&1
sed -i 's/BOOT_ORDER=.*/BOOT_ORDER="*lts, *"/' "$R/etc/default/limine"
mig rollback backlight-native >/dev/null 2>&1
check "rollback after a user edit removes only our parameter" '! grep -q acpi_backlight "$R/etc/default/limine" && grep -qx "BOOT_ORDER=\"\*lts, \*\"" "$R/etc/default/limine" && grep -q "pcie_aspm=force\"" "$R/etc/default/limine"'
check "partial rollback leaves other steps applied" '[ "$(mig status | grep -c " applied ")" = 1 ] && mig status | grep -q "^keyboard-iso *applied"'

# Unknown content is left alone.
mkroot 3
sed -i 's/pcie_aspm=force/pcie_aspm=force acpi_backlight=video/' "$R/etc/default/limine"
mig apply >/dev/null 2>&1
check "a different acpi_backlight= is foreign and kept" 'grep -q "acpi_backlight=video\"" "$R/etc/default/limine" && ! grep -q native "$R/etc/default/limine" && mig status | grep -q "^backlight-native *foreign"'
mkroot 4
sed -i 's/pcie_aspm=force"/pcie_aspm=force acpi_backlight=native"/' "$R/etc/default/limine"
check "parameter already present: done, no change" 'mig status | grep -q "^backlight-native *done" && ! mig plan | grep -q backlight'
mkroot 5
printf 'KERNEL_CMDLINE[default]+="a"\nKERNEL_CMDLINE[default]+="b"\n' >"$R/etc/default/limine"
check "two default cmdline lines: foreign" 'mig status | grep -q "^backlight-native *foreign"'
mkroot 5b
echo "/swapfile none swap defaults 0 0" >>"$R/etc/fstab"
check "existing swap in fstab: hibernate foreign, nothing done" 'mig status | grep -q "^hibernate *foreign" && mig apply hibernate | grep -q "^skip hibernate"'
mkroot 5c
sed -i "s/ btrfs / ext4 /" "$R/etc/fstab"
check "non-btrfs root: hibernate unsupported" 'mig status | grep -q "^hibernate *unsupported"'
mkroot 5d
sed -i 's/ systemd / udev /' "$R/etc/mkinitcpio.conf"
check "initramfs without resume support: hibernate unsupported" 'mig status | grep -q "^hibernate *unsupported"'

# Failing regeneration restores the file.
mkroot 6
before=$(sha "$R/etc/default/limine")
printf '#!/usr/bin/bash\nexit 1\n' >"$T/regen-fail"; chmod +x "$T/regen-fail"
MACBOOK91_SYSROOT=$R MACBOOK91_REGEN="$T/regen-fail" "$MIG" apply >/dev/null 2>&1; rc=$?
check "failed regeneration: exit 1, cmdline restored, step not recorded" '[ $rc = 1 ] && [ "$(sha "$R/etc/default/limine")" = "$before" ] && mig status | grep -q "^backlight-native *pending"'
# A failing regeneration in the hibernate step restores the command line; rollback cleans up.
mkroot 6h
before_fstab=$(sha "$R/etc/fstab"); before=$(sha "$R/etc/default/limine")
MACBOOK91_SYSROOT=$R MACBOOK91_REGEN="$T/regen-fail" "$MIG" apply hibernate >/dev/null 2>&1; rc=$?
check "hibernate: failed regeneration restores the cmdline, step is partial" '[ $rc = 1 ] && [ "$(sha "$R/etc/default/limine")" = "$before" ] && mig status | grep -q "^hibernate *partial"'
check "hibernate: apply on a partial step refuses with a hint" 'out=$(mig apply hibernate 2>&1); [ $? = 1 ] && grep -q "rollback hibernate" <<<"$out"'
mig rollback hibernate >/dev/null 2>&1; rc=$?
check "hibernate: rollback after a failed apply restores fstab and cmdline" '[ $rc = 0 ] && [ "$(sha "$R/etc/fstab")" = "$before_fstab" ] && [ "$(sha "$R/etc/default/limine")" = "$before" ] && [ ! -e "$R/swap" ]'

# Wrong machine.
mkroot 7
echo "MacBook10,1" >"$R/sys/class/dmi/id/product_name"
mig apply >/dev/null 2>&1; rc=$?
check "other model: exit 3, nothing changed" '[ $rc = 3 ] && ! grep -q acpi_backlight "$R/etc/default/limine" && [ ! -e "$R/var/lib/macbook91-hw-fixes/applied" ]'
mkroot 9
mkdir -p "$R/var/lib/macbook91-hw-fixes"
exec 7>"$R/var/lib/macbook91-hw-fixes/lock"; flock -n 7
mig apply >/dev/null 2>&1; rc=$?
exec 7>&-
check "a second concurrent run is refused" '[ $rc = 1 ] && ! grep -q acpi_backlight "$R/etc/default/limine"'
mkroot 10
mig apply backlight-native >/dev/null 2>&1; mig rollback backlight-native >/dev/null 2>&1; sleep 1; mig apply backlight-native >/dev/null 2>&1
check "a second apply keeps the first backup" '[ "$(ls "$R/var/lib/macbook91-hw-fixes/backup/backlight-native" | wc -l)" = 2 ]'

# The packaged lid hook, against a fake /proc (a write there shows as "LID0").
HOOK=$REPO/sleep/macbook91-lid-wake
hook() { MACBOOK91_SYSROOT=$R "$HOOK" "$@"; }
lidroot() { # lidroot open|closed enabled|disabled
	mkroot lid
	mkdir -p "$R/proc/acpi/button/lid/LID0"
	echo "state:      $1" >"$R/proc/acpi/button/lid/LID0/state"
	printf 'LID0\t  S4\t*%s   platform:PNP0C0D:00\n' "$2" >"$R/proc/acpi/wakeup"
}
lidroot open enabled; hook pre suspend
check "lid hook: open lid switches LID0 wake off before suspend" '[ "$(cat "$R/proc/acpi/wakeup")" = LID0 ] && grep -q "lid open, LID0 wake off" "$R/lid-wake.log"'
lidroot closed enabled; hook pre suspend
check "lid hook: closed lid keeps LID0 wake on" 'grep -q "\*enabled" "$R/proc/acpi/wakeup"'
lidroot open disabled; hook post suspend
check "lid hook: post switches LID0 wake on again" '[ "$(cat "$R/proc/acpi/wakeup")" = LID0 ]'
lidroot open enabled; echo MacBook10,1 >"$R/sys/class/dmi/id/product_name"; hook pre suspend
check "lid hook: other model, nothing changed" 'grep -q "\*enabled" "$R/proc/acpi/wakeup"'

# Optional ISO keyboard layout.
mkroot 12; : >"$T/regen.log"
mkdir -p "$R/sys/module/applespi/parameters"; echo N >"$R/sys/module/applespi/parameters/iso_layout"
check "keyboard-iso: optional, not part of apply without names" 'mig status | grep -q "^keyboard-iso *optional" && mig apply >/dev/null 2>&1 && [ ! -e "$R/etc/modprobe.d/macbook91-applespi.conf" ]'
n0=$(wc -l <"$T/regen.log")
mig apply keyboard-iso >/dev/null 2>&1; rc=$?
check "keyboard-iso: apply writes the option, sets it live, rebuilds the initramfs" '[ $rc = 0 ] && grep -qx "options applespi iso_layout=1" "$R/etc/modprobe.d/macbook91-applespi.conf" && [ "$(cat "$R/sys/module/applespi/parameters/iso_layout")" = Y ] && [ "$(wc -l <"$T/regen.log")" = $((n0 + 1)) ] && mig status | grep -q "^keyboard-iso *applied"'
mig rollback keyboard-iso >/dev/null 2>&1; rc=$?
check "keyboard-iso: rollback removes the option and switches it off live" '[ $rc = 0 ] && [ ! -e "$R/etc/modprobe.d/macbook91-applespi.conf" ] && [ "$(cat "$R/sys/module/applespi/parameters/iso_layout")" = N ] && mig status | grep -q "^keyboard-iso *optional"'
mkroot 13
mkdir -p "$R/etc/modprobe.d"; echo "options applespi iso_layout=1" >"$R/etc/modprobe.d/applespi.conf"
check "keyboard-iso: a user file with iso_layout=1 counts as done" 'mig status | grep -q "^keyboard-iso *done" && mig apply keyboard-iso >/dev/null 2>&1 && [ ! -e "$R/etc/modprobe.d/macbook91-applespi.conf" ]'
echo "options applespi iso_layout=0 fnmode=2" >"$R/etc/modprobe.d/applespi.conf"
check "keyboard-iso: iso_layout=0 set elsewhere is foreign" 'mig status | grep -q "^keyboard-iso *foreign"'
check "usage error exits 2" 'mig frobnicate >/dev/null 2>&1; [ $? = 2 ]'
check "rollback of an unknown step exits 2" 'mkroot 8; mig rollback nosuch >/dev/null 2>&1; [ $? = 2 ]'

# --- verify against a fake system
mkdir -p "$T/bin"
for c in pacman dkms journalctl; do printf '#!/usr/bin/bash\n' >"$T/bin/$c"; chmod +x "$T/bin/$c"; done
cat >"$T/bin/pacman" <<'EOF'
#!/usr/bin/bash
[ "$1" = -Q ] && case $2 in macbook91-hw-fixes) echo "$2 20261013.01-1" ;; macbook91-*) [ -z "${NO_DRIVERS-}" ] && echo "$2 20261013.01-1" || exit 1 ;; *) exit 1 ;; esac
EOF
printf '#!/usr/bin/bash\nfor m in macbook91-cs4208 macbook91-facetimehd macbook91-wireless macbook91-backlight ${DKMS_EXTRA-macbook91-applesmc}; do echo "$m/1, $3, x86_64: installed"; done\n' >"$T/bin/dkms"
vroot() {
	mkroot v
	mkdir -p "$R"/sys/class/backlight/"$1" "$R"/sys/power/suspend_stats "$R"/sys/bus/spi/drivers/applespi/spi-APP000D:00 \
		"$R/sys/class/leds/spi::kbd_backlight" "$R"/sys/bus/iio/devices/iio:device0 "$R"/sys/module/applespi/parameters
	echo "$2" >"$R/sys/class/backlight/$1/max_brightness"
	if [ "$1" = intel_backlight ]; then
		mkdir -p "$R/sys/class/backlight/macbook91_backlight"
		echo platform >"$R/sys/class/backlight/macbook91_backlight/type"
		echo 1000 >"$R/sys/class/backlight/macbook91_backlight/max_brightness"
	fi
	echo 255 >"$R/sys/class/leds/spi::kbd_backlight/max_brightness"
	echo acpi-als >"$R"/sys/bus/iio/devices/iio:device0/name
	echo "s2idle [deep]" >"$R"/sys/power/mem_sleep
	echo 0 >"$R"/sys/power/suspend_stats/fail
	printf 'LID0\t  S4\t*enabled   platform:PNP0C0D:00\nSPIT\t  S3\t*enabled   spi:spi-APP000D:00\n' >"$R"/proc/acpi/wakeup
	ser=$(uname -r | sed -nE 's/^([0-9]+\.[0-9]+)\..*/\1/p')
	mkdir -p "$R/usr/src/macbook91-applesmc-1/$ser"; : >"$R/usr/src/macbook91-applesmc-1/$ser/applesmc.c"
	echo "quiet ${3:-}" >"$R"/proc/cmdline
}
ver() { PATH=$T/bin:$PATH MACBOOK91_SYSROOT=$R MACBOOK91_MIGRATE="$T/mig" "$VER" "$@"; }
printf '#!/usr/bin/bash\nMACBOOK91_SYSROOT=%s MACBOOK91_REGEN=true %s "$@"\n' "$T/rootv" "$MIG" >"$T/mig"; chmod +x "$T/mig"

vroot intel_backlight 1388 acpi_backlight=native
MACBOOK91_SYSROOT=$R MACBOOK91_REGEN=true "$MIG" apply >/dev/null 2>&1
# What the packaged udev rule does at boot.
echo 0 >"$R/sys/bus/pci/devices/0000:01:00.0/d3cold_allowed"
out=$(ver); rc=$?
check "verify: native backlight passes" 'grep -q "^PASS backlight: native intel_backlight, 1389 levels" <<<"$out"'
check "verify: perceptual backlight passes" 'grep -q "^PASS backlight: macbook91_backlight drives it in 1001 perceptual" <<<"$out"'
check "verify: dkms module macbook91-backlight checked" 'grep -q "^PASS dkms: macbook91-backlight installed" <<<"$out"'
check "verify: installed driver packages are checked" '[ "$(grep -c "^PASS package: macbook91-" <<<"$out")" = 4 ] && grep -q "^PASS dkms: macbook91-cs4208 installed" <<<"$out"'
check "verify: missing driver packages are optional, not a FAIL" '(o=$(NO_DRIVERS=1 ver); grep -q "^INFO package: macbook91-cs4208-dkms not installed (optional" <<<"$o" && ! grep -qE "^FAIL (package|dkms): macbook91-(cs4208|facetimehd|wireless)" <<<"$o" && ! grep -q "^PASS dkms: macbook91-wireless" <<<"$o")'
rm -r "$R/sys/class/backlight/macbook91_backlight"
check "verify: missing perceptual backlight fails" 'ver | grep -q "^FAIL backlight: macbook91_backlight missing"'
check "verify: missing NVMe is a FAIL and exit 1" 'grep -q "^FAIL nvme" <<<"$out" && [ $rc = 1 ]'
check "verify: packaged lid hook passes" 'grep -q "^PASS sleep: hook macbook91-lid-wake" <<<"$out"'
check "verify: d3cold_allowed=0 passes" 'grep -q "^PASS nvme: d3cold_allowed=0" <<<"$out"'
check "verify: migration applied passes" '[ "$(grep -c "^PASS migration" <<<"$out")" = 1 ]'
check "verify: dkms module macbook91-applesmc checked" 'grep -q "^PASS dkms: macbook91-applesmc installed" <<<"$out"'
check "verify: missing charge limit warns" 'grep -q "^WARN charge limit: BAT0 has no charge_control_end_threshold" <<<"$out"'
mkdir -p "$R/sys/class/power_supply/BAT0"; echo 80 >"$R/sys/class/power_supply/BAT0/charge_control_end_threshold"
check "verify: charge limit passes" 'ver | grep -q "^PASS charge limit: BAT0 charge_control_end_threshold 80 %"'
check "verify: missing macbook91-applesmc on a kernel with a source fails" 'DKMS_EXTRA= ver | grep -q "^FAIL dkms: macbook91-applesmc not installed"'
rm -r "$R/usr/src/macbook91-applesmc-1"
check "verify: macbook91-applesmc without a source for the kernel warns" 'DKMS_EXTRA= ver | grep -q "^WARN dkms: macbook91-applesmc has no source for Linux"'
rm -f "$R/sys/class/power_supply/BAT0/charge_control_end_threshold"
check "verify: charge limit without a source names the kernel" 'ver | grep -q "^WARN charge limit: not available on Linux"'
vroot acpi_video0 90
out=$(ver)
check "verify: acpi_video0 without parameter warns" 'grep -q "^WARN backlight: acpi_video0 reaches only 90 %" <<<"$out"'
check "verify: d3cold_allowed=1 fails" 'grep -q "^FAIL nvme: d3cold_allowed=1" <<<"$out"'
vroot acpi_video0 90 acpi_backlight=native
out=$(ver)
check "verify: parameter set but acpi_video0 in use fails" 'grep -q "^FAIL backlight: acpi_backlight=native is on the command line" <<<"$out"'
vroot intel_backlight 1388
echo N >"$R/sys/module/applespi/parameters/iso_layout"; echo "KEYMAP=de-latin1" >"$R/etc/vconsole.conf"
out=$(ver)
check "verify: German keymap without iso_layout warns" 'grep -q "^WARN keyboard: keymap .de-latin1. suggests an ISO keyboard" <<<"$out"'
echo "KEYMAP=us" >"$R/etc/vconsole.conf"
check "verify: US keymap without iso_layout does not warn" '! ver | grep -q "^WARN keyboard"'
sed -i 's/SPIT\t  S3\t\*enabled/SPIT\t  S3\t*disabled/' "$R/proc/acpi/wakeup"
check "verify: SPIT disabled is only INFO" 'o=$(ver); grep -q "^INFO wakeup: SPIT disabled" <<<"$o" && ! grep -q "^FAIL wakeup: SPIT" <<<"$o"'
sed -i 's/LID0\t  S4\t\*enabled/LID0\t  S4\t*disabled/' "$R/proc/acpi/wakeup"
out=$(ver)
check "verify: LID0 disabled fails" 'grep -q "^FAIL wakeup: LID0" <<<"$out"'
echo "MacBookPro12,1" >"$R/sys/class/dmi/id/product_name"
ver >/dev/null; rc=$?
check "verify: other model exits 3" '[ $rc = 3 ]'
check "verify: usage error exits 2" 'ver --bogus >/dev/null 2>&1; [ $? = 2 ]'

# --- kernel module builds (only where the running kernel's headers are installed)
KB=/lib/modules/$(uname -r)/build
if [ -r "$KB/Module.symvers" ] && [ -z "${SKIP_KBUILD:-}" ]; then
	cp "$REPO"/kernel/macbook91_backlight.c "$REPO"/kernel/Makefile "$T/"
	check "kernel module builds without warnings" 'out=$(make -C "$T" KDIR="$KB" PKGVER=test 2>&1) && [ -f "$T/macbook91_backlight.ko" ] && ! grep -qi warning <<<"$out"'
	mkdir -p "$T/as" && cp -r "$AS"/Makefile "$AS"/0001-applesmc-charge-limit-through-BCLM.patch "$AS"/upstream "$T/as/"
	check "applesmc builds without warnings for the running kernel" 'out=$(make -C "$T/as" sources 2>&1 && make -C "$T/as" KDIR="$KB" PKGVER=test 2>&1) && [ -f "$T/as/build/applesmc.ko" ] && ! grep -qi warning <<<"$out" && modinfo -F macbook91 "$T/as/build/applesmc.ko" | grep -qx "charge-limit test"'
fi

# --- release promotion against a fake repository
if command -v makepkg >/dev/null; then
	RR=$T/rel
	mkdir -p "$RR"/packaging/arch "$RR"/dist "$RR"/release/20260101.01 "$RR"/release/20260201.01
	cp VERSION "$RR"/
	v=$(cat VERSION)
	echo source >"$RR/dist/macbook91-hw-fixes-$v.tar"
	echo package >"$RR/dist/macbook91-hw-fixes-$v-1-any.pkg.tar.zst"
	cp packaging/arch/macbook91-hw-fixes.install "$RR"/packaging/arch/
	sed "s/^sha256sums=('[0-9a-f]*')/sha256sums=('0000')/" packaging/arch/PKGBUILD >"$RR"/packaging/arch/PKGBUILD
	(cd "$RR"/packaging/arch && makepkg --printsrcinfo >.SRCINFO 2>/dev/null)
	prom() { MACBOOK91_RELEASE_ROOT=$RR "$REPO"/packaging/promote-release.sh "$@"; }
	check "promote: refuses a tarball the PKGBUILD does not pin" '! prom >/dev/null 2>&1 && [ ! -e "$RR/release/$v" ]'
	sed -i "s/^sha256sums=('0000')/sha256sums=('$(sha "$RR/dist/macbook91-hw-fixes-$v.tar")')/" "$RR"/packaging/arch/PKGBUILD
	check "promote: refuses a stale .SRCINFO" '! prom >/dev/null 2>&1 && [ ! -e "$RR/release/$v" ]'
	(cd "$RR"/packaging/arch && makepkg --printsrcinfo >.SRCINFO 2>/dev/null)
	check "promote: copies, seals and records the package checksum" 'prom >/dev/null 2>&1 && (cd "$RR/release/$v" && sha256sum -c --quiet SHA256SUMS) && grep -q "^$(sha "$RR/dist/macbook91-hw-fixes-$v-1-any.pkg.tar.zst")  macbook91-hw-fixes-$v-1-any.pkg.tar.zst" "$RR/release/$v/STATUS.txt"'
	check "promote: keeps the two newest releases" '[ -d "$RR/release/20260201.01" ] && [ ! -e "$RR/release/20260101.01" ]'
	check "promote: never overwrites a release" '! prom >/dev/null 2>&1'
	check "promote: --seal refuses a STATUS.txt with TODO" '! prom --seal "$v" >/dev/null 2>&1'
	sed -i 's/TODO.*/filled in/' "$RR/release/$v/STATUS.txt"
	check "promote: --seal covers the filled-in STATUS.txt" 'prom --seal "$v" >/dev/null && (cd "$RR/release/$v" && sha256sum -c --quiet SHA256SUMS)'
fi

# --- package contents
if [ -n "${PKGDIR_CHECK:-}" ]; then
	check "package: lid hook installed executable" '[ -x "$PKGDIR_CHECK/usr/lib/systemd/system-sleep/macbook91-lid-wake" ]'
	check "package: DKMS source with versioned dkms.conf" '[ -f "$PKGDIR_CHECK/usr/src/macbook91-backlight-$(cat VERSION)/macbook91_backlight.c" ] && grep -qx "PACKAGE_VERSION=\"$(cat VERSION)\"" "$PKGDIR_CHECK/usr/src/macbook91-backlight-$(cat VERSION)/dkms.conf"'
	check "package: applesmc DKMS tree with patched sources for every series" '(d=$PKGDIR_CHECK/usr/src/macbook91-applesmc-$(cat VERSION); grep -qx "PACKAGE_VERSION=\"$(cat VERSION)\"" "$d/dkms.conf" && for s in "$AS"/upstream/*/; do grep -q "applesmc_charge_attach" "$d/$(basename "$s")/applesmc.c" || exit 1; done)'
	check "package: NVMe udev rule installed" '[ -f "$PKGDIR_CHECK/usr/lib/udev/rules.d/60-macbook91-nvme-d3cold.rules" ]'
	check "package: tools installed executable" '[ -x "$PKGDIR_CHECK/usr/bin/macbook91-hw-verify" ] && [ -x "$PKGDIR_CHECK/usr/bin/macbook91-hw-migrate" ]'
fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
