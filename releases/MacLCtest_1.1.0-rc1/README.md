# MacLCtest 1.1.0-rc1 — RELEASE CANDIDATE (parked 2026-08-20)

The full CPU-perf stack + the 32 KB read ring on Hard Disk 1:
Phase B collapsed bus FSM, Phase C demand engine with slot-phase
quantized starts (t==1, load-bearing — docs/F-Line_Build_Errors.md
Case 3), always-on 1 KB I-cache, RING_LOG=6 on SCSI target 0.

- shipped as test-slot build "1.1.0-hd32c"
- fit: seed 7 (third roll of this netlist — seeds 4/11 lost the
  placement lottery at 275/308 M10K; Law 7 budget applied)
- ap_core.rbf md5: 6871d2814923a5a1a2b7f8f43ce9f61d (archived with .sof:
  scratch/builds/2026-08-20-hd32-seed7-*)
- netlist source: tree at bd6ab7b (pre-hoist; the later strict-LRM
  declaration hoists are map-verified zero-delta, so current main
  rebuilds this functionally identically)
- STA: met all corners (+2.039 setup / +0.119 hold)

HW verdict (user, 2026-08-20): working — including the 7.5.5 volume
that consistently corrupted on 1.1.0-sp (bus error / jump-to-garbage,
docs/F-Line_Build_Errors.md). The deeper ring was the user's theory for
that issue; the corruption MECHANISM remains unexplained (mitigated, not
root-caused) — the ncr5380 face bench on the Verilator box is still owed.

WATCH ITEM: one transient guest "out of memory" dialog on one boot,
cleared by a core restart. Single occurrence, not reproduced. If it
recurs, treat as new evidence (possible relative: the cold-load SDRAM
init class).

Fallbacks: v1.1.0-sp (16 KB ring, fully validated) then v1.0.3.
