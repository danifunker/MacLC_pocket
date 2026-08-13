# RESUME — MacLC Pocket, session handoff (2026-08-13: write-path fix + ISO CD-ROM in; crash hunt armed)

Paste into a fresh session: **"Resume docs/RESUME.md — continue the SCSI boot
crash hunt."** Read this file fully, then the two ★★★ sections at the end of
`docs/boot_problems.md`. Where they disagree, boot_problems.md wins on
history; this file wins on current state.

---

## 0. THE IMMEDIATE STATE

**Cold boot SOLVED. SCSI reads verified. The frontier is unchanged — the
deterministic +59-sector System-load crash — but the day produced a prime
suspect WITH a fix already in the tree, plus the witness to convict or
acquit it:**

- ★ **FOUND BY INSPECTION (2026-08-13): the SCSI WRITE path staged corrupt
  data.** apf_blockdev's C_FILL sampled `sd_buff_din` one cycle early
  (scsi.v's sector buffer is a registered read; every other RAM reader in
  the file has a wait state, the write fill didn't). Every sector the Mac
  wrote reached the card shifted one 16-bit word — word 0 doubled, word 255
  lost. **Fixed** (`C_FILL_W`, commit `1eabeae`). If System startup flushes
  the MDB (it typically does, early), every pre-fix boot wrote a corrupt MDB
  onto `maclc.hda`. This is RESUME-suspect-3's exact mechanism.
- **BDWR/BDWW probes now exist** (write count + LBA + err-sticky, first
  staged pair): one crash round answers "do writes fire, where, and did the
  OS accept them" — no more guessing.
- **CD-ROM (ISO-only) is back at SCSI ID 3** — scsi.v CDROM mode + the new
  `rtl/cd_toc_stub.sv` (single-data-track TOC synthesized from img_blocks,
  byte-per-byte cd_audio's no-blob fallback). Slot 320, `maclc.iso`
  auto-mounts, read-only, CDA1 probe. NO audio/bin-cue/Toolbox/Changer.
  HW-unvalidated.
- Disks already had the 16KB read-ahead (RING_LOG=5 default = 32 sectors per
  target, identical to MiSTer) — the user's question is answered, nothing to
  add.

**buildAB** (all of the above) was building at session end — check
`scratch/builds/` and `src/fpga/output_files/`. buildAA (.sof archived)
remains the pre-bundle baseline. ★ buildAB is deliberately a THREE-part
bundle (fix + instruments + CD) — the one-variable rule was traded for a
card-trip's worth of progress; the single-axis levers if it regresses vs
buildAA: revert `C_FILL_W` (one hunk) / rebuild with `cd_enable=1'b0` in
mac_lc_pocket.sv (the CD A/B lever).

## 1. FIRST ACTIONS NEXT SESSION

1. Confirm buildAB finished clean (map/fit/asm/sta all green, fit deltas vs
   13,021 ALM / 252 M10K — the CD body should cost ~2K ALMs, ~6 M10K).
   Archive the .sof to `scratch/builds/2026-08-13-buildAB-*.sof` BEFORE
   anything else.
2. ★ **BEFORE flashing: capture the evidence.** Copy `maclc.hda` OFF the
   card and diff against the user's master copy. Pre-fix crash rounds may
   have written shifted sectors (the MDB block is the prime spot). A diff
   showing exactly the C_FILL signature (content shifted +2 bytes, first
   word doubled) CONVICTS the write path as the crash mechanism with zero
   further builds. If they differ, re-copy a fresh maclc.hda before testing.
3. Flash buildAB (JTAG push → OSD-mount maclc.hda after EVERY push, or SD
   launch → auto-mount; §5 crib of the 08-12 RESUME still applies verbatim).
4. Reproduce: OSD Reset PRAM → `quartus_stp_tcl -t scripts/jboot.tcl` →
   `scripts/watch_lba.tcl`. Then `scripts/read_bdst.tcl` and read the NEW
   rows: **WRITES err/count/LBA + last-written words** (BDWR/BDWW).
   - If the crash is GONE and System boots: the write path was the killer;
     mission System-6-Finder likely COMPLETE — validate with a second cold
     boot, then commit/tag/release.
   - If writes fired and were REJECTED (err=1): the OS refuses
     target_dataslot_write on deferload-by-filename slots → different fix
     (surface the error to the guest? investigate APF write rules).
   - If NO writes fired: suspect 3 is dead; fall back to §3 instruments
     (ROMV v4 RAM-range oracle stays the favorite; polled-path SDW0 mirror
     second).
5. CD smoke test (independent): put any ISO on the card as `maclc.iso`
   (Assets/maclc/common/), boot with an AppleCD-driver-equipped System, and
   read CDA1 via read_bdst.tcl — cmds>0 proves the driver talked to ID 3;
   toc_rdy=1 + mounted=1 + a Finder desktop volume = mission accomplished.
   (System 6.0.8 needs the Apple CD-ROM extension installed to mount CDs.)

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
