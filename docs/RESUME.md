# RESUME — MacLC Pocket (2026-08-14d: buildAZ VALIDATED — games playable)

## 0.0 ★★★ 08-14d: THE PORT WORKS. PROBES WERE THE POISON.

buildAZ (d04b8a2: ZERO probes — no sld hub in the fabric, all levers tied
off) + pristine maclc.hda (SHA-restored from zip): user played Prince of
Persia and "everything" on System 7.1 from a cold card boot, no OSD
touch (auto-mount buildAY working), no JTAG cable. The nondeterministic
late-boot faults (bus error @~217 / F-line @~800 / fast-restart deaths,
all post-scsi_dpram-fix) do NOT occur on the probe-less fit. The A/B vs
the same morning's buildAY cold boot (probed fit, pristine image, bus
error at first extension) isolates the instrument deck as the variable.
Treat ISSP debug fits as SUSPECT INSTRUMENTS from now on: they perturb
the machine they observe (hub + hot levers + placement pressure).
Re-enable instruments ONE at a time via USE_ISSP_<X> qsf macros
(per-instrument guards shipped in buildAZ; see ap_core.qsf).

Open items (user list 08-14d): floppy not working (Pocket floppy path
likely never HW-exercised — symptom TBD); PRAM color seeding or full
persistence (+ landmine #2: pram_save_req to nonexistent slot 220 stalls
SCSI ~450 ms per guest PRAM write — fix with whatever PRAM route);
patched boot0.rom (forced-warm POST skip) to card; remove Video Test
Pattern + Debug Disk Stage from interact/RTL; per-key input remapping;
video.json display_modes to match other cores.

(2026-08-14b header below: mystery B narrowed to ONE HASH; 256K VRAM SIMM shipped)

Paste into a fresh session: **"Resume docs/RESUME.md — §1-NEXT: fix the
Verilator harness, align it with mac_lc_pocket.sv (10 MB RAM, 256K VRAM,
real Egret), and reproduce the games-disk System 7.1 crash in
simulation."** boot_problems.md ★★★ sections carry deep history; this
file is current state. §2 down is the 08-13 ops crib (still accurate).
The 08-14 daytime QuickDraw/blit theory is DISPROVEN — history in
scratch/2026-08-14-autonomous-session.md and the session transcript.

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
★ jboot is EDGE-fired on ANY source change and the script writes a LEVEL:
alternate `jboot.tcl` / `jboot.tcl 0`, or back-to-back same-value calls
are SILENT NO-OPS (cost this session two phantom rounds).

Card launches were never affected. The old toggle-dance is obsolete.

## 0.5 ★ 08-14c: AUTO-MOUNT FIXED (buildAY); MYSTERY B IS NOW A BUS ERROR

- **Launch auto-mount SHIPPED + HW-VALIDATED** (buildAY = 69f48c9, on card
  AND the card-loaded fabric): core_top scans the framework data slot
  table once after dataslot_allcomplete and synthesizes mounts for slots
  310/311/320/210 with nonzero size (openFPGA docs: 0x008A is sent only
  for user re-loads; a deferload slot's launch assignment is table-only).
  Cold card boot auto-boots maclc.hda with ZERO OSD touches (user-
  confirmed). AMNT probe in read_bdst.tcl is the witness (HW read:
  fired=1 armed=1 state=7). JTAG pushes still need JMNT — reconfig wipes
  the table. Bench: scratch/amnt_bench (ModelSim; the block extracted
  verbatim, driven through the real core_bridge_cmd + mf_datatable +
  apf_blockdev; 15 checks incl. one-shot + OSD-pick regression).
- **Mystery B changed class**: with b389e16 (scsi_dpram prefetch fix) the
  games-disk death is now a BUS ERROR "after the first extension loads" —
  at the SAME dlv=+217 as the old II. IIOP did NOT fire at the death
  (vector 2 dispatches via $8, not $10): the bomb text and the silent
  IIOP independently confirm the class change. User: the Verilator run
  (other machine) did not show this — consistent with §1-NEXT's
  "sim boots clean => suspect Pocket-only glue/serving timing".
- **★ The machine SELF-RESTARTS after the bomb** (SysError re-fire
  escalation) — corpses are PERISHABLE. The restart's POST RAM test
  sweeps RAM with ascending AAAA fills (writer PC A4686E; read/XOR loop
  at A468D2-D8, fetches 241A/B592), so WWSP/WW40 "AAAA" evidence in any
  post-restart corpse is POST, not the killer — and IIOP fires
  SPURIOUSLY on POST's data read of $10. Old frozen-at-II captures stay
  valid (IIOP freezes on first trigger, which was the true death).
- Bus-error capture protocol: freeze BEFORE the restart. FRZE's compare
  is a raw 8-bit >= (landmine #3) — from a high count: release, poll
  until the counter wraps, then arm ABSOLUTE (scratch/buserr/roundA.sh
  automates this). Round A freezes late-boot to read the System's
  vector-2 handler from RAM ($8); Round B stages `frze trig +217` +
  `pcrb arm 0 <handler>` so the ring freezes at handler entry = the 64
  pre-fault PCs, then manual `frze on` preserves the format-$A/B bus
  fault frame (fault address at frame+$10).

## 1-NEXT ★ USER DIRECTIVE: REPRODUCE MYSTERY B IN VERILATOR

Goal: make the games-disk System 7.1 crash happen inside the Verilator
harness, where visibility is unlimited (per-instruction cpu_trace.log,
$display probes on anything, FST waves, MAME PC-stream diffing). The
next agent figures out the alignment details; this section is everything
known that they need.

### Why this is feasible
- The crash lands ~15-20 GUEST-seconds in ≈ 900-1200 video frames at the
  Pocket's 512x384 timing — same order as the routine 730-frame
  screenshot runs. Reasonable wall-clock.
- It is deterministic and invariant across cold/warm boot, card/JTAG,
  2/10 MB, 512K/256K VRAM — a software-visible divergence a full-trace
  sim should catch red-handed.
- MAME 0.264 boots the same image+ROM clean → docs/mame_compare.md's
  PC-stream divergence diff (sim trace vs MAME maincpu trace, same disk,
  same ROM) can mechanically find the FIRST divergent instruction.

### Harness status (verilator/) — BROKEN since 2026-08-09, fix first
- sim.v still references dataController ports deleted by the CD/Toolbox
  + second-floppy cuts: cd_snd_*, dbg_cda*, cdtb_*, cd_io_*, tb_lba,
  dskReadAddrExt (~11 refs). Delete/tie exactly as mac_lc_pocket.sv does
  (it is the reference consumer of dataController_top).
- Some later port syncs WERE kept: cd_* tie-offs (08-13) and buildAW's
  addrController `vram_force_512k` is already tied 0 (= 256K SIMM) in
  sim.v. The 256K alias + 512-B stride live in SHARED RTL — nothing to
  port there.
- ★ sim.v is its OWN top (`module emu`) with its OWN CPU instantiation
  and bus glue (VPA/DTACK/BERR/overlay) — NOT mac_lc_pocket.sv.
  docs/verilator_differences.md is the tracked-differences checklist:
  read it BEFORE editing, update it after. CPU-glue divergence between
  the two tops is exactly the class of bug that could make the sim NOT
  reproduce — aligning them IS the job (user: "make sure it matches
  what we have on the main maclc top, including the 10 MB RAM and
  such").
- Verilator tolerates multiple always-drivers; Quartus does not — any
  fix flowing BACK to FPGA must stay single-driver (CLAUDE.md).

### Config the sim must present (match the crashing hardware)
- **10 MB RAM**: the machine samples the memory config at reset;
  mac_lc_pocket gets cfg from core_top (opt_mem_size default 1 = 10 MB).
  Find sim.v's hardwired config and set 10 MB (SIMM 8 MB + motherboard
  2 MB). Fallback: the crash also fires at 2 MB — matching EITHER
  crashing config exactly is acceptable, but match one.
- **256K VRAM**: already default (vram_force_512k=0). Fast sanity: once
  booted, guest word $106 (ScreenRow) must read $0200 = 512.
- **Real HC05 Egret** (unconditional since 08-09). Do NOT enable
  EGRET_BEHAVIORAL for this hunt — VIA/Egret timing is part of the
  environment under test.
- **ROM**: releases/boot0.rom (SHA1 6bef5853ae736f3f06c2b4e79772f65910c3b7d4
  = MAME's verified 350eacf0.rom).
- **Disk**: a copy of Mac68KColorGames_v1.hda with SHA1
  dcd02c6c31335b87397af2c1944ebbea70cf4e26 (786,473,472 bytes).
  ★ NOT ON THIS PC — get it from the SD card (Assets/maclc/common/,
  card currently in the Pocket; the zip beside it holds the same file)
  or from the MAME box (its copy was restored from that zip). VERIFY the
  SHA1 before burning hours of simulation. (C:/repos/MacAtrium-7.1.hda
  is a DIFFERENT, older 256 MB image — not the reproducer; also
  Apple-partitioned, which scripts/hfs_check.py cannot walk yet.)
- How sim.v mounts a SCSI HD: it has its own dio/download plumbing
  (sim_main.cpp, `--help`). Watch image-size plumbing at 750 MB.

### Instrumentation once it boots (the whole point)
- $display on completed writes to $3FF700-$3FF7BF and $400E00-$400EFF
  with the current fetch PC = buildAX's WWSP with unlimited depth, one
  line of sim code.
- Trap the death directly: on fetch at $400E6C (or the vector-4 read of
  $10), dump A7, the $C000-$C17B patch frame, the BootGlobals band, and
  stop with a trace window around it.
- cpu_trace.log across the fatal window vs MAME maincpu trace of the
  same boot → first-divergence diff (docs/mame_compare.md; MAME PCs are
  8-digit 00Axxxxx; MAME's debugger defaults to the Egret HC05 — switch
  to the 68020).
- ★ If the sim boots the games disk CLEAN, that is ALSO decisive: the
  divergence then lives in Pocket-only glue (core_top/mac_lc_pocket/
  pocket_sdram/apf_blockdev serving timing), not shared RTL — diff
  sim.v's glue vs mac_lc_pocket.sv and suspect the ms-scale APF serving
  latencies the sim doesn't model.

### The fault signature to hunt (three identical HW captures + cold-card)
- ~15-20 s in: System 7.1 late boot (post-"Welcome", pre-Finder; GrayRgn
  unbuilt, CurApName unset), DSErrCode ($AF0) = 3.
- The Gestalt-family RAM patch $C000-$C17B (8-byte {selector,proc}
  records off ExpandMem+$5C; 'mach' selector visible in the fatal stack
  band) exits via its clean LINK/UNLK epilogue; the RTS at $C17A pops
  **$400E6C = the boot-blocks image base** ('LK' $4C4B, then BRA $6000
  0086, bbVersion $4418, bbSysName "\x06System") → executes the
  signature → II vector 4.
- The machine's last write before the fatal fetches: **AAAA → $3FF76E**
  (live stack). BootGlobals fields $400E60-66 churn AAAA/3400 values.
- CurStackBase = $3FF7BE; BootGlobals ptr table $3FF7AE-B9 =
  {$400BFC, $400E6C, $3FFBBE}; boot-handoff CODE executes at $3FF7BE+
  (move.l a3,-(sp); _ReleaseResource; movea.l ROMBase,a0; ...).
- The fault RE-FIRES periodically during the SysError wait (parked at
  ROM A02A38-3E polling $172) — in sim, the FIRST occurrence is the one
  with the clean trace.

## 1B. MYSTERY B DOSSIER — what is eliminated (all measured)

MAME 0.264 maclc (verified romset; our boot0.rom byte-identical) boots
the SAME image (SHA1-verified both ends) to desktop at 10 MB in BOTH
VRAM worlds. The card's copy hashes dcd02c6c… exactly, mtime untouched
since build — disk exonerated. Eliminated by direct measurement: the
image, the ROM, memory size (2/10 MB), VRAM size (512K/256K), the JTAG
boot path (cold card boot crashes identically), machine-identity bits
(VIA1 PA $D5 = MAME's $D4|config), analog RAM marginality
(deterministic, same PC 5+ rounds), TG68K decode ('LK' is genuinely
illegal; kernel byte-identical to MiSTer). Remaining suspects: Pocket
glue / timing-scale effects the shared RTL never sees (APF ms-scale
serving, SDRAM controller behavior under the 7.1 boot's access pattern)
— or a shared-RTL bug both FPGA tops exercise but MAME's model doesn't.

**A (maclc.hda +59):** still NOT re-run at true 10 MB. Bind maclc.hda to
slot 310 (card boot auto-mounts since buildAY; after a JTAG push use
jmnt), then push+jmnt(41992192)+jboot.

### Parallel hardware thread (PAUSED mid-compile — resume any time)
buildAX (WWSP writer-PC watcher, committed 83472dd) was COMPILING at
pivot time — check src/fpga/output_files, STA-gate all corners, archive
as scratch/builds/2026-08-14-buildAX-wwsp.sof. Round: push → romc_poll →
romv → jmnt 310 786473472 → jboot (EDGE-fired! alternate `jboot.tcl` /
`jboot.tcl 0`) → await II (~90 s, dlv +217) → scripts/wwsp.tcl +
iiop.tcl. Newest WWSP slots = the II exception-frame pushes (pinpoints
A7-at-fault); behind them, the AAAA writer WITH ITS PC. The Pocket sits
FROZEN on a buildAW card-boot corpse (`frze off` before any new round;
card now carries buildAW).

**The fault, fully decoded** (three identical captures incl. a cold card
boot): System 7.1's late boot handoff (code executing in the BootGlobals
area at CurStackBase $3FF7BE; 'mach' Gestalt selector in the fatal stack
band) calls into a Gestalt-family RAM patch ($C000-$C17B, 8-byte
{selector,proc} records off ExpandMem+$5C). The patch's clean
LINK/UNLK/RTS epilogue at $C172-$C17A returns THROUGH a return-slot that
holds $400E6C = the BOOT-BLOCKS IMAGE base ('LK' $4C4B, BRA $6000 0086,
bbVersion $4418, bbSysName "\x06System" — every field textbook) →
executes the signature → II vector 4 → DSErrCode 3. IIOP's last-write
capture: AAAA → $3FF76E (live stack) immediately before the fatal
fetches; WW40 sees AAAA/3400 churn in the BootGlobals fields $400E60-66.
So either the frame/return slot was overwritten mid-call (buildAX's
target), or the code/pointers loaded FROM DISK were corrupt (the hash's
target). The fault also RE-FIRES periodically during the SysError wait,
which is why PCRB match-rings on $400E6A/$400E6C freeze full of the
A02A38-3E wait loop — the delivery trigger stages at quiescence (the
crash itself), so match-rings can only ever catch the post-death
re-execution, not the first death. Dead theories with their disproofs:
wild-QuickDraw-blit (cold-boot POST-fill tracer shows no blit ever
touched $400E00-53), unresolved-jump-table (same), 16bpp/'scrn' geometry
(crash identical at ScreenRow=512), machine identity (VIA1 PA $D5 =
MAME's $D4|config bit).

**A (maclc.hda +59):** still NOT re-run at true 10 MB. Bind maclc.hda to
slot 310 (fresh card boot auto-mounts since buildAY — fixed 08-14c;
after a JTAG push use jmnt), then push+jmnt(41992192)+jboot.

## 1.5 SHIPPED THIS SESSION (buildAW, committed; dist/card = buildAV)

- **256K VRAM SIMM presentation** (4f81048 + this session): the LC ROM
  sizes VRAM by wrap test ('512K'@+$7FFFC then '256K'@+$3FFFC, readback —
  ROM $A04BC38, observed live in MAME at PC $A4BC4C/58). We now alias the
  CPU-side VRAM window mod 256K (A18 of a 256K SIMM is unconnected) and
  switch the CPU-side line map 1024→512-byte stride to match the 256K
  layout the driver then builds (ScreenRow=512 CONFIRMED on HW 3/3 and in
  MAME). Honest hardware: a 256K LC's own ROM refuses >8bpp, so the
  16bpp mode this fork cut can never be offered. **V256 JTAG lever**
  (scripts/v256.tcl, source_clk=clk_sys like FRZE — the clk_74a-sourced
  2-bit levers are the broken ones) restores 512K for A/B, no rebuild.
  buildAW sof archived (scratch/builds/2026-08-14-buildAW-vram256k.sof),
  STA all corners positive, ON THE FABRIC NOW. The card still carries
  buildAV — package buildAW for the next card trip.
- **verilator/mame/vram_256k.lua** — the same experiment as a MAME Lua
  write-alias tap, VALIDATED on MAME 0.264 (three API gotchas documented
  in its header; the display shears in alias mode because MAME's
  screen_update hardcodes the 1024 stride — judge by ScreenRow, not
  pixels). scratch/mame_agent_prompt.md = the full remote-agent protocol.
- Corpse-forensics craft: cold-boot POST fill (B6DB…) = a virgin-RAM
  write tracer; ramv bulk sweeps SMEAR (GDevice tail, trap table both
  faked corruption — single-word majority-of-3 for anything load-bearing;
  ramv_dump nw arg is DECIMAL).
- MAME-side caveat for future runs: attach disks as CHD (raw .hda/.hdv
  attaches READ-WRITE and the guest modifies the file; the agent's copy
  was restored from zip after SHA drift).

Full detail: scratch/2026-08-14-autonomous-session.md + this session's
transcript (mame_agent_prompt.md results in the chat).

## 2. WHAT SHIPPED 08-13 (all committed; dist/card = buildAV as of 08-14, fabric = buildAW)

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
