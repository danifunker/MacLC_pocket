#!/usr/bin/env python3
"""Bake a MiSTer MacLC .NVR PRAM save into rtl/egret/egret.pram.

The MiSTer core ("SC2,NVR,Mount PRAM;") stores the Egret's 256 PRAM bytes in
the first sector of the .NVR file (rest padding). The Pocket seeds its Egret
PRAM at synthesis from rtl/egret/egret.pram ($readmemh in egret_wrapper.sv:
one hex byte per line, 256 lines) -- so a PRAM written by the REAL guest on
MiSTer (e.g. Monitors set to 256 colors on the 512x384 monitor) becomes the
Pocket's power-up default. Requires a rebuild to take effect.

Usage:
    python scripts/nvr_to_pram.py <file.nvr> [--dry-run]

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
    new = raw[:256]
    if all(b == 0x00 for b in new) or all(b == 0xFF for b in new):
        sys.exit("ERROR: source PRAM is blank (all-00/FF) — never saved into?")

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
