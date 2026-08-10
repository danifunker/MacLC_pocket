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

for f in core.json video.json audio.json data.json input.json interact.json variants.json; do
    cp "$f" "$DEST/"
done
[ -f dist/icon.bin ] && cp dist/icon.bin "$DEST/" || true

# Bit-reverse every byte (see the header note — this is what _r means).
python3 - "$RBF" "$DEST/bitstream.rbf_r" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
table = bytes(int(format(b, '08b')[::-1], 2) for b in range(256))
data = open(src, 'rb').read()
open(dst, 'wb').write(data.translate(table))
print("bit-reversed %d bytes" % len(data))
PY

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
echo "Pocket UI) is not generated here — it is a raw 521x165 BGRA blob and has"
echo "to be authored separately. Its absence does not stop the core loading."
