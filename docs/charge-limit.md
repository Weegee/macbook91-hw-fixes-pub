# Read and set the charge limit

The DKMS module `macbook91-applesmc` replaces the kernel driver `applesmc` with the same source
plus a patch of its own. It offers the SMC key `BCLM` as the battery's
`charge_control_end_threshold`, so you can also set the limit in the Plasma settings (**Power
Management**; the Plasma interface itself is NOT VERIFIED). Measured: above the limit, charging
stops at once.

Read the limit in percent. The file exists only on kernels the module is built for
([kernel-series.md](kernel-series.md)); on kernel 7.3.3 the command reports that the file does
not exist (VERIFIED 2026-11-09):

```fish
cat /sys/class/power_supply/BAT0/charge_control_end_threshold
```

Set the limit; replace PERCENT with a value from 10 to 100 (NOT VERIFIED for this version, it
changes the battery):

```fish
echo PERCENT | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
```

According to reports, the SMC keeps the value until an SMC reset, also across reboots (NOT
VERIFIED on the test MacBook9,1). Removing the package resets the limit to 100 %.

On any other kernel this package offers no charge limit, but one set earlier presumably stays in
effect; the pacman hook and `macbook91-hw-verify` then warn. Before you move to a new kernel
series, set the limit to 100 %, or boot the LTS kernel (`linux-cachyos-lts`) to change it.
