# macbook91-hw-fixes

Hardware fixes for the Apple MacBook9,1 (A1534, 2016) on CachyOS and Arch Linux, outside audio,
camera and WLAN/Bluetooth. They cover NVMe and lid wake after suspend, a perceptual brightness
curve, a battery charge limit, the ISO keyboard layout and hibernate. The package stands on its
own and needs none of the driver packages (see [See also](#see-also)). On other models
`macbook91-hw-migrate` and `macbook91-hw-verify` do nothing and exit with 3.

<!-- Abweichung von DSP-1: the documentation is English, the project language; the rules
for German wording (Du or infinitive) do not apply, the structure rules do. -->

## What the package does

- udev rule `60-macbook91-nvme-d3cold.rules`: keeps the NVMe's PCIe port in D0 during
  suspend (a known workaround for an NVMe that is missing after wakeup). It takes effect right
  after installation.
- Sleep hook `macbook91-lid-wake`: keeps a suspend with the lid open from waking up again
  right away when the lid is closed. With the lid open, the power button then wakes the
  machine (keyboard and touchpad cannot wake it under Linux); with the lid closed, opening it.
- `macbook91-hw-migrate`: sets `acpi_backlight=native` (full, fine brightness; 0 = off)
  and, on request, sets up the ISO keyboard layout (`keyboard-iso`) and hibernate. Every
  step is backed up and can be undone. It only changes files that have the shape it expects.
- pacman hook `71-macbook91-hw-fixes-series.hook`: reports after a kernel update every
  installed kernel the two modules do not cover (see [Kernel series](#kernel-series)).
- `macbook91-hw-verify`: checks packages, DKMS modules, charge limit, migration steps,
  brightness, wake sources, NVMe, keyboard, light and the hibernate configuration; `--deep`
  also runs the check tools of the driver packages that are installed.
- DKMS modules `macbook91_backlight` (brightness curve) and `macbook91-applesmc` (charge limit),
  described under [Usage](#usage).

## Installation

Install the package from the files of a release, or build it from a checkout of the repository.
Both ways end with the migration steps, which set the kernel parameter for the native
backlight. [Verification status](#verification-status) lists which commands were run.

### Prerequisites

- A MacBook9,1 with CachyOS or another Arch-based system.
- The packages `base-devel` and `dkms`, and the headers of every kernel you use: the package
  builds two DKMS modules. The package itself pulls in `linux-cachyos-lts-headers`, which pulls
  in `linux-cachyos-lts` (see [Kernel series](#kernel-series)).
- For the checkout route: a git checkout of the repository, not an unpacked tarball or a
  release download, because `make dist` needs it.

The driver packages are optional; each has its own installation instructions.

### Install from the release files

1. Download all files of the latest [release](https://github.com/Weegee/macbook91-hw-fixes-pub/releases/latest)
   into one empty directory. `makepkg` needs `PKGBUILD`, `macbook91-hw-fixes.install` and the
   source tarball `macbook91-hw-fixes-VERSION.tar`, where VERSION is the version of the release.
   `SHA256SUMS` lists the files to check.

   > **Warning:** `--ignore-missing` skips every line of `SHA256SUMS` whose file is not in the
   > directory, so step 2 can exit successfully while the install file or the tarball is
   > missing. A missing or changed file ends up in a package that runs as root. Run step 3 only
   > when `PKGBUILD`, `macbook91-hw-fixes.install` and the tarball all read `OK`.

2. In that directory, check the files:

   ```fish
   sha256sum -c --ignore-missing SHA256SUMS
   ```

   Expected output (`STATUS.txt` is checked too; `.SRCINFO` is skipped, because GitHub serves it
   as `default.SRCINFO`):

   ```text
   PKGBUILD: OK
   macbook91-hw-fixes.install: OK
   STATUS.txt: OK
   macbook91-hw-fixes-VERSION.tar: OK
   ```

3. Build and install the package. `makepkg` asks for your password through `sudo` when it
   installs. Do not run it as root:

   ```fish
   makepkg -si
   ```

   When a release also lists a ready-built package, install that instead of steps 2 and 3,
   with `sudo pacman -U PACKAGE`; replace PACKAGE with the file name of the package. The
   packages are not signed.

If you maintain your own pacman repository, add the package to it as usual.

### Build from a checkout

The release files of the checked-out version are in `release/VERSION/`; copy them to an empty
directory and follow the steps above. To build from the source tree instead:

1. In the root of the checkout, build the source tarball and the package. `make arch-pkg` runs
   `make dist` itself; the package ends up in `build/arch/`:

   ```fish
   make dist && make arch-pkg
   ```

2. Install the package:

   ```fish
   sudo pacman -U build/arch/macbook91-hw-fixes-*.pkg.tar.zst
   ```

### Apply the migration steps

After the installation, with the package installed:

1. Show what `apply` would change; the command changes nothing:

   ```fish
   macbook91-hw-migrate plan
   ```

2. Apply the default step, which sets `acpi_backlight=native`:

   ```fish
   sudo macbook91-hw-migrate apply
   ```

3. Optional: only with an ISO keyboard (for example German), set up the ISO keyboard layout:

   ```fish
   sudo macbook91-hw-migrate apply keyboard-iso
   ```

4. Reboot, so the kernel parameter takes effect:

   ```fish
   systemctl reboot
   ```

5. Check the result. `RESULT` should report `fail=0` (see [Check the state](#check-the-state)):

   ```fish
   macbook91-hw-verify --deep
   ```

NOT VERIFIED for this version: steps 2 to 4 change the system and were not run again for
release 20261102.01.

To undo the steps, see [Roll back, update and remove](#roll-back-update-and-remove).

## Usage

### Check the state

Run the verifier without options:

```fish
macbook91-hw-verify
```

Output on the test machine (kernel 7.3.3-1-cachyos, package 20261102.01-1, 2026-11-09). Whole
lines are left out where marked with `[...]`; the full output has 29 lines:

```text
PASS dmi: Apple MacBook9,1
PASS package: macbook91-hw-fixes 20261102.01-1
[...]
PASS dkms: macbook91-backlight installed for 7.3.3-1-cachyos
WARN dkms: macbook91-applesmc not built: kernel 7.3.3-1-cachyos (Linux 7.3) is not a series macbook91-applesmc has a source for (6.18 7.2), so the charge limit of this package is not built for it. [...]
[...]
WARN charge limit: this package's charge limit is not built for kernel 7.3.3-1-cachyos; a limit set earlier presumably stays in the SMC; boot the LTS kernel (linux-cachyos-lts) to read or change it
PASS migration: backlight-native applied
PASS migration: keyboard-iso done
INFO migration: hibernate not applied (optional)
PASS backlight: native intel_backlight, 1389 levels, 0 switches the backlight off
PASS backlight: macbook91_backlight drives it in 1001 perceptual (CIE L*) levels
[...]
PASS nvme: d3cold_allowed=0, its root port stays in D0 during suspend
[...]
RESULT pass=21 warn=2 fail=0
```

Both warnings report the missing charge limit on kernel 7.3 (see
[Kernel series](#kernel-series)). The verifier prints one `PASS`, `WARN`, `FAIL` or `INFO` line
per check, then the `RESULT` line, and exits with 1 on a `FAIL`.

Show what each migration step finds:

```fish
macbook91-hw-migrate status
```

Each line reads `ID  STATE  description`. `STATE` is `applied`, `pending`, `optional`, `done`,
`partial`, `foreign` or `unsupported`.

### Change the brightness

The DKMS module `macbook91_backlight` provides a backlight device with a perceptual curve
(CIE L*), which KDE prefers over the linear `intel_backlight`. The keys F1 and F2 change the
brightness in 20 steps that look even, Shift+F1 and Shift+F2 in steps of 1 %.

The module takes effect after the next reboot. To load it without a reboot, run these two
commands (NOT VERIFIED for this version):

```fish
sudo modprobe macbook91_backlight
systemctl --user restart plasma-powerdevil
```

### Read and set the charge limit

The DKMS module `macbook91-applesmc` replaces the kernel driver `applesmc` with the same source
plus a patch of its own. It offers the SMC key `BCLM` as the battery's
`charge_control_end_threshold`, so the charge limit can be set in the Plasma settings (**Power
Management**). PowerDevil needs only this attribute; the Plasma interface itself is NOT
VERIFIED. Measured: above the limit, charging stops at once.

Read the limit in percent. The file exists only on kernels the module is built for (see
[Kernel series](#kernel-series)); on kernel 7.3.3 the command reports that the file does not
exist (VERIFIED 2026-11-09):

```fish
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Set the limit. Replace PERCENT with a value from 10 to 100 (NOT VERIFIED for this version, it
changes the battery):

```fish
echo PERCENT | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

According to reports, the SMC keeps the value until an SMC reset, also across reboots (NOT
VERIFIED on the MacBook9,1 used for testing). Removing the package resets the limit to 100 %.

On any other kernel this package offers no charge limit, but one set earlier presumably stays in
effect; the pacman hook and `macbook91-hw-verify` then warn. Before you move to a new kernel
series, set the limit to 100 %, or boot the LTS kernel (`linux-cachyos-lts`) to change it.

### Set up hibernate (optional)

Hibernate and resume have never run on the test machine: every command in this section is
NOT VERIFIED (`docs/test-status.json`: `hibernate` BLOCKED, because the test needs someone at
the machine for the LUKS passphrase). Only the hermetic tests of the migration are checked
(swap file, fstab, command line, rollback).

The step creates the Btrfs subvolume `@swap` (not in Snapper snapshots) with a swap file of
RAM size and priority -2 behind zram, and adds `resume=` and `resume_offset=` to the kernel
command line. On resume the initramfs asks for the LUKS passphrase as it does at boot.

> **Warning:** After a hibernate, do not boot any other entry (snapshot, LTS kernel, another
> system). The saved state of the hibernated session is lost. Resume from the entry you
> hibernated from.

1. Apply the step:

   ```fish
   sudo macbook91-hw-migrate apply hibernate
   ```

2. Reboot. Hibernate only works after the reboot:

   ```fish
   systemctl reboot
   ```

3. Hibernate:

   ```fish
   systemctl hibernate
   ```

To undo the step:

```fish
sudo macbook91-hw-migrate rollback hibernate
```

### Roll back, update and remove

NOT VERIFIED for this version: the commands in this section change the system and were not run
again for release 20261102.01.

Undo all steps, then reboot:

```fish
sudo macbook91-hw-migrate rollback
```

Undo one step:

```fish
sudo macbook91-hw-migrate rollback backlight-native
```

Update from a newer build, then show what the new version would change:

```fish
sudo pacman -U macbook91-hw-fixes-*.pkg.tar.zst
macbook91-hw-migrate plan
```

Remove the package. Applied steps stay after the removal, so roll them back first:

```fish
sudo pacman -R macbook91-hw-fixes
```

### Use the tools in scripts

Every tool answers `-h` and `--help` (full help on stdout, exit 0) and `-V` and `--version`.
Messages read `program: error: what happened, why, what to do` on stderr. A usage error ends
with 2 and the line `Help: program --help`.

`macbook91-hw-verify` colours only the `PASS`, `WARN` and `FAIL` keywords on a terminal. It keeps
its line format for scripts: one `PASS`, `WARN`, `FAIL` or `INFO` line per check, then
`RESULT pass=N warn=N fail=N`. See [Configuration](#configuration) for the colour settings.

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
pacman shows them. The hook builds nothing and never stops the transaction.

CachyOS's Linux 7.3 builds no applesmc: it brings its own Apple SMC driver, `macsmc-acpi`.
The two must not drive the SMC at the same time, so `macbook91-applesmc` is not built for 7.3
(`docs/FINDINGS.md`). Whether the charge limit of the kernel's `macsmc-power` works on the
MacBook9,1 is NOT VERIFIED.

To ask by hand whether a kernel has an applesmc source, run the script with the kernel release.
It prints the reason and exits with 0 if the kernel is covered, 1 if not (VERIFIED 2026-11-09 on
kernel 7.3.3, exit 1):

```fish
/usr/lib/macbook91-hw-fixes/kernel-series --applesmc "$(uname -r)"
```

To check all installed kernels, as the hook does:

```fish
/usr/lib/macbook91-hw-fixes/kernel-series --hook
```

## Verification status

The read-only commands of this README (`macbook91-hw-verify`, `macbook91-hw-migrate status` and
`plan`, `kernel-series`, `sha256sum -c` on a downloaded release) were run on the test machine on
2026-11-09 with package 20261102.01-1 on kernel 7.3.3-1-cachyos. The commands that change the
system are marked NOT VERIFIED for this version. Earlier runs are recorded in
`docs/test-status.json`.

On the test machine the modules were checked with `linux-cachyos-lts` 6.18.55-2 (built with
GCC 16.2.1) and `linux-cachyos` 7.2.11-1 (built with clang 23.1.3).

VERIFIED on 6.18 (maintainer, 2026-10-20, `6.18.55-2-cachyos-lts` booted, `macbook91-hw-verify`
with the earlier package `macbook91-hw-fixes` 20261020.01-1, a release that is not part of this
repository: `pass=26 warn=0 fail=0`):

- All five DKMS modules (`cs4208`, `facetimehd`, `wireless`, `backlight`, `applesmc`) are
  installed for 6.18.
- The charge limit is readable (`BAT0` `charge_control_end_threshold` 100 %, SMC key `BCLM`); it
  was read, not changed.
- The backlight is the native `intel_backlight` with `macbook91_backlight` on top, in 1001
  CIE L* levels.
- NVMe `d3cold_allowed` is 0.
- Keyboard, keyboard light and ambient light are present.

The driver packages build and run on 6.18 as well: the verify tools of
`macbook91-cs4208-dkms` 20261020.03, `macbook91-wireless-dkms` 20261020.02 (Bluetooth was
blocked by rfkill and not exercised) and `macbook91-facetimehd-dkms` pass. The details are in the
section "Kernel 6.18 LTS" of [docs/FINDINGS.md](docs/FINDINGS.md).

NOT VERIFIED on 6.18: suspend and resume, wake with the lid (`macbook91-lid-wake`), the
backlight across a suspend, and whether a charge limit below 100 % persists. No suspend
happened in the checked boot (`suspend_stats` success 0). The hardware suspend series for
6.18 is NOT_RUN in `docs/test-status.json`; the earlier suspend results were measured on
7.2 and say nothing about 6.18.

## Configuration

The package installs no configuration file. These settings exist:

- Colour of `macbook91-hw-verify`: `--color=auto|always|never` and `--no-color`, and the
  environment variables `MACBOOK91_HW_VERIFY_COLOR`, `NO_COLOR` and `FORCE_COLOR`. The order
  is: `--color`, `MACBOOK91_HW_VERIFY_COLOR`, `NO_COLOR`, `FORCE_COLOR`, `TERM=dumb`, a terminal
  check.
- Backups and state of `macbook91-hw-migrate`: `/var/lib/macbook91-hw-fixes/`. The backups are
  kept after `rollback`.

## Documentation

- [docs/FINDINGS.md](docs/FINDINGS.md): findings and evidence. It is installed as
  `/usr/share/doc/macbook91-hw-fixes/FINDINGS.md`.
- [docs/CHANGELOG.md](docs/CHANGELOG.md): what changed in each version.
- [docs/test-status.json](docs/test-status.json): every test run with its result and the open
  hardware gates.
- `macbook91-hw-verify --help`, `macbook91-hw-migrate --help`: the options of the tools.

## Bug reports

Report bugs in the [issue tracker](https://github.com/Weegee/macbook91-hw-fixes-pub/issues)
of the public repository. Name the kernel (`uname -r`), the package version and the output of
`macbook91-hw-verify`.

## AI assistance

This project was written by Claude (an AI model by Anthropic): Claude wrote the
project's own code, tests and documentation, and the maintainer gave the directions
and made the decisions. Hardware checks were run on a MacBook9,1 under the
maintainer's direction and count only as far as docs/test-status.json records them as
run; everything else there is marked as not run or carried over. Commits that Claude
contributed to carry a Co-Authored-By trailer; the first public commit is a snapshot
of the earlier private history and carries it too. Read the code before you load a
kernel module or run a script as root.

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
the top-level `Makefile`: DKMS and the module build do not use them. Own files with comment
syntax name their license in an `SPDX-License-Identifier` line; Markdown, JSON and text files
carry none. `LICENSE` is the GPL-3.0-or-later text that GitHub shows; the same text is in
`LICENSES/GPL-3.0-or-later.txt` next to the other two. The first three snapshots
(20261013.01, 20261014.01 and 20261015.01) carried a GPL-2.0-only notice; those releases
are not part of this repository.

## See also

- [macbook91-cs4208-dkms](https://github.com/Weegee/macbook91-cs4208-pub): the audio driver
  for the MacBook9,1.
- [macbook91-facetimehd-dkms](https://github.com/Weegee/macbook91-facetimehd-pub): the camera
  driver.
- [macbook91-wireless-dkms](https://github.com/Weegee/macbook91-wireless-pub): the WLAN and
  Bluetooth driver.
