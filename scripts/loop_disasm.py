#!/usr/bin/env python3
"""Aggregate sample_loop.tcl output into a reconstructed loop disassembly.
Ported from lbmactwo_MiSTer (MacLC I/O decode: 24-bit bus, I/O at $F0xxxx).

Usage:
    bash -c 'PATH=/c/intelFPGA_lite/17.0/quartus/bin64:$PATH \
        quartus_stp_tcl -t scripts/sample_loop.tcl 120' > samples.txt
    python scripts/loop_disasm.py samples.txt

Collects unique (PC, opcode-word) pairs, sorts by PC, fills the word map,
and (with capstone) disassembles the byte stream starting at the lowest
PC. Unfilled gaps print as nop markers. Also tallies the I/O reads (PDRD).
"""
import sys, collections

words = {}            # addr16 -> Counter of opcode words seen
iords = collections.Counter()   # (addrfield, value) -> count

for line in open(sys.argv[1]):
    p = line.split()
    if len(p) != 3:
        continue
    if p[0] == "IFPAIR":
        a, d = int(p[1], 16), int(p[2], 16)
        words.setdefault(a, collections.Counter())[d] += 1
    elif p[0] == "IORD":
        iords[(int(p[1], 16), int(p[2], 16))] += 1

if not words:
    sys.exit("no IFPAIR samples")

print(f"=== {sum(sum(c.values()) for c in words.values())} IF samples, "
      f"{len(words)} distinct PCs ===")
lo = min(words)
hi = max(words)
print(f"PC range 0x{lo:04X}..0x{hi:04X} (low 16 bits only — see PIFA/PADR for the full address)")

# Word map (majority vote per address — stray misattributed pairs lose).
wmap = {}
for a, ctr in sorted(words.items()):
    best, cnt = ctr.most_common(1)[0]
    flag = "" if len(ctr) == 1 else f"  (AMBIGUOUS {dict(ctr)})"
    wmap[a] = best
    print(f"  {a:04X}: {best:04X}  x{cnt}{flag}")

# Assemble contiguous byte stream for capstone (gaps -> 0x4E71 NOP marker).
try:
    import capstone
    code = bytearray()
    for a in range(lo, hi + 2, 2):
        w = wmap.get(a)
        code += (w if w is not None else 0x4E71).to_bytes(2, "big")
    md = capstone.Cs(capstone.CS_ARCH_M68K, capstone.CS_MODE_M68K_020)
    md.skipdata = True
    print("\n=== disassembly (gaps shown as nop) ===")
    for i in md.disasm(bytes(code), lo):
        gap = "" if wmap.get(i.address) is not None else "   <- GAP/unsampled"
        print(f"  {i.address:04X}: {i.mnemonic} {i.op_str}{gap}")
except ImportError:
    print("(capstone not available — word map only)")

if iords:
    # MacLC: I/O lives at $F00000 + (field<<4) on the 24-bit bus
    # (the 32-bit-mode alias the OS uses is $50F00000 | offset).
    print("\n=== I/O reads (addr = 0xF00000 | field<<4) ===")
    for (af, val), n in iords.most_common(20):
        full = 0xF00000 | (af << 4)
        off = full & 0x1FFFFF
        dev = "?"
        if   0x10000 <= off < 0x12000: dev = f"SCSI reg {(off >> 4) & 7}"
        elif 0x06000 <= off < 0x08000: dev = "SCSI DACK ($F06000)"
        elif 0x12000 <= off < 0x14000: dev = "SCSI DACK ($F12000)"
        elif off < 0x04000:            dev = f"VIA1 reg {(off >> 9) & 15}"
        elif 0x04000 <= off < 0x06000: dev = "SCC"
        elif 0x14000 <= off < 0x16000: dev = "ASC"
        elif 0x16000 <= off < 0x18000: dev = "IWM/SWIM"
        elif 0x24000 <= off < 0x26000: dev = "Ariel"
        elif 0x26000 <= off < 0x28000: dev = f"PseudoVIA reg ${off & 0x1FFF:X}"
        print(f"  0x{full:06X} ({dev}) = 0x{val:04X}   x{n}")
