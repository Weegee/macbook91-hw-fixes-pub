Structure version: 20261026.01

Layout rules for this repository; the sibling packages macbook91-cs4208,
macbook91-wireless and macbook91-facetimehd follow the same layout.

src/                the packaged tools: macbook91-hw-migrate and
                    macbook91-hw-verify, installed verbatim to /usr/bin;
                    kernel-series (which kernel series the two modules cover),
                    installed to /usr/lib/macbook91-hw-fixes/ with its
                    version filled in; macbook91-hw-fixes-series.hook, the
                    pacman hook that runs it, installed as
                    /usr/share/libalpm/hooks/71-macbook91-hw-fixes-series.hook.
udev/               packaged udev rules, installed to /usr/lib/udev/rules.d.
sleep/              packaged systemd-sleep hook, installed to
                    /usr/lib/systemd/system-sleep.
kernel/             DKMS module macbook91_backlight (perceptual backlight),
                    installed to /usr/src/macbook91-backlight-<VERSION>, with
                    TESTED-SERIES (the kernel series it was checked on).
kernel/applesmc/    DKMS replacement for in-tree applesmc (charge limit):
                    upstream/<series>/applesmc.c pristine kernel.org copies
                    pinned in UPSTREAM.lock, one own patch applied with fuzz 0
                    at `make install`, installed to
                    /usr/src/macbook91-applesmc-<VERSION>/<series>/.
                    add-series.sh <tag> pins a further series (fetches from
                    kernel.org, refuses unless the patch applies; not packaged).
packaging/          mkdist.py (reproducible source tarball), promote-release.sh
                    (dist/ -> release/<pkgver>/, sealed; publishes nothing).
packaging/arch/     PKGBUILD (macbook91-hw-fixes, arch any), .SRCINFO and the
                    install scriptlet. Not part of the source tarball, which is
                    what lets the PKGBUILD pin the tarball's checksum.
LICENSE, LICENSES/  license texts: LICENSE is the GPL-3.0 (own work by default),
                    LICENSES/<SPDX-ID>.txt holds every license in use, the
                    GPL-3.0 included (GPL-2.0-only: applesmc copies, their
                    patch, macbook91_backlight.c; GPL-2.0-or-later: the
                    modules' Makefiles and dkms.conf). Own files with comment
                    syntax carry an SPDX-License-Identifier line; README.md
                    maps all paths.
Makefile, VERSION   the package contract: `make dist` writes
                    dist/NAME-VERSION.tar, `make install` is package(),
                    `make arch-pkg` builds against the pinned checksum,
                    `make check` runs the tests. VERSION is YYYYMMDD.NN;
                    pkgver and the tag v<VERSION> equal it.
tests/              run-tests.sh: hermetic (no root, hardware or network).
tools/              development helpers for the test machine, not packaged
                    (dev-suspend-series.sh, dev-backlight-check.sh).
docs/               FINDINGS.md (packaged), PLAN.md, CHANGELOG.md,
                    coverage.json, test-status.json.
release/<pkgver>/   promoted releases (PKGBUILD, .SRCINFO, scriptlet, source
                    tarball, STATUS.txt, SHA256SUMS); promote-release.sh keeps
                    the two newest, older releases are not part of this
                    repository. A built package is not tracked; a release may
                    list one as an asset.
dist/, build/       gitignored output.

Local working files are not described here.

Never tracked: serial numbers, MAC addresses, SSIDs, LUKS UUIDs, tokens.
