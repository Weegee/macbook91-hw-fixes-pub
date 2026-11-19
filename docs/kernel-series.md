# Kernel series

Supported are the CachyOS LTS kernel (`linux-cachyos-lts`), the default, and the current series
of `linux-cachyos` where the modules support it. With `linux-cachyos-headers` installed as well,
DKMS also builds for `linux-cachyos`.

- `macbook91-applesmc` (the charge limit) is built only for the series pinned in
  `kernel/applesmc/UPSTREAM.lock`.
- `macbook91_backlight` is built for every kernel; `kernel/TESTED-SERIES` lists the series it was
  checked on.

After every kernel installation or upgrade the pacman hook `71-macbook91-hw-fixes-series.hook`
checks the installed kernels. For a series without an applesmc source it warns on stderr: no
charge limit of this package there, boot the LTS kernel. For a series the backlight was not
tested on it prints a note. The hook builds nothing and never stops the transaction.

CachyOS's Linux 7.3 builds no applesmc: it brings its own Apple SMC driver, `macsmc-acpi`. The
two must not drive the SMC at the same time, so `macbook91-applesmc` is not built for 7.3
(`docs/FINDINGS.md`). Whether the charge limit of the kernel's `macsmc-power` works on the
MacBook9,1 is NOT VERIFIED.

Ask by hand whether a kernel has an applesmc source (exit 0 if covered, 1 if not; VERIFIED
2026-11-09 on kernel 7.3.3, exit 1), and check all installed kernels as the hook does:

```fish
/usr/lib/macbook91-hw-fixes/kernel-series --applesmc "$(uname -r)"
/usr/lib/macbook91-hw-fixes/kernel-series --hook
```
