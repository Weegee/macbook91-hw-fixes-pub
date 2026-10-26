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
#   promote-release.sh -n               run the checks, change nothing
#   promote-release.sh --seal <version> redo SHA256SUMS after STATUS.txt,
#                                       which it covers, has been filled in
#   promote-release.sh --gate           run the local gate alone (below)
#
# Run it with --help for the options, the exit codes and the messages.
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

PROG=promote-release.sh
CMD=packaging/promote-release.sh # as typed from the repository root
VERSION=$(cat "$ROOT/VERSION" 2>/dev/null || echo dev)
STAGE='' CREATED='' # removed again when a signal ends the run early

err() { # err MESSAGE [LINE...]: the error on stderr, further lines indented
	local l
	printf '%s: error: %s\n' "$PROG" "$1" >&2
	shift
	for l in "$@"; do printf '  %s\n' "$l" >&2; done
}
usage_error() { err "$@"; printf 'Help: %s --help\n' "$PROG" >&2; exit 2; }
usage() {
	cat <<EOT
Usage: $PROG [-n]
       $PROG --seal VERSION
       $PROG --gate

Copy the built package of the PKGBUILD version into release/VERSION/, write a
STATUS.txt to fill in and seal SHA256SUMS over the tracked files. It does not
commit, tag, push or publish anything.

Examples:
  $PROG -n
      check that a promotion would work
  $PROG
      promote the version in the PKGBUILD
  $PROG --seal 20261026.02
      seal again once STATUS.txt is filled in

Options:
  -n, --dry-run      run the checks and list what would be promoted; change
                     nothing
      --seal VERSION redo SHA256SUMS of release/VERSION/ once STATUS.txt has no
                     TODO line left
      --gate         run the local gate alone (tests and export guard of a
                     checkout with the extra check directory; skipped without)
  -h, --help         show this help
  -V, --version      show the version

Environment:
  MACBOOK91_RELEASE_ROOT   use this directory as the repository root (tests)

Files:
  VERSION, packaging/arch/PKGBUILD   the version to promote
  dist/                              the built package and source tarball
  release/VERSION/                   the result; promoted releases are never
                                     overwritten, the two newest are kept

Exit status:
  0  done
  1  a check or the local gate failed; nothing was promoted
  2  usage error
 130  interrupted by SIGINT
 143  ended by SIGTERM

Docs and bug reports: https://github.com/Weegee/macbook91-hw-fixes-pub
EOT
}

MODE=promote SEAL_VERSION='' DRY=0
while [ $# -gt 0 ]; do
	case $1 in
	-h | --help) usage; exit 0 ;;
	-V | --version) printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
	-n | --dry-run) DRY=1 ;;
	--gate)
		[ "$MODE" = promote ] || usage_error "--gate and --seal exclude each other"
		MODE=gate ;;
	--seal)
		[ "$MODE" = promote ] || usage_error "--gate and --seal exclude each other"
		[ $# -ge 2 ] || usage_error "--seal needs a version"
		MODE=seal SEAL_VERSION=$2
		shift ;;
	--) shift; [ $# -eq 0 ] || usage_error "unexpected argument '$1'"; break ;;
	-?*) usage_error "unknown option '$1'" ;;
	*) usage_error "unexpected argument '$1'" ;;
	esac
	shift
done
[ "$DRY" -eq 0 ] || [ "$MODE" = promote ] || usage_error "-n only goes with a promotion, not with --gate or --seal"

# A signal ends the run with 128+N after removing what this run created.
on_signal() { # on_signal CODE
	trap - INT TERM
	[ -z "$STAGE" ] || rm -rf "$STAGE"
	if [ -n "$CREATED" ]; then
		rm -rf "${CREATED:?}"
		err "interrupted; removed ${CREATED#"$ROOT"/}" "Run again: $CMD"
	else
		err "interrupted"
	fi
	exit "$1"
}
trap 'on_signal 130' INT
trap 'on_signal 143' TERM

TRACKED_FILES='PKGBUILD .SRCINFO macbook91-hw-fixes.install STATUS.txt'
seal() { # seal DIR
	local src="" f
	for f in "$1"/*.tar; do
		[ -e "$f" ] && { src=$(basename "$f"); break; }
	done
	[ -n "$src" ] || { err "no source tarball in ${1#"$ROOT"/}" "Run: make dist"; return 1; }
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
		bash "$t" || { err "local gate: ${t#"$ROOT"/} failed"; rc=1; }
	done
	[ "$found" -eq 1 ] || echo "local gate: no test script found"
	# 2. the export guard over the files a commit would carry: tracked and
	# untracked-but-not-ignored files of the working tree, minus the paths
	# the export removes. A hit of the path-name group is a hard failure here.
	ex="$PRIV/export"
	if [ ! -f "$ex/guard.sh" ]; then
		err "local gate: the export guard is missing" "Expected: ${ex#"$ROOT"/}/guard.sh"
		return 1
	fi
	stage=$(mktemp -d "${TMPDIR:-/tmp}/promote-gate.XXXXXX")
	STAGE=$stage
	local -a specs=()
	mapfile -t specs < <(bash -c 'source "$1/lib.sh"; kit_pathspecs exclude "$1"/priv[a]te-paths.txt' _ "$ex")
	[ "${#specs[@]}" -gt 0 ] || { err "local gate: no path list for the export guard"; rm -rf "$stage"; STAGE=''; return 1; }
	(
		cd "$ROOT"
		git ls-files -z --cached --others --exclude-standard --deduplicate -- . "${specs[@]}" \
			| while IFS= read -r -d '' f; do
				{ [ -e "$f" ] || [ -L "$f" ]; } && printf '%s\0' "$f"
			done \
			| tar --null --no-recursion -T - -cf - | tar -C "$stage" -xf -
	) || { err "local gate: could not stage the files for the export guard"; rm -rf "$stage"; STAGE=''; return 1; }
	echo "local gate: scanning $(find "$stage" -type f | wc -l) files with the export guard"
	bash "$ex/guard.sh" --conf "$ex" --strict tree "$stage" || { err "local gate: the export guard found hits"; rc=1; }
	rm -rf "$stage"
	STAGE=''
	return "$rc"
}

if [ "$MODE" = gate ]; then
	if local_gate; then exit 0; else exit 1; fi
fi

if [ "$MODE" = seal ]; then
	DIR="$ROOT/release/$SEAL_VERSION"
	[ -d "$DIR" ] || { err "no such release: release/$SEAL_VERSION" "Promote it first: $CMD"; exit 1; }
	if grep -q 'TODO' "$DIR/STATUS.txt"; then
		err "release/$SEAL_VERSION/STATUS.txt still has TODO lines" "Fill it in, then run: $CMD --seal $SEAL_VERSION"
		exit 1
	fi
	seal "$DIR"
	exit 0
fi

PKGVER=$(sed -n 's/^pkgver=//p' "$ARCH/PKGBUILD" | head -1)
PKGREL=$(sed -n 's/^pkgrel=//p' "$ARCH/PKGBUILD" | head -1)
PKGBASE=$(sed -n 's/^pkgbase=//p' "$ARCH/PKGBUILD" | head -1)

DEST="$ROOT/release/$PKGVER"
PKGFILE="$ROOT/dist/${PKGBASE}-${PKGVER}-${PKGREL}-any.pkg.tar.zst"
SRCTAR="$ROOT/dist/${PKGBASE}-${PKGVER}.tar"

# 1. release/<ver>/ is promoted, immutable history - never overwritten.
if [ -e "$DEST" ]; then
	err "release/$PKGVER already exists; a promoted release is never overwritten" "For a new release raise VERSION and pkgver in the PKGBUILD."
	exit 1
fi

# 2. the version in the PKGBUILD is the one the sources carry.
if [ "$(cat "$ROOT/VERSION")" != "$PKGVER" ]; then
	err "VERSION is $(cat "$ROOT/VERSION") but the PKGBUILD says $PKGVER" "Make them equal, then run: make dist"
	exit 1
fi

# 3. .SRCINFO must actually match the PKGBUILD being promoted.
if ! diff -q <(cd "$ARCH" && makepkg --printsrcinfo) "$ARCH/.SRCINFO" >/dev/null 2>&1; then
	err ".SRCINFO does not match the PKGBUILD" "Run: make srcinfo"
	exit 1
fi

# 4. the built package for this exact version must already exist...
if [ ! -e "$PKGFILE" ]; then
	err "the package ${PKGFILE#"$ROOT"/} does not exist" "Run: make arch-pkg"
	exit 1
fi

# 4b. ...from the tarball the PKGBUILD pins, not from some other build.
PINNED=$(sed -n "s/^sha256sums=('\([0-9a-f]*\)').*/\1/p" "$ARCH/PKGBUILD")
if [ ! -e "$SRCTAR" ] || [ "$(sha256sum "$SRCTAR" | cut -d' ' -f1)" != "$PINNED" ]; then
	err "${SRCTAR#"$ROOT"/} is missing or does not match the sha256sums in the PKGBUILD" "Run: make dist, pin the checksum in packaging/arch/PKGBUILD, then make arch-pkg"
	exit 1
fi

if [ "$DRY" -eq 1 ]; then
	echo "dry run: the checks passed; would promote $PKGBASE $PKGVER-$PKGREL to ${DEST#"$ROOT"/}:"
	for f in "$ARCH/PKGBUILD" "$ARCH/.SRCINFO" "$ARCH/macbook91-hw-fixes.install" "$SRCTAR" "$PKGFILE"; do
		echo "  ${f#"$ROOT"/}"
	done
	echo "then seal SHA256SUMS and run the local gate; nothing was changed"
	exit 0
fi

install -dm755 "$DEST"
CREATED=$DEST
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
	CREATED=''
	err "the local gate failed; removed ${DEST#"$ROOT"/}" "Fix the failures above, then run again: $CMD"
	exit 1
fi
CREATED=''

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
