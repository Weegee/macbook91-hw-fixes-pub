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
# Before: check that the distribution kernel of that series builds applesmc
# itself (CONFIG_SENSORS_APPLESMC=m) and ships no other driver for the SMC,
# such as macsmc-acpi in CachyOS 7.3: two drivers would drive the SMC ports at
# the same time (docs/FINDINGS.md). Afterwards by hand: git add
# upstream/<series>/applesmc.c, run make check, and build it with DKMS for a
# kernel of that series before a release. The README names no series; the
# pacman hook reports the list from the installed tree.
set -euo pipefail
PROG=${0##*/}
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH=$HERE/0001-applesmc-charge-limit-through-BCLM.patch
URL='https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/hwmon/applesmc.c?h='

err() { printf '%s: error: %s\n' "$PROG" "$*" >&2; }
usage_error() { err "$@"; printf 'Help: %s --help\n' "$PROG" >&2; exit 2; }
usage() {
	cat <<EOT
Usage: $PROG TAG

Add a kernel series to the applesmc replacement: fetch drivers/hwmon/applesmc.c
of the stable tag TAG from kernel.org, check that the patch applies with fuzz 0
and pin the copy in UPSTREAM.lock and dkms.conf. A series is pinned once.

Examples:
  $PROG v7.3.1

Options:
  -h, --help       show this help
  -V, --version    show the version of this repository

Environment:
  MACBOOK91_APPLESMC_SRC   a local copy of applesmc.c, used instead of the
                           network

Exit status:
  0  the series is pinned
  1  refused (already pinned, wrong source, patch does not apply), or the
     fetch failed
  2  usage error

Messages and the verbose file operations go to stderr; stdout stays empty.
Docs and bug reports: https://github.com/Weegee/macbook91-hw-fixes-pub
EOT
}
case ${1:-} in
-h | --help) usage; exit 0 ;;
-V | --version) printf '%s %s\n' "$PROG" "$(cat "$HERE/../../VERSION" 2>/dev/null || echo dev)"; exit 0 ;;
-?*) usage_error "unknown option '$1'" ;;
esac
[ $# -le 1 ] || usage_error "unexpected argument '$2'"

tag=${1:-}
[ -n "$tag" ] || usage_error "no tag given (for example v7.3.1)"
[[ $tag =~ ^v([0-9]+)\.([0-9]+)(\.[0-9]+)?$ ]] || usage_error "'$tag' is not a kernel tag like v7.3 or v7.3.1"
series=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}
dest=$HERE/upstream/$series/applesmc.c
if [ -e "$dest" ] || grep -q "^$series " "$HERE/UPSTREAM.lock"; then
	err "series $series is already pinned (a series is pinned once); nothing changed"
	exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
if [ -n "${MACBOOK91_APPLESMC_SRC:-}" ]; then
	cp -v "$MACBOOK91_APPLESMC_SRC" "$tmp/applesmc.c" >&2
else
	curl --fail --silent --show-error --location -o "$tmp/applesmc.c" "$URL$tag" ||
		{ err "cannot fetch drivers/hwmon/applesmc.c of $tag from kernel.org; check the tag and the network"; exit 1; }
fi
grep -q 'MODULE_DESCRIPTION("Apple SMC")' "$tmp/applesmc.c" ||
	{ err "$tag did not yield drivers/hwmon/applesmc.c; nothing changed"; exit 1; }
patch -s --dry-run --fuzz=0 -o /dev/null "$tmp/applesmc.c" "$PATCH" ||
	{ err "the patch does not apply with fuzz 0 to $tag; rework it first, nothing changed"; exit 1; }

sum=$(sha256sum "$tmp/applesmc.c" | cut -d' ' -f1)
install -Dvm644 "$tmp/applesmc.c" "$dest" >&2
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
grep -qxF "$line" "$tmp/dkms.conf" || { err "dkms.conf has no BUILD_EXCLUSIVE_KERNEL line to update; $dest and UPSTREAM.lock are already changed, undo them with git"; exit 1; }
cp -v "$tmp/dkms.conf" "$HERE/dkms.conf" >&2
printf '%s: note: pinned Linux %s (%s, sha256 %s)\n  Next:  git add %s && make check\n' "$PROG" "$series" "$tag" "$sum" "$dest" >&2
