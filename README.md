# macbook91-hw-fixes

Hardware fixes for the Apple MacBook9,1 (A1534, 2016) on CachyOS/Arch, outside audio,
camera and WLAN/Bluetooth. The package stands on its own and needs none of the driver
packages. Those are separate projects: audio `macbook91-cs4208-dkms`
(https://github.com/Weegee/macbook91-cs4208-pub), camera `macbook91-facetimehd-dkms`
(https://github.com/Weegee/macbook91-facetimehd-pub) and WLAN/Bluetooth
`macbook91-wireless-dkms` (https://github.com/Weegee/macbook91-wireless-pub).
This package owns these measures:

- udev rule `60-macbook91-nvme-d3cold.rules`: keeps the NVMe's PCIe port in D0 during
  suspend (a known workaround for an NVMe that is missing after wakeup). Takes effect right
  after installation.
- Sleep hook `macbook91-lid-wake`: keeps a suspend with the lid open from waking up again
  right away when the lid is closed. With the lid open, the power button then wakes the
  machine (keyboard and touchpad cannot wake it under Linux); with the lid closed, opening it.
- `macbook91-hw-migrate`: sets `acpi_backlight=native` (full, fine brightness; 0 = off)
  and, on request, sets up the ISO keyboard layout (`keyboard-iso`) and hibernate. Every
  step is backed up and can be undone. It only changes files that have the shape it expects.
- pacman hook `71-macbook91-hw-fixes-series.hook`: after a kernel update, reports every
  installed kernel the two modules do not cover (see Kernel series).
- `macbook91-hw-verify`: checks packages, DKMS modules, charge limit, migration steps,
  brightness, wake sources, NVMe, keyboard, light and the hibernate configuration; `--deep`
  also runs the check tools of the driver packages that are installed.

## AI assistance

This project was written by Claude (an AI model by Anthropic): Claude wrote the
project's own code, tests and documentation, and the maintainer gave the directions
and made the decisions. Hardware checks were run on a MacBook9,1 under the
maintainer's direction and count only as far as docs/test-status.json records them as
run; everything else there is marked as not run or carried over. Commits that Claude
contributed to carry a Co-Authored-By trailer; the first public commit is a snapshot
of the earlier private history and carries it too. Read the code before you load a
kernel module or run a script as root.

## Brightness and charge limit

Brightness: the DKMS module `macbook91_backlight` provides a backlight device with a
perceptual curve (CIE L*), which KDE prefers over the linear `intel_backlight`.
F1/F2 change it in 20 steps that look even, **Shift+F1/F2 in 1 %**.
Takes effect after the next reboot (or `sudo modprobe macbook91_backlight` and
`systemctl --user restart plasma-powerdevil`).

Charge limit: the DKMS module `macbook91-applesmc` replaces the kernel driver `applesmc` with
the same source plus a patch of its own. It offers the SMC key `BCLM` as the battery's
`charge_control_end_threshold`, so the charge limit can be set in the Plasma settings
(Power Management) (PowerDevil needs only this attribute; the
Plasma UI itself is NOT VERIFIED). Measured: above the limit, charging stops
at once. According to reports, the SMC keeps the value until an SMC reset, also across
reboots (NOT VERIFIED on the MacBook9,1 used for testing); removing the package resets it to 100 %.
Built only for the kernel series with a source (see Kernel series). On any other kernel this
package offers no charge limit, but one set earlier presumably stays in effect; the pacman hook
and `macbook91-hw-verify` then warn. Before moving to a new kernel series, set the limit to
100 %, or boot the LTS kernel (`linux-cachyos-lts`) to change it.

```fish
cat /sys/class/power_supply/BAT0/charge_control_end_threshold          # read
echo 80 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold   # 10..100
```

Findings and evidence: `docs/FINDINGS.md` (installed under `/usr/share/doc/macbook91-hw-fixes/`).
On other models both tools do nothing (exit 3).

## Kernel series

Supported are the CachyOS LTS kernel (`linux-cachyos-lts`), the default, and the current
series of `linux-cachyos` where the modules support it. The package depends on
`linux-cachyos-lts-headers`, which pulls in `linux-cachyos-lts`; with `linux-cachyos-headers`
installed as well, DKMS also builds for `linux-cachyos`.

- `macbook91-applesmc` (the charge limit) is built only for the series pinned in
  `kernel/applesmc/UPSTREAM.lock`.
- `macbook91_backlight` is built for every kernel; `kernel/TESTED-SERIES` lists the series it
  was checked on.

After every kernel installation or upgrade the pacman hook `71-macbook91-hw-fixes-series.hook`
checks the installed kernels. For a series without an applesmc source it prints a warning
(`macbook91-hw-fixes: warning: ...`): no charge limit of this package there, boot the LTS
kernel. For a series the backlight was not tested on it prints a note. Both go to stderr, so
pacman shows them. It builds nothing and never stops the transaction. The same answer by hand:

```fish
/usr/lib/macbook91-hw-fixes/kernel-series --applesmc (uname -r)
/usr/lib/macbook91-hw-fixes/kernel-series --hook      # all installed kernels
```

CachyOS's Linux 7.3 builds no applesmc: it brings its own Apple SMC driver, `macsmc-acpi`.
The two must not drive the SMC at the same time, so `macbook91-applesmc` is not built for 7.3
(`docs/FINDINGS.md`). Whether the charge limit of the kernel's `macsmc-power` works on the
MacBook9,1 is NOT VERIFIED.

## Kernel 6.18 (CachyOS LTS)

On the test machine the modules were checked with `linux-cachyos-lts` 6.18.55-2 (built with
GCC 16.2.1) and `linux-cachyos` 7.2.11-1 (built with clang 23.1.3).

VERIFIED on 6.18 (maintainer, 2026-10-20, `6.18.55-2-cachyos-lts` booted,
`macbook91-hw-verify` with the earlier package `macbook91-hw-fixes` 20261020.01-1, a
release that is not part of this repository: pass=26 warn=0 fail=0):

- all five DKMS modules (`cs4208`, `facetimehd`, `wireless`, `backlight`, `applesmc`) are
  installed for 6.18;
- the charge limit is readable (`BAT0` `charge_control_end_threshold` 100 %, SMC key
  `BCLM`); it was read, not changed;
- the backlight is the native `intel_backlight` with `macbook91_backlight` on top, in
  1001 CIE L* levels;
- NVMe `d3cold_allowed` is 0;
- keyboard, keyboard light and ambient light are present.

The driver packages build and run on 6.18 as well: the verify tools of
`macbook91-cs4208-dkms` 20261020.03, `macbook91-wireless-dkms` 20261020.02 (Bluetooth was
blocked by rfkill and not exercised) and `macbook91-facetimehd-dkms` pass.

NOT VERIFIED on 6.18: suspend and resume, wake with the lid (`macbook91-lid-wake`), the
backlight across a suspend, and whether a charge limit below 100 % persists. No suspend
happened in the checked boot (`suspend_stats` success 0). The hardware suspend series for
6.18 is NOT_RUN in `docs/test-status.json`; the earlier suspend results were measured on
7.2 and say nothing about 6.18.

## Installation (Arch Linux and derivatives)

Install the headers of every kernel you use (the package builds two DKMS modules); the
package itself pulls in `linux-cachyos-lts-headers` (see Kernel series).
The driver packages are optional; each has its own installation instructions.

Then download all files of the latest release of this package into one empty directory,
check them and build the package. `makepkg` needs `PKGBUILD`,
`macbook91-hw-fixes.install` and the source tarball
`macbook91-hw-fixes-<version>.tar`; `SHA256SUMS` lists the files to check:

    sha256sum -c --ignore-missing SHA256SUMS
    makepkg -si          # needs base-devel, dkms and the kernel headers

`sha256sum` must print `OK` for `PKGBUILD`, `macbook91-hw-fixes.install` and the source
tarball. `--ignore-missing` skips every line of `SHA256SUMS` whose file is not in the
directory (`.SRCINFO`, `STATUS.txt`), so the command can exit successfully while the
install file or the tarball is missing: look for the three `OK` lines, not only for
the exit status. If one of them is missing or reads `FAILED`, do not run `makepkg`.

From a checkout the same files are in release/<version>/; copy them to an empty
directory first. To build from the source tree (`make dist`, which `make arch-pkg`
runs, needs a git checkout of the repository, not an unpacked tarball or a release
download):

    make dist && make arch-pkg
    sudo pacman -U build/arch/macbook91-hw-fixes-*.pkg.tar.zst

When a release also lists a ready-built package, install that with
`sudo pacman -U` instead. The packages are not signed.
If you maintain your own pacman repository, add the package to it as usual.

After the installation:

```fish
macbook91-hw-migrate plan
sudo macbook91-hw-migrate apply
sudo macbook91-hw-migrate apply keyboard-iso    # only with an ISO keyboard (e.g. German)
systemctl reboot
macbook91-hw-verify --deep
```

## Status, update, rollback, removal

```fish
macbook91-hw-verify                      # PASS/WARN/FAIL, exit 1 on FAIL
macbook91-hw-migrate status              # applied / pending / optional / done / partial / foreign / unsupported
sudo pacman -U macbook91-hw-fixes-*.pkg.tar.zst   # update from a newer build; afterwards: macbook91-hw-migrate plan
sudo macbook91-hw-migrate rollback       # undo all steps, then reboot
sudo macbook91-hw-migrate rollback backlight-native   # just one step
sudo pacman -R macbook91-hw-fixes        # applied steps stay; roll back first
```

Every tool answers `-h`/`--help` (full help on stdout, exit 0) and `-V`/`--version`. Messages
read `program: error: what happened, why, what to do` on stderr; a usage error ends with 2
and the line `Help: program --help`. `macbook91-hw-verify` colours only the PASS/WARN/FAIL
keywords on a terminal (`--color=auto|always|never`, `--no-color`; `NO_COLOR`, `FORCE_COLOR`
and `MACBOOK91_HW_VERIFY_COLOR` are honoured) and keeps the line format for scripts: one
PASS, WARN, FAIL or INFO line per check, then `RESULT pass=N warn=N fail=N`.

## Hibernate (optional)

```fish
sudo macbook91-hw-migrate apply hibernate    # swap file on @swap behind zram, resume=
systemctl reboot                             # only then: systemctl hibernate
sudo macbook91-hw-migrate rollback hibernate
```

Creates the Btrfs subvolume `@swap` (not in Snapper snapshots) with a swap file of
RAM size, priority -2 behind zram, and adds `resume=`/`resume_offset=`. On
resume the initramfs asks for the LUKS passphrase as it does at boot. After a
hibernate, do not boot any other entry (snapshot, LTS, another system), or the
saved state is lost.
NOT VERIFIED: hibernate and resume have never run on the test machine
(`docs/test-status.json`: `hibernate` BLOCKED, the test needs someone at the machine for
the passphrase). Only
the hermetic tests of the migration are checked (swap file, fstab, command line, rollback).

Backups and state: `/var/lib/macbook91-hw-fixes/`. The backups are kept after
`rollback`.

## License

Own work is GPL-3.0-or-later (`LICENSE`, `LICENSES/GPL-3.0-or-later.txt`). Exceptions
(texts in `LICENSES/`):

- `kernel/applesmc/upstream/*/applesmc.c`: GPL-2.0-only. Unmodified copies from Linux
  (Nicolas Boichat and others), origin and SHA256 in `kernel/applesmc/UPSTREAM.lock`.
- `kernel/applesmc/0001-applesmc-charge-limit-through-BCLM.patch`: GPL-2.0-only, like the
  file it changes.
- `kernel/macbook91_backlight.c`: GPL-2.0-only. The CIE conversion follows `cie1931()` in
  the kernel's `drivers/video/backlight/pwm_bl.c`.
- `kernel/Makefile`, `kernel/dkms.conf`, `kernel/applesmc/Makefile` and
  `kernel/applesmc/dkms.conf`: GPL-2.0-or-later. Under GPLv2 section 3 the scripts that
  build and install a module are part of its source; whoever passes on a built module
  must be able to provide them under the GPLv2.

Everything else is GPL-3.0-or-later, including `src/`, `sleep/`, `udev/`, `packaging/`,
`tests/`, `tools/`, `docs/` and the other documentation, as well as
`kernel/applesmc/UPSTREAM.lock`, `kernel/applesmc/add-series.sh`, `kernel/TESTED-SERIES` and
the top-level `Makefile`: DKMS and the module build do not use them. Own files with comment syntax name
their license in an `SPDX-License-Identifier` line; Markdown, JSON and text files carry
none. `LICENSE` is the GPL-3.0-or-later text that GitHub shows; the same text is in
`LICENSES/GPL-3.0-or-later.txt` next to the other two. The first three snapshots
(20261013.01, 20261014.01 and 20261015.01) carried a GPL-2.0-only notice; those releases
are not part of this repository.
