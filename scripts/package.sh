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
# core.json. The _r suffix is not decoration: it marks the reversed-bit-order
# RBF that the Pocket's loader expects.
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

cp "$RBF" "$DEST/bitstream.rbf_r"

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
