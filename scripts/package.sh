#!/bin/bash
# package.sh — assemble the openFPGA SD-card tree from a completed Quartus build.
#
# Produces dist/, which is copied to the root of the Pocket's microSD card:
#
#   /Cores/danifunker.MacLC/     the seven JSONs + bitstream.rbf_r
#   /Platforms/maclc.json        platform metadata (name shown in the UI)
#   /Assets/maclc/common/        where the user puts boot0.rom and disk images
#
# The bitstream MUST be named bitstream.rbf_r and match the "filename" field in
# core.json. The _r suffix is not decoration: it marks the REVERSED-BIT-ORDER
# RBF that the Pocket's loader expects, and Quartus does NOT produce it.
#
# ★ Every byte of the .rbf must have its BITS reversed (0b10110010 -> 0b01001101).
# Merely renaming ap_core.rbf to bitstream.rbf_r produces a core that the Pocket
# rejects at load time with:
#       Load error in 'core'  General error
# Verified against the stock core-template bitstream: its first non-FF bytes are
# 56 56 56 56 6c 2f, and bit-reversing those gives 6a 6a 6a 6a 36 f4 — byte for
# byte what Quartus emits in a plain .rbf.
#
# Usage:  bash scripts/package.sh
# Requires: src/fpga/output_files/ap_core.rbf (run quartus_asm first)

set -eu
cd "$(dirname "$0")/.."

AUTHOR="danifunker"
CORE="MacLC"
PLATFORM="maclc"
RBF="src/fpga/output_files/ap_core.rbf"
DEST="dist/Cores/${AUTHOR}.${CORE}"

if [ ! -f "$RBF" ]; then
    echo "ERROR: $RBF not found."
    echo "  Run the Quartus flow first:"
    echo "    cd src/fpga && quartus_map ap_core && quartus_fit ap_core && quartus_asm ap_core && quartus_sta ap_core"
    exit 1
fi

mkdir -p "$DEST" "dist/Platforms/_images" "dist/Assets/${PLATFORM}/common"

# Ship the JSONs with CRLF line endings.
#
# Every JSON in the reference core (Pocket-Amiga) is CRLF; ours are LF because
# .gitattributes pins them that way for readable diffs. JSON does not care
# about line endings in principle, but the Pocket's parser is not ours to
# assume about, and matching a known-good core costs nothing. The repo stays
# LF; only the shipped copies are converted.
PY_BIN=""
for cand in python3 python py; do
    p="$(command -v "$cand" 2>/dev/null)" || continue
    [ -n "$p" ] || continue
    "$p" -c 'import sys; sys.exit(0)' >/dev/null 2>&1 || continue
    PY_BIN="$p"
    break
done
if [ -z "$PY_BIN" ]; then
    echo "ERROR: no WORKING python3/python on PATH — needed to bit-reverse the RBF."
    echo "       (Candidates found but non-functional are usually the Windows"
    echo "        Store alias stubs in %LOCALAPPDATA%\\Microsoft\\WindowsApps.)"
    exit 1
fi

# ★ 2026-08-15: byte-DETERMINISTIC conversion, replacing `sed 's/$/\r/'`.
# The sed form has two failure modes that cost a full evening of bisecting
# "Load error in 'interact' general error": (1) on a file that already has
# CRLF (Windows Python's text-mode json.dump writes them) it produced \r\r\n;
# (2) on a file with no trailing newline (json.dump never writes one) GNU sed
# preserves the missing terminator, shipping a final line ending in a lone
# \r — which the Pocket's interact parser rejects outright. Normalize to LF,
# force the final newline, then emit clean CRLF. Idempotent for any input.
for f in core.json video.json audio.json data.json input.json interact.json variants.json; do
    "$PY_BIN" -c "
import sys
d = open(sys.argv[1], 'rb').read().replace(b'\r\n', b'\n')
if not d.endswith(b'\n'): d += b'\n'
open(sys.argv[2], 'wb').write(d.replace(b'\n', b'\r\n'))
" "$f" "$DEST/$f"
done
[ -f dist/icon.bin ] && cp dist/icon.bin "$DEST/" || true

# Bit-reverse every byte (see the header note — this is what _r means).
# Git Bash on Windows often has `python` but not `python3`; WSL/Linux usually
# the reverse. Pick whichever exists so this runs unchanged on both.
#
# ★ Must TEST each candidate, not just look it up. Windows ships App Execution
# Alias stubs at %LOCALAPPDATA%\Microsoft\WindowsApps\python{,3}.exe that exist
# on PATH, satisfy `command -v`, and do nothing but open the Microsoft Store.
# On a machine with real Python installed, `command -v python3` can still hit
# the stub while `python` resolves correctly -- so the old python3-first pick
# selected the stub and the bit-reversal produced nothing. A silently missing
# or stale bitstream.rbf_r is exactly the failure this script exists to avoid.

"$PY_BIN" - "$RBF" "$DEST/bitstream.rbf_r" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
table = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
data = open(src, 'rb').read()
open(dst, 'wb').write(data.translate(table))
print("bit-reversed %d bytes" % len(data))
PY

# info.txt: root is the source of truth; card wants CRLF + final newline.
# (2026-08-16: the dist copy was a static leftover nothing regenerated — the
# import-era "SCSI not implemented" text shipped in v1.0.0 because of it.)
"$PY_BIN" - << 'PYEOF'
s = open('info.txt', 'rb').read().replace(b'
', b'
')
if not s.endswith(b'
'): s += b'
'
open('dist/Cores/danifunker.MacLC/info.txt', 'wb').write(s.replace(b'
', b'
'))
PYEOF

echo "packaged $(du -h "$DEST/bitstream.rbf_r" | cut -f1) bitstream into $DEST"
echo
echo "Copy to the SD card root:"
echo "    dist/Cores/${AUTHOR}.${CORE}/   ->  /Cores/${AUTHOR}.${CORE}/"
echo "    dist/Platforms/${PLATFORM}.json ->  /Platforms/${PLATFORM}.json"
echo
echo "Then place the boot ROM at:"
echo "    /Assets/${PLATFORM}/common/boot0.rom"
echo
echo "NOTE: /Platforms/_images/${PLATFORM}.bin (the platform art shown in the"
echo "Pocket UI) is not generated here — it is 521x165 8-BIT INK, stored column-"
echo "major one pixel per 16-bit word with only the low byte used, and has to be"
echo "authored separately (scripts/convert_platform_image.py). The Pocket paints"
echo "luminance = 255 - ink, so ink 0x00 is WHITE. It is NOT BGRA and NOT RGB565"
echo "— both misreadings have cost us a release each."
echo "Its absence does not stop the core loading."
