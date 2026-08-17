#!/usr/bin/env bash
# make_test_slot.sh — build a THIRD card slot ("MacLCtest") for trying a build
# without touching the main core or the prev-slot fallback.
#
# Card layout this produces:
#   /Cores/danifunker.MacLC/       main    — the released build (v1.0.2 = buildBP)
#   /Cores/danifunker.MacLCprev/   prev    — the known-good fallback (hand-made)
#   /Cores/danifunker.MacLCtest/   test    — WHATEVER WE ARE TRYING TODAY
#
# ★ Output goes to scratch/ (gitignored), NOT dist/. dist/ is the release tree;
#   a test slot living there would get committed and could ride a release zip.
#
# ★ platform_ids stays "maclc" and every data.json slot has the core-specific
#   bit CLEAR, so all three cores share /Assets/maclc/common/ — one copy of
#   boot0.rom and the disk images, no duplication. Settings and interact
#   persists ARE per-core (keyed on the folder name), so the test slot cannot
#   poison the main core's menu state. That isolation is the point: a corrupt
#   fit has made Analogue OS persist garbage interact values before.
#
# ★ The bitstream is bit-reversed here, same as package.sh. Renaming a plain
#   .rbf to bitstream.rbf_r yields "Load error in 'core' General error".
#
# Usage:
#   bash scripts/make_test_slot.sh <path-to.rbf> [label]
#   bash scripts/make_test_slot.sh                      # uses the current build
#
# label lands in core.json "version", which the Pocket shows in the core list —
# so you can tell at a glance which build is in the test slot. Keep it short.

set -eu
cd "$(dirname "$0")/.."

AUTHOR="danifunker"
CORE="MacLC"
TESTCORE="MacLCtest"
SRC_DIR="dist/Cores/${AUTHOR}.${CORE}"
DEST="scratch/staging/testslot/Cores/${AUTHOR}.${TESTCORE}"

RBF="${1:-src/fpga/output_files/ap_core.rbf}"
LABEL="${2:-test}"

[ -f "$RBF" ] || { echo "ERROR: no such rbf: $RBF" >&2; exit 1; }
[ -d "$SRC_DIR" ] || { echo "ERROR: no source core at $SRC_DIR" >&2; exit 1; }

# Pick a working python (Git Bash has `python`, WSL usually `python3`; the
# Windows Store alias stubs resolve but do not run — test, don't assume).
PY_BIN=""
for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "pass" >/dev/null 2>&1; then PY_BIN="$c"; break; fi
done
[ -n "$PY_BIN" ] || { echo "ERROR: no working python on PATH (needed to bit-reverse the RBF)" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"

# Copy every card file byte-for-byte. The JSONs are already CRLF with a trailing
# newline in dist/ and MUST stay that way — a missing final newline is a proven
# "Load error" cause (2026-08-15). Copying bytes preserves both.
for f in "$SRC_DIR"/*.json "$SRC_DIR"/info.txt "$SRC_DIR"/icon.bin; do
    [ -f "$f" ] && cp "$f" "$DEST/"
done

# Patch core.json by BYTE replacement, not a json round-trip: a load/dump would
# rewrite line endings and drop the trailing newline.
"$PY_BIN" - "$DEST/core.json" "$TESTCORE" "$LABEL" <<'PY'
import re, sys
path, testcore, label = sys.argv[1], sys.argv[2], sys.argv[3]
b = open(path, 'rb').read()
tail = b[-8:]

def sub_once(data, field, value):
    pat = re.compile(rb'("' + field.encode() + rb'"\s*:\s*")[^"]*(")')
    out, n = pat.subn(lambda m: m.group(1) + value.encode() + m.group(2), data, count=1)
    if n != 1:
        sys.exit("ERROR: expected exactly 1 %r in core.json, found %d" % (field, n))
    return out

b = sub_once(b, 'shortname', testcore)
b = sub_once(b, 'version',   label)

if b[-8:] != tail:
    sys.exit("ERROR: patch disturbed the file tail — refusing to write")
if not b.endswith(b'}\r\n') and not b.endswith(b'}\n'):
    sys.exit("ERROR: core.json would not end in a newline — refusing to write")
open(path, 'wb').write(b)
print("  core.json: shortname -> %s, version -> %s" % (testcore, label))
PY

# Bit-reverse every byte of the bitstream (this is what the _r suffix means).
"$PY_BIN" - "$RBF" "$DEST/bitstream.rbf_r" <<'PY'
import sys
tbl = bytes(int('{:08b}'.format(i)[::-1], 2) for i in range(256))
data = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'wb').write(data.translate(tbl))
print("  bitstream.rbf_r: %d bytes, bit-reversed from %s" % (len(data), sys.argv[1]))
PY

echo ""
echo "Test slot built: $DEST"
ls -l "$DEST"
echo ""
echo "sha1:"
( cd "$DEST" && sha1sum bitstream.rbf_r )
echo ""
echo "Copy to the card (adjust the drive letter):"
echo "  mkdir -p /d/Cores/${AUTHOR}.${TESTCORE}"
echo "  cp $DEST/* /d/Cores/${AUTHOR}.${TESTCORE}/"
