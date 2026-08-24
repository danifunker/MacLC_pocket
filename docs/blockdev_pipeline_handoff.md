# Handoff: SCSI refill root fix (Case 5 + disk perf) — macOS/Verilator session

Written 2026-08-24 on the Windows box for the macOS box. **Your half is the
bench-gated design work; the Windows box does the Quartus build afterward.**
Do not attempt Quartus here; do not ship anything that hasn't passed the
benches below — reasoning-only hardware fixes on this subsystem are **0-for-3
across the trees** (Law 4).

## Why (three arrows, one fix)

1. **Case 5** — the 7.5.5 startup crash (Bus Error in `_InternalWait`,
   A0=`$50F06060`, during Macintosh Easy Open's boot-time scan; photographed
   twice, `docs/F-Line_Build_Errors.md` Case 5, RESUME §-8). Converged
   mechanism (08-22, three-way corroborated): `apf_blockdev` fetches ONE
   sector at a time, on demand, no prefetch/overlap — a full
   clk_sys→clk_74a→bridge→SD round-trip per sector. Under 7.5.5's sustained
   reads the ncr5380 read-ring drains faster than that serialized refill, the
   ring empties, and the shared host face crosses its stall/refill boundary at
   Pocket-specific alignments `dma_settle` was never validated against ⇒
   byte shift/dup ⇒ clean-wrong data ⇒ crash. The hd32b 32KB HD1 ring
   (shipped v1.1.3+) only buffers 2× in front of the same slow refill —
   mitigation, not fix.
2. **Disk performance** — the same serialization is why disk-bound work (app
   launches, extension parade, Finder browsing) feels slower than MiSTer
   (whose HPS delivers sectors in fast bulk). User raised this explicitly
   08-24.
3. **The seed-lottery tax** — whether a given fit expresses Case 5 has decided
   shippability on three consecutive netlists (RESUME §-8/§-9 seed ledgers).
   Removing the starvation margin ends that tax.

## Step 1 — run the disambiguator FIRST

```bash
cd verilator/modelsim_bench
bash run_scsi_face_verilator.sh
```

Needs Verilator ≥ 5.x with `--timing` (this box's proven toolchain) and
python3. PASS = final line `ALL FACE CHECKS PASSED`. **This bench decides the
design**:

- **FAILS at any pacing** ⇒ the shared ncr5380 pseudo-DMA host face has a
  real byte-shift bug. Fix THAT (root cause); pipelining would paper over it.
  (MiSTer shares this face but its fast refill may simply never reach the
  failing alignment — a face bug here is still shared-RTL truth.)
- **PASSES at all pacings** ⇒ the host face is clean and the corruption is
  refill STARVATION ⇒ proceed to Step 2.

★ The stock run drives Phase-B pacing. Then extend it to the **real
`apf_blockdev` refill cadence** (slow refill: hundreds of µs per sector, the
documented mechanism) — the memory crib explicitly says "drive it at real
apf_blockdev refill cadence". A pass only at fast cadence is not a verdict.

## Step 2 — pipeline `apf_blockdev` (if Step 1 passes)

Target: `src/fpga/core/apf_blockdev.v` (Pocket-only; sits between the
MiSTer-shaped `io_lba/io_rd/io_wr/io_ack` + `sd_buff_*` interface consumed by
`rtl/ncr5380.sv`/`rtl/scsi.v` and the APF target-dataslot bridge commands).

Design intent: **double-buffer the sector path — launch sector N+1's bridge
read while sector N drains into the ring** so sustained reads see overlapped
refill instead of fetch-then-drain-then-fetch. Constraints:

- Keep the `io_*`/`sd_buff_*` contract toward ncr5380/scsi.v **byte-identical
  in semantics** — the ring bookkeeping (`rd_hps_blk` advances on io_ack fall,
  exactly one fetch outstanding per ack today) and the per-command re-init
  (`scsi.v:406`) are validated behavior. If the pipeline changes the
  one-outstanding-ack invariant, the scsi.v side must be co-designed and
  co-benched, not assumed.
- The 74a↔sys CDC (sd_buff drain vs done) is the documented **secondary
  suspect** on this path. Mind the MiSTer mailbox-ordering law (their commit
  `7227654`): model-side publishes go LAST — data must be readable before the
  completion flag crosses domains.
- M10K budget: the second sector buffer costs ~1 M10K. Fit is at 261/308
  (85%); keep additions minimal and report the delta for the Windows build.
- Prefetch policy: read-ahead beyond the command's remaining blocks is how
  you get phantom reads at image end — bound by `rd_blk_total` semantics the
  same way the current ring does (`rd_blk_remain`/`rd_ring_space`).

## Gates on this box (all must pass before handing back)

1. `verilator/modelsim_bench/run_scsi_face_verilator.sh` — at stock AND real
   refill cadence.
2. `verilator/tb_blockdev.v` — the blockdev's own bench (build line in its
   header). Extend it to cover the pipelined overlap: two outstanding
   sectors, ack ordering, the dataslot_update multi-cycle LEVEL detail it
   already models.
3. `verilator/modelsim_bench/run_scsi_ring.sh` (tb_scsi_ring) — the
   ring/prefetch seam bench (passed pre-change; must still pass).
4. `verilator/tb_disk_swap.v` — canary that the floppy/mount protocol is
   untouched.
5. If the full sim harness is alive on this box (it was 08-14, then the
   CPU-perf port broke `verilator/sim.v` — RESUME §-6): reviving it is a
   SEPARATE mission; do not block this work on it, and do not port sim.v
   as a side effect.

## Do-NOT-touch list (hard-won)

- `src/fpga/core/pocket_sdram.v` start gating: **`t == 3'd1` is a law**
  (any-phase starts F-line-bomb on this board — `docs/F-Line_Build_Errors.md`).
  The CPU-side perf tax is real but is NOT this mission.
- `src/fpga/apf/` framework files and `core_bridge_cmd.v` — off-limits
  (CLAUDE.md).
- The hd32b asymmetric ring (`rtl/ncr5380.sv` `RING_LOG(i==0 ? 6 : 1)`) stays
  as-is during this work; whether to return both disks to 16KB (M10K refund)
  is a FOLLOW-UP decision taken only after the pipeline is HW-validated.
- One behavior-relevant variable per shipped build (house rule).

## Hand-back contract (for the Windows/Quartus box)

Commit on THIS branch: the RTL change(s), the extended benches, and a short
`docs/` note stating (a) the tb_scsi_face verdict incl. cadence sweep,
(b) which design path was taken (face fix vs pipeline vs both), (c) expected
M10K delta. The Windows box then: merges, builds (seed lottery awareness —
3-seed patience), stages the MacLCtest slot, and runs the HW gates: repeated
7.5.5 + Easy Open boots (cold AND warm restarts), a whole-disk Finder copy,
PoP2 launch, and the subjective disk-speed check vs MiSTer.

## Current state when this was written

- main (local, unpushed beyond origin where applicable): v1.2.0 released-ready
  (time fixes, `6e01d8c`+`0e1217a`) + warm-restart soft reset (`b24859b`,
  HW-validated on rst-s7 with one post-warm-restart disk crash attributed to
  Case-5 fit marginality — RESUME §-9 seed ledger).
- The restart netlist's seed-12 roll was compiling on the Windows box when
  this branch was cut; its qsf/build_id churn is deliberately NOT committed.
