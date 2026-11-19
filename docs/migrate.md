# Apply and undo the migration steps

`macbook91-hw-migrate` changes the kernel command line and related files. Every step is backed
up under `/var/lib/macbook91-hw-fixes/` (the backups stay after `rollback`) and only touches
files of the shape it expects; anything else is reported as `foreign` and left alone.

| Step | What it does | Default |
| --- | --- | --- |
| `backlight-native` | kernel parameter `acpi_backlight=native`: full, fine brightness, 0 = off | yes |
| `keyboard-iso` | `applespi iso_layout=1`, only for an ISO keyboard (for example German) | no |
| `hibernate` | swap file on the Btrfs subvolume `@swap` behind zram, `resume=` and `resume_offset=` | no |

## Apply the default step

NOT VERIFIED for this version: steps 2 and 3 change the system and were not run again for
release 20261102.01.

1. Show what `apply` would change; the command changes nothing:

   ```fish
   macbook91-hw-migrate plan
   ```

2. Apply the default step. Add `keyboard-iso` to the command for an ISO keyboard:

   ```fish
   sudo macbook91-hw-migrate apply
   ```

3. Reboot so the kernel parameter takes effect:

   ```fish
   systemctl reboot
   ```

4. Check the result; `RESULT` should report `fail=0` ([verify.md](verify.md)):

   ```fish
   macbook91-hw-verify --deep
   ```

`macbook91-hw-migrate status` shows `ID  STATE  description` per step. `STATE` is `applied`,
`pending`, `optional`, `done`, `partial`, `foreign` or `unsupported`.

## Set up hibernate

Hibernate and resume have never run on the test machine: every command here is NOT VERIFIED
(`docs/test-status.json`: `hibernate` BLOCKED, the test needs someone at the machine for the
LUKS passphrase). Only the hermetic tests of the migration ran. The swap file has RAM size and
priority -2; on resume the initramfs asks for the LUKS passphrase as at boot.

> **Warning:** After a hibernate, do not boot any other entry (snapshot, LTS kernel, another
> system). The saved state of the hibernated session is lost. Resume from the entry you
> hibernated from.

```fish
sudo macbook91-hw-migrate apply hibernate
systemctl reboot
systemctl hibernate
```

Reboot before the first hibernate; hibernate works only after it.

## Undo steps

NOT VERIFIED for this version: these commands change the system.

```fish
sudo macbook91-hw-migrate rollback
sudo macbook91-hw-migrate rollback backlight-native
sudo macbook91-hw-migrate rollback hibernate
```

The first undoes all steps (reboot afterwards), the others one step each.

## More help

`macbook91-hw-migrate --help` shows one screen, `--help all` the full help with the output
format and every exit status.
