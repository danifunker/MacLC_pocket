# RESUME — MacLC Pocket (2026-08-13 evening: data path EXONERATED, the crash is IN CODE; PCRB names it)

Paste into a fresh session: **"Resume docs/RESUME.md — continue the SCSI boot
crash hunt."** boot_problems.md ★★★ sections carry the history; this file is
current state.

---

## 0. WHERE THE HUNT STANDS — THE CRASH IS AN EGRET STALL, NOT SCSI

**The +59 "SCSI crash" is the System's first PRAM write (startup-device
entry) STALLING mid-Egret-transaction.** The "+59" is merely how much disk
I/O precedes it. The "PRAM poisoning" of the last two days was never a
side effect — the half-completed write IS the crash. Chain of proof:

- Every SCSI data face measured byte-perfect (card, blockdev face, target
  face, CPU receipt via SDCP full-burst: LBA 64, 512/512).
- K=384 PC window (PCRB): the masked-interrupt ioResult wait at ROM
  A14872, hand-pumping VIA1's SR (A148D8 cluster writes VIA1+$1400 = SR)
  — an Egret transaction being fed byte by byte.
- K=511 window: post-give-up wander ADB machinery — the abandonment is
  inside the ~2000 instructions between.
- **buildAL2 EGS1 snapshot at the death window: SR=$01 loaded, shift-OUT
  active, bit counter parked at 7 (ZERO bits shifted), CB1 idle high, no
  edge pending, HC05 running.** The Mac waits; the Egret never clocks the
  byte out. Mid-packet (earlier bytes pumped fine).
- Why MiSTer never saw it: its us-scale serving completed the async I/O
  before the wait loop ever needed the completion path; Pocket ms-scale
  serving makes the wait real and the Egret transaction runs under
  masked-interrupt hand-pumped pacing for the first time.

**The one remaining fork (buildAM decides):** did the Egret send NO CB1
edges in the death window (HC05/egret_wrapper side — fix its pacing), or
did it send them and the VIA swallowed them (the documented
ext_fall_edge_pending coalescing, CLAUDE.md's standing suspect — fix the
SR path / rate-limit CB1 per the repo's own recommendation)? EGS2 is now
window-scoped [trigger..freeze]: cb1_falls=0 => Egret side; >0 with bit
still parked => VIA side.

Also measured today (all in boot_problems/CLAUDE-adjacent comments):
write-path double-shift fixed & proven; ISO CD at ID 3 shipped (its
transient-wedge theory is UNCONVICTED — CDPH exists to check);
BootMask explains the wander (no PRAM); repeat mounts invisible;
seed-7 had a clk_sys hold violation at buildAL — seed 2 now.

## 1. NEXT ACTION — run buildAM's fork-decider, then fix

1. buildAM (window-scoped EGS2) was compiling at session end — verify STA
   CLEAN (the seed lesson), archive, push, mount.
2. Canonical capture: `frze off` -> `frze trig +59` -> `pcrb arm 384` ->
   `jboot` -> poll frozen -> `read_bdst` (EGS1/EGS2 lines).
3. Fork: cb1_falls==0 -> instrument/inspect egret_wrapper + HC05 firmware
   state at the stall (is the HC05 stuck in ADB autopoll? did it miss the
   Mac's TIP/BYTEACK transition?). cb1_falls>0 -> via6522 SR shift-out
   edge path (ext_fall_edge_pending) — fix per CLAUDE.md guidance
   (rate-limit CB1 in egret_wrapper preferred over touching the SR).
4. After the fix build: full boot expected — System 6.0.8 to Finder. Then
   the write round-trip acceptance (card diff vs zip), the CD smoke test
   (image already carries the Apple CD-ROM extension), and buildAB-class
   release packaging.

## 2. THE INSTRUMENT SUITE (buildAF carries everything)

| lever/probe | what | script |
|---|---|---|
| FRZE | manual freeze + auto-freeze at ABSOLUTE delivery count (8-bit, wraps — mind thresholds; drain quantizes to command boundaries) | `scripts/frze.tcl` on/off/arm N/arm +K/cycle |
| PCRB/PCRS | last-64-PCs ring, freezes on machine reset | `scripts/pcrb.tcl` [arm] |
| SDCP | full last pseudo-DMA burst (512 beats) | `scripts/sdcp.tcl`; identify with `scratch/evidence/burst_id.py` |
| ROMV v4 | arbitrary-SDRAM-range sums/peeks (machine resets per scan unless FRZE holds it) | `scripts/ramv_sum.tcl`, `ramv_dump.tcl`, `ramv_sweep.tcl`, `romv.tcl` (refs still valid) |
| BDST/BDW0/BDLB/BDWR/BDWW/CDA1/SDW0/SDCT/SCS1/SCS2 | serving/write/CD/burst deck | `scripts/read_bdst.tcl` |

★ ROMV scans RELEASE the machine after each trigger — RAM dumps of a dead
machine REQUIRE `frze.tcl on` first or the reboot marches over the corpse
(measured: DB6D:B6DB pattern mid-dump).
★ The offline side lives in `scratch/evidence/` (gitignored, regenerable):
master image + HFS map (System rsrc fork abs LBA 2075+, catalog 749+,
Driver43 64..95), `system_ref.txt`, `burst_id.py`.

## 3. BUILD/RELEASE STATE

- dist/ (SD card release) = **buildAB** (write fixes + BDWR/BDWW + ISO
  CD-ROM at ID 3 + 16KB-read-ahead-confirmed). The card carries it + the
  restored maclc.hda + data.json with CD slot 320 (`maclc.iso`
  auto-mounts; the image's System Folder already has the Apple CD-ROM
  extension).
- JTAG-only instrument builds: AC (ROMV v4) → AD (FRZE) → AE (SDCP) →
  AF (PCRB). All archived in scratch/builds/, all STA-clean, ~83% ALMs.
- Ops crib (push/mount/jboot/JTAG traps): unchanged, boot_problems §8 +
  the 08-12 RESUME at git 8cc9782.

## 4. APPENDIX — the MiSTer comparison (settled 2026-08-13)

The user's hint "compare the SCSI from the mister maclc core" is DONE:
- `rtl/scsi.v` / `rtl/ncr5380.sv` / `rtl/dataController_top.sv` are
  byte-identical to `../MacLC_MiSTer` @ 5a75f9b except the documented cuts
  (CD/Toolbox/2nd-floppy) — now partially restored (CD, ISO-only).
- The ONLY divergence surface is `src/fpga/core/apf_blockdev.v` (Pocket-only;
  replaces the HPS). Audit of it against scsi.v's HPS-face contract found:
  1. the C_FILL off-by-one (FIXED — see §0);
  2. the C_IDLE arbiter acked BOTH slots on simultaneous requests (FIXED —
     one-hot ack; was unobservable with one disk, structural with three);
  3. the read path, ack envelope, ring-refill handshake are CORRECT — the
     serving contract (io_rd cleared on ack rise, rd_hps_blk on ack fall,
     one fetch per envelope) is satisfied; same clk domain, no races found.
- The read ring: RING_LOG=5 → 16KB/disk target, MiSTer-identical. CD ring
  RING_LOG=3 → 4KB (M10K budget; CD is never the boot device).

## 5. WORKING AGREEMENTS

Unchanged (one variable per shipped build — buildAB is a documented
exception; archive every .sof; controls before conclusions; the screen is
the final oracle; MiSTer @ 5a75f9b is ground truth). The user (Dani
Sarfati, they/them, danifunker) wants: System 6.0.8 to the Finder from
maclc.hda, CD-ROM mounting from maclc.iso, then floppy validation, Egret
later.
