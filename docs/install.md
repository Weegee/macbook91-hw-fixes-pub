# Install, update and remove

## Prerequisites

- A MacBook9,1 with CachyOS or another Arch-based system.
- `base-devel`, `dkms` and the headers of every kernel you use: the package builds two DKMS
  modules. It pulls in `linux-cachyos-lts-headers` and with it `linux-cachyos-lts`.
- For the checkout route: a git checkout, not an unpacked tarball, because `make dist` needs it.

## Install from the release files

The short route is in the README. Details:

- `makepkg` needs `PKGBUILD`, `macbook91-hw-fixes.install` and the tarball
  `macbook91-hw-fixes-VERSION.tar`; `SHA256SUMS` lists the files to check.
- `sha256sum -c --ignore-missing SHA256SUMS` can exit 0 while the install file or the tarball is
  missing. Build only when all three read `OK`. Expected output (`.SRCINFO` is skipped, because
  GitHub serves it as `default.SRCINFO`):

  ```text
  PKGBUILD: OK
  macbook91-hw-fixes.install: OK
  STATUS.txt: OK
  macbook91-hw-fixes-VERSION.tar: OK
  ```

- When a release lists a ready-built package, install it with `sudo pacman -U PACKAGE` instead
  (PACKAGE is the file name). The packages are not signed.
- With your own pacman repository, add the package to it as usual.

## Build from a checkout

The release files of the checked-out version are in `release/VERSION/`; copy them to an empty
directory and follow the release route. To build from the source tree instead, in the root of
the checkout (`make arch-pkg` runs `make dist` itself; the package ends up in `build/arch/`):

```fish
make dist && make arch-pkg
sudo pacman -U build/arch/macbook91-hw-fixes-*.pkg.tar.zst
```

## Update and remove

NOT VERIFIED for this version: these commands change the system and were not run again for
release 20261102.01.

Update from a newer build, then show what the new version would change:

```fish
sudo pacman -U macbook91-hw-fixes-*.pkg.tar.zst
macbook91-hw-migrate plan
```

Applied migration steps stay after a removal, so undo them first
([migrate.md](migrate.md#undo-steps)), then remove the package:

```fish
sudo pacman -R macbook91-hw-fixes
```

Removing the package resets the charge limit to 100 %.
