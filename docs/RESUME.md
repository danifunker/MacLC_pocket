# RESUME — MacLC Pocket (2026-08-13 evening: data path EXONERATED, the crash is IN CODE; PCRB names it)

Paste into a fresh session: **"Resume docs/RESUME.md — continue the SCSI boot
crash hunt."** boot_problems.md ★★★ sections carry the history; this file is
current state.

---

## 0. WHERE THE HUNT STANDS (read this, believe this)

**The +59 crash is NOT a data problem. Every face is measured byte-perfect:**
- Card: `maclc.hda` restored from the zip; the retried sector (LBA 82 class)
  serves `FFFC 4ED0` = master-exact at the blockdev face (BDW0, repeated).
- CPU receipt: **SDCP** (buildAE, full-burst capture) caught the driver
  re-read's sector as the CPU received it: **LBA 64, 512/512 bytes perfect**.
- The final command before death (READ10, pmap block 3) completes GOOD with
  correct bytes ('PM' received, hs2=F). **Then the machine dies executing
  code.** The dying routine is the question; buildAF's **PCRB** (64-PC ring,
  frozen at the crash reset) answers it.

**The +59 round's true anatomy** (freeze-mapped): DDM + pmap + boot blocks +
~26 System-file sectors + **a ~19-sector driver RE-read (READ6 from LBA 64,
fetch frontier parks at 82)** — that's System startup re-loading Driver43 to
install it — then pmap 2,3 re-reads (driver Open locating its partition?),
then death. Rounds are BIT-DETERMINISTIC: 2 MB of RAM is sum-identical
across separate rounds frozen at the same drained delivery count.

**Theories executed this session (do not resurrect):**
- Write-path corruption: was REAL (two bugs, fixed buildAB, on-card proof in
  boot_problems ★★★) but NOT the crash — a zero-write round crashes at +59.
- PRAM poisoning: DEAD. The user's ROM-reload experiment (PRAM untouched)
  booted a full round. Post-crash wander is ROM boot-search state, cleared
  by any machine reset, sometimes self-clears (~2 min retries).
- scsi_irq -> pseudovia IFR3: tie-off is CORRECT (MAME LC ground truth;
  MiSTer MacLC.sv 1184-1205 carries the full reversal history; System 6 was
  immune there). Do NOT re-wire.
- CD at ID 3: passive and polite through every round (CDA1 answers no-disc
  sense; boot proceeds past it). Not a factor.

## 1. NEXT ACTION — one capture, then read code

buildAF (PCRB) flow, all JTAG, card stays in:
1. Push `scratch/builds/2026-08-13-buildAF-pcrb.sof`, wait BRGC/ROMC=262144
   (`scratch/tools/rom_repush_check.tcl`), user OSD-mounts maclc.hda.
2. `jboot.tcl` → wait ~2 s (round underway) → `pcrb.tcl arm` (arming before
   jboot is useless — jboot's own reset would freeze the ring).
3. Round crashes (~10 s). `pcrb.tcl` → 64 PCs, oldest→newest.
4. Read PCs against `docs/MacLC_ROM_disasm.txt` (ROM = 00A0xxxx) /
   `docs/MacLC_ROM_Boot_Sequence_Analysis.md`. RAM PCs = System/driver code
   (the re-read driver image or System startup — correlate with where the
   19-sector re-read landed if needed).
5. The routine names the divergence; fix follows. Candidate classes if the
   PC lands in: driver Open (env divergence: V8/pseudovia flags, memory
   config — note Memory=2MB is still the default from the diag era); the
   ROM blind-transfer primitive $A08CFA (its $8-vector bus-error dance —
   MiSTer MacLC.sv:826 records that contract); slot/PDS scan artifacts.

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
