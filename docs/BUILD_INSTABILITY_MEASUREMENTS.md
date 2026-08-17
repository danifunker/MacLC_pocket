# Build instability — the measurements

2026-08-16. Companion to `BUILD_INSTABILITY.md`, which recorded the arc as a
narrative and named fit/placement marginality as the surviving hypothesis.
This document reports the first **direct measurements** comparing a good
netlist against a bad one, and one of them falsifies that hypothesis as
stated.

Everything here is reproducible from artifacts in the repo. No hardware was
needed except the one control described immediately below.

## The control that makes this possible

buildBP's exact tree (`f85739a`, worktree `../MacLC_BBcolor`) was recompiled
on this machine and toolchain, packaged into a **third card slot**
(`danifunker.MacLCtest`, built by `scripts/make_test_slot.sh`), and
**user-verified working 100% on hardware**.

So the comparison below is between two netlists compiled hours apart on one
toolchain, one known good on hardware and one known bad on hardware. That is
the cleanest A/B this project has ever had.

Archived, complete (bitstreams, reports, logs — not just summaries):

```
scratch/builds/2026-08-16-buildBP-determinism-output_files/   GOOD  (HW-verified)
scratch/builds/2026-08-16-buildBX-output_files/               BAD   (corrupts Finder every boot)
```

★ `src/fpga/output_files/` is **overwritten by every compile**. Before this
archive, exactly one build's reports existed on disk. Archive the whole
directory alongside the `.sof`, every build, or this comparison is impossible
to make later.

## Determinism, measured correctly

Recompiling BP's tree reproduces BP:

| comparison | differing bytes |
|---|---|
| archived BP `.sof` vs recompiled BP `.sof` | **47** (header/usercode/checksum + build_id ROM) |
| same two, converted to compressed `.rbf` | **327** (matches the figure in `BUILD_INSTABILITY.md`) |
| the flow's `.rbf` vs `quartus_cpf` from the same `.sof` | **0** |

★ Do NOT diff the shipped `bitstream.rbf_r` against a fresh `.rbf` to judge
determinism. The RBF is compressed; the *shipped* file is also bit-reversed.
A raw diff of those reports ~1.69 M differing bytes for two builds that are
functionally identical. Compare `.sof` files, or regenerate both `.rbf`s the
same way.

## 1. THE HEADLINE: STA slack does not predict hardware health

BP was fitted while `clk_sys` was declared **asynchronous** to `clk_mem`, so
its own timing report never analysed the CPU↔SDRAM interface. To compare
like with like, BP's **already-fitted netlist** (same placement, same
routing, no refit) was re-analysed under BX's corrected SDC using
`scripts/sta_replay.tcl`.

Method validated first: replaying BP's own constraints reproduced its
archived report exactly on all six clocks (2.589 / 3.966 / 5.880 / 6.497 /
9.894 / 48.583).

Worst-case setup slack, identical constraints, identical corner:

| clock domain | **BP — works on HW** | **BX — corrupts every boot** |
|---|---|---|
| `general[0]` clk_mem 65 MHz | **−4.453 ns** ❌ | **+2.660 ns** ✅ |
| `general[1]` dram phase 65 MHz | +2.589 ns | +2.038 ns |
| `general[2]` clk_sys 32.5 MHz | +2.136 ns | +4.647 ns |
| `clk_74a` 74.25 MHz | +3.966 ns | +3.632 ns |
| `general[3]` clk_pix 15.67 MHz | +48.583 ns | +48.669 ns |

**The working build violates timing by 4.45 ns. The broken build meets it
with 2.66 ns to spare, and is better timed on clk_sys as well.**

Consequences:

- The placement-marginality hypothesis **as measured by STA** is falsified.
  Slack on the SDRAM interface is not merely a poor predictor here; on this
  pair it is anti-correlated with hardware health.
- The planned experiment "add `set_max_delay` to the VRAM-shadow RMW cone on
  condemned netlist BX" is predicted to do nothing. BX already meets timing
  in that cone with margin. Do not spend a build on it as specified.

## 2. What BP's violating path actually is

Every one of BP's twelve worst paths runs from the TG68K register file to the
SDRAM write-data register:

```
tg68k|TG68KdotC_Kernel|altsyncram:regfile_rtl_0|…PORT_B_WRITE_ENABLE_REG
   →  pocket_sdram|sd_dout_r[9]        −4.453 ns
```

CPU write data → SDRAM write register, crossing clk_sys → clk_mem. It
violates by 4.45 ns and the machine is flawless on hardware, through hours of
games and full OS installs.

The explanation is that **the constraint is over-pessimistic, not that the
hardware is lucky.** A 68020 write holds its data stable across a multi-cycle
bus transaction, and `pocket_sdram`'s state machine wraps every 8 clk_mem
cycles (the "65 MHz must stay exactly 8×" law). The data is stable for far
longer than one 15.4 ns period. Constraining it as single-cycle demands
closure that the design never needed.

★ This has a consequence for BW/BX. Merging the clock groups was correct —
the interface must be analysed — but it was landed **without the matching
multicycle exceptions**, so the fitter was told to close a path with ~4.5 ns
of fictitious violation. Effort spent there comes out of every other cone.
`core_constraints.sdc` already does exactly this for `periph_din_reg` and the
TG68 kernel internals, with the reasoning written out; the CPU→SDRAM write
path needs the same treatment. Suspect for the BW/BX failures — but it cannot
explain BQ/BR/BS/BU, which predate the SDC change.

## 3. The anchor costs 2× what its comment claims

| | BP (good) | BX (bad) | delta |
|---|---|---|---|
| ALMs | 13,565 (73%) | 13,836 (75%) | +271 |
| registers | 8,776 | 9,521 | **+745** |
| M10K | 256 (83%) | 256 (83%) | — |
| `ncr5380` registers | 1,614 | 1,808 | +194 |
| `scsi:target[0]` registers | 422 | 497 | +75 |
| `scsi:target[1]` registers | 427 | 493 | +66 |

The anchor block in `mac_lc_pocket.sv` states "~352 FFs is the entire cost."
The measured cost is **745 registers** — the 11 preserved 32-bit words plus
the SDMA snapshot deck, plus roughly 280 registers *inside* `scsi.v`,
`ncr5380.sv` and `floppy.v` that were previously dead-code-eliminated and are
now revived by having their witness ports connected.

Reviving them is the anchor's declared purpose, so this is not a defect. But
the cost comment is wrong by more than 2×, and the anchor is present in every
failing build from BS onward and absent from the only reliably-good build.

## 4. Metastability: identical, therefore not the differentiator

Both builds report the same:

```
The design MTBF is not calculated because there are no specified synchronizers.
Number of Synchronizer Chains Found: 205
Fraction of Chains for which MTBFs Could Not be Calculated: 1.000
```

205 asynchronous crossings, no MTBF for any of them, no
`SYNCHRONIZER_IDENTIFICATION` or `OPTIMIZE_FOR_METASTABILITY` in
`ap_core.qsf`. This is a real robustness gap and worth closing on general
principle — but it is **byte-for-byte the same in the good build and the bad
one**, so it does not explain BP vs BX. Demoted from suspect to backlog.

Other findings from the reports, none of them differentiators: two
unconstrained clocks (`i2s|aud_mclk_divider[1]`, `audgen_mclk` — logic-generated
audio clocks, in both builds); unconstrained ports limited to `bridge_*` and
`scal_*`, which is normal for the APF template.

## 5. The process finding: the ladder was abandoned mid-climb

`BUILD_INSTABILITY.md` concludes "no code delta separates the two
populations." That conclusion is not supported, because **no build after BP is
one variable away from BP**:

| build | delta **from BP** | verdict |
|---|---|---|
| BQ / BR | + rung 3 | bad (two seeds) |
| BS | + rung 3 + partial anchor | good 2 days, then bad |
| BU | + rung 3 + full anchor + ASC pin | bad |
| BW | + rung 3 + full anchor + ASC pin + SDC | bad |
| BX | + full anchor + ASC pin + SDC | bad |

BX was designed as "BW minus rung 3" — one variable from BW, but **three from
BP**. The single-variable experiments that would attribute the failure were
never run. "No single change is responsible" has not been tested; it has been
skipped.

## 6. Revised plan

Drop the RMW-constraint experiment (§1). Resume the ladder from BP, one
variable per build, each gated by the one-boot test plus the Finder icon
check. The test slot exists now, so a candidate can be tried without
disturbing the main or prev slots.

1. **BY = BP + the ASC alert fix, alone.** Unchanged from the existing plan —
   small, proven to cure the stuck alert, and it ships v1.0.1's headline
   known issue. Re-roll the seed if the fit is bad.
2. **BZ = BP + the anchor, alone.** The experiment nobody has run. The anchor
   is in every bad build from BS on and in no good build. Bad ⇒ mechanism
   found and the whole post-BP era is explained. Good ⇒ the anchor is
   exonerated for the first time on evidence rather than argument.
3. **CA = BP + the SDC merge, alone — plus the CPU→SDRAM write multicycle**
   that §2 shows is missing. Tests the constraint change on its own and
   removes the fictitious violation at the same time.

If BZ and CA are both good, the fit-lottery reading survives and seed/density
becomes the story. If either is bad, we have a mechanism instead of a
hypothesis.

## 7. buildBY — the smallest perturbation yet, and it fails

Added the same day: **buildBY = BP + ~20 registers.** A single option register,
a 2FF sync, and one reset term, all inside `pocket_input` — an
input-synthesis module with no path to memory or video. It **F-lines on
hardware.**

Its gates were green and matched BP almost exactly: SDRAM write path +2.596
(BP +2.589), every domain positive, write 3 / read 3 real paths, zero probes,
13,526 ALMs against BP's 13,565.

This kills three more theories in one build:

- **The anchor.** BY does not contain it. It was the last suspect standing
  after §1-§5, and the planned buildBZ experiment is now unnecessary.
- **The rung-3 curse.** BY has no live-follow logic.
- **The SDC, in both directions.** BY was fitted with BP's ORIGINAL
  constraints — clk_sys declared asynchronous, the CPU↔SDRAM interface
  untimed. Good BP and bad BY share that configuration.

Scoreboard: good = BO, BP, BP-rebuild (adjacent rungs). Bad = BQ, BR, BU, BW,
BX, BY — six independent netlists.

**buildBY2** (RTL byte-identical to BY, fitter seed 2 → 11) is the
discriminator: it moves placement while holding the netlist fixed, which every
prior experiment confounded. BY2 good ⇒ placement lottery, proven. BY2 bad ⇒
placement exonerated and the netlist implicated, at which point the coordinate
and post-fit-netlist comparison becomes the main line of attack.

★ ARCHIVE `db/`, NOT JUST `output_files/`. The compilation database holds the
fitted netlist — the only artifact that can answer placement-vs-restructuring.
BP's and BY's databases were both lost to subsequent compiles before anyone
thought to keep them. BY2's is archived (110 MB, `…-buildBY2-seed11-output_files/db`).
The bitstream itself is NOT a substitute: it is proprietary, undocumented and
compressed, and byte-diffing it is actively misleading (see §"Determinism").
`scripts/placement_probe.tcl` reads node coordinates out of a database.

## 8. ★★★ buildBY2 WORKS — the fit lottery is proven

**buildBY2 = buildBY with the fitter seed changed from 2 to 11. Nothing else.
Both source files verified byte-identical to BY's commit (3cb357f). BY F-lines
on every boot; BY2 works on hardware.**

This is the first clean isolation of placement in the entire arc. Every prior
experiment moved the netlist and the placement together. This one moved
placement alone, and it flipped the outcome.

Confirmed: **the fit lottery is real.** The same logic, compiled twice, lands
in a working or a broken physical arrangement depending on nothing but the
fitter's starting seed.

Exonerated, permanently — none of these can be the mechanism, because the
netlist did not change between BY and BY2:

- the marginality anchor (§7)          - rung 3 / startup input mode (§7)
- the SDC clock-group change (§7)      - the ASC FIFO pin
- design density                       - any specific RTL edit

Also confirmed: **STA cannot predict it.** All three of BP, BY and BY2 had
green, near-identical gates (§7 table). Slack does not discriminate.

Observed good-fit rate: BO, BP, BY2 good; BQ, BR, BU, BW, BX, BY bad ⇒ roughly
1 in 3. Low enough that a build failing its first roll is unremarkable, and
high enough that re-rolling converges fast.

### The process this makes official

1. Make the change. One behaviour-relevant variable per build, as always.
2. Compile, run the desk gates (STA, `check_sdram_paths`, zero-probe).
3. Flash to the **test slot** and run the one-boot damn-test + Finder icon gate.
4. **If it fails, re-roll the seed and repeat.** A bad fit is not a bug in the
   change — do not debug the RTL on a failed roll. That mistake cost this
   project weeks: BQ/BR/BU/BW/BX were all read as evidence about their
   features, and every one of those readings was wrong.
5. Soak the passing roll before shipping (see the caution below).

### ★ The stuck-alert bug was fit-expressed too — the ASC fix is unnecessary

buildBY2 plays the alert sound and stops it correctly, and it contains **no
ASC fix at all**: `rtl/asc.sv` is byte-identical to the BP base, and neither
`dbg_asc` nor `anchor_asc0` exists in its tree.

The fix (an anchor pin on the ASC FIFO-A status cone) was credited on buildBW,
which was a bad fit in every other respect. The credit was misattributed: the
alert never needed a code change, it needed a good placement.

"Alert plays and never stops" was v1.0.1's headline known issue and drove the
documented workaround (alert volume 0 = menu-bar flash). It joins the list of
symptoms blamed on logic that were actually the fit:

  Finder colour-icon garbling · F-line bombs · video corruption ·
  boot hangs · the stuck alert

**The queued "BY = BP + ASC alert fix" build is therefore dropped.** Confirm
across the soak by triggering several alerts; if the bug ever reappears on a
good fit, the fix comes back off the shelf — it still exists on `main`.

### The caution that has burned us before

buildBS passed its gates, ran clean for ~2 days, then failed a clean-state
retest. One good boot is enough to REJECT a fit, not enough to bless one.
Soak a passing roll across several power-off boots, both card slots, and real
Finder/disk work before it becomes a release.

## What this does not settle

- Two builds. A good/bad pair is not a population.
- BS's two good days followed by a failed retest remains unexplained.
- Nothing here identifies the *physical* mechanism of the corruption. It rules
  out the leading candidate's measurable signature; it does not replace it.
