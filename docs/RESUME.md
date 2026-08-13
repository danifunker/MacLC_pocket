# RESUME — MacLC Pocket, session handoff (2026-08-12 end-of-day: the SCSI boot crash)

Paste into a fresh session: **"Resume docs/RESUME.md — continue the SCSI boot
crash hunt."** Read this file fully, then the two ★★★ sections at the end of
`docs/boot_problems.md` (the day's root-cause writeups: the download-tear saga
and the SCSI arc). Where they disagree, boot_problems.md wins on history; this
file wins on current state.

---

## 0. THE IMMEDIATE STATE

**Cold boot is SOLVED. SCSI is 90% there and stuck on ONE deterministic bug:**
the machine mounts the disk, reads it correctly, loads and runs the Apple
Driver43 partition, shows the **happy Mac**, loads ~26 sectors of System
6.0.8 — then crashes, resets to the `?` search loop, and (side effect) poisons
PRAM so later boots don't even scan SCSI until PRAM is reset.

Fabric at session end: **buildAA** via JTAG under a live OS session (mounts
lost at every push — see §5 ops). The SD card carries the SAME buildAA +
auto-mount data.json, so a fresh SD launch auto-attaches `maclc.hda` (40 MB
System 6.0.8 image, Assets/maclc/common/) with zero menu work.

First actions tomorrow:
1. `jtagconfig` (Pocket on? §6 traps). If the user relaunched from SD, the
   fabric is still buildAA (same bitstream) and instruments answer.
2. Reproduce once to warm up: user does OSD **Reset PRAM** (revival lever!) →
   `quartus_stp_tcl -t scripts/jboot.tcl` → watch with
   `scripts/watch_lba.tcl` → expect a +59-sector round ending back at `?`.
3. Then build the next instrument (§3 plan).

## 1. PROJECT STATE, ONE PARAGRAPH

Macintosh LC core for the Analogue Pocket (fork of the working MiSTer core at
`../MacLC_MiSTer`, the reference for "how the Mac works"). As of today the
port cold-boots reliably through the full ROM POST (including the cold RAM
march) to the flashing-`?` on every attempt — the months-long boot lottery was
the download path scatter-corrupting the ROM at SDRAM row crossings, fixed and
verified byte-perfect. SCSI serving works end to end (mount → size → sectors →
driver executes). The user (Dani Sarfati, they/them, handle danifunker) wants:
System 6.0.8 booting to the Finder from `maclc.hda`, then floppy validation,
PRAM/Egret work later ("let's get SCSI working first, then maybe explore the
egret again").

## 2. GIT / BUILD STATE

- Branch `instr/stm-console` @ `83ade7b`, tree clean. User pushed mid-evening;
  the last two commits (dist release `c267ff8`, README `83ade7b`) may still
  need a push.
- `dist/Cores/danifunker.MacLC/` is COMMITTED (force-added past the gitignore,
  deliberate release commit) and byte-current with buildAA.
- Every bitstream archived: `scratch/builds/2026-08-12-build{A..Q,R,S,T,U,V,W,X,Y,Y2,Z,Z2,AA}-*.sof`.
  buildAA = `2026-08-12-buildAA-sdbuff-endian.sof`.
- Day's fix chain (do NOT re-suspect these, each was measured then verified):
  buildS/T download row-crossing tear (arbiter form + one-shot accept; ROM now
  byte-perfect in SDRAM ×many scans) · buildU forced-warm patch retired (cold
  march passes on clean code) · buildV SCSI_DISABLE_DIAG=0 · buildW power-up
  PRAM ghost request disarmed · buildY mount-announcement latch un-gated (+
  data.json auto-mount maclc.hda/maclc2.hda) · buildZ SDMA_TIMEOUT 250 µs →
  250 ms · buildAA sd_buff face endianness (byte pairs no longer swapped).

## 3. THE FRONTIER — the deterministic System-load crash

**Facts (all measured, reproducible at will):**
- Each boot round delivers **exactly +59 sectors** (observed 83→142→201):
  DDM(1) + Driver43(32) + partition map(3) + boot blocks + ~21-26 System
  sectors. Last requested LBA at death = **partition-map block 3** (odd — a
  re-read, possibly the driver's error path).
- Screen: happy Mac (sometimes only a flash), then "some kind of reset", back
  to `?`. The user's words. No sad-mac codes observed yet — WATCH FOR THEM.
- **PRAM poisoning**: the dying System writes PRAM (startup-device entry)
  before the crash; afterwards boots never scan SCSI (the ID walk wanders,
  zero reads) until the OSD **Reset PRAM** action. This is the reproduction
  lever: Reset PRAM → jboot → one full crash round, every time.
- The System-load reads go through the driver's **POLLED NCR register path**,
  NOT pseudo-DMA: the CPU-side burst capture (SDW0/SDCT) saw only the ROM's
  512-beat byte-mode bursts (48 total), while the blockdev served 83+. The
  polled path at millisecond OS-serving latencies is essentially UNTESTED
  territory (MiSTer's HPS served in tens of µs).
- Data THROUGH the pseudo-DMA hop is verified correct post-buildAA ("PM"
  arrives 50 4D). The polled path's data has NOT been captured.

**Suspects, in order:**
1. The polled NCR read path under ms-scale REQ stalls (ring refills): the
   driver polls for REQ with its own budgets; scsi.v's ring/REQ gating
   (rd_cur_unfilled / rd_ahead_unfilled, scsi.v:455-473) is the 07-29 MiSTer
   fix class — correct on MiSTer's latencies, stress-tested here for the
   first time.
2. A specific sector/boundary in the System read sequence (the determinism
   suggests a fixed offset — e.g. a multi-sector READ crossing a ring
   boundary at a particular alignment).
3. SCSI WRITES: the System may write during startup (it definitely writes
   PRAM; does it write the DISK?). The write path (C_FILL/wrbuf, buildAA
   endian fix applied) is UNVALIDATED on Pocket — a corrupting write would
   also explain a deterministic crash AND would damage the image over time.
   ★ Check `maclc.hda`'s integrity against a known-good copy when the card
   is next in the PC (the user re-copied it fresh yesterday; repeated crash
   rounds MAY have dirtied it if startup writes fire).

**Next instruments (pick one per build, ~20 min each):**
1. **ROMV v4 — the favorite.** Generalize the oracle (mac_lc_pocket.sv
   ~line 1590) to scan ARBITRARY SDRAM ranges: widen the ROMV source
   encoding so base covers the full word space (currently {5'b10100, 18-bit}
   = ROM region only; needs ~23-bit base + the same completion-paired scan).
   After a crash, scan the RAM where the System landed and diff against the
   file offline — the exact technique that cracked the ROM tears. Needs the
   System file's expected bytes: copy `maclc.hda` off the card to this PC
   (next card trip) and walk HFS offline (`scripts/hfs_check.py` exists in
   the MiSTer repo's tooling; or raw-sector compare using the LBAs the
   blockdev logs).
2. Wire scsi.v's `dbg_ring0/1` (ring serve/refill anchor words,
   ncr5380.sv:791-792 feeds, dataController passthrough exists) to ISSPs —
   MiSTer's purpose-built watch for exactly this marginality class.
3. Polled-path data capture: mirror SDW0 at the NCR register read (selectSCSI
   data-register reads), compare against BDW0's blockdev-side words.
4. A write-watch: count sd_wr events + capture the first written sector's
   words — answers suspect 3 cheaply.

## 4. THE INSTRUMENT SUITE (all standing on buildAA, all JTAG)

Everything from the morning deck (§ RESUME history / boot_problems §6) PLUS
today's SCSI instruments:

| probe | meaning | decoder |
|---|---|---|
| BDST | [31] saw_tmo [30] read [29] ack [28] done [27] delivered [26] mount-seen [25:23] RAW announce count [22:0] img blocks | `scripts/read_bdst.tcl` |
| BDW0 | first two words of last DELIVERED sector (blockdev side) | same |
| BDLB | {deliveries[7:0], last requested LBA[23:0]} | same |
| SDW0 | first two words of last pseudo-DMA burst (CPU side) | same |
| SDCT | {bursts[7:0], prev beats[11:0], cur beats[11:0]} (512=byte-mode, 256=word) | same |
| SCS1 | {dbg_scsi2 (phases+io), dbg_scsi (sel/arb: out_en/SEL/BSY/tbsy/mounted/busdata)} | same |
| SCS2 | {last opcode per target, rst count + hs2 completion flags} | same |
| ROMV/RVSU/RVAX | the v3 ROM oracle (still ROM-region-only) | `scripts/romv.tcl` (×3), `romv_survey.tcl`, `romv_peek.tcl` |
| JBOO/DIAG/STMC/SCCR/SCCS | boot strobe / diag entry / STM console | `scripts/jboot.tcl`, `diag_boot.tcl`, `stm_console.tcl` |
| BOOT/CPUC/CPUA/... | the original deck | `scratch/tools/boot_state.tcl`, `cpu_probe.tcl` |

Live stream: `scripts/watch_lba.tcl` (deliveries+LBA+bursts every 2 s ×40 s).
★ ROMV v3 instrument honesty: ~1%/trigger startup misreads — trust single-
trigger range sums, verify lg=0 findings with romv_peek majority-of-3.
★ Never scan while a download may be in flight (romv_run steals ram_addr but
not ram_we).

## 5. OPS CRIB — the mount/push/boot cycle (learned the hard way today)

- **JTAG push** = fabric swap: the OS re-pushes the ROM slot automatically
  (~60 s, watch BRGC/ROMC = 262144) but does NOT replay disk announcements —
  the user must OSD-mount `maclc.hda` on Hard Disk 1 after EVERY push. Read
  BDST first: mount seen + 82016 blocks = ready.
- **SD launch** = fresh OS session: auto-mount works (announcement un-gate +
  data.json filenames). Hands-free reproduction: launch → cold boot → the
  crash round runs by itself.
- **jboot** re-boots the machine hands-free; mounts survive machine resets.
  BUT post-crash the poisoned PRAM blocks SCSI scanning — **OSD Reset PRAM
  first**, then jboot.
- The `?`-loop's SCSI rescan walks IDs DOWNWARD from 6 with real selection
  timeouts — a round can take >40 s to reach our ID-0 disk. Don't declare
  "no reads" from a short watch window.
- Machine probes (cpu_probe/boot_state) are passive; ROMV scans RESET the
  machine (0.5 s hold).
- Card workflow when needed: `bash scripts/package.sh` → copy → `cmp` →
  PowerShell eject (Namespace(17) InvokeVerb Eject; retry once if "still
  mounted"). Card files live at `D:\Assets\maclc\common\` — `maclc.hda`
  (40 MB 6.0.8, partition map verified), `maclc2.hda` reserved name,
  `Mac68KColorGames_v1.hda` (750 MB, MiSTer-proven, also DDM-valid).
- Quartus 18.1.0/625 at `C:\intelFPGA_lite\18.1`; Bash PATH exports, python
  3.12, JTAGServer service trap, `quartus_stp_tcl` script style, Tcl signed
  `scan %x` trap: all unchanged, see boot_problems §8 and the environment
  crib in the old resume (git history of this file @ `34e858a`).
- Build chain: `cd /c/repos/MacLC_Pocket/src/fpga && quartus_map ap_core &&
  quartus_fit ap_core && quartus_asm ap_core && quartus_sta ap_core`
  (~20 min, background task, absolute cd). Archive every .sof to
  scratch/builds/ BEFORE pushing the next.

## 6. WORKING AGREEMENTS (unchanged, they carried the day)

1. ONE behavioral variable per shipped build; passive probes ride along.
2. Archive every .sof; commit every tested state.
3. CONTROLS BEFORE CONCLUSIONS — today's wins all came from instruments that
   survived cross-examination (repeat-scan stability, dual-sided captures,
   known-byte references).
4. The screen is the final oracle; the user narrates it. Ask them to watch
   for sad-mac CODES specifically.
5. MiSTer (`../MacLC_MiSTer` @ 5a75f9b) is ground truth for how the Mac
   works; its docs/git carry the prior SCSI sagas (scsi.v:172 records the
   'RE'-for-'ER' swap saga this port re-lived one layer up).
