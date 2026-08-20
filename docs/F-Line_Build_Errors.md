# F-Line Build Errors — reference and decision tree

**Standing reference for the "bad F-line instruction" failure class on this
core. Read this BEFORE debugging any F-line report; append every new
instance to the case history. Last updated 2026-08-19.**

---

## 1. What an F-line error is, and what it actually tells you

The 68020 traps any opcode whose top nibble is `$F` (line-1111, the
coprocessor space) and the Mac OS posts the "bad F-Line instruction" bomb.
On a stock LC **no legitimate code path executes F-line opcodes** — so an
F-line bomb means the CPU **fetched a word that was never part of the
instruction stream**. It is an *executed-garbage* signature, sibling to
"illegal instruction" and "coprocessor not installed" (which specific bomb
you get is just a function of which garbage nibble came back).

Ranked sources, from this project's history:

1. **Memory-path data corruption** — the fetch returned the wrong word
   (SDRAM timing, handshake race, wrong-address service, cache serving
   stale data).
2. **Fit marginality** — same RTL, losing placement; corruption clusters in
   whatever cones the fitter left thin (the 2026-08 icon-garbling era).
3. **Genuine stale-done / shared-mux protocol bugs** — the Law 1/3/6 class
   from the MiSTer CPU-perf mission (false DTACK ⇒ CPU latches the
   *previous* access's data).

**Where it fires matters.** F-line at *Finder/System load* = the first
heavy write→fetch traffic (decompressing code into RAM and immediately
executing it, QuickDraw building blit code). A clean ROM boot up to that
point exonerates **nothing** about that traffic class — ROM fetches are
read-only, snoop-free, and mostly cache-resident.

---

## 2. Case history

### Case 1 — MiSTer, 2026-08-18: the multicycle lie (Phase C bring-up)

- **Symptom:** "System Update" bomb, error type 10 (F-line), after
  STA-met fits; sim clean.
- **Mechanism:** a plausible-sounding multicycle constraint on the
  `tg68k|addr → sdram|sd_addr` request paths granted 2 destination periods
  the silicon never had. True requirement ~22 ns into a 15.38 ns capture
  window: **slack −6.710 ns, hidden by the constraint.** The controller
  latched half-settled row/column addresses; reads/writes landed at wrong
  locations.
- **Fix:** register the entire request bundle in `clk_sys`
  (structural), delete the multicycle with a DO-NOT-RE-ADD note.
- **Law:** never put a multicycle on the memory request paths. If they
  fail, fix the pipelining. (`MacLC_MiSTer/docs/CPU_Perf_Log.md` entry 4.)

### Case 2 — Pocket, 2026-08 (buildBN→BP era): per-fit marginality

- **Symptom:** Finder-load corruption on *some* fits of unchanged RTL —
  garbled icons, F-lines, stuck alerts; ?-screen and Welcome always clean.
- **Mechanism:** placement lottery on unanchored cones; "GCR bombing" and
  other phantom RTL defects were all this.
- **Fix:** the always-on marginality anchor (buildBS/BU trio) + the
  video-first per-fit gate + ≥2-boot soak; release retreats to proven
  builds (v1.0.1 = buildBP).
- **Law:** a bad fit is not evidence about the code — but see Case 3's
  law for when fit-lottery stops being the explanation.
  (`docs/BUILD_INSTABILITY.md`, `docs/boot_problems.md`.)

### Case 3 — Pocket, 2026-08-19: demand-start pin-phase statistics ★ the big one

- **Symptom:** v1.1.0 CPU-perf port (Phase B + C + I-cache, all
  HW-validated on MiSTer): F-line **at the same point of Finder load on
  seed 4 and seed 11** — two placements, and (with the probe build) three
  fits across two netlists. Deterministic location ⇒ not classic
  marginality noise.
- **Digital layer exonerated offline, in order:**
  1. Token-level transcription diff of `pocket_sdram.v` vs the validated
     MiSTer `sdram.v` — engine identical, adaptations accounted for.
  2. Honest STA on the fresh netlist: request bundle +7.07 setup /
     +1.16 hold, `cpu_dout` +8.2, no multicycles anywhere near it
     (Case 1's lesson pre-applied).
  3. Loader-handshake audit (`scripts/audit_loader_handshake.py`) — the
     bridge→`dl_*` protocol clean.
  4. **`verilator/modelsim_bench/tb_pocket_sdram.v`** — the REAL
     controller under 4-state ModelSim against a JEDEC-checking chip
     model: 0 protocol violations, 0 data mismatches (2140 stale-done
     checks, posted-write→read ordering, abandons, refresh, dl, flp).
  5. **`tb_mem_seam.v`** — REAL `fetch_cache` + REAL `pocket_sdram` +
     verbatim glue equations under a Phase-B bus-functional model,
     including self-modifying write→fetch torture: all seam checks pass.
- **The A/B that settled it:** `1.1.0-sp` = identical stack with
  `req_cpu` (and opportunistic refresh) gated to **`t == 3'd1`** — one
  fixed SDRAM command phase per clk_8 period, i.e. the pin-level command
  statistics the board was always validated at — versus the ported
  engine's any-idle-edge starts (`t[0]` parity = 4 phases). Result:
  **any-phase → F-line; single-phase → boots clean, floppy/SCSI healthy,
  and Speedometer lands at MiSTer-level numbers.**
- **Surviving mechanism:** board-level, phase-dependent signal-integrity
  margin (SSO/crosstalk/supply class) on the SDRAM interface at command
  phases the old slot machine never issued. **STA is structurally blind
  to it** — the I/O numbers are fixed per-path constants (copied from
  Pocket-Amiga, and already contradicted by hardware once, per the
  build-acceptance history), not phase-dependent noise models.
- **Why the perf survived quantization:** the I-cache serves ~98–99% of
  fetches bus-silently at 6 ticks; fetches are ~45% of bus cycles. The
  any-phase freedom was carrying far less benchmark value than designed —
  the slot-phase build keeps effectively all of the measured win.

---

## 3. The laws (the "build better next time" list)

1. **SDRAM command-start phases are part of the hardware-validated
   surface.** RTL correctness, honest STA, and passing benches do NOT
   cover a change in *when* commands hit the pins. Any widening of the
   start-phase set (demand-start, new arbiter slots, refresh scheme
   changes) is a **hardware change** and gets its own single-variable
   hardware A/B — even when every offline gate is green.
2. **Two seeds failing identically is netlist-family evidence.** One
   failure = roll the dice once (Case 2 is real). Identical failure at
   the same guest location on the second placement = stop reseeding and
   start discriminating (Case 3 burned exactly one extra trip on this).
3. **"STA met" exonerates paths, not pins.** Fabric paths: trust honest
   STA (no multicycles — Case 1). Pin interfaces: STA is only as true as
   its I/O delay constants, and phase-statistics effects are outside the
   model entirely.
4. **Run the exoneration ladder in cost order**, each rung kills a
   hypothesis class: (a) transcription/token diff against the validated
   reference → (b) STA path queries on the changed cones (`quartus_sta -t`,
   see `/tmp`-style scripts in the session logs; REQ/CPU_DOUT/ICACHE
   classes) → (c) seam benches on the REAL RTL (see §4) → (d) ONE
   hardware A/B with ONE variable. Reasoning-only fixes shipped to
   hardware have a 0-for-2 record on the MiSTer side and 0-for-1 here.
5. **4-state-simulate the real controller, always.** This fork's
   `pocket_sdram.v` compiles under ModelSim (continuous-assign tristate —
   deliberate). The MiSTer's never did, and that blindness hid the Law 6
   defect for a month. The X-init class (uninitialized `reg` counters)
   is sim-only but masks everything behind it — fix with explicit
   `initial` (bitstream-identical on Cyclone V).
6. **F-line at Finder load ⇒ suspect the write→fetch seam first**, and
   test it offline with self-modifying-code patterns (tb_mem_seam does).

---

## 4. The toolkit (what exists, where)

| Tool | What it proves | Run |
|:--|:--|:--|
| `verilator/modelsim_bench/tb_pocket_sdram.v` | REAL controller vs JEDEC-checking chip model: protocol legality, data integrity, stale-done, ordering | `bash run_sdram.sh` |
| `verilator/modelsim_bench/tb_mem_seam.v` | REAL cache + REAL controller + verbatim glue: hit correctness, snoop/fill coherency, write→fetch | `bash run_seam.sh` |
| `scripts/audit_loader_handshake.py` | bridge→dl_* download protocol | `python scripts/audit_loader_handshake.py` |
| STA path queries | the changed cones are ANALYZED and met (not cut, not multicycled) | `quartus_sta -t` with `get_timing_paths` per class |
| `scripts/check_hierarchy.py` | every instantiated module exists | `python scripts/check_hierarchy.py rtl src/fpga` |
| Seed roll | marginality vs netlist-family discrimination (Law 2) | refit `--seed=N`, compare failure signatures |

PASS lines: `ALL CHECKS PASSED` / `ALL SEAM CHECKS PASSED`. Any
`VIOLATION`/`MISMATCH` is a real finding — the benches have no known
false positives after the harness fixes of 2026-08-19 (3-cycle read
drive window, off-edge stimulus, NBA clock dividers).

## 5. Known-good states

- **`v1.1.0-sp`** (tag; `releases/MacLCtest_1.1.0-sp/`): the full CPU-perf
  stack with slot-phase starts — HW-clean, benchmarks at MiSTer level.
  rbf md5 `4487633bb4c2034f7db15bd61526fbab`, seed 4, STA +2.041/+0.064,
  built from `7023c47`.
- **v1.0.2 / v1.0.3** (`releases/`): the pre-port line, the fallback of
  last resort.

## 6. Open questions for future phase work

- Is a 2-phase start set (`t[0]` restricted to 2 of 4 phases) also clean?
  Each widening step is its own hardware A/B (Law 1). The perf argument
  for bothering is weak (§2 Case 3, last bullet) — measure first.
- The I/O delay constants deserve a ground-truth pass (they are
  Pocket-Amiga numbers). Until then, treat every STA verdict on the
  dram_* pins as provisional.
- `dram_clk` phase retune is the OTHER historically-burned knob
  (135°→180° destroyed a working state, 2026-08-12 era). Do not stack a
  phase move on any other change, ever.
