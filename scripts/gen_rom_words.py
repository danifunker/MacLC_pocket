# Convert boot0.rom into a tcl-sourceable word list for the ROMV binary search.
import struct, sys, io

src = sys.argv[1] if len(sys.argv) > 1 else r"..\MacLC_MiSTer\releases\boot0.rom"
dst = sys.argv[2] if len(sys.argv) > 2 else r"scratch\rom_words.tcl"

d = io.open(src, "rb").read()
assert len(d) == 524288, f"unexpected size {len(d)}"
words = struct.unpack(">262144H", d)

with io.open(dst, "w", encoding="ascii") as f:
    f.write("set ROMW {")
    f.write(" ".join(str(w) for w in words))
    f.write("}\n")
print(f"wrote {dst}: {len(words)} words")
# sanity: full sums must match the known references
s = sum(words) & 0xFFFFFFFF
a = sum((i ^ w) for i, w in enumerate(words)) & 0xFFFFFFFF
print(f"file sums: {s:08X} (expect 350F8EEE)  {a:08X} (expect F486F3D8)")
