# Mission: blockdev reset consistency — kill the restart crash AND the unrecoverable-hang, for real

Written 2026-08-24 late, after a full day of evidence. This is the resume
prompt for the NEXT session(s). Two boxes, two halves: **macOS = bench +
RTL** (Verilator 5 lives there; Windows ModelSim segfaults on ncr5380 —
don't retry it), **Windows = Quartus build + HW gates**. Branch of work:
`blockdev-pipeline` on origin (contains everything through the pipeline +
this doc); Windows merges to `main` when HW clears.

**The law that governs everything here:** no RTL ships without the benches.
Reasoning-only hardware fixes on this subsystem are 0-for-3 across the
trees. Tonight's benches were green and hardware still failed — that is not
a reason to skip benches, it is a reason to bench the CASES WE MISSED,
which are now known precisely.

## The two symptoms (user-verified 08-24 evening, fresh disks, fit bd-s6)

1. **Special ▸ Restart works a couple of times, then a bus error.**
   Intermittent — the signature of a race with in-flight state, not a
   deterministic wedge.
2. **After any crash, the OSD/core-restart path does NOT recover** (Mac
   hangs at boot, every time) — **but quitting the core to the Analogue
   menu and relaunching recovers fully.** No power-off needed. The volumes
   are NOT damaged (user-confirmed; a corrupt volume would hang the
   relaunch too).

Same family, one seam: **partial state survival at the apf_blockdev
boundary across each reset flavor.** A full core teardown re-initializes
both clock domains from the bitstream — the only reset that currently
leaves the seam consistent.

## The mechanism (located, not yet fixed)

`src/fpga/core/apf_blockdev.v` — the Pocket-only block between the
MiSTer-shaped `io_lba/io_rd/io_wr/io_ack` + `sd_buff_*` interface (consumed
by `rtl/scsi.v` inside `rtl/ncr5380.sv`) and the APF target-dataslot bridge
commands. Facts:

- It has `input wire reset_n` (~line 46) from the framework side.
- **No guest reset flavor reaches it at all**: neither `_cpuReset`
  (Egret-driven) nor the new `soft_periph_rst` (the RESET-instruction pulse
  from `mac_lc_pocket.sv`, 2026-08-24 §-9). A guest warm restart therefore
  inherits: any in-flight transfer, the serve FSM mid-envelope toward
  scsi.v, and (since commit `229e3e3`) the speculation state
  (`pf_valid`/`pf_lba`/`pf_slot`/stream tracker/`x_busy`/`x_kind`/
  `req_buf`/`drain_half`).
- The **request/completion toggle pairs cross clk_74a ↔ clk_sys**. Any
  reset that clears one domain's phase but not the other's desyncs the
  handshake PERMANENTLY — every later transfer pairs with the wrong
  completion. That is the post-crash "no safe boot until full reload"
  state. (Whether the OSD-restart path pulses `reset_n` into a wedged FSM,
  or the Analogue host side keeps its own session state, the observable is
  the same: only full teardown recovers. Fix what we own: make the seam
  self-consistent under every reset we receive, and re-sync-able.)
- **Deliberate exemption that must survive**: the buildY dataslot-update
  latch (~line 274) is intentionally NOT gated on `reset_n` — Analogue
  sends dataslot updates while the core is still in reset; clearing the
  latch on reset breaks core load. Any reset rework must preserve this.
- scsi.v's side of the seam re-inits per command (`rd_hps_blk` zeroes in
  any non-transfer phase, scsi.v:406) and the guest issues a SCSI bus reset
  at boot — the GUEST side recovers by design. The blockdev side is the
  one that doesn't.

## The fix (design intent — the bench decides the details)

1. **Guest soft reset ⇒ quiesce.** Route `soft_periph_rst` (clk_sys,
   16-clk pulse in `mac_lc_pocket.sv`) up through `core_top.sv` into
   apf_blockdev, properly synchronized into the 74a domain (the pulse is
   ~492 ns — comfortably wide; still 2FF-sync it and stretch if needed).
   On quiesce: let/force the in-flight bridge transaction terminate
   cleanly (complete-and-discard beats abort if the APF host protocol has
   no abort), drop the serve envelope toward scsi.v in a way scsi.v's
   phase-idle re-init tolerates, clear `pf_valid` + the stream tracker +
   `pf_mnt_kill`-style discard for an in-flight speculative fetch, return
   the job layer to idle. Do NOT blindly zero the cross-domain toggles —
   handle their phase atomically (see 2).
2. **`reset_n` ⇒ phase-consistent, not phase-blind.** Either reset both
   domains' toggle trackers through a synchronized sequence, or make the
   handshake self-resynchronizing (e.g., on the 74a side, treat
   req-toggle-difference as the request signal and re-baseline the
   difference at reset exit). Preserve the buildY update-latch exemption
   verbatim.
3. **Cold-boot safety is structural, keep it that way**: the ROM's T+4s
   RESET fires the soft pulse on EVERY cold boot, with blockdev idle
   (PRAM load completes before the 68020 is released — Egret holds the
   CPU in reset until `pram_loaded`). Quiesce-while-idle must be a no-op.
   The PRAM load path (C_PR_*/C_PV_* states) must be unreachable by the
   guest pulse by construction — verify, don't assume.
4. **Untouched, per standing law**: NCR/SCC get no new reset (2026-06-12
   cold-boot lesson); `pocket_sdram.v` `t == 3'd1`; `src/fpga/apf/`;
   the hd32b `RING_LOG` asymmetry; `verilator/sim.v` (still a separate
   mission).

## Bench plan (macOS, FIRST — this is the mission's core)

Extend `verilator/tb_blockdev.v` (its host model + latency + per-LBA
content oracle are already good — commit `229e3e3` rewrote it) with the
cases the seam has never had:

- **(a) soft-quiesce mid-DEMAND transfer** → seam consistent, next command
  serves correct data.
- **(b) soft-quiesce mid-SPECULATIVE fetch** → result discarded, pf state
  clear, next demand correct.
- **(c) soft-quiesce during the drain envelope** (ack high, sd_buff
  streaming) → scsi.v-side tolerated (its phase re-init), next command
  correct.
- **(d) `reset_n` pulse mid-transfer, modeling the REAL Analogue restart
  sequence** — Reset Enter, dataslot updates re-sent as multi-cycle
  LEVELS, Reset Exit (see core_top.sv ~line 802 comments) → seam
  phase-consistent afterward; the update latch still catches updates sent
  during reset.
- **(e) quiesce while idle** (the T+4s cold-boot case) → provable no-op.
- **(f) the full existing suite still passes** (cold read, sequential
  stream + overlap witness, seek, write round trip, write/media-change
  invalidation, floppy interleave, CDC monitor, spurious-ack watch).

Then the standard gates: `run_scsi_face_verilator.sh` (stock + real
cadence), `run_scsi_ring_verilator.sh`, `tb_disk_swap.v`,
`check_hierarchy`. Hand back on the branch: RTL + benches + a results note
(what changed, which cases caught what, expected fit delta ≈ 0).

## Windows half (after the Mac hand-back)

Merge → build (seed lottery patience — but see Phase 2) → test slot →
HW gates, **with disposable-image discipline** (restore images before every
verdict; the corruption loop poisoned evidence twice on 08-24):

1. Cold boot ×3 to Finder, mouse alive (T+4s exercises the quiesce).
2. **Special ▸ Restart ×5 consecutive** to the desktop (it survived ×2
   before failing — 2 is not a gate).
3. **OSD core-restart ×3 mid-session** → clean boot each time (the
   recovery-wedge gate).
4. The extension-parade crash class (Easy Open / Foreign File Access
   faces) judged across repeated boots ONLY after 1-3 pass.

## Phase 2 — end the seed lottery (Windows, after the seam is clean)

The extension-parade class survived the pipeline across FOUR placements
(seeds 12/4/7/6, varied crash faces, cold boots clean on s6) — the
standing explanation is **placement marginality in the SCSI cones**, the
same category as the F-line and icache-enable stories. The structural fix
queued since 08-20: **make the validated placement reproducible** — pin
the marginal cones (ncr5380 host face, scsi.v ring/serve, blockdev CDC
synchronizers) via LogicLock regions or design-partition incremental
compile on Quartus 18.1 Lite, export into `ap_core.qsf`, and verify a
pinned rebuild reproduces both STA and hardware behavior. Pick the
mechanism that 18.1 Lite actually supports well; the goal is the
invariant, not the feature name. After pinning, a good fit stops being a
dice roll and every future netlist change inherits it.

## Context you'll want open

- `docs/RESUME.md` §-8/§-9/§-10 — the full 08-24 evidence chain, seed
  ledgers, retracted theories (7.1-disk contamination, starvation-as-sole-
  cause), screenshot decodes (`scratch/20260824_*.png` on the Windows box).
- `docs/blockdev_pipeline_results.md` — the pipeline design + bench
  verdicts; `docs/blockdev_pipeline_handoff.md` — its mission.
- `docs/F-Line_Build_Errors.md` — the marginality case history incl.
  Case 5.
- Recovery procedure until fixed: after any crash, QUIT the core and
  relaunch (no power-off; volumes survive).
- Current cards/slots: MacLCtest = `1.2.0-bd-s6` (cold-boot clean);
  main slot = v1.1.3 (stable daily driver); v1.2.0 zip built and
  UNPUBLISHED in `output/` (predates restart+pipeline — decide at publish
  time whether to re-cut).
- House rules: one behavior-relevant variable per shipped build; commit
  with the HW verdict; releases from `main` only via `scripts/release.sh`.
