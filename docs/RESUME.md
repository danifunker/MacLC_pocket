# RESUME — MacLC Pocket (2026-08-14b: mystery B narrowed to ONE HASH; 256K VRAM SIMM shipped)

Paste into a fresh session: **"Resume docs/RESUME.md — §1: hash the card's
games disk against dcd02c6c…; if it differs, restore from the zip and
re-test; if it matches, build the buildAX stack-band write-watcher."**
boot_problems.md ★★★ sections carry deep history; this file is current
state. §2 down is the 08-13 ops crib (still accurate). The 08-14 daytime
QuickDraw/blit theory is DISPROVEN — history in
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

## 1. MYSTERY B (games-disk Illegal Instruction) — down to ONE HASH

**Status 08-14 evening: a real LC boots this disk.** MAME 0.264 maclc
(verified romset; our boot0.rom SHA1 6bef5853ae736f3f06c2b4e79772f65910c3b7d4
= byte-identical to MAME's 350eacf0.rom) boots the BUILDER-OUTPUT copy of
Mac68KColorGames_v1.hda (System 7.1, vol "MacAtrium_Sys") to a working
desktop at 10 MB, in BOTH the 512K and 256K VRAM worlds. So the crash is
NOT an LC-vs-image incompatibility, NOT the ROM, NOT VRAM size, NOT
memory size (2 MB and 10 MB both crash on Pocket, user-confirmed on a
cold CARD boot — JTAG path exonerated too).

**THE FORK (next session starts here):**
- **Hash the CARD's Mac68KColorGames_v1.hda** (card trip; certutil/sha1sum)
  against the builder output **dcd02c6c31335b87397af2c1944ebbea70cf4e26**
  (786,473,472 bytes; the card also carries Mac68KColorGames_v1.zip with
  the same file).
- **DIFFERS** → the card copy took corrupt sector writes during the
  pre-08-13 write-path-bug era (maclc.hda was restored from zip 08-13;
  the games disk NEVER was). Fix = restore from the zip, cold boot,
  expect it to just work. Mystery B closed as collateral of the fixed
  write bug.
- **MATCHES** → residual Pocket-vs-real difference on the System 7.1 late
  boot path. Next instrument = **buildAX**: a WW40-style write-watcher on
  the stack band $3FF7xx that ALSO latches the writer's PC (latch
  last-fetch-PC alongside {addr,data}; last-4 + count). It names whatever
  writes AAAA-pattern data over the live stack during the fatal call.

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
slot 310 (OSD pick or fresh card boot — NOTE auto-mount does NOT work,
the core only mounts on a real OSD dataslot_update; fix task spawned),
then push+jmnt(41992192)+jboot.

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
