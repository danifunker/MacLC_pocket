#!/usr/bin/env bash
# snapshot_release.sh — freeze what a release actually shipped into
# releases/<version>/, so card files can be DIFFED across versions.
#
# WHY: git tags already contain everything, but nothing makes drift VISIBLE.
# v1.0.3 was nearly cut with a stale info.txt for exactly that reason —
# package.sh's propagation step had been failing silently since 2026-08-16 and
# nobody could see it, because comparing a copy against its source only ever
# proves the copy. A committed per-version snapshot turns that into one line:
#
#     diff -r releases/v1.0.2 releases/v1.0.3
#
# Text copies are normalised to LF so the diff shows REAL changes: the shipped
# files are CRLF on disk but git stores them LF, so an un-normalised backfill
# reports every single file as changed. MANIFEST.sha256 carries the TRUE
# shipped bytes, so nothing is lost by normalising the readable copies.
#
# The bitstream is not copied — it is already tracked in dist/ and attached to
# the GitHub release; 1.9 MB per version would bloat the repo for nothing. Its
# hash is in the manifest.
#
# ★ Normalisation goes through python using bytes([13,10]), NOT a shell escape
#   like tr -d '\r'. Backslash escapes in this repo's tooling have twice been
#   collapsed before the interpreter saw them (package.sh's info.txt step, and
#   the first version of this script). Byte values cannot suffer that.
#
# Usage:
#   bash scripts/snapshot_release.sh              # snapshot the current version
#   bash scripts/snapshot_release.sh v1.0.2       # backfill from a git tag
set -eu
cd "$(dirname "$0")/.."

AUTHOR="danifunker"; CORE="MacLC"
SRC="dist/Cores/${AUTHOR}.${CORE}"

PY_BIN=""
for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "pass" >/dev/null 2>&1; then PY_BIN="$c"; break; fi
done
[ -n "$PY_BIN" ] || { echo "ERROR: no working python on PATH" >&2; exit 1; }

# to_lf <in> <out>
to_lf() {
    "$PY_BIN" -c "import sys
d = open(sys.argv[1], 'rb').read().replace(bytes([13,10]), bytes([10]))
open(sys.argv[2], 'wb').write(d)" "$1" "$2"
}

if [ $# -ge 1 ]; then
    TAG="$1"; VER="${TAG#v}"; OUT="releases/v${VER}"
    echo "backfilling $OUT from git tag $TAG"
    rm -rf "$OUT"; mkdir -p "$OUT"
    TMP="$(mktemp -d)"
    : > "$OUT/MANIFEST.sha256"
    for f in $(git ls-tree --name-only "$TAG" "$SRC/"); do
        b="$(basename "$f")"
        git show "$TAG:$f" > "$TMP/$b"
        sha256sum "$TMP/$b" | sed "s|$TMP/||" >> "$OUT/MANIFEST.sha256"
        case "$b" in
            *.json|info.txt) to_lf "$TMP/$b" "$OUT/$b" ;;
        esac
    done
    rm -rf "$TMP"
else
    VER="$("$PY_BIN" -c "import json;print(json.load(open('core.json'))['core']['metadata']['version'])")"
    OUT="releases/v${VER}"
    echo "snapshotting $OUT from $SRC"
    rm -rf "$OUT"; mkdir -p "$OUT"
    for f in "$SRC"/*.json "$SRC"/info.txt; do
        to_lf "$f" "$OUT/$(basename "$f")"
    done
    ( cd "$SRC" && sha256sum * ) > "$OUT/MANIFEST.sha256"
fi

echo "  files: $(ls "$OUT" | tr '\n' ' ')"
echo "  diff against the previous release with:  diff -r releases/<prev> $OUT"
