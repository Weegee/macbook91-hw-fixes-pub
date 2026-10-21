#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# promote-release.sh - copy a built package into release/<pkgver>/ (scheme of
# macbook91-cs4208 and macbook91-wireless). It does not commit, tag, push or
# publish anything.
#
# SHA256SUMS covers exactly the files the repository tracks; the checksum of
# the built package (gitignored; makepkg output differs per machine, so the
# checksum is informational) is recorded in STATUS.txt.
#
#   promote-release.sh                  promote the version in the PKGBUILD
#   promote-release.sh --seal <version> redo SHA256SUMS after STATUS.txt,
#                                       which it covers, has been filled in
#   promote-release.sh --gate           run the local gate alone (below)
#
# Optional local gate: when the checkout has an extra check directory (test
# scripts under tests/ and an export guard), promotion also runs them over what
# a commit would carry, and removes the new release directory again when
# either fails. A checkout without that directory skips the gate.
#
# MACBOOK91_RELEASE_ROOT replaces the repository root (tests).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${MACBOOK91_RELEASE_ROOT:-$(cd "$HERE/.." && pwd)}"
ARCH="$ROOT/packaging/arch"

TRACKED_FILES='PKGBUILD .SRCINFO macbook91-hw-fixes.install STATUS.txt'
seal() { # seal DIR
	local src="" f
	for f in "$1"/*.tar; do
		[ -e "$f" ] && { src=$(basename "$f"); break; }
	done
	[ -n "$src" ] || { echo "no source tarball in $1" >&2; return 1; }
	# shellcheck disable=SC2086 # word splitting of the file list is intended
	(cd "$1" && sha256sum -- $TRACKED_FILES "$src" >SHA256SUMS)
	echo "sealed $1/SHA256SUMS over: $TRACKED_FILES $src"
}

# The local gate is optional: it runs only in a checkout that has the extra
# check directory and is skipped otherwise. The directory is found by glob so
# that this script does not carry its literal name.
PRIV=""
for d in "$ROOT"/priv[a]te; do
	[ -d "$d" ] && PRIV="$d"
done

local_gate() {
	local t ex stage rc=0 found=0
	if [ -z "$PRIV" ]; then
		echo "local gate: skipped (no extra check directory in this checkout)"
		return 0
	fi
	# 1. the extra test scripts, each with its own counters.
	for t in "$PRIV"/tests/run-*.sh; do
		[ -e "$t" ] || continue
		found=1
		echo "local gate: running ${t#"$ROOT"/}"
		bash "$t" || { echo "local gate: FAILED: ${t#"$ROOT"/}" >&2; rc=1; }
	done
	[ "$found" -eq 1 ] || echo "local gate: no test script found"
	# 2. the export guard over the files a commit would carry: tracked and
	# untracked-but-not-ignored files of the working tree, minus the paths
	# the export removes. A hit of the path-name group is a hard failure here.
	ex="$PRIV/export"
	if [ ! -f "$ex/guard.sh" ]; then
		echo "local gate: FAILED: the export guard is missing" >&2
		return 1
	fi
	stage=$(mktemp -d "${TMPDIR:-/tmp}/promote-gate.XXXXXX")
	local -a specs=()
	mapfile -t specs < <(bash -c 'source "$1/lib.sh"; kit_pathspecs exclude "$1"/priv[a]te-paths.txt' _ "$ex")
	[ "${#specs[@]}" -gt 0 ] || { echo "local gate: FAILED: no path list" >&2; rm -rf "$stage"; return 1; }
	(
		cd "$ROOT"
		git ls-files -z --cached --others --exclude-standard --deduplicate -- . "${specs[@]}" \
			| while IFS= read -r -d '' f; do
				{ [ -e "$f" ] || [ -L "$f" ]; } && printf '%s\0' "$f"
			done \
			| tar --null --no-recursion -T - -cf - | tar -C "$stage" -xf -
	) || { echo "local gate: FAILED: could not stage the files" >&2; rm -rf "$stage"; return 1; }
	echo "local gate: scanning $(find "$stage" -type f | wc -l) files with the export guard"
	bash "$ex/guard.sh" --conf "$ex" --strict tree "$stage" || { echo "local gate: FAILED: the export guard found hits" >&2; rc=1; }
	rm -rf "$stage"
	return "$rc"
}

if [ "${1:-}" = "--gate" ]; then
	if local_gate; then exit 0; else exit 1; fi
fi

if [ "${1:-}" = "--seal" ]; then
	DIR="$ROOT/release/${2:?usage: promote-release.sh --seal <version>}"
	[ -d "$DIR" ] || { echo "no such release: $DIR" >&2; exit 1; }
	if grep -q 'TODO' "$DIR/STATUS.txt"; then
		echo "refusing: $DIR/STATUS.txt still has TODO lines - fill it in first" >&2
		exit 1
	fi
	seal "$DIR"
	exit 0
fi
[ $# -eq 0 ] || { echo "usage: promote-release.sh [--seal <version> | --gate]" >&2; exit 2; }

PKGVER=$(sed -n 's/^pkgver=//p' "$ARCH/PKGBUILD" | head -1)
PKGREL=$(sed -n 's/^pkgrel=//p' "$ARCH/PKGBUILD" | head -1)
PKGBASE=$(sed -n 's/^pkgbase=//p' "$ARCH/PKGBUILD" | head -1)

DEST="$ROOT/release/$PKGVER"
PKGFILE="$ROOT/dist/${PKGBASE}-${PKGVER}-${PKGREL}-any.pkg.tar.zst"
SRCTAR="$ROOT/dist/${PKGBASE}-${PKGVER}.tar"

# 1. release/<ver>/ is promoted, immutable history - never overwritten.
if [ -e "$DEST" ]; then
	echo "refusing: $DEST already exists - release history is not overwritten" >&2
	exit 1
fi

# 2. the version in the PKGBUILD is the one the sources carry.
if [ "$(cat "$ROOT/VERSION")" != "$PKGVER" ]; then
	echo "refusing: VERSION is $(cat "$ROOT/VERSION"), the PKGBUILD says $PKGVER" >&2
	exit 1
fi

# 3. .SRCINFO must actually match the PKGBUILD being promoted.
if ! diff -q <(cd "$ARCH" && makepkg --printsrcinfo) "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	echo "refusing: makepkg --printsrcinfo differs from $ARCH/.SRCINFO - run make srcinfo first" >&2
	exit 1
fi

# 4. the built package for this exact version must already exist...
if [ ! -e "$PKGFILE" ]; then
	echo "refusing: $PKGFILE does not exist - build it first (make arch-pkg)" >&2
	exit 1
fi

# 4b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	echo "refusing: $SRCTAR is missing or does not match the PKGBUILD's sha256sums - run make arch-pkg" >&2
	exit 1
fi

install -dm755 "$DEST"
cp -v "$ARCH/PKGBUILD" "$ARCH/.SRCINFO" "$ARCH/macbook91-hw-fixes.install" "$SRCTAR" "$PKGFILE" "$DEST/"

PKGSUM=$(sha256sum "$PKGFILE" | cut -d' ' -f1)

cat >"$DEST/STATUS.txt" <<EOF
$PKGBASE $PKGVER-$PKGREL - TODO: RELEASED / CANDIDATE / WITHDRAWN

TODO: what changed, why, what was measured, what is not yet verified, and
the test suite counts. Mark every result PASS, FAIL, NOT_RUN, BLOCKED or
NOT_APPLICABLE; a check that was not run is never PASS.

Built package (not tracked; local build, makepkg output differs per machine):
$PKGSUM  $(basename "$PKGFILE")
EOF

seal "$DEST"

# 4c. the optional local gate. A failed gate removes the directory this run created,
# so a rerun is possible; nothing else was touched.
if ! local_gate; then
	rm -rf "${DEST:?}"
	echo "refusing: the local gate failed; removed $DEST" >&2
	exit 1
fi

# 5. retention: keep the two newest releases; older ones are removed from the
# tree and are not part of this repository. Only after the new one is written
# and sealed, and every removal is named.
n=0
while read -r v; do
	[ -n "$v" ] || continue
	n=$((n + 1))
	[ "$n" -le 2 ] && continue
	rm -rfv "${ROOT:?}/release/$v" | tail -1
	echo "pruned release/$v (kept the 2 newest; older releases are not part of this repository)"
done < <(find "$ROOT/release" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V -r)

echo "promoted $PKGBASE $PKGVER-$PKGREL to $DEST"
echo "fill in $DEST/STATUS.txt, then re-seal the checksums it is part of:"
echo "  $HERE/promote-release.sh --seal $PKGVER"
