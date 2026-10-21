# SPDX-License-Identifier: GPL-2.0-or-later
# Out-of-tree build of macbook91_backlight (see macbook91_backlight.c).
# Only public kernel headers are used, so the installed headers package of
# each kernel is all DKMS needs.

obj-m += macbook91_backlight.o
PKGVER ?= 0
ccflags-y += -DMB91_VERSION=\"$(PKGVER)\"

KDIR ?= /lib/modules/$(shell uname -r)/build
PWD  := $(shell pwd)

# A clang-built kernel (CachyOS) takes clang-only flags; build with the same
# compiler family as the target kernel's own .config says.
ifeq ($(shell grep -qx 'CONFIG_CC_IS_CLANG=y' $(KDIR)/.config 2>/dev/null && echo clang),clang)
  LLVM ?= 1
  export LLVM
endif

all:
	@test -r "$(KDIR)/Module.symvers" || { echo "ERROR: no complete kernel tree at $(KDIR) (headers installed?)"; exit 1; }
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
