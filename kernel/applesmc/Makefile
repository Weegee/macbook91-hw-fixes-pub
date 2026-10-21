# SPDX-License-Identifier: GPL-2.0-or-later
# Out-of-tree build of applesmc with the charge limit (see the patch).
#
#   make sources   checkout only: writes <series>/applesmc.c from
#                  upstream/<series>/applesmc.c and the patch (fuzz 0)
#   make           builds applesmc.ko in build/ for KDIR, from the source of
#                  KDIR's kernel series; the installed DKMS tree carries the
#                  patched <series>/applesmc.c files already
#
# Only public kernel headers are used, so the installed headers package of
# each kernel is all DKMS needs.

KDIR ?= /lib/modules/$(shell uname -r)/build
PKGVER ?= 0
PWD := $(shell pwd)
PATCH := 0001-applesmc-charge-limit-through-BCLM.patch
SERIES := $(shell sed -n 's/.*UTS_RELEASE "\([0-9]*\.[0-9]*\).*/\1/p' $(KDIR)/include/generated/utsrelease.h 2>/dev/null)

# A clang-built kernel (CachyOS) takes clang-only flags; build with the same
# compiler family as the target kernel's own .config says.
ifeq ($(shell grep -qx 'CONFIG_CC_IS_CLANG=y' $(KDIR)/.config 2>/dev/null && echo clang),clang)
  LLVM ?= 1
  export LLVM
endif

.PHONY: all sources clean

all:
	@test -r "$(KDIR)/Module.symvers" || { echo "ERROR: no complete kernel tree at $(KDIR) (headers installed?)"; exit 1; }
	@test -n "$(SERIES)" -a -r "$(PWD)/$(SERIES)/applesmc.c" || \
	  { echo "ERROR: no patched applesmc source for Linux $(SERIES) (in a checkout: make sources)"; exit 1; }
	rm -rf build
	mkdir build
	cp $(SERIES)/applesmc.c build/
	echo 'obj-m += applesmc.o' >build/Kbuild
	echo 'ccflags-y += -DMB91_VERSION=\"$(PKGVER)\"' >>build/Kbuild
	$(MAKE) -C $(KDIR) M=$(PWD)/build modules

sources:
	@for f in upstream/*/applesmc.c; do \
	  s=$$(basename $$(dirname $$f)); mkdir -p $$s; \
	  patch -s --fuzz=0 --no-backup-if-mismatch -o $$s/applesmc.c $$f $(PATCH) || exit 1; \
	done

clean:
	rm -rf build
