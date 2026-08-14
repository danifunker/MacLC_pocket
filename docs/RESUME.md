# RESUME — MacLC Pocket (2026-08-13 end-of-day: two ships fixed, one deception unmasked, two mysteries armed)

Paste into a fresh session: **"Resume docs/RESUME.md — continue the boot
hunt."** boot_problems.md ★★★ sections carry deep history; this file is
current state. Yesterday's RESUME (git `8cc9782`) keeps the ops crib.

---

## 0. ★ READ FIRST — THE MEMORY-REGISTER DECEPTION (found at day's end)

`opt_mem_size` (core_top.sv:381, RTL default 0 = **2 MB**) is written by
the OS only at core launch or when the menu VALUE CHANGES. **A JTAG fabric
push resets it to 2 MB and the OS never rewrites it** — the menu keeps
showing the persisted "10 MB" while the machine boots 2 MB. Every crash
round measured on 08-12/08-13 (all JTAG-push sessions) ran at effective
2 MB with the menu claiming otherwise.

**After EVERY JTAG push:** Core Settings → Memory → flip to 2 MB → back
to 10 MB (a re-select of the same value does NOT write) → Reset & Apply.
(Or fix it properly: see LANDMINES #1.)

## 1. THE TWO OPEN MYSTERIES

**A. Does maclc.hda boot to the Finder at TRUE 10 MB?** — THE highest-value
single observation, still UNTESTED at session end (the games disk got the
first true-10MB round). If YES: the deterministic "+59 crash" closes as
"System 6.0.8 + heavy extensions failing CLEANLY in 2 MB" (fits every
measurement: all I/O byte-perfect, boot code gives up on purpose via
BadDisk→BootMe, deterministic, latency-independent, MiSTer-passing).
If NO: the buildAQ trail capture (§3) decides — with memory eliminated.

**B. The games disk (Mac68KColorGames_v1.hda) dies "Illegal instruction"
after "Welcome to Macintosh" AT TRUE 10 MB** (user-confirmed at day's
end). This is PAST where maclc.hda ever got. Suspects: a TG68K 68020 gap
(docs/tg68kmissing.md is the repo's own list — bitfields etc. exercised
by that image's System/INITs), or a genuine extension fault. Trace plan
in §3 — the toolkit does this in one capture.

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

## 3. THE INSTRUMENT SUITE (buildAQ = pushed fabric; scratch/builds has all)

| lever/probe | what | script |
|---|---|---|
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

1. **opt_mem_size JTAG-push reset** (§0). Honest fix: RTL default → 1
   (10 MB); 2 MB stays selectable for diagnostics.
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
