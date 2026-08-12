# Cold-boot problems on the Analogue Pocket — findings

**Session of 2026-08-11.** Everything here was established by MEASUREMENT on
hardware, not by reading RTL. Where a theory was refuted it is recorded as
refuted, with the evidence, so nobody re-runs it.

The one-line state: **a cold core load does not boot; reloading `boot0.rom`
two or three times does, and the ROM in SDRAM is byte-identical either way.**

---

## ★★ 2026-08-12 — the evening regression, reconstructed. READ FIRST.

The 2026-08-11 session continued ~5 h past this doc's last update. It ended
with the **reload-to-"?" workaround dead** ("only unhappy mac sounds") and the
regression NOT fully reverted. Reconstructed from the session transcript;
timeline in local time (transcript stamps are UTC = local+7):

* **~09:58 — the GOLDEN BUILD.** PRAM slot removed, SDMA 250 µs, five parity
  fixes, 135°, `SCSI_DISABLE_DIAG=1`. Cold boot fails, but **2-3 ROM reloads →
  startup chime → "?" floppy screen. Captured via JTAG as the golden
  reference** (3×262144 counters, overlay cleared). This is the acceptance
  test every subsequent build must pass before anything else is measured.
* 10:00–13:00 — auto post-download re-reset added (cold boots now clear the
  overlay and loop the RAM test instead of wedging in slot space);
  `download_cycle` restored to MiSTer's arbiter form; `serialCTS` 0→1.
  **The reload workaround was never re-tested on any of these builds.**
* **17:13 — `dram_clk` phase 135° → 180°** (mf_pllbase), argued from
  MemTest_Pocket/Amiga analogies + STA (write +3.95/read +8.99, both
  "healthy"). DDIO clock restoration tried and backed out (STA can't model
  it; `scripts/check_sdram_paths.tcl` was born from that near-miss).
* **18:22 — first reload-workaround test since golden, on the 180° build:
  "major regression … only unhappy mac sounds."**
* 18:25–18:48 — partial revert, shipped to SD: `SCSI_DISABLE_DIAG` 1→0,
  auto re-reset disconnected, `download_cycle` back to the golden-era sim
  form, Memory default back to 2 MB. **KEPT: 180° phase, serialCTS=1, the
  8 MB SDRAM BIST (600 ALMs, runs once during the post-download reset hold,
  result never read).** User's next-morning report on this build: multiple
  reloads → death chimes, occasionally happy chime, no "?" screen.

**Two standing corrections to everything measured 2026-08-11 mid-day:**

1. `SCSI_DISABLE_DIAG=1` (all media hidden) was set for one bisection
   experiment in the morning and **silently shipped in every build until the
   final 18:48 revert**. Every "SCSI not detected" observation in that window
   was guaranteed by the switch, not evidence about `apf_blockdev`.
2. The 180° phase's healthy STA margins came from SDC delay numbers copied
   from Pocket-Amiga. Hardware disagreed (death chimes = POST RAM-test
   failures at exactly the phase RESUME.md already recorded as "tried and
   worse"). **The SDC model is relative guidance only; the reload-to-"?" test
   is ground truth for this interface. No phase moves without a hardware A/B.**

**Bisect plan from here (single variable per build, test the reload
workaround FIRST on every build):**

* **Build A (2026-08-12): 180° → 135°. Everything else = the 18:48 revert
  build.** If reload→"?" returns: 180° was the killer; baseline restored WITH
  the day's parity fixes; proceed to cold-boot root cause + SCSI (media now
  visible — first honest SCSI test since the golden build).
* If Build A still fails: next single steps in order — `SCSI_DISABLE_DIAG`
  back to 1 (media hidden, exact-golden A/B) → BIST compiled out → serialCTS
  back to 0. Each is one build, workaround-tested.
* **Archive every `.sof`** under `scratch/builds/<date>-<label>.sof` — the
  golden bitstream was lost to an overwrite and cannot be re-probed.

### RESULTS 2026-08-12 (same morning, JTAG-push flow)

* **Build A (135°, other deltas kept): reloads → sad-mac + STM.** BIST (in
  fabric, first read ever): **0 errors across 8 MB at BOTH 180° and 135°** —
  word-granular SDRAM integrity is fine at either phase. Phase theory dead.
* **Build B (exact golden-equivalent: 135°, serialCTS=0, media hidden, BIST
  off): reloads → "extremely slow" death chimes.** THE GOLDEN CONFIGURATION
  DOES NOT REPRODUCE THE GOLDEN BEHAVIOR. The regression is NOT in any RTL
  delta since the golden build.
* Three consecutive fits of near-identical RTL produced three different
  failure severities (normal-speed sad-mac / slow / extremely slow). Prime
  suspect is now a **fit-to-fit placement lottery on a path STA cannot see**
  (the SDC set_input/output_delay numbers were copied from Pocket-Amiga and
  have never been validated against this board — margins computed from them
  proved meaningless once already, see the 180° episode).
* Also measured en route: video pipe healthy (test pattern renders, greyscale
  = a properly programmed grey CLUT); machine's terminal state = CritErr/STM
  spin parked just below MemTop=$A00000 (which is config-independent on an LC
  — motherboard RAM lives at $800000-$9FFFFF, so a $9Fxxxx park does NOT
  imply a 10 MB sizing); PA0 diag-entry pin reads normal; fc7/MOVES STM
  protection verbatim-identical to MiSTer.
* In flight: same config rebuilt with `--seed=7` (lottery test) + an SCC
  TX-capture probe (`SCCT`, reader `scripts/read_scc.tcl`) — the STM banner
  carries the 12 status digits, i.e. the failing subtest's identity, on the
  pinless modem port.
* If the seed build changes behavior again: stop trusting the borrowed SDC
  numbers. Options, in order: characterize/repair the SDC delays against the
  Pocket's real board data, or adopt MemTest_Pocket's shipped-and-working
  DDIO clock topology (accepting that STA cannot model it — that is what
  MiSTer and MemTest actually ship).

### RESULTS 2026-08-12 continued — the code is exonerated

* **Seed-7 build** (anchor config + SCC capture, `--seed=7`): cold boot showed
  the ORIGINAL early-wedge phenotype (overlay stuck, $EExxxx slot sweep,
  1 interrupt, no STM — the golden-era cold signature, absent from the three
  prior fits). Reloads: consistent-tempo sad-macs. Fourth distinct
  fit-behavior datapoint.
* **Recon-golden build** (`recon/golden-0811` @ 5a4bd32 — the golden source
  reconstructed edit-by-edit from the session transcript; 11,830 ALMs vs
  golden's 11,776): **reloads still sad-mac.** THE EXACT GOLDEN SOURCE FAILS
  ON TODAY'S HARDWARE. Every code change since golden is exonerated.
* Per-boot variance persists within single bitstreams ("once in a while,
  straight lines") → a genuine boot-time RACE whose odds shift with placement
  — the golden fit had good odds, today's fits bad ones. The race predates
  everything; golden-era "2-3 reloads needed" was the same coin with a
  friendlier bias.
* SCC capture: LC's STM sends NOTHING unsolicited (confirmed: 72 writes at
  boot then silent command-poll; reload burst = 24 writes ending EA 01 00).
  The one-shot burst can't be caught by polling — needs a fabric-side ring
  buffer, or better, the **STM console build**: drive `serial_rxd` from an
  ISSP source (JTAG→9600-baud bridge) and converse with the monitor — `*R`
  returns the failing-test status directly, `*T` runs individual critical
  tests (Size Memory / Data Bus / Mod3 RAM / Address Line) on demand.
* Environmental control in flight: recon-golden via SD card on a POWER-CYCLED
  Pocket (fresh Analogue OS session — all of today's tests shared one
  marathon session with many JTAG fabric swaps under it; golden ran on fresh
  sessions).

### 2026-08-12 afternoon — FORCED-WARM breakthrough + standing decisions

* Fresh-session/SD-flow control: FAILED (7 perfect loads, still the early
  wedge). `main` is untestable by construction (pre-loader-fix). Device runs
  warmer than usual; thermal drift on a marginal path remains the leading
  environment theory. Cool-silicon testing preferred.
* **FORCED-WARM PATCH WORKS** (`instr/stm-console` 9cf81bf): NOP the ROM's
  warm-vs-cold `bne.w` (words $5232AF/$5232B0 — the inherited MiSTer patch
  aimed at $52322F was a typo and NEVER fired anywhere). First reload on cool
  silicon: **grey DrawBeepScreen + clean audio + 138k interrupts serviced**
  before a late-stage sad-mac. Everything through Stage 15 (screen setup) is
  healthy; the fault is now confined to (a) the bypassed cold RAM march and
  (b) something in Stages 16-18 (InitSoundMgr/InitFS/INITSCSIBOOT/BootMe).
* **STM console works** — JTAG serial injector (STMC) reached the monitor; a
  `*R` drew a 90-write response. Full-transcript readback via the SCCR ring
  (4e30241) is the current build.
* The cold "$E00000-$EFFFFF wedge" may be FINITE: cycles complete via VPA, so
  the crawl is ROM-paced; at SDMA=250 µs the sweep projects to ~1-2 min (at
  the old 250 ms it projected to HOURS, hence "for ever"). The fresh-session
  capture sat at $EFxxxx — nearly done. **Nobody has ever waited a cold boot
  out. Standing experiment: cold boot, hands off, five minutes.**
* **USER DECISION: lock the core to 10 MB eventually** (single config). The
  SDRAM occupancy map audits clean at 10 MB (mb $000000 / SIMM $100000-$4FFFFF
  / ROM $500000 / VRAM shadow $580000 / floppy $600000 — the old ROM@$280000
  overlap bug is fixed). Blocked on: the cold RAM march must pass, since
  10 MB runs the full 8 MB SIMM test.

### 2026-08-12 evening — the console works both ways; the failure flow decoded

Ring v2 ({rw, port, byte} tagged transcript, `instr/stm-console` branch,
builds G-J archived in scratch/builds/) produced the register-level truth:

* **The SCC was structurally deaf AND mute since import** — MiSTer-era shims:
  RX chars dropped forever post-loopback (scc.v:259) + RR0 RxAvail forced 0
  (scc.v:962) + TxEmpty forced busy post-loopback (scc.v:926). All three now
  truth-with-a-one-shot-flush on the instr branch. This Pocket port is the
  first thing to ever actually USE this SCC's port.
* **The famous cold-boot "$E00000-$EFFFFF wedge" is the DIAGNOSTIC FLOW, not
  a hang**: after an early failure the ROM (a) polls the serial port ~50
  times for a TechStep terminal (captured: R-ctA RR0=0x04 ~50-75x), then
  (b) walks the PDS slot space looking for a diag card — the "endless" sweep,
  which LOOPS (observed wrapping $EF->$E8 within one boot). The wedge is a
  symptom; the failure that routes boots into it happens EARLIER, overlay
  still on, and per-boot randomly (the race).
* **Forced-warm results**: many boots now reach grey-screen + deep
  interrupt-driven running (138k IRQs) before a late sad-mac (stages 16-18);
  other boots
  still divert into the diag flow before the patch's branch point. The race
  has (at least) two strike points: early POST and stages 16-18.
* **Live lever discovered**: if a character arrives DURING the post-failure
  serial poll window, the ROM should enter the interactive STM instead of the
  slot scan — a sanctioned command prompt at the instant of failure, with the
  *T test suite (Size Memory / Data Bus / Mod3 / Address Line) runnable
  against the just-failed hardware state. `scripts/stm_spam.tcl` streams '*'
  for ~90 s; run it OVERLAPPING a ROM reload. First attempt missed (reload
  didn't coincide); repeat coordinated.
* Next instruments queued: JTAG boot strobe (ISSP source faking the ROM-
  download latch + reset — the ROM persists in SDRAM, so boots would need NO
  user hands), and if the window-catch works, a scripted *T battery.

### ★★ 2026-08-12 late — SDRAM RETENTION is the prime suspect for the early failure

A jboot immediately after a `quartus_pgm` fabric push boots whatever survived
the ~1-2 s **refresh gap during FPGA reconfiguration** — and warm DRAM decays
on exactly that timescale. Evidence pattern:
* jboot-after-push: 11/11 early wedge (rotted ROM executed).
* jboots on a fabric whose ROM had been OSD-reloaded after the push: reached
  the STM spin / grey screen (fresh content).
* The user's SD/OSD flow always re-downloads the ROM post-config — masking
  decay; JTAG pushes never do.
* Every "ROM verified byte-perfect" claim (rom_sum/rom_axsum) measured the
  DOWNLOAD STREAM at acceptance time, not what SDRAM still held when the CPU
  fetched it. The project has NEVER verified retention.
* Thermal fit: device "warmer than usual"; retention shortens with heat; the
  golden era was a cooler machine on fresher content.
* Golden-era transcript, user's own words after a JTAG push: "the jtag was
  working ONCE the rom was fully loaded."
**Missing instrument: a retention oracle** — JTAG-triggered re-checksum of
the ROM region READ BACK from SDRAM (BIST-style port), compared against the
known sums. Distinguishes decay (post-push mismatch, post-reload match, and
possibly drift over minutes on a warm chip) from everything else. If decay is
real even across normal operation (refresh-interval marginality at 135°?),
it also explains the late-stage race: seldom-refreshed rows rot mid-boot.
NOTE: the auto-refresh interval/logic in pocket_sdram vs the 64 ms JEDEC
window should be re-audited with real numbers in the same pass.

Console status: full duplex PROVEN + console-speed shim in (buildN) — the
monitor's All-Sent poll budget (~200 us) can't span an honest 9600-baud char
(1150 us); both ends now run ~325 kbaud internally. Awaiting a fresh-ROM
boot for the *R/*T interrogation.

### ★ 2026-08-12 evening — THE ORACLE'S MIRAGE, and what actually survives

The retention/corruption narrative went through three self-corrections. Final
state of knowledge — record so nobody re-walks it:

1. ROMV v2's "one-word offset" was real (pairing bug) — fixed in v2.1.
2. v2.1's "21,600 corrupt words / 8% of ROM, mostly word-0 copies" was a
   MIRAGE: slow isolated re-reads of the same address returned DIFFERENT
   values run-to-run (sometimes correct, mostly 350E). The scanner's
   free-running reads often never issued; dout then held the machine's own
   most-recent fetch — which, after the scan-induced reset, is overwhelmingly
   the RESET VECTOR AT WORD 0 (350E). The instrument photographed its own
   reflection. The CPU booting deep on the same content was the tell.
3. **Therefore the reconfig-gap "decay proof" is ALSO unproven** — the
   pre/post-reload sum differences are contaminated by the same stale-read
   artifact (different machine states = different reflected dout). Decay
   remains plausible, unmeasured.
4. ROMV v3 (completion-paired via pocket_sdram dout_stb + settle windows) is
   the airtight rebuild. Re-run the full protocol on it: post-push scan vs
   post-reload scan vs file, plus repeated-scan stability, before ANY new
   conclusion about memory content.

**What genuinely survives all controls today:**
* Arrival-side ROM delivery: byte-perfect, every load (accumulator exact).
* CPU-path reads: reliable enough for deep boots (grey screen, 138k IRQs).
* The regression/bisect chain: code exonerated to golden; OS-session, SD
  flow, power-cycle, phase all excluded.
* **jboot determinism: instant-reset boots fail early 11/11, while
  long-download-reset (OSD) boots frequently reach the late stages.** The
  reset-hold-duration difference is the tightest reproducible discriminator
  of the underlying fault. Next experiment when instruments allow: a
  source-configurable jboot hold time — sweep it; if long holds rescue
  jboots, the fault is time-in-reset-dependent state settling (Egret, PLL,
  SDRAM bank state, ...).
  [RESOLVED 2026-08-12 — see the ROOT CAUSE section below: the discriminator
  was content freshness, not reset duration. jboot re-executes the SAME
  scarred ROM; an OSD reload re-rolls the scar dice.]
* Instrument suite now standing: hands-free boot (JBOO), diag-mode-on-demand
  (DIAG/PA0), two-way STM console at working speed (STMC/SCCR/SCCS + three
  scc.v truth fixes), ROM retention oracle v3 (ROMV/RVSU/RVAX).

---

## ★★★ 2026-08-12 — ROOT CAUSE FOUND AND MEASURED: the download-path
## row-crossing tear scatter-corrupts the ROM as it lands

ROMV v3's first honest look at SDRAM content (buildR, post-push, no reload)
found the ROM differing from the file — **stable across 4 identical full
scans** (sum=350797DA axsum=F488E2C4 vs reference 350F8EEE/F486F3D8), so a
real, frozen content difference, not the v2.x mirage. A binary-descent survey
(`scripts/romv_survey.tcl`, 5,616 range scans, ~3 min) then located every bad
word. After isolated-read verification (`romv_peek.tcl`, majority-of-3):

* **~278 corrupt words. EVERY one at an SDRAM row-boundary word**
  (word addr xx00 — pocket_sdram maps addr[7:0] to column, addr[19:8] to row).
* **EVERY one holds exactly `content(addr+0x100)`** — the NEXT row's col-0
  value. 278/278 byte-exact against boot0.rom, zero exceptions. (Values like
  8902 with 5 occurrences in all 256K words rule out coincidence.)
* 278 of 1023 row crossings hit ≈ 27% — matching the 1-in-4 t-phase odds of
  the mechanism below.
* Flip "direction" mixed both ways, all 16 data lanes uniform: value
  REPLACEMENT, not charge decay. **The decay theory is dead** — DRAM leakage
  cannot copy the next row's value into this row.

### The mechanism (RTL-level, exact)

`pocket_sdram` samples the LIVE `addr` twice per access: row/bank at t=0
(ACT), column + data at t=2 (CAS), ~31 ns apart. The sim-form download path
(`download_cycle = dio_download && ioctl_wr`) switches `ram_addr` to the
download the moment the loader raises `ioctl_wr` (a level) — but the latched
`dio_a` takes one more clk_sys to load the new word's address. For that one
cycle: `ram_we=1`, addr = OLD word's, din = NEW word's (live `ioctl_dout`).
If the controller's t=0 lands in that window the access tears: **ACT opens
the old row, CAS writes the new column with the new data.**

* Mid-row the tear is INVISIBLE: old row == new row, and the torn write lands
  exactly where the next word was about to be written anyway.
* At a row crossing it writes `(row R, col 0) <= value(row R+1, col 0)` —
  the exact observed corruption. The victim word's own correct write (255
  words earlier) is clobbered; no other word is lost (the new word's level
  hold rewrites it correctly in later chipset cycles).
* The new word's `valid` rise is timed by the loader pop / bridge arrival
  (clk_74a-flavored, async to the t counter), so the t=0 alignment is a
  ~1-in-4 dice roll per boundary — hence ~27% of row starts scarred, and a
  DIFFERENT scar set every download.

### Why every previous instrument said "fine"

* `rom_sum`/`rom_axsum` accumulate the STREAM (latched dio word at ack time),
  not what landed — a torn write is invisible to them by construction. Every
  historical "ROM verified byte-perfect" was measuring the stream.
* The SDRAM BIST holds its addresses stable per access — no tear, 0 errors.
* CPU/chipset accesses hold addresses stable across the whole access — the
  running machine never tears its own reads/writes.
* Word COUNTS are exact: no word is dropped; one extra (mis-addressed) write
  fires.

### What it explains (the whole season, plausibly)

* **The per-reload boot lottery**: each OSD reload re-rolls ~250-300 scarred
  words across the ROM. Boots then die at random depths — early POST wedge,
  grey-screen + late sad-mac, occasionally a full boot ("2-3 reloads to the
  ?") — on IDENTICAL checksums.
* **jboot 11/11 early wedge**: jboot re-executes the SAME scarred content —
  deterministic failure. OSD reloads re-roll — variable outcomes. The
  "reset-hold duration" discriminator dissolves.
* **Fit-to-fit and thermal variance**: the clk_74a->clk_sys arrival phase and
  FIFO occupancy patterns shift the per-boundary odds with placement and
  temperature. The golden fit had friendly odds; nothing about the code
  changed.
* The post-push content diff that looked like "decay across the reconfig
  refresh gap" was the last pre-push download's scar set, frozen.

### The fix (buildS)

Re-applied the MiSTer arbiter form in mac_lc_pocket.sv — the exact form
MacLC.sv.reference:2185-2206 ships and the 2026-08-11 bisection panic had
reverted:

    wire download_cycle = dio_download && dioBusControl;  // slot-gated
    ram_din = download_cycle ? dio_data  : ...            // latched, not live
    ram_we  = download_cycle ? dio_write : ...            // frozen through slot

Tear-proof by construction: `dio_write` is sampled only while
`~dioBusControl` (frozen through the slot), and a new word's `valid` can only
rise after the ack at slot end, so every `dio_write=1` slot sees `dio_a`/
`dio_data` that latched before the slot began. The floppy download path is
cured by the same change (its images got the same row-start scars — likely
the real face of "mounting a floppy crashes the core").

**Acceptance protocol for buildS**: push -> user does ONE OSD reload ->
`romv.tcl` x3 must return EXACTLY 350F8EEE/F486F3D8 -> then boot testing.
With clean content, cold boots and reloads go through the same fixed path;
the cold-vs-reload distinction should disappear entirely.

### Instrument honesty note (ROMV v3 characterization)

Misreads are per-TRIGGER (scan startup), ~1% of triggers, not per-word —
four full-ROM scans were bit-identical while the 5,616-trigger descent
produced ~14 phantoms (values smeared onto neighbor addresses, e.g. flagged
xx01 entries whose isolated re-reads were correct while the real scar sat at
the xx00 sibling). Rules: trust single-trigger range sums; verify every
bottom-level (lg=0) finding with `romv_peek.tcl` majority-of-3 before calling
it content. The transient "SCAN WEDGED st=0" is the same startup glitch —
`romv_survey.tcl` now retries.

---

## 1. The symptom, precisely

| | cold load (fails) | after 2-3 ROM reloads (works) |
|---|---|---|
| ROM checksums | **perfect** | **perfect** |
| `BRGC`/`POPC`/`ROMC` | 262144 | 786432 (3 loads) |
| `memoryOverlayOn` | **still set** | **cleared** |
| `byteack` | 1 | 0 |
| VIA SR active / bit_cnt | 0 / 0 | 1 / 7 |
| CPU | sweeps `$E00000-$EFFFFF` for ever | reaches the "?" floppy screen |

Because the ROM content is identical in both cases, **ROM corruption is
excluded**. What differs is the machine's state around the first reset release
after a fresh download. A manual ROM reload asserts
`dio_download && dio_index==0`, which drives `n_reset` low and then releases it
through the full 8 ms + 129 ms sequence — i.e. **a complete machine reset with
the ROM already resident**. The cold path releases reset only once, right after
the ROM lands.

**Next thing to try:** issue one extra full machine reset automatically after
the ROM download completes, mimicking what a manual reload does. If that boots
reliably it both fixes the user-visible problem and localises the bug.

### UPDATE — after the automatic post-download re-reset was added

The cold-load state changed materially. Measured on a cold load, no manual
ROM reload:

| | before the re-reset | after |
|---|---|---|
| `memoryOverlayOn` | still set | **CLEARED** |
| `reset_680x0` / `cpu_reset_out` | varies | released / asserted |
| CPU | stuck sweeping `$E00000-$EFFFFF` | **sweeps RAM `$000000-$800000` uniformly** |
| CPU rate | ~325 bus cycles/s (crawling) | ~34 M bus cycles between samples — full speed |
| instruction fetches | n/a | 0 of 400 samples (a tight cached loop) |

So POST now gets **past the relocation** and into the RAM test, which is much
further than before. The screen is still blank, so this is not a fix yet, but
the failure has moved from "wedged in early POST" to "running the memory test".

**Where it now sits, and the open question.** The address climbs steadily across
passes (`$0D13DE` -> `$17016A` -> `$1C2B5E`), covering `$000000-$800000` — the
full 8 MB SIMM range — so the sweep is progressing, not spinning on one bank.
But the machine has been in this state for tens of minutes and ~3.4 billion bus
cycles, far longer than an 8 MB walk should take, so it is looping over the
whole range rather than finishing.

The strongest clue is the interrupt state:

```
_cpuIPL = 110  -> LEVEL 1 - VIA1 asserted
interrupts acked: 1   (ONE, for the machine's entire lifetime, not increasing)
```

**VIA1 has a level-1 interrupt permanently asserted that the CPU never
acknowledges.** Exactly one interrupt has ever been taken. If the RAM test is
timer-paced — and the MiSTer POST notes say the VIA1 Timer-1 self-test is — a
pending-but-never-serviced timer would make it retry for ever. That is the
next thing to chase: either the CPU has interrupts masked in SR and is waiting
on something that only an ISR can clear, or the VIA1 IRQ is asserted for a
reason nothing will clear.

---

## 2. Proven by measurement — do not re-litigate

* **The ROM download path is correct, content AND addressing.**
  `rom_sum` = `0x350F8EEE` and `rom_axsum` = `0xF486F3D8` match values computed
  from `boot0.rom` exactly. `rom_axsum` folds the word INDEX into the sum, so it
  is sensitive to *where* each word landed — a permuted or misaddressed ROM
  cannot pass it. The file's own embedded Mac checksum also verifies
  (`0x350EACF0`).
  ★ Word COUNTS alone (`BRGC`/`POPC`/`ROMC`) are NOT sufficient — they look
  identical for a well-formed corrupt load. That mistake was made here.
* **SDRAM stores what it is given.** `DHLD` = 0: the download never overlapped
  the init ladder. And the ROM executes from SDRAM for hundreds of millions of
  correct fetches.
* **Video is healthy.** `vidrst_s`=0, ~60 fps, hblank/vblank toggling. A black
  screen is the guest not drawing, not a video fault.
* **The Egret handshake completes** on both good and bad boots.
* **`apf_blockdev` is not the boot blocker.** With `img_mounted` forced low
  (all SCSI media hidden) the boot still failed identically.
* **All shared RTL matches MiSTer `5a75f9b`.** Every file under `rtl/` diffs
  clean apart from the documented cuts (CD audio, Toolbox, second floppy,
  512x384-only video). So does `_cpuVPA`/`_cpuDTACK`/`slot_space`/`fc7_*`,
  `cpuAddr` formation, `addrDecoder.v`, `pseudovia.sv` (incl. its IRQ gating
  fix), and `pocket_sdram.v`.

## 3. Refuted theories — do NOT spend time on these again

1. **CB1 edge coalescing (`ext_fall_edge_pending`).** That register has **zero
   functional fanout**; its only reader is a debug port (`via6522.sv:976`).
   Upstream already fixed the bug — in `ext_clock_mode` both the data path and
   the bit counter advance on per-clk `shift_tick_r`/`shift_tick_f`. A capture
   on `dbg_boot_bus` bits 12/15 WILL show coalescing and it means nothing.
2. **Loader FIFO overflow / missing backpressure.** `BRGC == POPC` in every
   capture. (`loader_busy` IS genuinely dangling in `core_top.sv` — a real
   defect — but it is not this bug.)
3. **Marginal SDRAM writes corrupting the ROM.** Checksums are perfect. The
   phase WAS badly mis-tuned though — see §4.
4. **SCSI media / `apf_blockdev`.** Bisection with `img_mounted` low still hung.
5. **SDRAM init-ladder race.** The theory was that the ~126 us JEDEC ladder
   swallowed early ROM writes. `DHLD` measured 0 — the download begins long
   after the ladder finishes. The `sdram_ready` gate added for it is harmless
   and worth keeping, but it fixed nothing.

## 4. Fixes applied this session

**MiSTer-parity defects, all dropped at import** (found by mechanically diffing
every module, port, RTL file and SDC line against `5a75f9b` — by far the most
productive technique of the session):

1. **`selectUnmapped` never connected to `dataController_top`.** The wire was
   driven; only the connection was missing, so the open-bus `16'hFFFF` case at
   `dataController_top.sv:330` could never fire and unmapped reads returned
   stale bus data. Ref `MacLC.sv.reference:1885`.
2. **`vpa_periph_read` / `periph_din_reg` / `cpu_din_muxed` absent entirely.**
   This is upstream's fix for what its own SDC calls **"the dice-roll boot"**:
   the peripheral read mux is the deepest cone in the design (SCSI CSR bit6
   `scsi_bsy`), so bit6 read wrong while shallow bit1 read right, depending on
   placement. Ref `:985-999`.
3. **No 2FF sync on `v8_vblank`/`v8_hblank`** crossing `clk_pix` -> `clk_sys`
   into pseudovia's VBlank **interrupt** and the VIA blanking inputs. Ref
   `:632-639`.
4. **`maclc_v8_video` reset was raw `~n_reset`** (a `clk_sys` signal) into a
   `clk_pix` module; upstream uses a synced `vidrst_s`. Ref `:623-629`.
5. **`core_constraints.sdc` had NONE of MiSTer's constraints** — no TG68 kernel
   multicycle (upstream: *"REQUIRED for reliable timing closure"*, without it
   *"closing timing by luck"*), no `periph_din_reg` multicycle, no synchronizer
   false paths.

**Other fixes:**

6. **SDRAM `dram_clk` phase 90 -> 135 degrees** (`mf_pllbase_0002.v`). At 90 the
   write/command side had **+0.107 ns** while reads had +9.21 — wildly
   lopsided, because the arithmetic that chose 90 counted only the SDC delays
   and ignored FPGA clock-to-out. Now write +2.03 / read +9.93.
   ★ `ap_core.sta.summary` reports per-CLOCK-DOMAIN worsts and HIDES the memory
   interface. Query the paths directly:
   ```tcl
   get_timing_paths -setup -from [get_ports {dram_dq[*]}]   ;# reads
   get_timing_paths -setup -to   [get_ports {dram_*}]       ;# writes
   ```
7. **`SDMA_TIMEOUT` 250 ms -> 250 us** (`mac_lc_pocket.sv`). Inherited from
   MacLC.sv, where it is safe because DREQ arrives normally. Here it fires on
   every pseudo-DMA access: the CPU advanced ~487 bus cycles per 1.5 s, about
   **6000x slower than healthy**. It was not hung, it was crawling. A real Mac's
   bus timeout is microseconds. This gave a ~3000x speedup.
8. **`scripts/package.sh`** now TESTS each python candidate by running it —
   `command -v python3` hits the Microsoft Store stub on Windows, which would
   have silently produced no bitstream.
9. **`sdram_ready`** exposed from `pocket_sdram` and the download gated on it
   (see §3.5 — harmless, fixed nothing).

## 5. Regressions introduced and removed this session

Recorded because both were caught by instrumentation, not by review:

* **PRAM slot held the 68020 in reset for ever.** `pram_ready` depended only on
  the save-file load resolving; it never did, so `reset_680x0` stayed asserted
  and the CPU executed exactly ONE bus cycle. Fixed with a ready backstop
  (~1 s) — MacLC.sv.reference:352 has the same guard.
  **Rule: the boot may WAIT for NVRAM, but must never DEPEND on it.**
* **PRAM slot corrupted the ROM.** 128 words of `0xFFFF` (the blank nonvolatile
  file the OS creates) were streamed through `apf_bridge_loader` and written at
  ROM word offsets **0-127** — over the reset SP/PC and header. Arithmetic was
  exact: data gap `0x007FFF80` = 128*0xFFFF, axsum gap `0x007FDFC0` =
  128*0xFFFF - sum(0..127). Root cause: `loader_active` is raised on the ROM's
  `dataslot_requestwrite` and cleared ONLY by `dataslot_allcomplete`
  (`core_top.sv:688-695`), so bridge writes for ANY later slot in that window
  are attributed to the ROM with `loader_slot_id = 0`.
  The slot is removed; the RTL remains and is inert. Before re-adding, give the
  slot an explicit `address` outside the loader's `0xC000_0000`-masked window
  and/or gate `accept` on the address belonging to the active slot.

## 6. The instrument deck

Enable `USE_BOOT_ISSP` in `src/fpga/ap_core.qsf` — **must be OFF for release
fits** (same convention as MiSTer's `USE_DBG_HUD`). Costs ~500 ALMs and roughly
doubles fitter time.

| script | answers |
|---|---|
| `bash scripts/read_boot_probes.sh` | full decode: ROM checksums, download path, arbitration, Egret/VIA state |
| `scripts/cpu_probe.tcl` | CPU address + AS/DTACK/RW/BERR/reset, video liveness, pseudo-DMA stall, interrupts |
| `scripts/post_stage.tcl` | buckets the PC against MiSTer's POST landmark table |
| `scripts/boot_watch.tcl` | is anything moving at all? |
| `scripts/sdma_watch.tcl` | watches `sdma_stall_ctr` for resets |

Probes: `BOOT` `ROMC` `FLPC` `BRGC` `POPC` `DLST` `CPUC` `CPUA` `VIDS` `SDMA`
`IRQS` `RSUM` `RAXS` `DHLD`.

**Use ISSP, not SignalTap, for boot questions.** `clk_sys` is 32.5 MHz, so 1024
SignalTap samples span 31 us against a ~137 ms boot. ISSP is polled from Tcl
over seconds, has no depth limit, and survives repeated power-cycling.

### Reading traps learned the hard way

* **Tcl `scan %x` is SIGNED.** A 32-bit probe value with bit 31 set comes back
  negative, so `$v == 0xF486F3D8` is false even when the hex printed on screen
  matches exactly. This produced a full false alarm — the reader announced
  "ADDRESSING IS WRONG" while printing two values that were visibly identical
  to the expected ones. Always `expr {$v & 0xFFFFFFFF}` before comparing.
  The same signedness shows up in the CPU cycle counter, which prints negative
  once it passes 2^31; add 2^32 to read it.

* **`CPUC` (bus-cycle count) distinguishes halted from spinning.** A frozen
  `BOOT` bus cannot. Sample it TWICE — one capture spanning less than a stall
  period looks frozen when the machine is merely slow.
* **The 68020's 256-byte I-cache hides instruction fetches.** A tight ROM loop
  shows only its DATA accesses, so "0 samples in ROM space" does not mean the
  ROM is not executing. Filter on `cpuFC` (110/010 = program space) for the
  real PC.
* **Counters are free-running and never cleared.** Read the DELTA across an
  event, not the absolute value.
* **Tcl treats `0xF486F3D8` as signed** — the "ADDRESSING IS WRONG" verdict in
  `boot_state.tcl` misfires on values above 2^31 even when they match. Compare
  the printed hex by eye.

### POST landmarks (from `../MacLC_MiSTer docs/post_diagnostics_and_irq_levels.md`)

| address | stage |
|---|---|
| `$A4644C` | PA0 diagnostic-mode check |
| `$A46582`/`$A465B0` | RAM bank-descriptor scan |
| `$A46C5C` | per-bank address/data walking subtest |
| `$A47170`-`$A471C6` | VIA1 Timer-1 interrupt-timing self-test |
| `$A4A87C` | relocation trampoline / config write — **this clears the overlay** |
| `$A498xx`/`$A49Fxx` | POST FAILURE reporter spin ("STM") |

Seeing ROM `$A49xxx` alternating with SCC `$F04002` means POST FAILED and the
ROM is reporting it out the serial port.

## 7. Other real defects found, not yet fixed

* **`loader_busy` is dangling** in `core_top.sv` — declared, connected to the
  loader's `.busy`, and read by nothing. `apf_bridge_loader`'s header claims it
  "backpressures the OS the same way ioctl_wait did on MiSTer". It does not.
* **`bd_dio_download` is raised on floppy mount without checking `flp_allow`**
  (`apf_blockdev.v:288`) and cleared only when the whole image is copied, so it
  steers `dio_index` to `8'd1` and defeats the machine's ROM reset-hold at
  `mac_lc_pocket.sv:257`.
* **`sdma_berr` never fires on a genuinely unanswered cycle** — worth
  re-checking now the timeout is 250 us.
* **`SCSI_DISABLE_DIAG` in `core_top.sv` is currently 1.** MUST be 0 for
  release.
* **`USE_BOOT_ISSP` is currently ON.** MUST be off for release.
* A **-9 ps hold violation** on `i2s_out|audgen_mclk` appeared in one fit and
  vanished in the next — placement-sensitive, so re-check before release.

## 8. Environment (Windows box, 2026-08-11)

### ★ TWO JTAG servers fight over the cable — this WILL bite again

Symptom: `jtagconfig` reports **"No JTAG hardware available"** while Device
Manager shows the USB-Blaster present and healthy (`Status OK`,
`CM_PROB_NONE`). Survives a Windows reboot. Nothing is wrong with the cable.

Cause: the newer driver package installed to get past HVCI ships its own
daemon at `C:ltera.1std\qdriversin64\jtagserver.exe` and registers it
as the **`JTAGServer` Windows service**, set to start automatically. After a
reboot that service claims the cable before Quartus 18.1's tools can, and
18.1's `jtagconfig` cannot talk to it. The 25.1 package is driver-only — it has
no `jtagconfig` — so you cannot simply use its client instead.

Fix: stop (or disable) the `JTAGServer` service, then 18.1's `jtagconfig`
spawns its own compatible `jtagserver` and the chain reads normally:

```
1) USB-Blaster [USB-0]
  02B050DD   5CE(BA4|FA4)
```

```powershell
Stop-Service JTAGServer -Force        # needs an elevated shell
Set-Service  JTAGServer -StartupType Disabled
```

It worked earlier in the same session purely because the service had not been
started yet at that point.


Quartus **18.1.0 build 625** at `C:\intelFPGA_lite\18.1` — the same build that
made the WSL fits, so no IP-upgrade risk. Python 3.12.10 at
`%LOCALAPPDATA%\Programs\Python\Python312` (prefix PATH explicitly). USB-Blaster
works; the earlier Code 39 was **HVCI/Memory Integrity** rejecting the 2018
driver (certs expired 2015/2016), fixed by updating the driver. No WSL distro,
so **no Verilator**. SD card is `D:`; core goes to
`D:\Cores\danifunker.MacLC\`, ROM at `D:\Assets\maclc\common\boot0.rom`.

Build (Git Bash):
```bash
export PATH=/c/intelFPGA_lite/18.1/quartus/bin64:$PATH
cd src/fpga && quartus_map ap_core && quartus_fit ap_core && quartus_asm ap_core && quartus_sta ap_core
cd ../.. && bash scripts/package.sh && cp info.txt dist/Cores/danifunker.MacLC/
```
