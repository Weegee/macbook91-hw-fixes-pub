# Change the brightness

The DKMS module `macbook91_backlight` provides a backlight device with a perceptual curve
(CIE L*, 1001 levels) on top of the native `intel_backlight`; KDE prefers it over the linear one.
F1 and F2 change the brightness in 20 steps that look even, Shift+F1 and Shift+F2 in steps of
1 %.

It needs `acpi_backlight=native` ([migrate.md](migrate.md)) and takes effect after the next
reboot. To load it without a reboot (NOT VERIFIED for this version):

```fish
sudo modprobe macbook91_backlight
systemctl --user restart plasma-powerdevil
```
