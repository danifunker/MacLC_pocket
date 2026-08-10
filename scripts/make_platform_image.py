#!/usr/bin/env python3
"""Generate dist/platforms/_images/maclc.bin — the platform art the Pocket
shows on the core's About / platform screen.

FORMAT — reverse-engineered from Pocket-Amiga's amiga.bin, because guessing at
it produced garbage twice. 171,930 bytes factors as both 521*165*2 and
521*110*3, and NEITHER of those layouts decodes to a picture. The real layout
was found by scanning candidate row strides for row-to-row similarity: the
clear winner is a 330-byte stride over 521 rows, i.e.

    165 pixels per row, 521 rows, little-endian RGB565, no header

The image is therefore stored COLUMN-MAJOR — a 521x165 landscape picture
rotated 90 degrees. Decoding amiga.bin that way renders "Commodore AMIGA"
correctly; getting the rotation direction backwards renders it upside-down and
mirrored, which is a useful tell if this ever needs re-deriving.

Mapping, with (x, y) in display space (x across 521, y down 165):

    storage[r * 165 + c]  =  display(520 - r, c)

The Amiga image's dominant pixel value is 0x0001 (essentially black), so a dark
background is the house style.

Draws a Macintosh LC: the flat "pizza box" case with its 12" RGB monitor on
top, in Apple's Platinum grey, with the six-colour stripe as an accent.

Usage:  python3 scripts/make_platform_image.py
"""
import struct
import os

W, H = 521, 165

def rgb(r, g, b):
    """Pack 8-8-8 into RGB565."""
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

# Apple Platinum palette + the six-colour logo stripes.
BG        = rgb(8, 8, 12)
PLAT_LIT  = rgb(214, 211, 202)   # top/left lit faces
PLAT      = rgb(190, 187, 178)   # main body
PLAT_DARK = rgb(150, 147, 140)   # shaded faces
BEZEL     = rgb(120, 118, 112)
SCREEN    = rgb(28, 40, 52)
SCREEN_LT = rgb(60, 86, 104)     # phosphor glow
INK       = rgb(226, 232, 236)
SHADOW    = rgb(4, 4, 6)
STRIPES = [rgb(94, 186, 71), rgb(253, 184, 39), rgb(245, 130, 32),
           rgb(224, 58, 62), rgb(150, 61, 151), rgb(0, 157, 224)]

fb = [BG] * (W * H)

def put(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        fb[y * W + x] = c

def rect(x0, y0, x1, y1, c):
    for y in range(max(0, y0), min(H, y1)):
        row = y * W
        for x in range(max(0, x0), min(W, x1)):
            fb[row + x] = c

def frame(x0, y0, x1, y1, c):
    for x in range(x0, x1):
        put(x, y0, c); put(x, y1 - 1, c)
    for y in range(y0, y1):
        put(x0, y, c); put(x1 - 1, y, c)

# ------------------------------------------------------------------- art ---
# The 1977 six-colour Apple mark, centred. Classic proportions: the body is
# built from a circle with a bite taken out on the right, a leaf on top, and a
# wedge cut from the lower left. Drawn as a coverage mask first, then the
# horizontal rainbow bands are applied through it, so the stripe boundaries are
# exactly horizontal the way the real mark is.

LOGO_H = 132                       # apple body height in pixels
CXp, CYp = W // 2, H // 2 + 6      # centre of the body

HALF_W = LOGO_H * 0.455            # body half-width; the mark is slightly
HALF_H = LOGO_H * 0.5              # taller than it is wide

def in_apple(px_, py):
    """Coverage test. x,y normalised so the body spans roughly [-1, 1]."""
    x = (px_ - CXp) / HALF_W
    y = (py - CYp) / HALF_H

    # --- leaf: slim ellipse, rotated, sitting above the right shoulder ---
    lx, ly = x - 0.20, y + 1.10
    ca, sa = 0.707, 0.707                        # 45 degrees
    rx, ry = lx * ca + ly * sa, -lx * sa + ly * ca
    if (rx / 0.155) ** 2 + (ry / 0.38) ** 2 <= 1.0:
        return True

    # --- body: four overlapping lobes give the shouldered apple silhouette ---
    def lobe(ox, oy, rxr, ryr):
        return ((x - ox) / rxr) ** 2 + ((y - oy) / ryr) ** 2 <= 1.0

    inside = (lobe(-0.40, -0.16, 0.63, 0.70) or   # upper left shoulder
              lobe( 0.40, -0.16, 0.63, 0.70) or   # upper right shoulder
              lobe(-0.36,  0.40, 0.66, 0.62) or   # lower left
              lobe( 0.36,  0.40, 0.66, 0.62))     # lower right
    if not inside:
        return False

    # --- cleft between the shoulders, tapering closed as it descends ---
    if y < -0.42:
        t = (-0.42 - y) / 0.58                    # 0 at the waist, 1 at the top
        if abs(x) < 0.30 * t * t:
            return False

    # --- the bite: a circle removed from the right edge, above centre ---
    if ((x - 1.02) / 0.34) ** 2 + ((y + 0.06) / 0.36) ** 2 <= 1.0:
        return False
    return True

# Six horizontal bands, green at the top, in Apple's order. The bands are cut
# across the whole mark (leaf included) so the boundaries line up exactly, as
# they do on the real logo.
# The six bands divide the BODY exactly; the leaf sits above the body and so
# takes band 0 (green), which is what the real mark does.
band_h = (HALF_H * 2.0) / 6.0
band_top = CYp - HALF_H
for py in range(max(0, int(band_top - LOGO_H * 0.42)), min(H, int(CYp + HALF_H) + 2)):
    band = int((py - band_top) / band_h)
    band = 0 if band < 0 else (5 if band > 5 else band)
    col = STRIPES[band]
    for px_ in range(W):
        if in_apple(px_, py):
            put(px_, py, col)

# ------------------------------------------------------------------ write ---
# Emit column-major / rotated, per the FORMAT note above:
#   storage[r*165 + c] = display(520 - r, c)
SW = H          # 165 pixels per stored row
SH = W          # 521 stored rows
store = [0] * (SW * SH)
for r in range(SH):
    for c in range(SW):
        store[r * SW + c] = fb[c * W + (W - 1 - r)]

out = os.path.join(os.path.dirname(__file__), '..',
                   'dist', 'platforms', '_images', 'maclc.bin')
out = os.path.normpath(out)
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as fh:
    fh.write(struct.pack('<%dH' % (SW * SH), *store))
print('wrote %s (%d bytes, %dx%d displayed, stored %dx%d column-major RGB565)'
      % (out, SW * SH * 2, W, H, SW, SH))
