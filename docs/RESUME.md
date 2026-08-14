# RESUME — MacLC Pocket (2026-08-14: mystery B = wild QuickDraw blit; next up = the VRAM/geometry seam)

Paste into a fresh session: **"Resume docs/RESUME.md — pick up §1.5: is the
games-disk QuickDraw crash caused by the Pocket's changed VRAM/screen
geometry?"** boot_problems.md ★★★ sections carry deep history; this file
is current state. The 08-13 RESUME body below (§2 down) is the ops crib;
§0–§1.5 are 08-14.

★ USER DIRECTIVE for next session: focus on the QuickDraw pieces. We
changed the VRAM for this core (16bpp@512 → 8bpp@512, and the V8 now
hardwires ONE screen geometry). Strong hypothesis: the games disk's
drawing derives a blit destination from the screen/PixMap geometry, and
the changed geometry makes it overrun into the A5 world. §1.5 is the plan.

---

## 0. ★ READ FIRST — AUTONOMY IS UNBLOCKED (buildAR+, 08-14)

The memory-register deception is FIXED: `opt_mem_size` RTL default is now
**1 (10 MB)** (core_top.sv) and interact.json defaultval matches, so a
JTAG fabric push boots HONEST 10 MB — no menu toggle-dance needed. And
**JMNT** (scripts/jmnt.tcl) replays the OSD mount from the PC, so a
pushed fabric needs no physical interaction:
`jmnt.tcl 310 <bytes>` then jboot. Known sizes: maclc.hda=41992192,
Mac68KColorGames_v1.hda=786473472. Full autonomous round:
push → romc_poll (OS auto ROM re-push) → romv (verify) → jmnt → jboot.

Card launches were never affected (the OS writes the persisted choice at
launch either way). The old toggle-dance workaround is obsolete.

## 1. MYSTERY B — TRACED: a wild QuickDraw blit corrupts the jump table

Games disk (Mac68KColorGames_v1.hda) at VERIFIED true 10 MB
(MemTop=$A00000 in-guest) dies **Illegal Instruction (DSErrCode=3)**,
DETERMINISTICALLY (same PC every round, 3/3), executing `4C4B 6000` at
guest **$400E6C** (= A5+$270, in the app jump-table/globals). `4C4B` is
genuinely illegal (capstone 68020 AND TG68K agree: DIVxL.L with An-direct
EA) — so the CPU is CORRECT; it's a wild branch into non-code.

Mechanism (WW40 write-watcher + PCRB corridor + frozen-stack, all
re-verified single-word): QuickDraw BLITS into the A5 world — WW40 caught
**40 writes to $400E6x this round** (blit pattern 3400), matching the
blit-dispatcher corridor (jmp (a1) @ A2CC32 → BFEXTU (a4),D0 loop →
MOVE.L D0,(a5)+). The blit corrupts the jump table at $400E6C; control
later returns/jumps into it → II. Frozen stack: saved-A5 $400BFC then
return-addr $400E6C at $3FF7B6 (5/5 stable).

**NOT** analog RAM marginality (deterministic), **NOT** a TG68K decode
gap (kernel BYTE-IDENTICAL to MiSTer 5a75f9b, CRLF-only; capstone agrees
4C4B is illegal), **NOT** a read-path bug ($400E6C=4C4B stable 5/5;
ScrnBase=$50F40000 is sane). The bad blit DESTINATION is some BitMap/
GrafPort baseAddr (NOT ScrnBase) computed wrong.

**THE OPEN FORK:** Pocket-video-layout divergence vs a games-disk
incompatibility that also fails on a real LC. Kernel is MiSTer-identical,
so **the user's pointer is the decider: does this disk boot on the MiSTer
core?** If yes → Pocket-side; diff the video/QuickDraw globals. Next
on-Pocket instrument: catch the blit's live baseAddr (the GrafPort/BitMap
the blit loop reads) — one build, freeze at the blit-dispatcher PC-match.

**A (maclc.hda +59):** NOT run this session. ★ JMNT replays the mount
EVENT + SIZE only — the SECTORS come from whatever FILE the OS bound to
slot 310, which is the user's last OSD pick (currently the games disk,
vol "MacAtrium_Sys"). To test maclc.hda at true 10 MB the user must bind
it to 310 (pick it in the OSD, or a FRESH CARD BOOT auto-mounts the
data.json default filename maclc.hda) — then push+jmnt+jboot runs it
autonomously. jmnt with the right byte size (41992192) still needed so
the fabric knows the geometry.

## 1.5 ★ NEXT SESSION — THE VRAM / SCREEN-GEOMETRY SEAM (QuickDraw)

Working theory (user's, and it fits the evidence): the games disk's
drawing derives a destination from the SCREEN/PixMap geometry, and the
Pocket's changed VRAM+geometry makes a blit overrun into the A5 world
(jump table at $400E6C) → the deterministic II. The blit dest $400E60 is
MAIN RAM near A5=$400BFC (an OFFSCREEN buffer in the app heap, most
likely) — so suspect a rowBytes/height/bounds mismatch overrunning that
buffer, OR a screen-PixMap field the game reads that the Pocket sets
differently. ScrnBase=$50F40000 is correct (low 24b = $F40000 = the CPU
VRAM window); the desktop draws fine, so BASIC geometry works — the game
does something more geometry-sensitive.

### WHAT ACTUALLY CHANGED (Pocket vs MiSTer 5a75f9b) — diff these first
- **rtl/vram_bram.sv**: framebuffer DEPTH 196,608 words (384 KB, 16bpp
  @512x384) → **106,496 words** (192 KB @8bpp + 8K headroom); AW 18→17.
  The on-chip BRAM mirror is now half-size, 8bpp only.
- **rtl/maclc_v8_video.sv** (the big one): the `monid_v` monitor-mode
  CASE (ID 1 = 512x384 on 640-wide timing; ID 2 = 512x384 "alternate",
  512-wide; ID 6 = VGA 640x480) is REPLACED by a SINGLE HARDWIRED
  geometry = the old **ID 2**: h_total=640 h_active=**512**, v_total=407
  v_active=**384**. 16bpp dropped (bits_per_pixel default now 8).
  words_per_line max 640→256, packed_row_start/fetch_packed_base 18→17b,
  linebuf 1024→512. So the V8 ALWAYS presents 512x384x≤8.
- **rtl/addrController_top.v**: VRAM write path packs `packed =
  line*words_per_line + col` into the smaller BRAM; vram_waddr [17:0]→
  [16:0]. (Same packing idea both cores; the Pocket's is bounded at 256
  words_per_line.)
- **rtl/ariel_ramdac.sv** differs too (256-entry palette = exactly 8bpp)
  — diff it for the pixel-depth/CLUT path.
- CLAUDE.md "★ FRAME NUMBER IS RESOLUTION-DEPENDENT": MiSTer ran
  **monitor ID 6** (640x480); Pocket runs **monitor ID 2** (512x384).
  THE MONITOR ID THE GUEST SEES CHANGED. That drives what the Sony/QD
  screen-init writes as ScrnRow (rowBytes), screen bounds, and the
  GDevice — the most likely origin of a wrong blit geometry.

### THE INVESTIGATION PLAN (in order)
1. **Read the guest's screen state from a frozen corpse** (frze on at the
   SysError-wait loop, ramv_dump single-word majority; guest→SDRAM word =
   $100000 + guestbyte/2 at 10 MB — SIMM base). Characterize what
   QuickDraw actually built and compare to a correct 512x384x8 screen
   (rowBytes should be 512; bounds 0,0,384,512; pixelSize 8):
   - ScrnBase $0824 = $50F40000 (done, correct).
   - **ScrnRow / screen rowBytes** — low-mem global, and the main
     GDevice's PixMap.rowBytes. Follow MainDevice ($08A2 is `MainDevice`
     handle on some ROMs; verify the LC's global) → GDevice → gdPMap
     (handle) → deref to PixMap: baseAddr(+0), rowBytes(+4, top 2 bits =
     flags), bounds(+6: top,left,bottom,right), pixelSize(+31... use the
     Inside-Mac PixMap layout). Handle deref = read handle → master ptr →
     +offset. Tedious but mechanical over ramv_dump.
   - The monitor **sense/monid** the guest latched (what mode it thinks
     it has). If the game or its saved 'scrn'/depth expects a different
     mode, drawing math goes wrong.
2. **Find the blit's live destination geometry.** New instrument (one
   build): freeze the CAPTURE (works) at a PC-match on the blit
   dispatcher $A2CC32 (or the blit loop head), and snapshot the CPU
   registers feeding it — the dest baseAddr (A-reg used as `(a5)+` in the
   loop is the CPU A5 register loaded by QD, NOT the framework A5) and
   rowBytes/width/height. TG68K registers aren't probe-exposed, so
   capture the effective addresses instead: the FIRST and LAST write
   addresses of the blit run (WW40 already shows it lands in $400E6x) plus
   last_data_addr at setup. Compare the run's span/stride to the
   offscreen buffer's real size.
   ⚠ MACHINE-FREEZE IS BROKEN (§4.0) — use capture-freeze + the
   SysError-wait `frze on` for corpses; do NOT rely on iiop mfreeze/JMEM.
3. **MiSTer A/B (user has the working core).** Does
   Mac68KColorGames_v1.hda boot on MiSTer? If YES → Pocket regression,
   and the delta is the geometry above; read the SAME screen globals on
   MiSTer (via its HPS/MAME tap, docs/mame_compare.md) and diff. If it
   also fails on MiSTer/real LC → image incompat, pivot to mystery A.
4. **If it's geometry:** the fix is making the V8's reported monitor
   ID / screen bounds / rowBytes match what a real LC at the games disk's
   expected depth presents — or honoring the depth the game sets. Do the
   video-budget arithmetic in docs/PORT_STATUS.md before touching bpp.

### FAST START for next session
- `git -C ../MacLC_MiSTer show 5a75f9b:rtl/maclc_v8_video.sv | diff` (and
  vram_bram.sv, ariel_ramdac.sv, addrController_top.v) — read the deltas.
- Reproduce: push buildAV (or a fresh build) → romc_poll → romv →
  `jmnt.tcl 310 786473472` → `jboot` → within ~20 s it faults; the ROM
  SysError bomb parks in a WaitMouseButton loop at ROM A02A3x, so
  `frze.tcl on` there = a stable fault-time corpse to read.
- Then walk the screen PixMap (plan step 1).

Full detail: scratch/2026-08-14-autonomous-session.md.

## 2. WHAT SHIPPED TODAY (all committed; dist = buildAB)

- **Write path FIXED, two root causes, on-card proof**: C_FILL off-by-one
  (apf_blockdev sampled sd_buff_din a cycle early) + bridge readback lag
  (OS pairs bulk-read responses with the PREVIOUS transaction; serve
  wrbuf[widx-1] compensates). Proof: 3,846 corrupt sectors diffed on the
  card, MDB fingerprint matched the composed transform; maclc.hda
  RESTORED from the user's zip and re-verified. boot_problems ★★★.
- **ISO CD-ROM at SCSI ID 3** (buildAB, in dist): scsi.v CDROM target +
  rtl/cd_toc_stub.sv (single-data-track TOC, cd_audio's no-blob fallback
  byte-for-byte). Slot 320, maclc.iso auto-mounts; the 6.0.8 image
  already carries the Apple CD-ROM extension. CDA1/CDPH probes.
  HW status: answers the ROM scan politely every round; disc mount
  untested (needs a maclc.iso on card).
- **16 KB read-ahead confirmed** already present (RING_LOG=5 per disk).
- **Red herrings buried with measurements**: every SCSI data face
  byte-perfect (incl. SDCP full-burst 512/512); the Egret PRAM-write
  transaction healthy mid-flight (EGS1/EGS3: HC05 caught mid-bit in its
  receive loop); "PRAM-poisoning" was BootMask/eject semantics — the ROM
  boot-search giving up on purpose; scsi_irq tie-off CORRECT per MAME;
  repeat OSD mounts are invisible to the guest (only 0→1 registers).
- **Seed 2** (seed-7 buildAL had a -33 ps clk_sys fast-hold; qsf tail
  also repaired — a newline-less stray SEED 7 line was eating appends).

## 3. THE INSTRUMENT SUITE (buildAV = pushed fabric; scratch/builds has all A→AV)

| lever/probe | what | script |
|---|---|---|
| JMNT | replay a dataslot_update mount from the PC (slot,bytes) — no OSD | `jmnt.tcl <slot> <bytes>` |
| IIOP | last 4 fetches {pc,data} + 2 any-cycles, frozen at the vector-4 read of $10 (kernel-view data, full-32b addr); WW40 = last 4 writes to $400E6x; IIO2 = PDS-probe witness + ring top-bytes | `iiop.tcl` / `iiop.tcl rearm <v>` |
| JMEM | ⚠ memory-size override — WRITES but does NOT APPLY (§4.0); readback works | `jmem.tcl 2\|10\|off` |
| FRZE | manual freeze / auto at ABSOLUTE dlv count / `trig` = fire-only (stages PCRB) | `frze.tcl` on/off/arm/trig/cycle |
| PCRB/PCRS | 64-PC ring; triggers: delivery (via trig) or **PC-match** (source[23:0], two-stage: the delivery trigger stages it); K countdown ×16 writes; **spin-filtered** (A07840-7F, A14870-83 suppressed → the ring spans the whole death corridor as a call trail) | `pcrb.tcl arm <K> [matchPC]` / dump |
| EGS1/EGS2/EGS3 | Egret SR+handshake snapshot at freeze / windowed CB1-BYTEACK-TIP counters / HC05 PC at freeze | `read_bdst.tcl` |
| PSN1/PSN2 | SCSI bus + per-target snapshot at freeze | same |
| SDCP | full last pseudo-DMA burst (512 beats) | `sdcp.tcl` + `scratch/evidence/burst_id.py` |
| ROMV v4 | arbitrary-SDRAM sums/peeks/dumps (machine resets per scan unless FRZE holds) | `ramv_sum/ramv_dump/ramv_sweep/romv.tcl` |
| BDST/BDW0/BDLB/BDWR/BDWW/CDA1/CDPH/SDW0/SDCT/SCS1/SCS2 | serving/write/CD/burst deck | `read_bdst.tcl` |

**Canonical capture** (buildAP+ semantics): `frze off` → `frze trig +59`
→ `pcrb arm <K> [matchPC]` → `jboot` → poll `pcrb` frozen → `read_bdst`
+ `pcrb` dump. The delivery trigger STAGES the PC-match when both armed
(the first match fetch after the round's last delivery fires). Byte-mode
PDMA duplicates each byte on both bus halves (5050 4D4D for 'PM' is
CORRECT, not corruption). ROM PC → disasm line = 40800000 + (pc & 7FFFF)
in docs/MacLC_ROM_disasm.txt; HC05 PCs → rtl/egret/egret_rom_disasm.md.

**Illegal-instruction trace plan (mystery B), zero new builds:**
1. Boot the games disk at true 10 MB, let the dialog appear, `frze on`
   (manual freeze — RAM and vectors intact).
2. `ramv_dump 8 2` → RAM words 8-9 = the LONG at byte address $10 = the
   Illegal Instruction vector target (a RAM address once the System owns
   vectors).
3. `frze off`; re-run the round with `pcrb arm 0 <that PC>` staged
   (`frze trig +N`, N picked from BDLB near the round's end — games-disk
   rounds deliver far more than 59) → the ring freezes ON the handler
   entry holding the 64 spin-filtered PCs BEFORE the fault = the faulting
   code and its callers. Cross-check against docs/tg68kmissing.md before
   suspecting the image.

## 4. LANDMINES / CLEANUPS (each small; none block the mysteries)

1. ~~opt_mem_size JTAG-push reset~~ **FIXED 08-14** (§0): RTL default → 1
   (10 MB), interact.json defaultval → 1. Pushed fabrics boot honest.
0. **★ NEW 2-bit-source levers don't APPLY downstream** (JMEM memory
   override, IIOP machine-freeze). Source WRITE works (JMEM readback:
   enable/value both settable) but the consuming logic ignores it —
   `jmem 2`+jboot still boots 10 MB; `iiop rearm 3` never holds reset
   though iiop_frozen=1 & src[1]=1. Single-bit sources (jboot, iiop
   rearm-bit0) and the 11-bit FRZE all work. Leading theory: the raw
   altsource_probe `source` outputs feed a DIFFERENT clock domain
   UNSYNCHRONIZED (FRZE's ext_freeze is synced in core_top first). Fix:
   2-FF sync jmem_src/iiop_src into their consuming domain. Until then:
   NO JMEM 2 MB control round and NO machine-freeze — use the
   SysError-wait freeze (the bomb dialog parks in a WaitMouseButton loop
   at ROM A02A3x WITHOUT unwinding the fault frame; `frze on` there =
   stable fault-time corpse).
2. **pram_save_req fires at a NONEXISTENT slot 220** on every guest PRAM
   write (dirty-tracking → apf_blockdev save → OS error/timeout wedges
   the shared sequencer ~450 ms, stalling SCSI serving exactly when the
   System writes PRAM). Disarm the save-req until PRAM persistence
   returns, or re-add slot 220 to data.json and re-arm the path.
3. FRZE/BDLB delivery counters are 8-bit and wrap — mind thresholds
   (frze.tcl's +K handles it; absolute arms near 255 do not).
4. tb_blockdev.v needs a write-path test + the post-buildAA endian
   expectation fix (bench stale on both).
5. CD transient-wedge theory: UNCONVICTED (CDPH read idle at every
   sample). Keep CDPH in view during any flaky-round session.
6. verilator/sim.v remains broken (pre-existing); dataController port
   additions were kept in sync (cd_* tied off, dbg outputs omitted).

## 5. WORKING AGREEMENTS (unchanged, plus today's lesson)

One behavioral variable per SHIPPED build (instrument builds may stack
passive probes); archive every .sof (scratch/builds/ has the full A→AQ
chain); controls before conclusions — this session's four exonerations
(SCSI data, Egret handshake, PRAM-poisoning, IRQ tie-off) each died to a
measurement, not an argument; the screen is the final oracle and the
user narrates it. MiSTer @ 5a75f9b remains ground truth for Mac
behavior — but the Pocket's ms-scale serving and JTAG-push workflow
create conditions MiSTer never sees: async windows that become real,
and fabric registers that silently reset behind a menu that says
otherwise. When a setting matters, verify it AT THE FABRIC.
