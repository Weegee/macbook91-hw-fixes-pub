#!/usr/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# add-series.sh - adds a kernel series to the applesmc replacement: fetches
# drivers/hwmon/applesmc.c of a stable tag from kernel.org, refuses unless the
# patch applies with fuzz 0, and pins the copy in UPSTREAM.lock and dkms.conf.
# Development tool, not packaged. Needs the network unless
# MACBOOK91_APPLESMC_SRC names a local copy of applesmc.c (tests).
#
#   kernel/applesmc/add-series.sh v7.3.1
#
# Afterwards by hand: git add upstream/<series>/applesmc.c, name the series in
# README.md (Charge limit), run make check, and build it with DKMS for a kernel
# of that series before a release.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH=$HERE/0001-applesmc-charge-limit-through-BCLM.patch
URL='https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/hwmon/applesmc.c?h='

tag=${1:-}
[[ $tag =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] || { echo "usage: add-series.sh vX.Y[.Z]" >&2; exit 2; }
series=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}
dest=$HERE/upstream/$series/applesmc.c
if [ -e "$dest" ] || grep -q "^$series " "$HERE/UPSTREAM.lock"; then
	echo "refusing: series $series is already pinned (a series is pinned once)" >&2
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -n "${MACBOOK91_APPLESMC_SRC:-}" ]; then
	cp -v "$MACBOOK91_APPLESMC_SRC" "$tmp/applesmc.c"
else
	curl --fail --silent --show-error --location -o "$tmp/applesmc.c" "$URL$tag"
fi
grep -q 'MODULE_DESCRIPTION("Apple SMC")' "$tmp/applesmc.c" ||
	{ echo "refusing: $tag did not yield drivers/hwmon/applesmc.c" >&2; exit 1; }
patch -s --dry-run --fuzz=0 -o /dev/null "$tmp/applesmc.c" "$PATCH" ||
	{ echo "refusing: the patch does not apply with fuzz 0 to $tag; rework it first" >&2; exit 1; }

sum=$(sha256sum "$tmp/applesmc.c" | cut -d' ' -f1)
install -Dvm644 "$tmp/applesmc.c" "$dest"
printf '# %s fetched on %s\n%s %s %s %s\n' "$series" "$(date +%F)" \
	"$series" "$tag" "$sum" "upstream/$series/applesmc.c" >>"$HERE/UPSTREAM.lock"

# BUILD_EXCLUSIVE_KERNEL lists exactly the series in upstream/.
list=""
for d in "$HERE"/upstream/*/; do
	s=$(basename "$d")
	list=${list:+$list|}${s//./\\.}
done
line=$(printf 'BUILD_EXCLUSIVE_KERNEL="^(%s)\\."' "$list")
L=$line awk '/^BUILD_EXCLUSIVE_KERNEL=/ {print ENVIRON["L"]; next} {print}' "$HERE/dkms.conf" >"$tmp/dkms.conf"
grep -qxF "$line" "$tmp/dkms.conf" || { echo "refusing: dkms.conf has no BUILD_EXCLUSIVE_KERNEL line" >&2; exit 1; }
cp -v "$tmp/dkms.conf" "$HERE/dkms.conf"
echo "pinned Linux $series ($tag, sha256 $sum); now: git add $dest, update README.md, make check"
