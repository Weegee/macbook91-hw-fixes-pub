#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the package's source tarball, byte-reproducibly.

Output: dist/NAME-VERSION.tar and .sha256 (or --out DIR). The tarball is what
packaging/arch/PKGBUILD pins, so it has to be the same bytes every time it is
built from the same inputs.

Contents, under NAME-VERSION/, laid out as in the repository so the Makefile's
`install` target works in both places: exactly the files in FILES plus the
upstream applesmc copies matching UPSTREAM, each of which must be tracked.
Unless --allow-dirty, a tracked file with uncommitted changes is refused,
because a release tarball holds committed content only.

Entries are sorted, owned by 0:0, mode 0755 for executables and 0644
otherwise, all with mtime 0. The tar is not compressed: gzip output depends on
the zlib implementation, and the pinned checksum has to hold on every machine.
Same scheme as packaging/mkdist.py in macbook91-facetimehd and -cs4208.
"""

from __future__ import annotations

import hashlib
import io
import os
import subprocess
import sys
import tarfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "macbook91-hw-fixes"
FILES = (
    "src/macbook91-hw-migrate",
    "src/macbook91-hw-verify",
    "sleep/macbook91-lid-wake",
    "kernel/macbook91_backlight.c",
    "kernel/Makefile",
    "kernel/dkms.conf",
    "kernel/applesmc/0001-applesmc-charge-limit-through-BCLM.patch",
    "kernel/applesmc/Makefile",
    "kernel/applesmc/UPSTREAM.lock",
    "kernel/applesmc/dkms.conf",
    "udev/60-macbook91-nvme-d3cold.rules",
    "docs/FINDINGS.md",
    "Makefile",
    "VERSION",
    "LICENSE",
    "LICENSES/GPL-2.0-only.txt",
    "LICENSES/GPL-2.0-or-later.txt",
    "LICENSES/GPL-3.0-or-later.txt",
    "README.md",
)
# One pristine applesmc.c per supported kernel series; a new series is a new
# directory, so these come from git instead of FILES.
UPSTREAM = "kernel/applesmc/upstream/*/applesmc.c"


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True, text=True).stdout


def fail(msg: str) -> int:
    print(f"mkdist: {msg}", file=sys.stderr)
    return 1


def sha256(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def main(argv: list[str]) -> int:
    allow_dirty = "--allow-dirty" in argv
    out_dir = os.path.join(ROOT, "dist")
    if "--out" in argv:
        out_dir = os.path.abspath(argv[argv.index("--out") + 1])
    with open(os.path.join(ROOT, "VERSION"), encoding="ascii") as fh:
        version = fh.read().strip()

    if not allow_dirty and git("status", "--porcelain", "--untracked-files=no").strip():
        return fail("working tree has uncommitted changes; commit first (or --allow-dirty)")

    tracked = set(f for f in git("ls-files", "-z", "--", *FILES).split("\0") if f)
    for f in FILES:
        if f not in tracked:
            return fail(f"{f} is not tracked")

    upstream = [f for f in git("ls-files", "-z", "--", UPSTREAM).split("\0") if f]
    if not upstream:
        return fail(f"no tracked {UPSTREAM}")

    files = sorted({*FILES, *upstream})
    prefix = f"{NAME}-{version}"
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as tar:
        parents = {os.path.dirname(f) for f in files} - {""}
        all_dirs = sorted({"/".join(d.split("/")[: i + 1]) for d in parents for i in range(d.count("/") + 1)})
        for d in ["", *all_dirs]:
            info = tarfile.TarInfo(f"{prefix}/{d}".rstrip("/"))
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            info.mtime = 0
            tar.addfile(info)
        for f in files:
            path = os.path.join(ROOT, f)
            with open(path, "rb") as fh:
                data = fh.read()
            info = tarfile.TarInfo(f"{prefix}/{f}")
            info.size = len(data)
            info.mode = 0o755 if os.stat(path).st_mode & 0o111 else 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
    os.makedirs(out_dir, exist_ok=True)
    target = os.path.join(out_dir, f"{prefix}.tar")
    with open(target, "wb") as fh:
        fh.write(raw.getvalue())
    digest = sha256(target)
    with open(target + ".sha256", "w", encoding="ascii") as fh:
        fh.write(f"{digest}  {prefix}.tar\n")
    print(f"{digest}  {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
