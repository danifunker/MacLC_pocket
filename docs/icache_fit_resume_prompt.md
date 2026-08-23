# RESUME PROMPT — I-cache `.enable` fix + the 89% M10K fit lottery

**Written 2026-08-22 mid-mission; updated ~13:40 after the ring revert was built and pushed to the card.** Paste this into a fresh session. Read
`CLAUDE.md` and `docs/RESUME.md` §-7 first; this file is the live state on top
of them.

---

## The mission

Port the MiSTer I-cache `.enable`-must-not-be-constant fix to the Pocket and
validate it on hardware. **The fix is written, committed and structurally
confirmed. It has NEVER been hardware-validated, because no fit of this netlist
has booted cleanly yet.**

## What is DONE (committed, `ca7bcb2` on `main`)

- `src/fpga/core/mac_lc_pocket.sv` — new `input icache_en`;
  `fetch_cache .enable( icache_en )`, **never `1'b1`**.
- `src/fpga/core/core_top.sv` — `reg opt_icache_off = 1'b0` decoded at bridge
  `0xF0000064` (read + write), 2FF-synced as `icoff_s1/s2`, wired
  `.icache_en( ~icoff_s2 )`. Purely additive: the commit has **zero deleted
  lines** in core_top.sv, so the adjacent 32-bit path is byte-identical to the
  validated `1.1.3-32b2`.
- Docs: `docs/RESUME.md` §-7 (full mechanism + evidence), a law in `CLAUDE.md`,
  a row in `docs/verilator_differences.md` (`1'b1` is correct in sim, wrong on
  FPGA — a deliberate divergence).
- **No `interact.json` row.** The menu is at its measured ceiling (13 vars + 5
  data slots; a 14th silently drops a row). None is needed — `bridge_wr_data`
  arrives on a pin, so Quartus cannot prove the register constant.

### Structural confirmation (this is the fix's whole point)

`enable_r` survives into the fitted netlist at **all three seeds tried**.
Verified by querying the fitted timing netlist, not by reading a report:

```tcl
# /tmp/q_enable.tcl  — run: quartus_sta -t q_enable.tcl   (from src/fpga/)
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
foreach pat {*icache|enable_r* *fetch_cache*enable_r* *opt_icache_off* *icoff_s*} {
    set c [get_registers $pat -nowarn]
    puts "PATTERN $pat -> [get_collection_size $c] register(s)"
    foreach_in_collection r $c { puts "    [get_register_info -name $r]" }
}
project_close
```

★ **Do NOT try to answer this with `build.sh --check`.** Analysis & Synthesis
never enumerates *surviving* registers, and `enable_r` is absent from the
removed-register table in BOTH the fixed and the `1'b1` control. That A/B was
run, it is not diagnostic, and repeating it wastes ~10 min. The folding is a
**fitter** behaviour.

---

## Hardware results — 3 seeds, 3 failures, all at 275/308 M10K (89%)

| seed | ALMs | registers | worst slack | hardware verdict |
|:--|--:|--:|--:|:--|
| 12 | 14,191 | 10,429 | +0.118 ns | Finder errors at 8bpp; 32-bit never reachable |
| 7  | 14,179 | 10,513 | +0.121 ns | **video corruption** + Finder errors |
| 11 | 14,205 | 10,411 | +0.091 ns | **video corruption on System 7.1** |

All three met timing with zero negative paths. Three distinct register counts =
three genuinely different placements.

### The deduction that matters

**Seed 11 failed on 7.1, not 7.5.5.** That rules out Case 5 (the 7.5.5-specific
corruption, `docs/F-Line_Build_Errors.md:140`) as the explanation. Combined with
*different* failures across seeds, this is the textbook placement-marginality
signature (Law 2 / Law 7 discriminator): **the netlist's resource pressure is
the suspect, not the logic.**

This reproduces `abb0663`'s finding exactly, at exactly the same density.

---

## THE NEXT STEP — ★ APPLIED 2026-08-22 ~13:40: built, verified, ON THE CARD

**Revert hd32: drop HD1's read ring from 32 KB back to 16 KB** to get M10K
from 275/308 (89%) down to ~259/308 (84%), the demonstrated placement
ceiling. Then re-roll seeds.

### What was done (all verified, nothing assumed)

- `rtl/ncr5380.sv` ~833-841: the `.RING_LOG(i == 0 ? 6 : 5),` override and
  its 5-line comment are GONE — the functional hunk is byte-identical to
  `abb0663`; a 7-line comment records why, and that Case 5's return is the
  accepted cost. Both disks now ride `scsi.v`'s default `RING_LOG = 5`
  (16 KB). **Uncommitted by design** until hardware clears it.
- Seed **12** in `ap_core.qsf` (first roll; rc1 canonical).
- Full compile `compile_20260822_131956.log`, 17 min, exit 0:

  | | 275-M10K fits (s12 / s7 / s11) | **this fit (r16, s12)** |
  |:--|--:|--:|
  | ALMs | 14,191 / 14,179 / 14,205 | **14,211 / 18,480 (77%)** |
  | registers | 10,429 / 10,513 / 10,411 | **10,405** |
  | **M10K** | **275 / 308 (89%)** | **259 / 308 (84%)** — exactly the ceiling |
  | block memory bits | 2,211,939 (70%) | 2,080,867 (66%) |
  | worst slack, all corners | +0.118 / +0.121 / +0.091 ns | **+0.151 ns**, 0 negative |

  Two combinational-loop critical warnings (162 + 171 nodes) are the same
  pre-existing pair the seed-11 log carries (166 + 166) — not new.
- **`enable_r` SURVIVES in this fitted netlist too** (`q_enable.tcl` re-run
  on the new fit — 4th placement confirmed):
  `core_top:ic|mac_lc_pocket:machine|fetch_cache:icache|enable_r`,
  `core_top:ic|opt_icache_off`, `icoff_s1`, `icoff_s2`. The script now lives
  at `scratch/icache_fix/q_enable.tcl` (log `q_enable_r16_s12.log`).
- Archived: `scratch/builds/20260822-r16-s12-2b4c4e26.{sof,rbf}` (raw rbf
  sha1 `2b4c4e26…`); the failed seed-11 fit is kept as
  `scratch/builds/20260822-icen-s11-m275.sof`.
- Staged `1.1.3-r16-s12` with `make_test_slot.sh`, copied to
  `D:\Cores\danifunker.MacLCtest\`, all 10 files `cmp`-identical to the
  staged copy, on-card `bitstream.rbf_r` sha1
  **`dd432dcfa9064a3f07de01c5e74afe9234d60112`**, card ejected
  (Shell.Application, first attempt).

### Hardware verdicts on the 259-M10K (r16) netlist

| seed | ALMs | registers | worst slack | hardware verdict (user) |
|:--|--:|--:|--:|:--|
| 12 | 14,211 | 10,405 | +0.151 ns | "a little better, but still quirky" — some hangs, some SCSI crashes |
| 7  | 14,242 | 10,435 | +0.082 ns | **ON THE CARD 2026-08-22 ~14:50** (`1.1.3-r16-s7`, rbf_r sha1 `2c7907d7…`) — seed-only re-roll, user directive: "DO NOT CHANGE ANYTHING ELSE"; verdict owed |

User's read (2026-08-22): we are getting closer; the same disk is fine on
MiSTer with the same CPU stack, so the task right now is purely to land a
clean placement — then a proper test. Partial-fail on s12 = one roll used
(Law 2: one failure -> roll once; identical failure on the second placement
-> stop rolling and discriminate).

### What to do with the hardware verdict

- **Boots clean (usual System volume, sane video, Finder works):** run the
  real icache gate ("Still owed", below). Then commit the ring revert + seed
  12 as the new canonical (the `374c981` pattern: seed lands with the
  verdict).
- **7.5.5 dies at/after Finder launch:** EXPECTED — Case 5 is unmitigated on
  a 16 KB ring. Not a regression, not a new bug; do not chase it.
- **Fails on the usual System volume:** the s12 roll is spent (quirky) and s7
  is on the card. If s7 also fails, next rolls are 4 then 11 (`build.sh
  --seed N`, nothing else).
  Same failure twice = netlist defect, stop rolling (Law 2). Different
  failures = still in the lottery even at 84%; the disk-2 ring trim (−8
  M10K) is a weak lever at this point — the LogicLock / load-bearing-RAM
  mission is the structural answer.

### ★★★ The known, user-ACCEPTED cost — do not re-litigate this

The 32 KB ring is **the only mitigation for Case 5**, the 7.5.5 corruption
(bus error `A0 = $50F06060`; jump to garbage PC `6DB6DE41`; corrupted pointer
slots). Mechanism unfound. On a 16 KB ring a 7.5.5 volume *"consistently dies
during/after Finder launch."*

The user was told this explicitly and directed the revert anyway, on the sound
grounds that **no fit boots at 89%, so 7.5.5 is untestable either way.**

**If 7.5.5 breaks after this change, that is EXPECTED and accepted — not a new
bug, not a regression to chase.** The Case-5-safe alternative (trim *disk 2's*
ring 5→4 instead, freeing ~8 M10K and leaving HD1's 32 KB intact) was offered
and not taken; it remains available if the full revert overshoots.

---

## Working-tree state right now (2026-08-22 ~13:40)

```
 M rtl/ncr5380.sv              <- hd32 REVERTED (uncommitted BY DESIGN until HW clears it)
 M src/fpga/ap_core.qsf        <- SEED 7 (seed-only re-roll after s12's quirky verdict; uncommitted BY DESIGN)
 M src/fpga/apf/build_id.mif   <- build stamp, regenerated every compile
?? docs/icache_fit_resume_prompt.md
```

Seed changes stay uncommitted until hardware clears them; that is the repo's
pattern (`374c981` made seed 7 canonical only after a good verdict). The ring
revert follows the same rule: the user directed it, but the commit should
carry the hardware verdict.

## Card state

`MacLCtest` slot = **`1.1.3-r16-s7`**, sha1 `2c7907d7…` — **awaiting the
hardware verdict.** Card ejected 2026-08-22 ~14:50. Previous occupant
`1.1.3-r16-s12` (sha1 `dd432dcf…`, verdict: quirky — hangs + SCSI crashes) is
backed up at `scratch/icache_fix/testslot_backup_1.1.3-r16-s12/`; its build is
`scratch/builds/20260822-r16-s12-2b4c4e26.{sof,rbf}`, the s7 build is
`scratch/builds/20260822-r16-s7-5d1f63d4.{sof,rbf}`. Backups of the previous
occupants: `scratch/icache_fix/testslot_backup_1.1.3-icen-s11/` (the failed
seed-11, sha1 `133c3ca2…`) and `testslot_backup_1.1.3-32b2/`.

## Build / flash loop

```bash
bash scripts/build.sh                                              # ~17 min full compile on this box (45 min is the old estimate)
bash scripts/build.sh --check                                      # A&S only, ~10 min
bash scripts/make_test_slot.sh src/fpga/output_files/ap_core.rbf <label>
cp scratch/staging/testslot/Cores/danifunker.MacLCtest/* /d/Cores/danifunker.MacLCtest/
```

Always: verify every file with `cmp` against the staged copy, print the
bitstream sha1, then eject via the Shell.Application COM verb. Card is `D:`.

---

## Rules that must not be broken

1. **Never hardwire `fetch_cache .enable` to `1'b1`** — that is the entire bug.
2. **Never edit `src/fpga/apf/`** (`build_id.mif` excepted; the build stamps it).
3. **Do not add `interact.json` rows.** The menu is at its ceiling, and the user
   explicitly refused an I-cache menu toggle ("THIS IS WHAT CAUSED ISSUES IN THE
   FIRST PLACE"). Do not touch the card's menu JSON.
4. **Seeds do not transfer between netlists**, and Quartus is deterministic —
   re-running a failed seed on unchanged RTL reproduces it bit-for-bit. Never
   propose it.
5. Same failure across seeds = systematic defect. Different failures across
   seeds = placement lottery. (Law 2 / Law 7.)
6. Don't spawn subagents, workflows, or deep-research unless asked.

## Still owed (lower priority)

- **The control fit.** `.enable(1'b1)` compiled all the way through the fitter,
  to show `enable_r` is *absent* there. Until that runs, "the fitter folds it"
  is the MiSTer handoff's account, not this fork's measurement. It does not
  block the hardware gate.
- **The real icache gate**, once any fit boots clean: System 7.5.5 → Monitors
  **256 colors** + Memory **32-bit ON** → **Special ▸ Shut Down** (NOT Restart —
  that path is separately broken and won't persist to PRAM) → reload → work the
  Finder. Then PoP2 launch and Speedometer ≈ 3.59. 1-bit hides the bug entirely;
  a PRAM reset silently masks the repro.
