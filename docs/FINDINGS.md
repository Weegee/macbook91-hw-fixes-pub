# Findings MacBook9,1

Measured on the MacBook9,1 test machine on 2026-10-13: kernel 7.2.9-2-cachyos, linux-cachyos-lts 6.18.55-2,
systemd 262, Plasma/KWin/PowerDevil 6.7.5, Mesa 26.2.4, libinput 1.32.0, Limine 12.9.0,
EFI 522.0.0.0.0. Labels: VERIFIED (measured or shown in the source code),
NOT VERIFIED, REFUTED. Raw data (journals, full firmware tables) is kept only by the maintainer and is not part of this repository.
The section on kernel 6.18 was measured later, on 2026-10-20.

## Display brightness → measure `backlight-native`
- VERIFIED (sysfs): only `acpi_video0` (type firmware, max_brightness 90) is registered,
  i915 reports "Skipping intel_backlight registration".
- VERIFIED (DSDT): `_BCL` = package of 0x50, 0x32 and the levels 0..0x5A (0..90);
  `_BCM` → `ABCM` → `AINT(1, L)` sets `BCLP = L·255/100` through the Intel OpRegion.
  Highest reachable level 90 → BCLP 229/255 ≈ 90 % of the i915 range, 91 levels.
- VERIFIED (register): `BLC_PWM_PCH_CTL2` (0xC8254) = 0x056C0000 → PWM period 1388.
- VERIFIED (source, `drivers/gpu/drm/i915/display/intel_backlight.c`, master):
  natively, `max_brightness` = hardware maximum; at brightness 0
  `intel_backlight_device_update_status` calls the power hook with enable=false (back-
  light off). Through ACPI, by contrast, it is clamped to `backlight.min` (VBT, ≤ 25 %).
- VERIFIED (source, `drivers/acpi/video_detect.c`): without the Win8 `_OSI` the kernel picks
  acpi_video. Upstream forces native through a DMI quirk for MacBookAir7,2,
  MacBookPro11,2, MacBookPro12,1 and others; MacBook9,1 is not in the table.
- Measure: `acpi_backlight=native` in `/etc/default/limine` (Limine + limine-entry-tool).
  Takes effect only after a reboot; acceptance: see docs/coverage.json. VERIFIED after the
  reboot on 2026-10-13: intel_backlight max 1388, acpi_video0 missing, all 1389 levels read
  back, 0 = dark; Plasma slider and keys (user). In the night series of 2026-10-14 (101 cycles)
  every cycle passed the series tool's brightness check (not 0 after wakeup,
  unless it was 0 before).
- Unneeded once `video_detect.c` has a `MacBook9,1` entry with
  `video_detect_force_native` (check: `grep -n MacBook9,1` in the kernel source
  of the installed kernel).

## NVMe Apple AP0256J (106b:2003, fw 9.135.01) → package rule `60-macbook91-nvme-d3cold.rules`
- VERIFIED (nvme id-ctrl): apsta=0, npss=0 (one power state), rtd3e=0, nn=2
  (second 8-KiB namespace nvme0n2, purpose NOT VERIFIED). No APST possible.
- VERIFIED (get-feature 0x07): the controller grants only one I/O queue
  (NCQA = NSQA = 1). Firmware limit, no change.
- VERIFIED (source, torvalds master): `d3cold_allowed=0` on the NVMe sets
  `bridge_d3 = false` on root port RP01 (00:1c.0) through `pci_dev_check_d3cold`
  (drivers/pci/pci.c). That makes `pci_power_manageable` (drivers/pci/pci.h) false for the
  port, and `pci_pm_suspend_noirq` (drivers/pci/pci-driver.c) leaves it in D0 in system suspend.
  Without the setting RP01 may go to D3hot: not a hotplug port, BIOS year 2023 ≥ 2015
  (`pci_bridge_d3_possible`).
- This is the known workaround for 2016 MacBooks whose NVMe does not come back after resume
  (Arch forum https://bbs.archlinux.org/viewtopic.php?id=246806, Pine64 forum
  pointing to mbp-2016-linux https://forum.pine64.org/showthread.php?pid=71654).
  NOT VERIFIED for this machine that it fails without the setting: a counter-test
  would put the system drive at risk and is not done. All suspend tests ran with
  `d3cold_allowed=0`.
- REFUTED: the rationale of an earlier hand-installed version of this rule (latency from
  D3cold while idle). The nvme driver never gives up the runtime PM reference from
  `local_pci_probe` (no pm_runtime calls in drivers/nvme/host/pci.c), and RP01 has only
  `_PRW`/`_DSM`, no `_PR3`: there is no runtime D3cold here.
- CORRECTION 2026-10-13: an earlier version therefore called the rule ineffective. That was
  wrong; the effect on the root port had been overlooked.
- Measure: the package ships the rule itself (limited to the MacBook9,1 by DMI, checked with
  `udevadm test`) and sets the value on installation.
- Unneeded only once the kernel itself keeps RP01 out of D3 in system suspend for
  106b:2003 (not the case today, see above). Check: in the source of a
  new kernel `grep -n '0x2003' drivers/pci/quirks.c drivers/nvme/host/pci.c`; a hit
  alone is not enough, the effect has to be shown in the source code as above
  (`pci_dev_check_d3cold`, `pci_bridge_d3_possible`).
- VERIFIED (source, `drivers/nvme/host/pci.c` master): 106b:2003 carries no
  NVME_QUIRK_* flags (0x2001 and the T2's 0x2005 do). The known nvme-apple suspend fix
  (2023) concerns Apple Silicon, not this machine.
- SMART: 29 °C, spare 87 %, 10 % used, no critical warning.

## Lid/wake sources → package hook `macbook91-lid-wake`
- VERIFIED: `mem_sleep` = `s2idle [deep]`; wake sources RP01 RP09 RP10 ARPT SPIT XHC1
  LID0 enabled. LID0 wakes through GPE 0x6F (PCH GPIO, `_L6F`).
- VERIFIED (journal 2026-10-13): after the lid has once been really closed and opened, every
  deep suspend with the lid open wakes up again after 4–5 s without a hook, 10 out of 10
  (PowerDevil idle every 10 min and test series, 20:45–22:06), each time GPE 0x6F and a LID0
  event. Before the first lid cycle of a boot it slept normally (21 cycles). That is the
  premise of an earlier hand-installed hook: correct.
- CORRECTION 2026-10-13: an earlier version called the premise "refuted for S3" and
  put an early wakeup down to the table shaking. Both were wrong; the tests without the hook
  ran before the first lid cycle.
- VERIFIED with the hook in the same state: 2/2 cycles slept until the RTC alarm,
  GPE 0x6F stayed unchanged.
- Measure: the package ships the hook itself (`/usr/lib/systemd/system-sleep/
  macbook91-lid-wake`): before suspend, LID0 wakeup off with the lid open (the power button
  wakes), on with the lid closed (opening wakes); afterwards always on again.
- Cause in the GPIO wake path (status stays set after the lid cycle?) NOT VERIFIED.
- VERIFIED (user test 22:17–22:20 with the package hook): close → open wakes;
  combined case (standby from the menu with the lid open stays asleep, wake, then close/open)
  wakes. With the lid open only the power button wakes, no normal key: `applespi`
  does not support wakeup by keyboard/touchpad (README of the original driver
  cb22/macbook12-spi-driver: "Wakeup on keypress / touchpad" under "What doesn't work";
  `wakeup_count` of the SPI device 0). Without the hook the machine could not be put to sleep
  at all with the lid open after a lid cycle; the power button is the smaller price.
- Unneeded once a suspend with the lid open sleeps through after a real close and open
  without the hook as well. Check (only with the user at the machine): after a lid cycle, with
  the lid open and LID0 `*enabled`, run `sudo rtcwake -m mem -s 30` three times; `rtcwake`
  writes directly to `/sys/power/state` and so bypasses the systemd-sleep hooks. If the machine
  sleeps the full 30 s every time, the hook is superfluous. A kernel fix is NOT known.

## PCIe ASPM → no change
- VERIFIED (FADT): "PCIe ASPM Not Supported" = 1. `pcie_aspm=force` (tuning, user
  cmdline) overrides that. The camera and WLAN packages were validated with it; the camera
  driver turns ASPM off with `pci_disable_link_state`, which only works under OS control.
  Decision: leave it unchanged, verify reports it.

## Keyboard, touchpad, light
- VERIFIED: applespi on `spi-APP000D:00` (GPE 0x07 = SPIT), fnmode=1.
- VERIFIED (source, applespi.c master lines 104–106, 1104): `iso_layout` is a bool with
  default 0; the driver does not detect the layout. ISO keyboards (German and most
  European ones) need `iso_layout=1`, otherwise `^` and `<` are swapped. Measure:
  optional step `keyboard-iso` (modprobe.d, live, initramfs for the passphrase);
  verify warns about an ISO keymap without the option. On the test machine the maintainer's file
  `/etc/modprobe.d/applespi.conf` does that, also in the initramfs (VERIFIED, lsinitcpio).
- XKB `de`/`pc105` is a user setting (variant `mac` follows the Mac key labels),
  not a hardware fix.
- VERIFIED: libinput 1.32.0 has a section "Apple Laptop Touchpad (SPI) applespi driver"
  for this touchpad (bus SPI, vendor 0x06cb) in `50-system-apple.quirks`
  (ModelAppleTouchpad, size, palm threshold). No quirk of our own needed.
- VERIFIED: keyboard light `spi::kbd_backlight` 0..255 (applespi), ALS `acpi-als`
  (ACPI0008, iio:device0); applesmc `light` hardly delivers values.
- VERIFIED (source powerdevil master, `KeyboardBrightnessLogic::calculateSteps`): with
  ≥ 80 levels Plasma steps the keyboard light in 5 steps (20 %). Intended, not a bug.
- KWin automatic brightness (iio-sensor-proxy + acpi-als) works with relative brightness
  0..1 and learns from manual corrections (kwin master `workspace.cpp`, `AutoBrightnessCurve`).
  With `acpi_backlight=native`, 1.0 = 100 % instead of 90 % PWM; no recalibration needed.
- VERIFIED (source kwin master `externalbrightness_v1.cpp`, powerdevil master
  `ScreenBrightnessLogic::calculateSteps`; kglobalshortcutsrc): KDE maps percent linearly to
  1..1388 (0 % = raw value 1, 5 % ≈ 70) and steps F1/F2 in 20 steps of 5 %. The eye
  perceives brightness roughly logarithmically, so 5 % steps look coarse at the low end.
  Shift+F1/F2 steps by 1 % (PowerDevil "Bildschirmhelligkeit um 1 % …" [screen brightness
  by 1 % …]).

## Brightness curve → DKMS module `macbook91_backlight`
- VERIFIED (invent.kde.org, bugs.kde.org): KDE does not plan a perceptual curve.
  Bug 448459 "Logarithmic brightness scaling" RESOLVED WONTFIX (2026-04-08, MR 102
  closed); MR 134 "Change screen brightness in perceptual space" open since 2023.
- VERIFIED (source powerdevil master `backlighthelper_linux.cpp`): PowerDevil picks
  backlight devices in the order firmware → platform → raw. `intel_backlight` is raw.
- Measure without a KDE patch: the module registers `macbook91_backlight` (type platform,
  scale non-linear, 0..1000 = CIE L* 0..100) and sets `intel_backlight` to the matching
  luminance (Y = L/903.3 up to L* 8, else ((L+16)/116)³; level ≥ 1 gives raw value ≥ 1,
  0 = off). Desktop keys, slider, OSD and automatic brightness so work in steps that
  look even; 5 % now means raw value 8 instead of 70.
- VERIFIED (test machine, 2026-10-13): builds without warnings for 7.2.9-cachyos and
  6.18.55-cachyos-lts; 15 sample levels match the reference
  calculation; if someone changes `intel_backlight` directly, the module value follows; after
  a reboot PowerDevil controls the module device (SetBrightness 3000 → level 301 → raw value 87).
- Correction (2026-10-20): the 2026-10-13 note said the 6.18 build used clang/LLVM. VERIFIED
  in the `.config` of the installed headers: `6.18.55-2-cachyos-lts` is built with GCC 16.2.1
  (`CONFIG_CC_IS_GCC=y`), `7.2.11-1-cachyos` with clang 23.1.3 (`CONFIG_CC_IS_CLANG=y`). The
  module Makefiles follow the compiler family of each kernel's own `.config`.
- Loads by DMI alias only on the MacBook9,1; waits up to 60 s for i915. Needs
  `acpi_backlight=native`. Superfluous once KDE itself scales perceptually.
- Journal: `crc mismatch` on applespi mode switch after resumes (31 messages in 57 resumes
  of one boot); libinput "Touch jump detected" (5). Keyboard and touchpad device were present
  after every series cycle; effect on typing NOT VERIFIED. No known
  remedy, no change.

## Color profile
- VERIFIED: panel EDID "Color LCD", manufacturer APP, product 0xa027, 2304×1440.
- VERIFIED: KWin uses `~/.local/share/icc/Macbook12_2016.icc` for eDP-1. The profile
  comes from X-Rite (creator XRCM, 2016-04-25, CxF/DDPS tags, `mmod` Apple 0x610 /
  0xa027): a measurement of another machine with the same panel model, not a calibration of
  this machine. Contains `vcgt`; check for gamma being applied twice.

## Other hardware
- Battery bq20z451, 624 cycles, 77 % of design capacity. Without `macbook91-applesmc` the
  kernel offers no `charge_control_*` (BAT0 comes from `sbs`, ACPI0002; the in-tree `applesmc`
  knows no charge limit), so PowerDevil reported "Charge thresholds are not supported". New
  (2026-10-14): VERIFIED that the SMC key `BCLM` (ui8, value 100) exists, as do CHGC/CHGV
  and other charging keys; `BFCL` (MagSafe LED) and `CH0B/CH0C` are missing. VERIFIED
  (2026-10-14, prototype): the firmware honors BCLM; at 62 % and BCLM=55 charging stops
  at once (1.22 A → 0), at 100 it charges again. REPORTED: AlDente
  lists the MacBook 12" 2016 as working with BCLM; applesmc-next uses BCLM for
  `charge_control_end_threshold`. Implemented as the DKMS replacement
  `macbook91-applesmc` (PLAN.md measure 10). VERIFIED: `capacity` in sysfs refers to the
  design capacity (charge_now/charge_full_design, 70 % at 3.87/5.55 Ah), Plasma/UPower to
  today's full charge (90 % at 3.87/4.31 Ah). At "full", sysfs therefore shows ~78 %.
- Charge limit (`macbook91-applesmc`) unneeded once in-tree `applesmc` itself offers the key
  BCLM as `charge_control_end_threshold`. Check: in the source of a new
  kernel `grep -n BCLM drivers/hwmon/applesmc.c`; with the in-tree module there is then
  `/sys/class/power_supply/BAT0/charge_control_end_threshold`. Until then every new
  kernel series needs its own pinned source (`kernel/applesmc/UPSTREAM.lock`).
- USB-C PD controller `APPLE-I2C-HPM0` without a Linux driver, no typec class.
- Thermals: passive; 69–70 °C package at idle on the power adapter with EPP=performance (the
  user's TLP tuning). Note, no change (general tuning).
- GPU HD 515: i915 defaults, DMC 1.27, DC5/DC6 active; PSR not supported by the panel
  (debugfs ENODEV), FBC off (pixel format). VA-API iHD 26.3.5 present.
- ACPI firmware messages (`\_SB.OSCP`, SSDT AE_ALREADY_EXISTS, `\_PR.CPU0.GCAP`): firmware
  noise without observed effect.

## Kernel 6.18 LTS (`linux-cachyos-lts`), booted 2026-10-20
- VERIFIED (maintainer, `6.18.55-2-cachyos-lts`, `macbook91-hw-verify` with `macbook91-hw-fixes`
  20261020.01-1): pass=26 warn=0 fail=0. All five DKMS modules (cs4208, facetimehd, wireless,
  backlight, applesmc) are installed for 6.18. The charge limit is readable (`BAT0`
  `charge_control_end_threshold` 100 %, SMC key `BCLM`); it was read, not changed. The
  backlight is the native `intel_backlight` with `macbook91_backlight` in 1001 CIE L* levels.
  NVMe `d3cold_allowed` is 0. Keyboard, keyboard light and ambient light are present.
- VERIFIED (maintainer, same boot): the verify tools of `macbook91-cs4208-dkms` 20261020.03 and
  `macbook91-wireless-dkms` 20261020.02 pass on 6.18, as does `macbook91-facetimehd-dkms`.
  Bluetooth was blocked by rfkill and not exercised.
- NOT VERIFIED on 6.18: suspend and resume (`suspend_stats` success 0, no suspend happened in
  the boot), wake with the lid, the backlight across a suspend, persistence of a charge limit
  below 100 % (the limit was only read). The 7.2 suspend results do not carry over.

## Journal warnings (`journalctl -b -p4`, review 2026-10-14)
The messages of devices that need no action. The other messages were handed over to the
sibling packages and to upstream.
- `ACPI Error: AE_ALREADY_EXISTS, SSDT … Table is already loaded`, `\_SB.OSCP` AE_NOT_FOUND,
  aborted `\_PR.CPUn._PDC/_OSC/GCAP`: the Apple firmware loads CPU SSDTs dynamically
  in each CPU's `_PDC`/`_OSC`; from the second CPU on they are already loaded.
  VERIFIED without effect: intel_pstate `active` with HWP, cpuidle `intel_idle` with
  C1 to C10. An ACPI override would bring risk without benefit. No change.
- `DMAR: Failed to find handle for ACPI object \_SB.PCI0.I2C0/UA00/UA02`: the DMAR table
  names devices that are missing from the DSDT. Harmless.
- `usb: port power management may be unreliable`: VERIFIED in the source code (v7.2.9
  `drivers/usb/core/port.c`, `link_peers_report`): linking a USB2 port with its
  USB3 peer port fails. That only affects port runtime PM. Harmless.
- `[Firmware Bug]: TSC ADJUST differs: CPU0 0 --> N. Restoring`: the firmware changes
  TSC_ADJUST on wakeup from S3, the kernel resets it (85× in 85 resumes on
  2026-10-13/14). Cannot be fixed, harmless.
- `applesmc: hwmon_device_register() is deprecated`: the in-tree driver uses the old
  hwmon API. Only fixable upstream.
- `macbook91_backlight: loading out-of-tree module taints kernel`: that is our own
  DKMS module (taint O). Expected.
- applespi `crc mismatch` and libinput `Touch jump`: see "Keyboard, touchpad, light".
