# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day). The release tag is v<version>. The per-release record (what was
measured, the package checksum) is `release/<version>/STATUS.txt`; the
release tool keeps at most the two newest releases in the tree, older releases
are not part of this repository.

## 20261021.01

**First release prepared for the public repository: changes to the shipped
scripts and the package dependencies, plus documentation and licensing text.
The kernel modules and the udev rule are unchanged.**

Commit hashes named in entries up to 20261021.01 belong to the maintainer's private history and do not exist in the public repository.

- The package stands on its own: it no longer depends on
  `macbook91-cs4208-dkms`, `macbook91-facetimehd-dkms` and
  `macbook91-wireless-dkms`. `macbook91-hw-verify` checks those packages and
  their DKMS modules only where they are installed (INFO otherwise, no FAIL),
  no longer checks for the camera firmware package (the camera package checks
  its firmware itself), and `--deep` skips a verify tool that is not installed.
- Removed: the two `macbook91-hw-migrate` steps that deleted earlier
  hand-installed files (an NVMe udev rule and a sleep hook of a previous
  setup), the matching check for that hook in `macbook91-lid-wake`, and the
  INFO branch for it in `macbook91-hw-verify`. The sleep check no longer
  accepts such a hand-installed hook in place of the packaged one (it was
  reported as INFO before): only `macbook91-lid-wake` passes, otherwise the
  check FAILs. `macbook91-hw-migrate` keeps three steps: `backlight-native`
  (default), `keyboard-iso` and `hibernate` (the last two only when named).
  Behaviour change: `status` and `rollback` no longer know the two removed
  steps. A state record `applied/legacy-d3cold-rule` or
  `applied/legacy-sleep-hook` under `/var/lib/macbook91-hw-fixes`, left by an
  earlier `apply`, is ignored, and `rollback` with one of those names reports
  `unknown step`. Such a leftover record is harmless and can be deleted by hand
  (VERIFIED by reading the step lists, NOT RUN on hardware). The packaged lid
  hook also no longer stands aside when an earlier hand-installed hook of the
  same kind is still present. Two such hooks would both toggle `LID0`, so an
  earlier hook has to be removed by hand (VERIFIED by reading the removed
  lines, NOT RUN on hardware). `docs/coverage.json` and `docs/test-status.json`
  describe the packaged rule and hook as the only ones and mark the old
  migration runs as historical.
- README: install instructions for Arch Linux from the release files or a
  checkout (the driver packages are optional and have their own instructions;
  all files of the release go into one empty directory;
  `makepkg` needs `PKGBUILD`, the scriptlet `macbook91-hw-fixes.install` and
  the source tarball; `sha256sum -c --ignore-missing SHA256SUMS` must print
  `OK` for those three, because `--ignore-missing` alone can succeed with a
  file missing; `make dist` needs a git checkout), the AI assistance note in
  the wording shared by the four repositories, the note that the first three snapshots
  (20261013.01 to 20261015.01) carried a GPL-2.0-only notice, and a license table that lists only paths
  of this repository. `LICENSES/GPL-3.0-or-later.txt` is added (identical to
  `LICENSE`) and the unused `LICENSES/MIT.txt` is removed. `docs/FINDINGS.md`
  and the Makefile header are worded for a public reader.
- Repository: the maintainer's working notes, hand-over files and runner
  scripts are no longer part of the published tree; the two development
  helpers are renamed `tools/dev-backlight-check.sh` and
  `tools/dev-suspend-series.sh` (they are not packaged). `.gitignore` lists
  build and test output only.
- Against the 20261020.02 source tarball the files that differ are
  `README.md`, `docs/FINDINGS.md`, `Makefile`, `VERSION`,
  `src/macbook91-hw-migrate`, `src/macbook91-hw-verify` and
  `sleep/macbook91-lid-wake`; `LICENSES/GPL-3.0-or-later.txt` is added. All
  files under `kernel/` and `udev/` and both GPL-2.0 license texts are byte for
  byte identical (VERIFIED by `diff -r` of the unpacked tarballs). Module
  identity of `macbook91-applesmc` and `macbook91-backlight` is therefore
  unchanged; only the embedded package version follows `pkgver`.
- Measured on 2026-10-21 without hardware: `tests/run-tests.sh` 99 passed,
  0 failed (hermetic) and 104 passed, 0 failed with the package contents
  checked; `make dist` gives the pinned tarball (sha256 `4f72b6dd...`).
  namcap: 0 errors, 5 dependency warnings (coreutils, grep, sed, systemd,
  dkms). ShellCheck at warning level and `git diff --check` are clean.
- Hardware gate PASS (2026-10-21, 7.2.11-1-cachyos): the package was installed
  with `pacman -U` and `macbook91-hw-verify` gave pass=23 warn=0 fail=0 (three
  fewer than before 20261021.01: the two removed migration steps and the
  removed camera firmware package check no longer report). Runtime of the modules and the udev rule is carried over from
  20261020.02 (same sources). The lid hook did not run at a real suspend after
  the install.

## 20261020.02

**Documentation only, no code change. 6.18 (CachyOS LTS) hardware gate
recorded: `macbook91-hw-verify` PASS; suspend on 6.18 NOT VERIFIED.** The
maintainer booted `6.18.55-2-cachyos-lts` on 2026-10-20 and ran
`macbook91-hw-verify` with `macbook91-hw-fixes` 20261020.01-1: pass=26 warn=0
fail=0. All five DKMS modules (cs4208, facetimehd, wireless, backlight,
applesmc) are installed for 6.18. The charge limit is readable (`BAT0`
`charge_control_end_threshold` 100 %, SMC key `BCLM`); it was read, not
changed. The backlight is the native `intel_backlight` with
`macbook91_backlight` in 1001 CIE L* levels, NVMe `d3cold_allowed` is 0, and
keyboard, keyboard light and ambient light are present. `suspend_stats` shows
success 0: no suspend happened in that boot, so suspend/resume, wake with the
lid, the backlight across a suspend and the persistence of a charge limit
below 100 % on 6.18 are NOT VERIFIED (NOT_RUN gates in
`docs/test-status.json`). The other packages on 6.18: the verify tools of
`macbook91-cs4208-dkms` 20261020.03, `macbook91-wireless-dkms` 20261020.02
and `macbook91-facetimehd-dkms` pass.

- `README.md` gets the section "Kernel 6.18 (CachyOS LTS)" with the verified
  and the NOT VERIFIED items. `docs/FINDINGS.md` gets the same as a measured
  section and corrects a compiler note: `6.18.55-2-cachyos-lts` is built with
  GCC 16.2.1 (`CONFIG_CC_IS_GCC=y`), `7.2.11-1-cachyos` with clang 23.1.3;
  the 2026-10-13 note had said clang/LLVM for 6.18. These two files and
  `VERSION` are the only packaged files that change.
- Not packaged: `docs/test-status.json` records the 6.18 hw-verify gate
  (PASS) and NOT_RUN gates for the 6.18 suspend series (hardware suspend
  series, lid close and wake, backlight across suspend, charge limit below
  100 % across suspend and reboot, driver suspend of the sibling packages),
  and updates the two stale "LTS 6.18" entries. `docs/PLAN.md` marks
  the superseded statements instead of rewriting them. This changelog is new.
- No code change: against the 20261020.01 source tarball only `README.md`,
  `docs/FINDINGS.md` and `VERSION` differ (VERIFIED by `diff -r`); the source
  tarball was built twice, identical.
- Module identity of `macbook91-applesmc` and `macbook91-backlight`
  unchanged. The DKMS trees of this package were built in a scratch
  directory against the headers of `6.18.55-2-cachyos-lts` and
  `7.2.11-1-cachyos` (no warnings) and compared with the installed
  20261020.01 modules: `srcversion` (applesmc `5A3B81D97F1C91FE86F89E1` on
  6.18, `C1A411C91A8153ACE885EA4` on 7.2; backlight `5F5B67A00A0F319FA8991DC`
  on both), `vermagic` and the `.text`, `.rodata`, `.data`, `.init.text` and
  `.exit.text` sections are identical. Only the embedded package version
  follows `pkgver`: `version` of `macbook91_backlight` and the `macbook91`
  tag of `applesmc` read 20261020.02 instead of 20261020.01.
- Runtime of the 20261020.02 build itself NOT_RUN, carried over from
  20261020.01: the package was not installed and its DKMS build not run by
  DKMS, the new modules were not loaded. The hw-verify results above are
  those of 20261020.01-1.
- Tests: `make check` 105 passed, 0 failed; with package contents 110
  passed, 0 failed; shellcheck clean; namcap 0 errors (8 dependency warnings).

## 20261020.01

No code change since 20261015.01; only packaged text. License: own work is
GPL-3.0-or-later, the module Makefiles and `dkms.conf` GPL-2.0-or-later,
`macbook91_backlight.c` and the applesmc copies GPL-2.0-only (GPLv2 section 3);
`LICENSE` and `LICENSES/` added. `macbook91_backlight.c`
changed in two comment lines only. README and `docs/FINDINGS.md` corrected;
the repository was translated from German to English. Install check on
2026-10-20: `pacman -U` of all five macbook91 packages exit 0, DKMS built
backlight and applesmc for 7.2.11-1-cachyos and 6.18.55-2-cachyos-lts, the
new modules were not loaded. Runtime checks of the new modules were NOT_RUN,
carried over from 20261015.01 (`macbook91-hw-verify` pass=26 warn=0 fail=0 on
7.2 after the boot of 2026-10-20 13:28).

## Earlier releases

20261013.01 to 20261015.01 are not part of this repository (20261015.01:
audit round 1, migrate/verify/scriptlet fixes; 20261014.01: charge limit
through `macbook91-applesmc`).
