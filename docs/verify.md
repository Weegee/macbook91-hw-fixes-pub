# Check the state of the machine

```fish
macbook91-hw-verify
```

It is read-only (as root it adds the NVMe health log) and checks packages, DKMS modules, charge
limit, migration steps, brightness, wake sources, NVMe, keyboard, light and the hibernate
configuration. `--deep` also runs the verify tools of the driver packages that are installed.

Output on the test machine (kernel 7.3.3-1-cachyos, package 20261102.01-1, 2026-11-09). Lines
are left out where marked `[...]`; the full output has 29 lines:

```text
PASS dmi: Apple MacBook9,1
PASS package: macbook91-hw-fixes 20261102.01-1
[...]
PASS dkms: macbook91-backlight installed for 7.3.3-1-cachyos
WARN dkms: macbook91-applesmc not built: kernel 7.3.3-1-cachyos (Linux 7.3) is not a series macbook91-applesmc has a source for (6.18 7.2), so the charge limit of this package is not built for it. [...]
[...]
WARN charge limit: this package's charge limit is not built for kernel 7.3.3-1-cachyos; a limit set earlier presumably stays in the SMC; boot the LTS kernel (linux-cachyos-lts) to read or change it
PASS migration: backlight-native applied
INFO migration: hibernate not applied (optional)
PASS backlight: native intel_backlight, 1389 levels, 0 switches the backlight off
PASS nvme: d3cold_allowed=0, its root port stays in D0 during suspend
[...]
RESULT pass=21 warn=2 fail=0
```

Both warnings reported the missing charge limit on kernel 7.3.3, before Linux 7.3 was pinned
([kernel-series.md](kernel-series.md)).

## Wake and NVMe

- The udev rule `60-macbook91-nvme-d3cold.rules` keeps the NVMe's PCIe port in D0 during
  suspend (a known workaround for an NVMe that is missing after wakeup). It takes effect right
  after installation.
- The sleep hook `macbook91-lid-wake` keeps a suspend with the lid open from waking up again
  right away when the lid is closed. With the lid open, the power button wakes the machine
  (keyboard and touchpad cannot wake it under Linux); with the lid closed, opening it.

## Use it in scripts

- One `PASS`, `WARN`, `FAIL` or `INFO` line per check, then `RESULT pass=N warn=N fail=N`.
  Exit 0 without a `FAIL`, 1 with one, 2 on a usage error, 3 on another model.
- Errors read `program: error: what happened, why, what to do` on stderr; a usage error ends
  with 2 and the line `Help: program --help`.
- Colour only on a terminal, only on the keywords. `--color=auto|always|never`, `--no-color`
  and the variables `MACBOOK91_HW_VERIFY_COLOR`, `NO_COLOR`, `FORCE_COLOR` set it; the order is
  `--color`, `MACBOOK91_HW_VERIFY_COLOR`, `NO_COLOR`, `FORCE_COLOR`, `TERM=dumb`, a terminal
  check.
