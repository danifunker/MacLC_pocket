#!/usr/bin/env python3
"""Validate (and if needed re-polarise) Pocket platform art: /Platforms/_images/<id>.bin

★ THE FORMAT IS 8-BIT INK, NOT RGB565, AND THE POCKET INVERTS IT.
  (Settled on hardware 2026-08-16, after getting it wrong twice.)

    521 x 165 landscape, stored COLUMN-MAJOR as 165 pixels per row x 521 rows,
    one pixel per 16-bit little-endian word, of which ONLY THE LOW BYTE IS
    USED.  The high byte is always 0x00.

        storage[r * 165 + c]  =  display(520 - r, c)
        word                  =  0x00II   where II = INK

    The Pocket displays  luminance = 255 - ink.  So:

        ink 0x00  ->  displays WHITE      ink 0xFF  ->  displays BLACK

    The house style is therefore a WHITE background: the shipping images are
    dominated by ink 0x00 (gb.bin is 93% of it), which paints white, not black.

HOW WE KNOW.  Two independent facts, one of which I misread the first time:

  1. Every one of the 230 platform images on a real card has a zero high byte
     in all 85,965 words -- including photographic ones (doom, playstation,
     snes) using all 256 low-byte values.  No real RGB565 picture can have a
     constantly-zero red channel.  This part was right from the start.

  2. amstrad.bin ships next to the amstrad.png it was made from.  Decoded as
     LUMINANCE the .bin is the PHOTOGRAPHIC NEGATIVE of that .png -- the
     "Amstrad CPC" lettering is dark in one and white in the other.  I first
     read the two as matching, which is how the inversion got in.  Confirmed
     on hardware: the lettering is white on the Pocket.

⚠ TWO SELF-CONCEALING TRAPS, both of which cost a release:

  - A greyscale image written as RGB565 still shows the right SHAPE, and pure
    white (0xFFFF) and black (0x0000) survive intact either way.  Only the
    MIDTONES invert.  Never diagnose this from the extremes.
  - Polarity cannot be judged from a decode alone.  Check it against a .bin
    whose source image ships beside it, and read the LETTERING, not the
    overall brightness.

INPUT.  The web-based generators already emit exactly what the Pocket wants,
so the default here is pass-through: this script validates the geometry and
the zero high byte and copies the file.  Use --invert only if your source
stores luminance instead of ink (i.e. it looks correct on screen as a plain
greyscale image, in which case it needs flipping for the Pocket).

Usage:
    python3 scripts/convert_platform_image.py IN.bin [OUT.bin] [--invert]

OUT.bin defaults to dist/Platforms/_images/maclc.bin.
"""
import os
import struct
import sys

W, H = 521, 165
NPIX = W * H
EXPECT = NPIX * 2  # 171,930


def main():
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if not argv:
        sys.exit(__doc__)
    invert = "--invert" in flags

    src = argv[0]
    dst = argv[1] if len(argv) > 1 else os.path.join(
        "dist", "Platforms", "_images", "maclc.bin")

    raw = open(src, "rb").read()
    if len(raw) != EXPECT:
        sys.exit("ERROR: %s is %d bytes, expected %d (%dx%d)"
                 % (src, len(raw), EXPECT, W, H))

    if any(raw[1::2]):
        sys.exit("ERROR: %s has non-zero HIGH bytes.\n"
                 "       Every valid platform image has a zero high byte in\n"
                 "       all %d words. This file is in some other format --\n"
                 "       most likely it was written as RGB565. Fix the source."
                 % (src, NPIX))

    ink = raw[0::2]
    out = bytearray()
    for v in ink:
        out += struct.pack("<H", (255 - v) if invert else v)

    open(dst, "wb").write(bytes(out))
    print("wrote %s (%d bytes) from %s%s"
          % (dst, len(out), src, "  [--invert]" if invert else "  [pass-through]"))


if __name__ == "__main__":
    main()
