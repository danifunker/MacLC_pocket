# gen_ncr_bench.py — generate ncr5380_bench.v: the REAL rtl/ncr5380.sv with
# ONLY (a) the module renamed and (b) its two unpacked-array ports flattened
# to plain vectors (this vintage 32-bit vsim SIGSEGVs elaborating the array
# ports through an instance boundary). Regenerated fresh every run; the guard
# below asserts nothing else differs, so the bench always tests shipping RTL.
import sys, re
src = open('../../rtl/ncr5380.sv', encoding='utf-8').read()
out = src
subs = [
 ("module ncr5380 #(", "module ncr5380_bench #("),
 ("\toutput reg [31:0] io_lba[DEVS],", "\toutput [DEVS*32-1:0] io_lba,  // BENCH-FLATTENED (was: output reg [31:0] io_lba[DEVS])"),
 ("\toutput      [15:0] sd_buff_din[DEVS],", "\toutput [DEVS*16-1:0] sd_buff_din,  // BENCH-FLATTENED (was: [15:0] sd_buff_din[DEVS])"),
 ("\t\t\t\t.io_lba ( io_lba[i] ),", "\t\t\t\t.io_lba ( io_lba[i*32 +: 32] ),"),
 ("\t\t\t\t.sd_buff_din( sd_buff_din[i] ),", "\t\t\t\t.sd_buff_din( sd_buff_din[i*16 +: 16] ),"),
]
n = 0
for a, b in subs:
    if a not in out:
        print(f"GUARD FAIL: pattern not found: {a!r}"); sys.exit(1)
    out = out.replace(a, b, 1); n += 1
# guard: identical except the 5 lines
d = sum(1 for x, y in zip(src.splitlines(), out.splitlines()) if x != y)
if d != 5 or len(src.splitlines()) != len(out.splitlines()):
    print(f"GUARD FAIL: {d} lines differ (want 5)"); sys.exit(1)
open('ncr5380_bench_gen.v', 'w', encoding='utf-8', newline='\n').write(out)
print(f"generated ncr5380_bench_gen.v ({n} substitutions, {d} lines differ)")
