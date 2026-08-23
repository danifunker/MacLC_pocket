# MacLCtest 1.1.3-rc1 — RELEASE CANDIDATE (parked 2026-08-22)

v1.1.2-rc1 (input settings) PLUS the I-cache correctness fix and the
Case-5 (7.5.5) mitigation.

## I-cache `.enable` must be a non-constant net (never `1'b1`)
Fixes the 8bpp + 32-bit-addressing Finder crash. `fetch_cache.enable(
icache_en)` <- core_top `opt_icache_off` @ bridge 0xF0000064. `enable_r`
confirmed surviving in the fitted netlist at every placement tried
(quartus_sta register query, not a report read). Structural fix — first
HW validation on the Pocket is this build (7.5.5 boots). Detail:
docs/RESUME.md §-7, CLAUDE.md, docs/verilator_differences.md.

## hd32b asymmetric SCSI read ring (rtl/ncr5380.sv, `RING_LOG(i==0?6:1)`)
HD1 (boot) = 64-sector/32 KB, HD2 = 2-sector minimum. Restores Case 5's
only known mitigation on the boot disk while reclaiming HD2's M10K so the
fit stays out of the ~89% placement-lottery band.

Mechanism: apf_blockdev refills the ring ONE sector at a time, on demand,
no prefetch/overlap (a full clk_sys->74a->bridge->SD round-trip each).
MiSTer's HPS keeps a 16 KB ring fed under 7.5.5's Macintosh Easy Open read
load; the serialized Pocket refill cannot — the ring empties and the
(shared) ncr5380 host face shifts a byte at the refill boundary, corrupting
a pointer (bus error, A0=$50F06060). 32 KB buffers 2x ahead of the same
slow refill.

★ This is a MITIGATION, not the root fix. The real answer is to pipeline
apf_blockdev so both disks run 16 KB like MiSTer (gate on tb_scsi_face,
which has never completed a run — owed on the Verilator box). Cost of the
2-sector HD2: HD2 is Case-5-prone under HEAVY HD2 reads; the boot path
(HD1) is protected.

## Fit
- shipped as test-slot build "1.1.3-hd32b-s12"
- seed 12; 261/308 M10K (85%) — out of the lottery band; 14,113 ALMs (76%)
- STA met all corners, worst slack +0.062 ns, zero negative paths
- ap_core.rbf raw sha1 fbbccc28…; bit-reversed bitstream.rbf_r sha1
  d5007a13… (.sof archived: scratch/builds/20260822-hd32b-s12-fbbccc28)

## HW verdict (user, 2026-08-22)
7.5.5 boots to Finder, **3 of 4 boots clean** (was 0-to-Finder before);
performance "much much better".

## Open / next
- 32-bit memory to be figured out properly (ongoing).
- apf_blockdev pipelining = the queued root fix for Case 5.

Fallbacks: v1.1.2-rc1 -> v1.1.1-rc1 -> v1.1.0-rc1 -> v1.1.0-sp -> v1.0.3.
