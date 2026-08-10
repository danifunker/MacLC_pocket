#!/usr/bin/env bash
# setup_roms.sh — assemble a MAME maclc rompath from the in-repo ROMs.
# Run from WSL: bash verilator/mame/floppy/setup_roms.sh
set -euo pipefail

REPO=/mnt/c/Temp/mistercore/MacLC_MiSTer
RP="$HOME/maclc_roms"

echo "=== egret ROM sha1 (repo copies) ==="
sha1sum "$REPO"/rtl/egret/344s0100.bin \
        "$REPO"/rtl/egret/341s0850.bin \
        "$REPO"/rtl/egret/341s0851.bin
cat <<'EOF'
expect 344s0100 = 540e752b7da521f1bdb16e0ad7c5f46ddc92d4e9
expect 341s0850 = 95e08ba0c5d4b242f115f104aba9905dbd3fd87c
expect 341s0851 = 8b0dae3ec66cdddbf71567365d2c462688aeb571
EOF

echo "=== build rompath at $RP ==="
rm -rf "$RP"
mkdir -p "$RP/maclc" "$RP/egret"
cp "$REPO/releases/boot0.rom" "$RP/maclc/350eacf0.rom"
for b in 344s0100 341s0850 341s0851; do
  cp "$REPO/rtl/egret/$b.bin" "$RP/egret/$b.bin"
  cp "$REPO/rtl/egret/$b.bin" "$RP/maclc/$b.bin"
done
ls -la "$RP/maclc" "$RP/egret"

echo "=== verifyroms maclc ==="
mame -verifyroms maclc -rompath "$RP" 2>&1 | tail -20
