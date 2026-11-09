# Changelog

Versions have the form YYYYMMDD.NN (release date, NN counts releases that
day). The release tag is v<version>. The per-release record (what was
measured, the package checksum) is `release/<version>/STATUS.txt`; the
release tool keeps at most the two newest releases in the tree, older releases
are not part of this repository.

## 20261109.01 (2026-11-09)

**The documentation follows the house HIG (documentation part). The modules, the
hook file, the udev rule, the migration steps and the tools are unchanged.**

- README: restructured in the house order: what the package does, Installation
  (prerequisites, install from the release files, build from a checkout, apply
  the migration steps), Usage, Kernel series, Verification status, Configuration,
  Documentation, Bug reports, AI assistance, License and See also. Installation
  and hibernate are numbered steps with one action each and every command in
  its own fish block; the warning about `--ignore-missing` stands before the
  step it concerns; every command that was not run for this release is marked
  NOT VERIFIED. New: an example of the `macbook91-hw-verify` output, a Bug reports
  section and the See also list of the three driver packages.
- README correction: `sha256sum -c --ignore-missing SHA256SUMS` skips only
  `.SRCINFO`, not `STATUS.txt`; the four files of a release read `OK` (VERIFIED
  against the public release 20261102.01).
- Changelog: every heading carries the ISO date, and incompatible changes come
  first and start with **Incompatible:**.
- Tests: none added; no code changed.

## 20261102.01 (2026-11-02)

**Exit statuses, log levels and message layout of the text interfaces follow
the house HIG (text part), which replaces the separate text HIG; the rule IDs
are the same. The modules, the hook file, the udev rule and the migration
steps are unchanged.**

**Incompatible:** three exit statuses changed. Check scripts that read them
(interface changes, STA-4; what scripts parse stays as it was):

- `macbook91-hw-migrate apply ID...`: a step that is named and cannot be
  applied because it is `foreign` or `unsupported` now ends with exit status 1
  and `macbook91-hw-migrate: error: step ID not applied: ...` on stderr, with
  the line `Check the state:  macbook91-hw-migrate status`. It used to print
  `skip ID: ...` on stdout and exit 0 (KAN-2). `apply` without names still
  only skips such a default step and exits 0; a step that is already `applied`
  or `done` is still a success.
- A missing root is exit status 1, not the usage error 2 (KAN-3), for
  `apply` and `rollback` of `macbook91-hw-migrate` and for
  `tools/dev-backlight-check.sh` and `tools/dev-suspend-series.sh` (these two
  also exit 1 for a missing `intel_backlight`, a missing default route and an
  empty `SUDO_USER`). Exit status 2 now means a usage error only; the help
  texts say so.
- `kernel-series`: a missing DKMS tree or a malformed series list is exit
  status 1 (it was 2), and with `--hook` exit status 0 with the error on
  stderr, as the help always said: a failing PostTransaction hook makes pacman print
  an error after an otherwise good transaction. Abweichung von KAN-2 und FEH-6: `--hook` exits 0
  even when it could not do its job, because it only advises.

Other interface changes:

- `macbook91-hw-migrate rollback ID` for a step that is not applied prints
  `nothing to roll back: ID` and exits 0; `rollback` without names prints
  `nothing to roll back` when nothing was applied. It was silent (ERF-2).
- `sleep/macbook91-lid-wake`: "could not switch LID0 wake on" is logged with
  priority `user.warning` (it was `user.info`). The `pre` branch now reads the
  wake state back like `post` does and logs `user.warning` when the write did
  not take effect, instead of reporting a switch that did not happen
  (ERF-2, LOG-3).
- Install scriptlet: the next-steps lines are wrapped at 80 columns (TYP-2);
  the commands are on lines of their own and can be copied as before.
- Tests: one check per change above, each of them fails against the old code;
  the verify check for an untested backlight series no longer depends on the
  series of the running kernel (it failed on 7.3).

## 20261026.02 (2026-10-26)

**Text interfaces follow the house text guidelines (HIG): help, version, error
and warning messages, colour and exit codes. The modules, the hook file, the
udev rule and the migration steps are unchanged.**

**Incompatible:** on a machine other than a MacBook9,1 the message of
`macbook91-hw-verify` goes to stderr, and the report of the pacman hook
(`kernel-series --hook`) and the messages of the install scriptlet have a new
form on stderr. Check scripts that read them (details below).

Interface changes (STA-4); what scripts parse stays as it was:

- `macbook91-hw-verify`: new `-h`/`--help`, `-V`/`--version`, `--color=WHEN`,
  `--no-color`; colour only on the PASS/WARN/FAIL keywords, by the order
  `--color`, `MACBOOK91_HW_VERIFY_COLOR`, `NO_COLOR`, `FORCE_COLOR`,
  `TERM=dumb`, terminal check. The PASS/WARN/FAIL/INFO lines and the RESULT
  line are unchanged. On a machine other than a MacBook9,1 the message
  `macbook91-hw-verify: error: this machine is ..., not an Apple MacBook9,1`
  now goes to stderr (before: an INFO line on stdout); the exit code stays 3.
- `macbook91-hw-migrate`: new `-h`/`--help`, `-V`/`--version`; an unknown
  option or command, a missing step ID and extra arguments are usage errors
  (exit 2, `Help: macbook91-hw-migrate --help`); step IDs are checked before
  the root check; the root error names the command to run with sudo; SIGINT
  and SIGTERM end the run with 130/143 and say how to check the state. The
  `status` and `plan` lines are unchanged. Abweichung von TYP-3: `status` has
  no header line, because `macbook91-hw-verify` and scripts read it. Abweichung
  von ARG-4 und GEF-3: the dry run is the command `plan`.
- Pacman hook (`kernel-series --hook`): the report goes to stderr in the form
  `macbook91-hw-fixes: warning: ...` with indented continuation lines and
  `macbook91-hw-fixes: note: ...`; the WARNING banner and its blank lines are
  gone. `--applesmc` and `--backlight` print the same reasons and exit codes.
  `kernel-series` gains `-h`/`--help` and `-V`/`--version`.
- Install scriptlet: every `:: macbook91-hw-fixes: ...` message is now
  `macbook91-hw-fixes: note: ...` or `... warning: ...` on stderr, with the
  next steps as commands that can be copied.
- `/usr/bin/macbook91-hw-verify` and `-migrate` carry the package version
  (`--version` prints `macbook91-hw-verify 20261026.02`).
- Repository tools: `kernel/applesmc/add-series.sh`, `tools/dev-backlight-check.sh`,
  `tools/dev-suspend-series.sh`, `packaging/promote-release.sh` and
  `packaging/mkdist.py` gain `-h`/`--help` and `-V`/`--version`; arguments are
  checked before the root check; errors read `program: error: ...` with a
  remedy and exit 2 for usage errors. `add-series.sh` writes its progress and
  result to stderr and nothing to stdout. `promote-release.sh -n` runs the
  checks and changes nothing; an interrupt removes a half-promoted release.
  The cycle, report and RESULT lines of the two dev tools are unchanged.
- `sleep/macbook91-lid-wake` logs with `logger -p user.info`.
- Tests: help, version and usage-error checks for all tools, the colour
  precedence of the verifier, the hook output form, scriptlet messages,
  `promote-release.sh -n`.

## 20261026.01 (2026-10-26)

**Kernel series: the LTS kernel is the default, and a pacman hook reports
every installed kernel the two modules do not cover. CachyOS 7.3 gets no
charge limit from this package, because that kernel brings its own Apple SMC
driver. The module sources and the udev rule are unchanged.**

- New `/usr/lib/macbook91-hw-fixes/kernel-series` and the pacman hook
  `71-macbook91-hw-fixes-series.hook` (after `70-dkms-install.hook`, on kernel
  installs and upgrades and on this package): a WARNING block for each
  installed kernel of a series without an applesmc source, one note line for a
  series `macbook91_backlight` is not tested on (`kernel/TESTED-SERIES`, new:
  6.18 and 7.2). It builds nothing and never stops the transaction. The
  install scriptlet and `macbook91-hw-verify` ask the same script.
- `macbook91-hw-verify` on such a kernel: names the kernel's own SMC driver
  (`macsmc-acpi`, `applesmc` or none) instead of claiming that in-tree applesmc
  runs; a `charge_control_end_threshold` of another power supply (the kernel's
  `macsmc-battery`) is reported as INFO, not passed; an untested backlight
  series is an INFO line. The running release is read from
  `/proc/sys/kernel/osrelease`.
- The package depends on `linux-cachyos-lts-headers` (pulls in
  `linux-cachyos-lts`); `linux-cachyos-headers` is optional. Both stay in
  `package()`, so a build host without the CachyOS repositories can build the
  package. `findutils` is listed for `kernel-series`.
- No 7.3 series for `macbook91-applesmc`: CachyOS 7.3.0-1 turns
  `CONFIG_SENSORS_APPLESMC` off, and its kernel brings `macsmc-acpi`, which
  drives the same SMC ports without reserving them; the two must not run at
  once (`docs/FINDINGS.md`). The patch applies to `v7.3` with fuzz 0 and
  builds against the 7.3.0-4 headers; that is not the obstacle. The series
  6.18 and 7.2 stay: the unchanged patch applies to both and builds against
  the 6.18.55-2 and 7.2.11-1 headers.
- README: a Kernel series section replaces the copies of the series list;
  `add-series.sh` names the second-driver check.
- Tests: kernel-series modes and hook file, the dkms.conf regex equals the
  upstream directories exactly, a fake 7.3 kernel with `macsmc-acpi` in the
  verifier, package contents.

## 20261021.01 (2026-10-21)

**First release prepared for the public repository: changes to the shipped
scripts and the package dependencies, plus documentation and licensing text.
The kernel modules and the udev rule are unchanged.**

Commit hashes named in entries up to 20261021.01 belong to the maintainer's private history and do not exist in the public repository.

- **Incompatible:** the two `macbook91-hw-migrate` steps that deleted earlier
  hand-installed files (an NVMe udev rule and a sleep hook of a previous
  setup) are removed, with the matching check for that hook in `macbook91-lid-wake`, and the
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
- **Incompatible:** the package stands on its own: it no longer depends on
  `macbook91-cs4208-dkms`, `macbook91-facetimehd-dkms` and
  `macbook91-wireless-dkms`. `macbook91-hw-verify` checks those packages and
  their DKMS modules only where they are installed (INFO otherwise, no FAIL),
  no longer checks for the camera firmware package (the camera package checks
  its firmware itself), and `--deep` skips a verify tool that is not installed.
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

## 20261020.02 (2026-10-20)

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

## 20261020.01 (2026-10-20)

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
