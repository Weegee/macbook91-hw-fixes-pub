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

Linux 7.3 (pinned from v7.3.5 on 2026-11-23): CachyOS 7.3.0 switched applesmc off and shipped
its own Apple SMC driver, `macsmc-acpi`; the 7.3.5-2 kernel has `CONFIG_SENSORS_APPLESMC=m`
again and ships `applesmc` and `macsmc-acpi` side by side (VERIFIED: kernel config and module
tree on the test machine, 2026-11-23). The charge limit patch applies to v7.3.5 with fuzz 0 and
the patched source builds against the 7.3.5-2 headers (VERIFIED offline, not installed). NOT
VERIFIED: that the DKMS build loads on 7.3.5, that the charge limit works there, and which of
the two drivers binds the SMC first. Both can drive the SMC ports at the same time without a
common lock (`docs/FINDINGS.md`, section Kernel 7.3); whether to keep `macsmc-acpi` from loading
on 7.3 is open.

Ask by hand whether a kernel has an applesmc source (exit 0 if covered, 1 if not; VERIFIED
2026-11-09 on kernel 7.3.3, exit 1), and check all installed kernels as the hook does:

```fish
/usr/lib/macbook91-hw-fixes/kernel-series --applesmc "$(uname -r)"
/usr/lib/macbook91-hw-fixes/kernel-series --hook
```
