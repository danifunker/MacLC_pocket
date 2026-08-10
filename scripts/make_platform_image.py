#!/usr/bin/env python3
"""Generate dist/platforms/_images/maclc.bin — the platform art the Pocket
shows on the core's About / platform screen.

FORMAT (derived from the reference cores, not from documentation): a raw
521 x 165 array of little-endian 16-bit RGB565 pixels, no header. That is
exactly 171,930 bytes, which is the size of both the stock core-template's
ex_platform.bin and Pocket-Amiga's amiga.bin. The Amiga image's dominant pixel
value is 0x0001 (essentially black), so a dark background is the house style.

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

# ---------------------------------------------------------------- machine ---
# Centred a little left so the stripe accent has room on the right.
CX = 196

# Drop shadow under the whole machine.
rect(CX - 104, 143, CX + 108, 149, SHADOW)

# --- Pizza-box base: wide, flat, the LC's defining shape ---
rect(CX - 100, 118, CX + 100, 142, PLAT)          # front face
rect(CX - 100, 118, CX + 100, 122, PLAT_LIT)      # lit top edge
rect(CX - 100, 138, CX + 100, 142, PLAT_DARK)     # shaded bottom lip
# Floppy slot (right of centre on a real LC) and a power LED.
rect(CX + 22, 128, CX + 82, 132, PLAT_DARK)
rect(CX - 84, 128, CX - 78, 132, rgb(120, 220, 130))
# Front vent grille.
for i in range(6):
    rect(CX - 66 + i * 8, 126, CX - 62 + i * 8, 135, PLAT_DARK)

# --- 12" RGB monitor sitting on the base ---
MX0, MX1 = CX - 66, CX + 66
MY0, MY1 = 26, 118
rect(MX0, MY0, MX1, MY1, PLAT)                    # case
rect(MX0, MY0, MX1, MY0 + 4, PLAT_LIT)            # lit top
rect(MX1 - 5, MY0, MX1, MY1, PLAT_DARK)           # shaded right side
# Neck/stand where the monitor meets the box.
rect(CX - 26, MY1 - 6, CX + 26, MY1 + 2, PLAT_DARK)

# --- Screen ---
SX0, SY0, SX1, SY1 = MX0 + 11, MY0 + 9, MX1 - 11, MY1 - 22
rect(SX0 - 2, SY0 - 2, SX1 + 2, SY1 + 2, BEZEL)
rect(SX0, SY0, SX1, SY1, SCREEN)
# Phosphor glow, brightest toward the top-left.
for y in range(SY0, SY1):
    for x in range(SX0, SX1):
        fy = (y - SY0) / max(1, SY1 - SY0)
        fx = (x - SX0) / max(1, SX1 - SX0)
        d = 1.0 - min(1.0, (fx * 0.7 + fy * 0.9) * 0.85)
        if d > 0.45:
            put(x, y, SCREEN_LT if d > 0.78 else rgb(
                int(28 + 32 * d), int(40 + 46 * d), int(52 + 52 * d)))

# --- A tiny Happy Mac on the screen ---
hx, hy = (SX0 + SX1) // 2 - 9, (SY0 + SY1) // 2 - 11
rect(hx, hy, hx + 18, hy + 22, INK)               # body
rect(hx + 2, hy + 2, hx + 16, hy + 12, SCREEN)    # its screen
rect(hx + 5, hy + 15, hx + 13, hy + 17, SCREEN)   # disk slot
put(hx + 6, hy + 5, INK); put(hx + 11, hy + 5, INK)   # eyes
for i in range(5):                                   # smile
    put(hx + 6 + i, hy + 8 + (1 if i in (0, 4) else 0), INK)

# --- Six-colour stripe, right of the machine ---
for i, c in enumerate(STRIPES):
    rect(360, 44 + i * 11, 470, 53 + i * 11, c)

# Baseline rule under the stripes.
rect(360, 118, 470, 120, PLAT_DARK)

# ------------------------------------------------------------------ write ---
out = os.path.join(os.path.dirname(__file__), '..',
                   'dist', 'platforms', '_images', 'maclc.bin')
out = os.path.normpath(out)
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as fh:
    fh.write(struct.pack('<%dH' % (W * H), *fb))
print('wrote %s (%d bytes, %dx%d RGB565)' % (out, W * H * 2, W, H))
