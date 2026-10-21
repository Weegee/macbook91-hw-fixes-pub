# SPDX-License-Identifier: GPL-3.0-or-later
# Package targets. Run from the repository root.
#
#   make check           hermetic tests (tests/run-tests.sh)
#   make dist            reproducible source tarball dist/NAME-VERSION.tar
#   make install         what macbook91-hw-fixes installs; its package() is
#                        exactly `make PREFIX=/usr DESTDIR="$pkgdir" install`,
#                        run from that tarball
#   make srcinfo         regenerate packaging/arch/.SRCINFO
#   make arch-pkg        release build: the tarball's SHA256 must be the one
#                        pinned in packaging/arch/PKGBUILD
#   make arch-pkg-dev    build of an unreleased tree: tracked files as they are
#                        on disk, the pin replaced in the build copy only
#
# Packages are built in build/arch and copied to dist/. MAKEPKG_FLAGS passes
# options to makepkg (e.g. --syncdeps in CI).

NAME := macbook91-hw-fixes
VERSION := $(shell cat VERSION)
APPLESMC_PATCH := 0001-applesmc-charge-limit-through-BCLM.patch

PREFIX ?= /usr
DESTDIR ?=
MAKEPKG_FLAGS ?=

.PHONY: check install dist srcinfo arch-pkg arch-pkg-dev _arch-build

check:
	tests/run-tests.sh

install:
	install -Dm755 src/macbook91-hw-verify "$(DESTDIR)$(PREFIX)/bin/macbook91-hw-verify"
	install -Dm755 src/macbook91-hw-migrate "$(DESTDIR)$(PREFIX)/bin/macbook91-hw-migrate"
	install -Dm755 sleep/macbook91-lid-wake "$(DESTDIR)$(PREFIX)/lib/systemd/system-sleep/macbook91-lid-wake"
	install -Dm644 udev/60-macbook91-nvme-d3cold.rules "$(DESTDIR)$(PREFIX)/lib/udev/rules.d/60-macbook91-nvme-d3cold.rules"
	install -Dm644 kernel/macbook91_backlight.c "$(DESTDIR)$(PREFIX)/src/macbook91-backlight-$(VERSION)/macbook91_backlight.c"
	install -Dm644 kernel/Makefile "$(DESTDIR)$(PREFIX)/src/macbook91-backlight-$(VERSION)/Makefile"
	sed 's/@PKGVER@/$(VERSION)/' kernel/dkms.conf >kernel/dkms.conf.out
	install -Dm644 kernel/dkms.conf.out "$(DESTDIR)$(PREFIX)/src/macbook91-backlight-$(VERSION)/dkms.conf"
	rm -f kernel/dkms.conf.out
	set -e; d="$(DESTDIR)$(PREFIX)/src/macbook91-applesmc-$(VERSION)"; \
	for f in kernel/applesmc/upstream/*/applesmc.c; do \
		s=$$(basename $$(dirname $$f)); install -d "$$d/$$s"; \
		patch -s --fuzz=0 --no-backup-if-mismatch -o "$$d/$$s/applesmc.c" $$f kernel/applesmc/$(APPLESMC_PATCH); \
		chmod 644 "$$d/$$s/applesmc.c"; \
	done; \
	install -m644 kernel/applesmc/Makefile kernel/applesmc/$(APPLESMC_PATCH) kernel/applesmc/UPSTREAM.lock "$$d/"; \
	sed 's/@PKGVER@/$(VERSION)/' kernel/applesmc/dkms.conf >"$$d/dkms.conf"; \
	chmod 644 "$$d/dkms.conf"
	install -Dm644 README.md "$(DESTDIR)$(PREFIX)/share/doc/$(NAME)/README.md"
	install -Dm644 docs/FINDINGS.md "$(DESTDIR)$(PREFIX)/share/doc/$(NAME)/FINDINGS.md"

dist:
	python3 packaging/mkdist.py

srcinfo:
	cd packaging/arch && makepkg --printsrcinfo > .SRCINFO

# The release build. The tarball holds no PKGBUILD, so pinning its checksum
# there does not change the tarball.
arch-pkg: dist
	@want=$$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" packaging/arch/PKGBUILD); \
	have=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256); \
	if [ "$$want" != "$$have" ]; then \
		echo "arch-pkg: PKGBUILD sha256sums is $$want, tarball is $$have" >&2; \
		echo "arch-pkg: set sha256sums to $$have, make srcinfo, commit (--amend), rerun" >&2; \
		exit 1; \
	fi
	$(MAKE) --no-print-directory _arch-build

arch-pkg-dev:
	python3 packaging/mkdist.py --allow-dirty
	$(MAKE) --no-print-directory _arch-build PIN=$$(cut -d' ' -f1 dist/$(NAME)-$(VERSION).tar.sha256)

# makepkg extracts into $$srcdir without clearing it, so build/arch is
# recreated every time and makepkg runs with --cleanbuild.
_arch-build:
	rm -rf build/arch
	mkdir -p build/arch
	cp packaging/arch/PKGBUILD packaging/arch/$(NAME).install dist/$(NAME)-$(VERSION).tar build/arch/
	if [ -n "$(PIN)" ]; then \
		sed -i "s/^sha256sums=('[0-9a-f]*')/sha256sums=('$(PIN)')/" build/arch/PKGBUILD; \
	fi
	cd build/arch && makepkg --cleanbuild --force --noconfirm $(MAKEPKG_FLAGS)
	cp build/arch/$(NAME)-$(VERSION)-*.pkg.tar.zst dist/
