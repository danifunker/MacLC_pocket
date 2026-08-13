# RESUME — MacLC Pocket, session handoff (2026-08-13: write-path fix + ISO CD-ROM in; crash hunt armed)

Paste into a fresh session: **"Resume docs/RESUME.md — continue the SCSI boot
crash hunt."** Read this file fully, then the two ★★★ sections at the end of
`docs/boot_problems.md`. Where they disagree, boot_problems.md wins on
history; this file wins on current state.

---

## 0. THE IMMEDIATE STATE

**Cold boot SOLVED. SCSI reads verified. And the crash-round evidence is
IN: the SCSI write path was corrupting the disk on every System startup —
two root causes, both found and FIXED this session (boot_problems.md ★★★
2026-08-13 has the full forensics):**

- ★ **PROVEN ON-CARD:** after the 08-12 crash rounds, the card's
  `maclc.hda` differs from the user's authoritative zip in **3,846
  sectors**. The on-card MDB (LBA 98) is the guest's own (sane) MDB
  shifted LEFT one 16-bit word, 'BD' signature wrapped to the tail —
  the exact composition of the two defects below. The System DOES write
  during startup (MDB, bitmap, catalog), every write shipped corrupt, and
  the first re-read of a just-written sector at a fixed point in the
  startup sequence is the most economical explanation of the
  deterministic +59 crash.
- **Fix 1 — C_FILL off-by-one** (`C_FILL_W`): the fill sampled
  `sd_buff_din` one cycle early → staged sectors right-shifted one 16-bit
  word. Found via the MiSTer diff (scsi.v/ncr5380/dataController are
  byte-identical to 5a75f9b modulo cuts; apf_blockdev is the only
  divergence surface).
- **Fix 2 — bridge readback lag** (`buf_ridx = widx-1`): the OS pairs
  each bulk SPI read response with the PREVIOUS transaction → file word w
  arrived as wrbuf[w+1]. Only multi-word readbacks see it; the sector
  buffer is the core's only one. Measured from the card fingerprint
  (127/128 words at exactly +1×32-bit).
- **Card RESTORED** — maclc.hda re-copied from `C:\files\MacLC_6-0-8.hda.zip`
  and cmp-verified. ★ Old .sofs corrupt it again on any System boot.
- **BDWR/BDWW probes** (write count/LBA/err + first staged pair) ride
  along; **CD-ROM (ISO-only) is back at SCSI ID 3** — cd_toc_stub TOC,
  slot 320, `maclc.iso` auto-mount, read-only, CDA1 probe. NO
  audio/bin-cue/Toolbox/Changer. HW-unvalidated.
- Disks already had 16KB read-ahead (RING_LOG=5, MiSTer-identical).

**buildAB** (both fixes + probes + CD) was building at session end.
buildAA (.sof archived) = pre-bundle baseline. Single-axis levers if
needed: revert `C_FILL_W` / revert `buf_ridx` / `cd_enable=1'b0`.

## 1. FIRST ACTIONS NEXT SESSION

1. Confirm buildAB finished clean (map/fit/asm/sta green; fit delta vs
   13,021 ALM / 252 M10K — CD body ≈ +2K ALMs, +6 M10K). Archive the .sof
   to `scratch/builds/2026-08-13-buildAB-*.sof`, then `bash
   scripts/package.sh` and copy to the card (card is at `D:`).
2. Boot it (SD launch auto-mounts; after any JTAG push, OSD-mount
   manually). Expect: the +59 crash GONE and System 6.0.8 reaching the
   Finder. Watch `read_bdst.tcl`: BDWR count>0 err=0 says writes fired and
   were accepted; BDWW shows the first pair of the last write (file
   order).
   - Crash gone → **write round-trip acceptance**: let the Finder settle,
     power off, pull the card, diff maclc.hda vs the zip — differences
     must now be ONLY legitimate (valid 'BD' MDB, sane fields). Then
     commit/tag/release; floppy validation next per the user's list.
   - Crash persists → BDWR tells whether writes even fired this round;
     the §3 ladder takes over (ROMV v4 RAM-range oracle first,
     polled-path SDW0 mirror second).
3. CD smoke test (independent): any ISO as `maclc.iso` in
   Assets/maclc/common/, boot a System with the Apple CD-ROM extension,
   read CDA1 (cmds>0 = driver talked to ID 3; toc_rdy=1 + desktop volume
   = done). System 6.0.8 needs the AppleCD extension installed to mount.

## 2. WHAT THE MISTER COMPARISON SETTLED (2026-08-13)

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

## 3. THE FRONTIER (unchanged facts, from 08-12)

- Each boot round delivers exactly +59 sectors (83→142→201): DDM(1) +
  Driver43(32) + pmap(3) + boot blocks + ~21-26 System sectors. Last
  requested LBA at death = partition-map block 3 (a re-read — driver error
  path?). Happy Mac shows, then reset to `?`, PRAM poisoned (startup-device
  entry) so later boots skip SCSI until OSD Reset PRAM.
- ROM-phase reads go through pseudo-DMA (48 × 512-beat byte-mode bursts,
  SDW0/SDCT); System-phase reads go through the driver's POLLED NCR path —
  data through PDMA verified correct post-buildAA; polled-path data still
  never captured (SDW0 mirror at selectSCSI data reads = instrument #3).
- Next instruments if the write theory dies: ROMV v4 (widen the oracle to
  arbitrary SDRAM ranges, scan where the System landed, diff offline — the
  technique that cracked the ROM tears), dbg_ring0/1 to ISSPs, polled-path
  capture, in that order. (§3 of the 08-12 RESUME, git `8cc9782`, has the
  full text — this file supersedes but does not repeat it.)

## 4. INSTRUMENT SUITE (buildAB = buildAA deck + three new)

| probe | meaning | decoder |
|---|---|---|
| BDST/BDW0/BDLB | blockdev serving story / first served words / deliveries+LBA | `scripts/read_bdst.tcl` |
| **BDWR** | {saw_wr_err, wr_cnt[6:0], last write LBA[23:0]} | same |
| **BDWW** | first two staged words of the last WRITE (file order) | same |
| **CDA1** | CD target: {toc_rdy,no_media,mounted,ok,sense,cmds,last_op} | same |
| SDW0/SDCT | CPU-side pseudo-DMA capture | same |
| SCS1/SCS2 | phases+handshake / last opcode+resets | same |
| ROMV/RVSU/RVAX | ROM-region oracle (v3, ROM-only) | `scripts/romv.tcl` etc. |
| JBOO/DIAG/STMC/... | boot strobe / STM console | `scripts/jboot.tcl` etc. |

★ Ops crib (mount/push/boot cycle, JTAG traps, card workflow, build chain):
§5-6 of the 08-12 RESUME at git `8cc9782` — unchanged, still authoritative.

## 5. WORKING AGREEMENTS

Unchanged (one variable per shipped build — buildAB is a documented
exception; archive every .sof; controls before conclusions; the screen is
the final oracle; MiSTer @ 5a75f9b is ground truth). The user (Dani
Sarfati, they/them, danifunker) wants: System 6.0.8 to the Finder from
maclc.hda, CD-ROM mounting from maclc.iso, then floppy validation, Egret
later.
