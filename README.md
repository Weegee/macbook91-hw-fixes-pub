# macbook91-hw-fixes

Hardware fixes for the Apple MacBook9,1 (A1534, 2016) on CachyOS and Arch Linux, outside audio,
camera and WLAN/Bluetooth: NVMe and lid wake after suspend, a perceptual brightness curve, a
battery charge limit, the ISO keyboard layout and hibernate. The package needs none of the
driver packages. On other models its tools do nothing and exit with 3.

## Install

1. Download all files of the latest [release](https://github.com/Weegee/macbook91-hw-fixes-pub/releases/latest)
   into one empty directory. You also need `base-devel`, `dkms` and the headers of every kernel
   you use.
2. Check the files. `--ignore-missing` hides missing files, so build only when `PKGBUILD`,
   `macbook91-hw-fixes.install` and `macbook91-hw-fixes-VERSION.tar` all read `OK`:

   ```fish
   sha256sum -c --ignore-missing SHA256SUMS
   ```

3. Build and install (not as root; it asks for your password through `sudo`):

   ```fish
   makepkg -si
   ```

Other routes (checkout, own repository) and update or removal: [docs/install.md](docs/install.md).

## First run

Look at what the migration would change, apply the default step (`acpi_backlight=native`),
reboot, then check the machine:

```fish
macbook91-hw-migrate plan
sudo macbook91-hw-migrate apply
systemctl reboot
macbook91-hw-verify
```

`macbook91-hw-verify` prints one line per check and ends with the result (excerpt):

```text
PASS dmi: Apple MacBook9,1
PASS backlight: native intel_backlight, 1389 levels, 0 switches the backlight off
PASS nvme: d3cold_allowed=0, its root port stays in D0 during suspend
RESULT pass=21 warn=2 fail=0
```

NOT VERIFIED for this version: `apply` and the reboot changed the system and were not run again
for release 20261102.01.

## What is in the package

| Part | What it does | Page |
| --- | --- | --- |
| `macbook91-hw-migrate` | sets `acpi_backlight=native`; on request the ISO keyboard layout and hibernate; every step can be undone | [migrate](docs/migrate.md) |
| `macbook91-hw-verify` | read-only check of packages, modules, steps, brightness, wake, NVMe, keyboard | [verify](docs/verify.md) |
| module `macbook91_backlight` | brightness in 1001 even steps (CIE L*), F1 and F2 | [brightness](docs/brightness.md) |
| module `macbook91-applesmc` | battery charge limit through `charge_control_end_threshold` | [charge limit](docs/charge-limit.md) |
| udev rule, hook `macbook91-lid-wake` | NVMe stays in D0 in suspend; a suspend with the lid open does not wake at once | [verify](docs/verify.md) |
| pacman hook `71-macbook91-hw-fixes-series.hook` | warns after a kernel update about kernels the modules do not cover | [kernel series](docs/kernel-series.md) |

## Read on

- [docs/install.md](docs/install.md), [docs/migrate.md](docs/migrate.md), [docs/verify.md](docs/verify.md),
  [docs/brightness.md](docs/brightness.md), [docs/charge-limit.md](docs/charge-limit.md),
  [docs/kernel-series.md](docs/kernel-series.md): one page per task.
- [docs/CHANGELOG.md](docs/CHANGELOG.md): what changed in each version.
- [docs/entwicklung/](docs/entwicklung/README.md): test status, findings and build notes for developers.
- Bugs: the [issue tracker](https://github.com/Weegee/macbook91-hw-fixes-pub/issues). Name `uname -r`,
  the package version and the output of `macbook91-hw-verify`.
- Driver packages: [audio](https://github.com/Weegee/macbook91-cs4208-pub),
  [camera](https://github.com/Weegee/macbook91-facetimehd-pub),
  [WLAN and Bluetooth](https://github.com/Weegee/macbook91-wireless-pub).

## AI assistance

Claude (an AI model by Anthropic) wrote the code, tests and documentation; the maintainer set the
directions and decided. Hardware checks count only as far as `docs/test-status.json` records them
as run. Read the code before you load a kernel module or run a script as root.

## License

Own work is GPL-3.0-or-later (`LICENSE`). Exceptions, with texts in `LICENSES/`: the unmodified
Linux `applesmc.c` copies, its patch and `kernel/macbook91_backlight.c` are GPL-2.0-only; the
module Makefiles and `dkms.conf` under `kernel/` are GPL-2.0-or-later. Files with comment syntax
name their license in an `SPDX-License-Identifier` line; origin and SHA256 of the upstream copies
are in `kernel/applesmc/UPSTREAM.lock`.
