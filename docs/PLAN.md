# Plan macbook91-hw-fixes

As of 2026-10-13 17:25. Basis: the maintainer's inventory of the machine (not part of this repository),
findings in `docs/FINDINGS.md`, matrix in `docs/coverage.json`.
Superseded points carry "→ SUPERSEDED"; README.md and FINDINGS.md are authoritative.

## Guiding decisions
- One package `macbook91-hw-fixes` (arch any). No DKMS module of its own needed: no finding
  requires a driver patch that cannot be solved by a kernel parameter or a hook.
  → SUPERSEDED (as of 2026-10-15): the package contains two DKMS modules, `macbook91_backlight`
  (brightness curve) and `macbook91-applesmc` (charge limit, measure 10).
- Hard dependencies: `macbook91-cs4208-dkms`, `macbook91-facetimehd-dkms`,
  `macbook91-wireless-dkms` (package names verified from the PKGBUILDs and pacman; firmware
  transitively via facetimehd-dkms → macbook91-facetimehd-firmware, wireless → linux-firmware-broadcom).
  No minimum version: no interface between the packages except the verify tools.
  → SUPERSEDED (as of 2026-10-21): no dependencies on the driver packages; the package
  stands on its own and `macbook91-hw-verify` checks the driver packages only where installed.
- Everything is controlled by DMI (`/sys/class/dmi/id/product_name` = `MacBook9,1`); on other hardware
  no part does anything except print a message.
- The kernel command line belongs to the user (`/etc/default/limine`, Limine 12.9 + limine-entry-tool).
  The package does not own it; `macbook91-hw-migrate` changes it selectively, with backup and rollback.

## Measures (priority)
1. **Brightness (P1, reboot needed):** `acpi_backlight=native` by migration. Reason:
   DSDT `_BCL` delivers 0..90 %, `AINT` sets BCLP = L·255/100 → acpi_video0 reaches only
   ≈90 % and 91 steps; 0 does not switch off. i915 native: max = PWM period (register
   0xC8254 = 0x056C → 1388 steps), brightness 0 switches the backlight off through
   the power hook (intel_backlight.c). Upstream makes the same choice for MacBookAir7,2,
   MacBookPro11,2/12,1 by a DMI quirk (video_detect.c). Acceptance after a reboot: intel_backlight
   present, acpi_video0 missing, 0 → dark, key up → bright again, max = hardware max,
   Plasma slider monotonic, resume restores the value. Auto restore before the 0 test.
2. **Lid wake source (P1):** an earlier hand-installed sleep hook (running, 8 journal
   entries) rests on the assumption that LID0 wakes immediately with the lid open. REFUTED for S3:
   today 15 direct rtcwake cycles (deep) with LID0 enabled and the lid open, each slept
   ~21 s until the RTC alarm (journal 15:27–15:35). The hook, on the other hand, carries the risk of leaving LID0
   switched off. Plan: remove the hook by migration, ship no replacement; in the
   suspend series, measure the systemd path with the lid open and without the hook for deep and s2idle. The user tests real
   lid closing (latched event); add a hook only if there is a finding.
   → SUPERSEDED (as of 2026-10-15): after a lid cycle, every suspend with the lid open wakes up again
   after 4 to 5 s (FINDINGS "Lid/wake sources", CORRECTION 2026-10-13). The package ships the
   hook `macbook91-lid-wake`.
3. **Earlier hand-installed tweaks (P1):** remove an earlier NVMe udev rule (matched by hash):
   NVMe port without _PR3/PowerResource → D3cold never possible, rule without effect.
   `applespi.conf iso_layout=1`
   stays a user file (a property of this ISO keyboard, not of the model); verify reports it.
   `pcie_aspm=force` stays (FADT "ASPM not supported"; facetimehd and wireless were
   validated with it, facetimehd switches ASPM off by pci_disable_link_state, which only takes effect this way).
   TLP/sysctl/hwp/scx/nice: general tuning, not taken over, only reported
   (EPP=performance on the power adapter + 70 °C idle on a fanless machine → note to the user).
   → SUPERSEDED (as of 2026-10-15): the rule is not without effect. `d3cold_allowed=0` keeps RP01
   in D0 during suspend (FINDINGS "NVMe", CORRECTION 2026-10-13); the package ships it itself as
   `60-macbook91-nvme-d3cold.rules`.
   → SUPERSEDED (as of 2026-10-21): the migration tool no longer touches the earlier hand-installed
   files; the steps that removed them were dropped again.
4. **Verify (P1):** `macbook91-hw-verify` checks DMI, dependencies (+ their verify), brightness,
   hook, migration steps, sleep states, NVMe health read-only, keyboard/LED/ALS, hibernate config,
   ICC assignment. PASS/WARN/FAIL, exit 0/1/2 like the siblings.
   → SUPERSEDED (as of 2026-10-15): verify checks no ICC assignment (measure 8 has no
   package part) and ends with exit 3 on other models; in addition it checks the DKMS modules
   and the charge limit.
5. **Migration (P1):** `macbook91-hw-migrate status|plan|apply|rollback`, state and backups
   under `/var/lib/macbook91-hw-fixes/`, idempotent, hash check before every change,
   unknown changes stay untouched.
6. **Suspend series (P2):** `tools/dev-suspend-series.sh` (development, not packaged): systemd path
   (`systemctl suspend`), RTC wake alarm, deep and s2idle, idle and load (WLAN download,
   audio playback, camera stream), check after every cycle (NVMe I/O with fsync, journal
   errors, WLAN, audio device, camera, keyboard input, brightness). Abort on errors,
   immediate end on storage/file system errors. Pre-run now, acceptance ≥100 cycles
   on the final candidate after a reboot.
7. **Hibernate (P3):** swap file on a dedicated Btrfs subvolume `@swap` (NOCOW, ≥ RAM),
   low priority behind zram, `resume=`/`resume_offset=` by migration, the initramfs has the
   `systemd` hook (resume before the root mount). Test only with the user (LUKS passphrase) → BLOCKED.
8. **ICC (P3):** the existing `~/.local/share/icc/Macbook12_2016.icc` is an X-Rite profile
   (2016-04-25, mmod Apple 0x610/0xa027 = EDID of this panel), i.e. a foreign measurement
   of the same panel model, not a calibration of this machine. An Apple profile from macOS data
   only if justifiable in time; otherwise a justified omission.
9. **Package/release (P2):** structure modeled on macbook91-facetimehd; release blocked on approvals
   that only the maintainer can give.
   → SUPERSEDED (as of 2026-10-15): releases 20261013.01 and 20261014.01 were published and
   installed.
10. **Charge limit (P2, research 2026-10-14):** the SMC key BCLM is present (VERIFIED).
   The route via applesmc-next (c---, GPL-2.0, last commit 2025-07) replaces applesmc **and**
   sbs (patched battery hook), which is too broad. Better: a DKMS replacement for applesmc only
   (in-tree source v7.2.9 plus ~110 lines). It attaches `charge_control_end_threshold` (BCLM,
   10–100) to BAT0 through the power_supply extension API. The API is present and exported in 7.2.9 and 6.18 LTS
   (VERIFIED in the headers/Module.symvers); sysfs is updated dynamically
   (power_supply_core.c). sbs stays unchanged. PowerDevil 6.7.5 needs only
   `charge_control_end_threshold` (VERIFIED in chargethresholdhelper_linux.cpp).
   Prototype (scratchpad) loaded on 2026-10-14 09:47 by rmmod/insmod: (a) PASS: attribute
   visible, `extensions/applesmc-charge`, reads 100; (b) PASS: with the power adapter at 62 %,
   BCLM=55 → current 1.22 A → 0 within 15 s, sbs status "Full", stable for 90 s; (c) PASS:
   100 → after 15 s "Charging" again at 1.8 A; range check: 5 → EINVAL. Open: (d) value across
   suspend/reboot/power-off (REPORTED: persistent until an SMC reset; Intel Macs may charge
   to 100 while switched off); (e) TLP conflict (TLP active; START/STOP_CHARGE_THRESH not
   set); (f) the PowerDevil setting shows and sets the limit; (g) DKMS build LTS 6.18.
   Implemented on 2026-10-14 as `macbook91-applesmc` (20261014.01): installed, DKMS for 7.2.9 and
   6.18 LTS, module loaded from updates/dkms, verify 27/0/0, PowerDevil without an error message.
   (d), (f) (user) and the boot with LTS remain open.
   → PARTLY SUPERSEDED (2026-10-20): the boot with LTS 6.18.55-2-cachyos-lts has happened;
   `macbook91-hw-verify` pass=26 warn=0 fail=0, all five DKMS modules installed for 6.18, the
   charge limit readable (100 %, read only). (d) on 6.18, i.e. persistence across suspend and
   reboot, and (f) remain NOT VERIFIED; no suspend happened in that boot.
   Risks: replacing an in-tree module (maintenance on kernel updates, DKMS override in
   /updates), unknown effect of the firmware, same situation as with applesmc-next (limit ±3 %, REPORTED).

## Not autonomous (collected for the user)
Reboot for brightness; lid closing; hibernate test; external displays/docks/headset;
perception (image quality, sound); GitHub approvals.
