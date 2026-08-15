#!/usr/bin/env python3
"""Bake a MiSTer MacLC .NVR PRAM save into rtl/egret/egret.pram.

The MiSTer core ("SC2,NVR,Mount PRAM;") stores the Egret's 256 PRAM bytes in
the first sector of the .NVR file (rest padding). The Pocket seeds its Egret
PRAM at synthesis from rtl/egret/egret.pram ($readmemh in egret_wrapper.sv:
one hex byte per line, 256 lines) -- so a PRAM written by the REAL guest on
MiSTer (e.g. Monitors set to 256 colors on the 512x384 monitor) becomes the
Pocket's power-up default. Requires a rebuild to take effect.

Usage:
    python scripts/nvr_to_pram.py <file.nvr> [--dry-run] [--keep-512k]

Prints a byte-level diff against the current seed first (this documents which
XPRAM offsets the setting actually lives in), then rewrites the seed unless
--dry-run. Refuses an all-zero/all-FF source (nothing was ever saved into it).
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PRAM = REPO / "rtl" / "egret" / "egret.pram"

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    dry = "--dry-run" in sys.argv[2:]

    raw = src.read_bytes()
    if len(raw) < 256:
        sys.exit(f"ERROR: {src} is {len(raw)} bytes; need at least 256")
    new = bytearray(raw[:256])
    if all(b == 0x00 for b in new) or all(b == 0xFF for b in new):
        sys.exit("ERROR: source PRAM is blank (all-00/FF) — never saved into?")

    # ★ 256K-VRAM fixup (root cause of the B&W-boot bug, found 2026-08-14 via
    # MAME A/B): the LC ROM validates the saved video-mode record against the
    # MACHINE — XPRAM 0x5A = montype | (0x08 if 256K VRAM else 0), 0x59 =
    # 0xA0 | (same). A .NVR written on MiSTer (512K VRAM SIMM) lacks bit 3;
    # this fork presents a 256K SIMM (buildAW), so without the bit the ROM
    # discards the record and boots 1bpp. Proof: MAME maclc @256K+montype2,
    # driver-open PC A4B7BC writes video config $10 (1bpp) with the 512K
    # record but $13 (8bpp) once 0x59/0x5A carry bit 3 (runs M1b/M2/M3,
    # scratch/pram/). --keep-512k skips this for a 512K-target seed.
    if "--keep-512k" not in sys.argv[2:]:
        if (new[0x59] & 0xF0) == 0xA0 and not (new[0x5A] & 0x08):
            print(f"256K-VRAM fixup: 0x59 {new[0x59]:02X}->{new[0x59]|8:02X}, "
                  f"0x5A {new[0x5A]:02X}->{new[0x5A]|8:02X}")
            new[0x59] |= 0x08
            new[0x5A] |= 0x08

    cur = bytes(int(l, 16) for l in PRAM.read_text().split())
    diffs = [(i, cur[i], new[i]) for i in range(256) if cur[i] != new[i]]
    if not diffs:
        print("No differences — seed already matches this .NVR.")
        return
    print(f"{len(diffs)} byte(s) differ vs current seed:")
    for off, old, nb in diffs:
        print(f"  XPRAM 0x{off:02X}: {old:02X} -> {nb:02X}")

    if dry:
        print("(dry run — seed not written)")
        return
    PRAM.write_text("".join(f"{b:02x}\n" for b in new))
    print(f"Wrote {PRAM} (256 lines). Rebuild to bake it in.")

if __name__ == "__main__":
    main()
