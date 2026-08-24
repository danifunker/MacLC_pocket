# blockdev-pipeline results — bench verdicts + design taken (macOS box, 2026-08-24)

Companion to `blockdev_pipeline_handoff.md` (the mission statement). This is
the hand-back note for the Windows/Quartus box: what the benches said, which
design path was taken, and what to expect at fit and on hardware.

## (a) tb_scsi_face verdict — the disambiguator

**PASS at stock AND real refill cadence ⇒ the shared ncr5380 pseudo-DMA host
face is clean; the corruption class is refill STARVATION ⇒ the pipeline path
(handoff Step 2) was taken.**

Full sweep (`verilator/modelsim_bench/run_scsi_face_verilator.sh`, Verilator
5.050): gap sweep × 4 skew modes, sample-distance sweep, ring-fetch stalls at
12/60 clks, **real apf_blockdev cadence at 3,250 / 9,750 / 32,500 clks per
sector (100 µs / 300 µs / 1 ms at 32.5 MHz) × all 4 modes**, plus 8-sector
sustained soaks (the Easy Open shape) — 0 mismatches, 0 timeouts, final line
`ALL FACE CHECKS PASSED`.

Caveats that matter for interpreting this:

- This was the bench's **first successful run anywhere** (the Windows
  ModelSim SIGSEGV predates it). Three bench-side defects had to be fixed
  first, none in the DUT: a Verilator ≥5.05 `disable <taskname>` self-return
  incompatibility (later calls bind to a 0-arg block; body block renamed),
  register byte-writes driven on one lane only (a 68000/TG68K mirrors the
  byte on both lanes — ODR latches `wdata[15:8]`, ICR `wdata[7:0]`; SELECT
  never happened), and no SCSI bus reset between runs (targets' `rst` is
  ICR bit 7, not the module reset — every run after the first started
  against stale target state and cascaded).
- The stall model was upgraded from "REQ drops exactly at data_cnt%512==0"
  to a **ring-frontier model faithful to scsi.v**: the io_busy read clause
  (`rd_cur` + the `+3` look-ahead with the tail clamp), per-command
  re-init (scsi.v:406), refill running concurrently with serving. That
  moves the REQ pause to byte 509/510/512 depending on the host train grid
  — alignments the old model never produced — and makes the first REQ of
  each command wait out the first fill, as the real cold ring does.
- The verdict is RTL-level. Case 5's fit-to-fit expression on STA-met
  builds is placement marginality in these same cones; what the pipeline
  removes is how often a sustained read sits ON the starved stall/refill
  boundary, not the existence of the boundary. HW A/B remains the judge —
  that is the Windows box's half of the contract.

## (b) Design path taken — pipelined `apf_blockdev` (double-buffer + sequential speculation)

`src/fpga/core/apf_blockdev.v` only. **Zero port changes; scsi.v, ncr5380.sv
and the 74a target-command FSM are untouched** (T_IDLE gained one mux term:
`bridgeaddr = BUF_BASE | (req_buf << 9)`).

- `rdbuf` grew 128×32 → **256×32 = two 512-byte halves** (address bit [7] =
  half; bridge window widens to 1 KB, BUF_BASE stays 1KB-aligned). `wrbuf`
  and every write/PRAM/floppy flow keep the low 512 B, including the −1
  readback-lag compensation exactly as it was.
- A thin job layer (`x_busy`/`x_kind`) fronts the single-transaction 74a
  FSM: demand jobs (the old C_REQ/C_WAIT flow, now posting only when the
  engine is idle) and **speculative jobs** — after serving sector L of a
  sequential HDD read stream, the fetch of L+1 is posted into the idle
  half **at drain start**, overlapping the drain, scsi.v's ring serve, and
  the Mac's own consumption. One transfer in flight ever; nothing aborts.
- A demand read that matches the speculative sector serves with **no OS
  round trip** (envelope toward scsi.v identical in shape — ack rise,
  256 sd_buff writes, ack fall — just short). A demand arriving while its
  own speculative fetch is in flight (the common starved case) waits in
  the one new state `C_HITWAIT` (level-wait on `!x_busy`; edge-waiting
  deadlocked when completion landed on the pick cycle — see the comment).
- **Speculation policy** (the conservative side of every trade):
  sequential HDD read streams only (`lba == last_lba + 1`, same slot; a
  hit keeps the chain), bounded by the slot's image size in blocks
  (phantom reads past image end would error/226 ms-stall the shared
  sequencer), never for the CD (working, HW-validated, left alone), never
  for writes. Random reads never wait out a wasted speculative transfer.
- **Invalidation** is one rule plus two edges: every demand post through
  C_REQ clears `pf_valid` (any demand transfer owns the buffers — this is
  also what makes write-then-read-same-lba safe); a mount pulse clears
  valid + the stream tracker and sets `pf_mnt_kill` so an in-flight
  speculative completion is discarded.
- **CDC**: unchanged structure — the OS writes rdbuf before done,
  done_tgl crosses (3-stage sync) before `pf_valid` rises, and `pf_valid`
  rises before any hit-drain reads. The new concurrency (bridge writing
  one half while clk_sys drains the other) is disjoint-address dual-clock
  M10K — no same-address mixed-port case exists.

Expected behavior change per sector on a sequential stream: the OS round
trip for N+1 starts at N's drain start instead of after N's drain + ack
fall + scsi re-request, i.e. the ~24 µs drain, the turnaround, and all of
the guest's own consume/think time now overlap the OS latency. In
tb_blockdev's model (108 µs host latency, ~60 µs guest think): demand path
133 µs, pipelined hits **48 µs**. If HW shows the OS round trip still
dominating after this, the next lever is multi-sector `target_dataslot_length`
amortization — deliberately NOT taken now (one behavior-relevant variable
per shipped build; it also inflates random-read latency).

## (c) Expected fit deltas

- **M10K: +0.** rdbuf was 4 Kbit forced into an M10K (`ramstyle`); 8 Kbit
  still fits one M10K (10 Kbit). wrbuf unchanged. Fit stays 261/308.
- ALMs: small — one 5-bit state added, ~15 new registers (speculation
  bookkeeping, per-slot block counts), a handful of 32-bit comparators in
  the pick logic. Well under +200 ALMs on a 14.2k-ALM fit.
- No new clocks, no constraint changes, nothing near pocket_sdram or the
  framework.

## Gate results on this box (all PASS, 2026-08-24)

| gate | result |
|---|---|
| `run_scsi_face_verilator.sh` (stock + real cadence, in one sweep) | `ALL FACE CHECKS PASSED` |
| `verilator/tb_blockdev.v` (rewritten, see below) | `ALL BLOCKDEV CHECKS PASSED` (11 checks) |
| `run_scsi_ring_verilator.sh` (new runner, same tb_scsi_ring) | `ALL RING CHECKS PASSED` (84,468 checks) |
| `verilator/tb_disk_swap.v` (mount-protocol canary) | `tb_disk_swap: PASS` |
| `scripts/check_hierarchy.py rtl src/fpga` | no dangling module references |

Bench notes:

- **tb_blockdev was rewritten.** Its content oracle predated buildAA
  (2026-08-12: the sd_buff face is little-endian; HW-validated) and had
  never been updated — the old expectation failed against known-good
  shipping RTL. The new bench models the host with real latency
  (~108 µs/transfer), per-LBA + per-generation content (stale-buffer
  serving cannot pass), and covers: cold demand read; a 5-sector
  sequential stream (exactly one host transfer per sector, hits ≪ demand
  latency, an explicit **overlap witness** — a host transfer live during
  an ack envelope, structurally impossible in the serialized design);
  seek reads not speculating; write round trip content-checked including
  the −1 readback lag; write invalidation; media-change invalidation both
  delivered and in-flight; the floppy bulk copy through the same
  sequencer with a SCSI read interleaved mid-copy; the mailbox/CDC law as
  a continuous monitor (no sd_buff word from a half the host is still
  writing); spurious-ack watch.
- `run_scsi_ring_verilator.sh` is new: the existing `run_scsi_ring.sh`
  hardcodes the Windows ModelSim path; this is the same fresh-extraction
  bench on this box's Verilator, mirroring `run_scsi_face_verilator.sh`.

## For the Windows box (unchanged from the handoff, plus specifics)

Merge, build (3-seed patience), then HW gates: repeated 7.5.5 + Easy Open
boots (cold AND warm restarts), whole-disk Finder copy, PoP2 launch,
disk-speed feel vs MiSTer. Watch specifically for:

- Boot-time feel on 7.5.5: the extension parade is the sequential-read
  shape the speculation targets.
- The BDLB witness (`dbg_bdlb`) now counts hit-serves in deliveries but
  latches the last DEMAND lba on the ack rise (hit serves included) —
  decode unchanged.
- If a seed still shows the Case-5 fingerprint at the same rate, the
  starvation-margin theory takes a hit and the remaining suspects are the
  fit-marginality of the ring-serve cones themselves (the anchors) — do
  not stack a second variable into the same build to find out.
