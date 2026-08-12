# RESUME — MacLC for Analogue Pocket, session handoff

---

## ★★ 2026-08-11 SESSION — READ THIS FIRST ★★

**The single most productive technique this session: mechanically diff every
module, port, RTL file and SDC line against `../MacLC_MiSTer` @ `5a75f9b`.**
Five real defects fell out in minutes, after hours of hypothesis-driven
probing had produced only refuted theories. The MiSTer core boots 100% of the
time; where the two differ, WE are wrong until proven otherwise. Do this
**first**, not last.

The sweep that works (`docs/mister_reference/MacLC.sv.reference` is the spec):

```bash
# every rtl/ file, comments+whitespace stripped
diff <(sed 's://.*::' rtl/X.sv) <(git -C ../MacLC_MiSTer show 5a75f9b:rtl/X.sv | sed 's://.*::')
# port-by-port for every module instantiated in BOTH tops (finds dropped
# connections and ports tied to constants here but driven upstream)
```

### Found and fixed (all were "dropped at import")

1. **`vpa_periph_read` / `periph_din_reg` / `cpu_din_muxed`** — absent entirely.
   This is upstream's fix for what its own SDC comment calls **"the dice-roll
   boot"**: the peripheral read mux is the deepest cone in the design (SCSI CSR
   bit6 `scsi_bsy`: scsi.v phase → `|target_bsy` → CSR → long route → 7-way
   `cpuDataOut` mux → CPU din), so bit6 read wrong while shallow bit1
   `scsi_sel` read right, **depending on placement**. Register the peripheral
   read one `clk_sys` stage and feed the registered value on VPA cycles.
   Ref `MacLC.sv.reference:985-999`.
2. **No 2FF sync on `v8_vblank` / `v8_hblank`** (`clk_pix` → `clk_sys`). They
   drove `pseudovia.vblank_irq` — an **interrupt** — and the VIA blanking
   inputs raw. Upstream syncs and consumes only `_s`. Ref `:632-639`, `:1181`.
3. **No sync on the video reset.** `maclc_v8_video` is clocked by `clk_pix`;
   we fed it raw `~n_reset` from `clk_sys`. Upstream uses `vidrst_s`. Ref
   `:623-629`, `:1663`.
4. **`selectUnmapped` never connected to `dataController_top`** (the wire
   existed and was driven; only the connection was missing), so the open-bus
   `16'hFFFF` case at `dataController_top.sv:330` could never fire and the
   ROM's RAM-probe read stale bus data. Ref `:1885`.
5. **`core_constraints.sdc` had NONE of MiSTer's timing constraints** — no
   TG68 kernel multicycle (upstream: *"REQUIRED for reliable timing closure"*,
   without it *"closing timing by luck"*), no `periph_din_reg` multicycle, no
   synchronizer false paths. Porting RTL fixes without their SDC is the
   "STA passes but HW fails" trap upstream warns about.

### The instrument that made hardware debugging possible

`USE_BOOT_ISSP` in `ap_core.qsf` (**must be OFF for release fits**) builds a
JTAG In-System probe deck; read it with `bash scripts/read_boot_probes.sh`
(full decode), `scripts/boot_watch.tcl` (is anything moving?) and
`scripts/cpu_probe.tcl` (CPU address + bus state).

Probes: `BOOT` (dbg_boot_bus), `ROMC`/`FLPC` (words retired into SDRAM),
`BRGC` (words OS→loader), `POPC` (words loader→machine), `DLST` (arbitration),
`CPUC` (bus-cycle counter), `CPUA` (address + AS/DTACK/RW/BERR/reset/overlay).

**Use ISSP, not SignalTap, for boot questions.** `clk_sys` is 32.5 MHz so 1024
SignalTap samples span 31 µs against a ~137 ms boot. ISSP is polled from Tcl
over seconds, has no depth limit, and costs ~500 ALMs. It also survives being
read repeatedly while the user power-cycles.

### What the probes settled (so nobody re-litigates it)

* **The ROM download path is CLEAN.** `BRGC = POPC = ROMC = 262144` for one
  512 KB load (524288 after two — the counters are free-running, read the
  DELTA). Not the loader, not the FIFO, not the bridge, not the OS.
* **SDRAM is fine.** The ROM is written to SDRAM *and executed from it* for
  hundreds of millions of correct fetches. A gross data fault is excluded.
* `pocket_sdram.v` **is** faithful to `rtl/sdram.v` — verified by
  comments-stripped diff. Only the 4 documented changes.
* **`CPUC` distinguishes halted from spinning.** A frozen `BOOT` bus cannot;
  the first capture was ambiguous for exactly this reason.
* A hang was captured at `addr=0xF13D24, AS=0, DTACK=1, RW=0, BERR=0` —
  decoded via `addrDecoder.v:169` as the **SCSI pseudo-DMA window**
  ($F12000-$F13FFF). DREQ never came and the 250 ms `sdma_berr` timeout
  ([mac_lc_pocket.sv:494](../src/fpga/core/mac_lc_pocket.sv)) did **not** fire
  — still unexplained, worth a probe on `sdma_stall_ctr`/`scsiDREQ`.
* POST failure lands the ROM in its **serial diagnostic loop** — alternating
  ROM `0xA49xxx` ↔ SCC `0xF04002`. If you see that pattern, POST failed; the
  code is in the SCC byte stream.

### Refuted this session (do not re-run these)

* CB1 coalescing / `ext_fall_edge_pending` — **zero functional fanout**; see §6.
* Loader FIFO overflow / missing backpressure — `BRGC == POPC` always.
  (`loader_busy` **is** genuinely dangling in `core_top.sv`, but it is not
  the boot bug.)
* SDRAM write-margin corruption — but the phase WAS badly mis-tuned; see below.

### SDRAM phase, re-measured

`ap_core.sta.summary` reports per-CLOCK-DOMAIN worsts and **hides the memory
interface**. Query the paths directly:

```tcl
get_timing_paths -setup -from [get_ports {dram_dq[*]}]   ;# reads
get_timing_paths -setup -to   [get_ports {dram_*}]       ;# writes
```

At the old 90° the write side had **+0.107 ns** while reads had +9.21 ns —
wildly lopsided, because the arithmetic that chose 90° counted only the SDC
delays and ignored FPGA clock-to-out. Now **135° (5769 ps)**: write +2.03,
read +9.93. Re-measure both directions after any PLL/pin/controller change.

### Environment (this Windows box)

Quartus **18.1.0 build 625** at `C:\intelFPGA_lite\18.1` — the *same* build
that made the WSL fits, so no IP-upgrade risk. Python 3.12.10 at
`%LOCALAPPDATA%\Programs\Python\Python312` (**prefix PATH explicitly**;
`command -v python3` hits the Microsoft Store stub — `scripts/package.sh` now
probes candidates by running them). USB-Blaster works; the earlier Code 39 was
**HVCI/Memory Integrity** rejecting the 2018 driver (certs expired 2015/2016),
fixed by updating the driver. No WSL distro, so **no Verilator**.
SD card is `D:\`; core goes to `D:\Cores\danifunker.MacLC\`.

---

**Updated 2026-08-10, end of session.** Paste this into a new Claude Code
session, or point it here. Deliberately long: it records what was learned the
hard way so none of it has to be rediscovered.

`docs/PORT_STATUS.md` is **partly stale** (written mid-session, before
`apf_blockdev` and the audio fix). Prefer this file where they disagree.

---

## 1. Where the project actually is

The core loads, boots, plays the **startup chime**, reaches the **"?" floppy
screen** with a working mouse cursor, and the SCSI block device has been
observed delivering a sector end to end.

| subsystem | state |
|---|---|
| Video | works (512×384) |
| SDRAM | works, properly constrained, timing measured |
| ROM load | works, but see the cold-boot race in §4 |
| **Audio** | **WORKS** — fixed this session, see §4 |
| Input | works (SELECT toggles mouse/keyboard) |
| **Boot reliability** | **RANDOM.** Sometimes black screen, sometimes chimes of death, sometimes a clean boot. Happens at BOTH 2 MB and 10 MB. **This is the #1 problem.** |
| SCSI | block device reaches stage 5 (sector delivered) but **no boot from disk** |
| Floppy | crashes the core; testing paused by the user |

Latest fit: **11,027 / 18,480 ALMs (60%)**, **251 / 308 M10K (81%)**, zero
negative slack all corners, SDRAM read setup ≈ +5.9 ns / hold ≈ +0.56 ns.

---

## 2. Environment on the new machine

### Do this: build natively on Windows

This session built in **WSL** only because Quartus lived there. On the new
machine install **Quartus Prime Lite 18.1 + Update 1 for Windows** and build
there — then Quartus, the USB-Blaster and SignalTap are all in one place and
the JTAG problem disappears. Keep WSL/Linux **only for Verilator**.

Version must be 18.1.x. A newer Quartus offers to upgrade `mf_pllbase`, and
regenerating it discards the retargeted clock plan.

### winget

```
winget install --id Git.Git -e
winget install --id Python.Python.3.12 -e
winget install --id 7zip.7zip -e
winget install --id Microsoft.VisualStudioCode -e
winget install --id Microsoft.WSL -e
```

`pip install pillow numpy`. Quartus is **not** on winget — download from
Intel's older-versions page, and take the **Cyclone V device support** pack.
The USB-Blaster driver ships inside Quartus but installs manually via Device
Manager → `<quartus>\drivers\usb-blaster`.

In WSL, for the testbenches:
`sudo apt install -y verilator build-essential pkg-config libsdl2-dev libgl1-mesa-dev python3`
(Verilator **5.x** — the Makefile uses `--timing`.)

### Build

```
cd src/fpga
quartus_map ap_core && quartus_fit ap_core && quartus_asm ap_core && quartus_sta ap_core
cd ../.. && bash scripts/package.sh && cp info.txt dist/Cores/danifunker.MacLC/
```

`package.sh` now works from Git Bash or WSL (picks `python`/`python3`).
`dist/Cores/` is **gitignored** — the bitstream does not travel via git.

**★ Verify the build really succeeded.** A wrapper ending in `echo` returns 0
even when Quartus failed, and a stale `.rbf` gets packaged silently — this
happened. Run `quartus_map` as its own step, and check `ap_core.fit.summary`'s
timestamp is fresh before packaging.

### First build on the new Quartus — three checks

```
git diff --stat src/fpga/core/mf_pllbase/      # MUST be empty (IP not regenerated)
grep -A1 "Phase Shift" src/fpga/output_files/ap_core.fit.rpt | grep degrees
grep -E "^(Type|Slack)" src/fpga/output_files/ap_core.sta.summary | paste - - | grep "general\[0\]"
```

Expect: no IP diff; outclk_1 at **90 degrees**; SDRAM setup **and** hold both
positive. All measurements in this file came from 18.1.0/625, and placement
will differ on 18.1.1 — treat the first build as a new baseline.

### Offline checks + testbenches

```
python scripts/check_json.py ; bash scripts/lint.sh ; python scripts/check_hierarchy.py rtl src/fpga
```

15 benches in `verilator/`. **Use them.** The biggest process failure of the
session was not doing so — several hardware round trips went on bugs a bench
caught in seconds once written.

```
cd verilator
verilator --binary --timing -Mdir obj_tb_blockdev -o Vtb_blockdev \
  tb_blockdev.v ../src/fpga/core/apf_blockdev.v --top-module tb_blockdev \
  -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-PINMISSING \
  -Wno-DECLFILENAME -Wno-MULTIDRIVEN -Wno-INITIALDLY -Wno-BLKANDNBLK -Wno-CASEINCOMPLETE
./obj_tb_blockdev/Vtb_blockdev
```

---

## 3. Reference cores (siblings — copy these too, git won't bring them)

| path | good for |
|---|---|
| `../MacLC_MiSTer` @ `5a75f9b` | the origin. `git -C ../MacLC_MiSTer show 5a75f9b:sys/hps_io.sv` = the authoritative `sd_*` contract. `MacLC.qsf` = the macro list |
| `../openfpga-PCXT` | **best APF reference.** `src/fpga/core/softcpu_fdd_bridge.sv` documents the target-dataslot protocol and byte order |
| `../Pocket-Amiga` | SDRAM SDC constraints, `deferload`, `i2s.v`, the `0xF0` register window |
| `../core-template` | stock openFPGA template |
| `../computer-msx` | leaves `sd_*` unconnected — not useful for block devices |

---

## 4. Bugs found and fixed (do not regress these)

### Audio — SOLVED. One missing build macro.

`rtl/asc.sv:44` gates the FIFO and sample-output path behind
`` `ifdef USE_ASC_AUDIO ``. Undefined, it compiles a stub where **`sample_l` and
`sample_r` are hardwired to `16'sd0`** — silent by construction.

MiSTer's `MacLC.qsf:78` sets it. The Pocket port dropped it. Now in
`src/fpga/ap_core.qsf`.

**Why it hid for so long:** `verilator/Makefile:8` *does* define it
(`+define+USE_ASC_AUDIO=1`), so simulation had working audio while hardware
never could. Sim-vs-FPGA divergence arriving through a build macro rather than
RTL. Lesson: **when hardware and sim disagree about whether a subsystem exists
at all, compare the build configurations before reading RTL.** Two earlier
audio diagnoses (floating `selectASC`; I2S framing) were both wrong because
they went to the RTL first.

Verify it is compiled in: `asc:asc_inst|cd_sdp:fifo_a_ram` appears in
`ap_core.map.rpt`. The stub has no FIFO.

### SDRAM — the big one

**The `dram_*` pins had NO timing constraints.** The APF template ships
`core_constraints.sdc` as a stub; MiSTer's equivalent lived in `sys/sys_top.sdc`
and was never ported. So STA never analysed the memory interface — "0 negative
slack" was *silence, not health* — and every recompile reshuffled placement into
a different marginal result. **Corruption appearing and vanishing across
rebuilds that touch nothing in the memory path is the fingerprint.**

Now in `core_constraints.sdc`:
1. `set_input_delay`/`set_output_delay` on `dram_dq` + command group.
2. `general[0]` (clk_mem) and `general[1]` (dram_clk) in **one** clock group —
   they were mutually asynchronous, which voids the I/O constraints.
3. **`-add_delay`** on the second of each min/max pair — without it Quartus
   *replaces* rather than adds. Pocket-Amiga omits this.
4. **`set_multicycle_path ... -hold -end 1`** with the `-setup -end 2`. Setup
   alone moved the same paths from −5.1 ns setup to −6.6 ns *hold*.
5. `FAST_INPUT_REGISTER`/`FAST_OUTPUT_REGISTER` on `dram_*` in `ap_core.qsf`.

**`dram_clk` phase is 90° (`phase_shift1 = 3846 ps`), MEASURED not guessed.**
180° was tried by analogy with MiSTer's `altddio_out` and was worse. At 65 MHz:
read budget `T − φ − tAC` = 5.63 ns at 90°, 1.79 ns at 180°; command budget
`φ − 2.0` = 1.85 / 5.69. Every failing path was `dram_dq[*] →
pocket_sdram|dout[*]` (reads). Re-check that slack after any PLL, controller or
pin change.

### ROM loader

`apf_bridge_loader.v` reloaded `rd_data` every clock while `dio_wr` stays
asserted until the SDRAM arbiter grants a slot — at realistic bridge rates it
delivered **0 of 256 words**. Now loads only when `rptr_sys` advances.

`ADDR_MASK` `0xE000_0000` matched only `0x0–0x1FFFFFFF`, excluding the floppy
window at `0x20000000`. Now `0xC000_0000`.

**Cold-boot race (fixed late in the session):** both `apf_bridge_loader` and
`apf_blockdev` drive the machine's single download port, and **both received the
same `dio_ack`** — each consumed completions meant for the other. With the
floppy now a `deferload` slot, its bulk copy starts on `dataslot_update` while
the ROM is still streaming, corrupting the ROM at cold boot. Symptom: "black
screen, force-reload the ROM twice and it comes good." Fixed by routing
`dio_ack` exclusively (`ldr_dio_ack`/`bd_dio_ack`) and gating the floppy copy on
`flp_allow` (= ROM download finished). **Effectiveness on hardware not yet
confirmed.**

### APF descriptor

* **`shortname` must match the core half of `Cores/<author>.<shortname>` and
  contain no spaces.** `"Macintosh LC"` vs directory `danifunker.MacLC` was
  almost certainly the original `Load error in 'core': General error`. A
  rejected descriptor also gives a **blank About screen** — one fault, not two.
* **Interact registers must be at `0xF0000000`, not `0xF1000000`.** At `0xF1`
  *no interact write reached the core at all*. Mechanism unknown; empirical.
* Writes are **read-modify-write**; mask bit 1 = preserve, 0 = writable.
* `"messages": []` **is legitimate** — core-template ships it.
* `.rbf_r` = bit-REVERSED. Known-good header: 128 × `0xFF` then
  `56 56 56 56 6c 2f`.

### APF signal semantics

* **`dataslot_update` is a multi-cycle LEVEL.** `core_bridge_cmd.v` raises it in
  the `0x008A` handler and clears it only at `ST_IDLE`. Must be **rising-edge
  detected** — testing the level toggled a CDC flag many times at 74.25 MHz and
  an even count nets to no edge, so `img_mounted` never pulsed and neither disks
  nor floppy were ever seen.
* **`target_dataslot_read`/`_write` is a LEVEL held until `_ack`**;
  **`_done` is a RISING EDGE.** Source:
  `../openfpga-PCXT/src/fpga/core/softcpu_fdd_bridge.sv:233-249`. Pulsing the
  request for one cycle meant the OS never saw it — every SCSI read stalled with
  `sd_ack` stuck high, which on hardware read as "the disk is never found and
  everything runs slowly."
* **Byte order:** dataslot byte 0 arrives in `bridge_wr_data[31:24]`, so the
  first 16-bit word is `[31:16]` — correct for the big-endian 68020.

### Reset / input

* **`mac_lc_pocket`'s reset block is gated by `if (clk8_en_p)`** — high one
  `clk_sys` cycle in four, so single-cycle pulses were **missed 75% of the
  time**. All three interact actions are now stretched to 16-cycle levels.
* `reset_n` (APF host reset) was wired to nothing but `status_running`; now in
  the machine's reset.
* Mouse Y was inverted — `adb_device` uses the PS/2 convention, **positive dy is
  UP**.
* `input.json` labelled START as the mode toggle; the code uses **SELECT**.

### Toolchain traps

* **Quartus rejects a reg array driven from two `always` blocks** (Error 10028)
  and no M10K takes two writes per cycle. The first `apf_blockdev` did both and
  **Verilator lint accepted it silently.**
* Verilator treats a comment whose first token is `verilator` as a directive.

---

## 5. Design map

| file | role |
|---|---|
| `src/fpga/core/apf_blockdev.v` | **new.** APF slots → hps_io `sd_*`. On-demand 512-byte sectors for SCSI; core-paced bulk copy for floppy. Timeouts (~226 ms). Exports `dbg_stage`. |
| `src/fpga/core/i2s.v` | **new**, ported from Pocket-Amiga (adds the missing CDC sync). Not the cause of the silence, but a genuine improvement. |
| `src/fpga/core/core_constraints.sdc` | **rewritten** — SDRAM timing |
| `verilator/tb_blockdev.v` | **new**, 15th bench; models the real host protocol |
| `scripts/check_json.py` | + undocumented-key and shortname/dir checks |
| `scripts/package.sh` | portable `python`/`python3` |

**Menu (interact.json):** Memory (persist, 2 MB default), Reset & Apply,
Reset PRAM, Interrupt (NMI), Video Test Pattern, Debug: Disk stage.
**Data slots:** 200 ROM (streamed), 210 Floppy, 310/311 Hard Disk 1/2 — the last
three all `deferload`. Slot 0/1 map to **SCSI ID 0 and 1**
(`scsi #(.ID(i[2:0]))` in `ncr5380.sv:693`), which is correct for a Mac boot
disk.

---

## 6. THE #1 PROBLEM — random boot. This is the JTAG job.

Boot succeeds **sometimes**. Observed: black screen; chimes of death; clean
boot — and it varies run to run **at both 2 MB and 10 MB**, so memory config is
NOT the determinant. (An earlier inference that 10 MB was broken was wrong; the
chime was probabilistic.) The user's read — "a startup timing thing" — fits.

### ~~The suspect, predicted in CLAUDE.md before bring-up~~ — REFUTED 2026-08-10

**Do not spend a capture on this. The CB1-coalescing theory is dead.** It was
refuted by reading, before any bitstream was built, exactly as §9 prescribes.

The theory was: `ext_fall_edge_pending` is a single-bit latch cleared only on
the VIA's `falling` (E-clock) phase, so at most one CB1 edge is consumed per E
period (~783 kHz); the real HC05 toggles CB1 faster, edges coalesce, SR bytes
corrupt, the Egret handshake never completes, `memoryOverlayOn` never clears —
and whether it coalesces depends on power-up phase, hence random.

**Why it cannot be the cause:** in this `via6522.sv`, `ext_fall_edge_pending`
has **no functional fanout whatsoever**. Grep the entire repo — it is written
at line 797, cleared at 819/827, and read at exactly one place: line 976,
`assign sr_dbg_fall_pending = ext_fall_edge_pending`, a debug port. Upstream
had already fixed this. In `ext_clock_mode` (ACR shift modes 3 and 7 — what the
Egret uses, `via6522.sv:129-131`) **both** the data path (865-879) and the bit
counter (941-953) advance on the per-clock edge pulses `shift_tick_r` /
`shift_tick_f`, decoupled from E. The comments at 859-864 and 936-940 name this
exact coalescing bug as the thing they fix. The sibling flag `ext_edge_pending`
survives only through `shift_pulse`, and `shift_pulse` is read solely inside
`!ext_clock_mode` branches (806, 927).

`rtl/via6522.sv` is byte-identical to MiSTer `5a75f9b` (verified by diff), so
the fork inherited the fix, not the bug.

**The trap this leaves behind:** `dbg_boot_bus` bits 12 and 15 (`fall_pending`,
`cb1`) are still wired, and on hardware they *will* show edges coalescing —
because the flag genuinely does coalesce, it just drives nothing. A capture
would have looked like confirmation. The rest of the bundle
(`memoryOverlayOn`, `handshake_done`, `bit_cnt`, `shift_reg`) is still the
right instrument for an Egret question; only the pending-flag reading was wrong.

**Also wrong in the old note:** "nothing reproduces it in simulation because the
behavioural Egret drives CB1 slowly." The behavioural Egret is not compiled at
all any more (CLAUDE.md: the real HC05 is unconditional since 2026-08-09). The
actual reason boot-timing faults are FPGA-only is that **simulation does not
run hardware startup timing**: `dataController_top.sv:197/209` sets the 68k
minimum-reset counter to `20'h0200` under `SIMULATION` versus `20'hFFFFF`
(1,048,575 counts of `clk8_en_p` = **129 ms**) on FPGA, and
`egret_wrapper.sv:232` sets `ONESEC_PERIOD` to `8192` (~2 ms) versus `4000000`
(~1 s). Those two shortcuts are not even the same ratio — 2048x against 488x —
so the sim runs a startup with the Egret's one-second timer and the CPU reset
release in a ~4.2x different relationship to each other than hardware does.
Any startup-ordering bug is structurally invisible to the current sim.

### JTAG status — PROVEN WORKING on the old machine

`jtagconfig` saw the cable and read the chain:

```
1) USB-Blaster [USB-0]
  02B050DD   5CE(BA4|FA4)      <- the Pocket's Cyclone V 5CEBA4
```

An initial "chain broken" was transient; a rescan succeeded. So the physical
link and the Windows driver are fine. The only blocker was version — the old
machine had Quartus **17.0** on Windows and built with **18.1.0** in WSL, and
SignalTap needs the same version that compiled the `.sof`. On the new machine
with 18.1.1 on Windows, that disappears.

### Already wired and waiting

`mac_lc_pocket.sv` has a `(* preserve *)` bus the Fitter cannot strip:

```
core_top:ic|mac_lc_pocket:machine|dbg_boot_bus[31:0]
```

| bits | signal |
|---|---|
| 27 | `memoryOverlayOn` ← **the documented failure mode** |
| 26, 25 | `n_reset`, `rom_loaded` |
| 19 | `egret_dbg_handshake_done` ← did the handshake ever complete? |
| 24–17 | Egret: cpu_reset_out, reset_680x0, byteack, tip, treq, port_test_done, running |
| 16–11 | `cb2`, **`cb1` (15)**, `dir`, `active`, **`fall_pending` (12)**, `edge_pending` |
| 10:3 | `via_sr_dbg_shift_reg` |
| 2:0 | `via_sr_dbg_bit_cnt` |

These `dataController_top` outputs existed since import and were dangling.

### ★ Sampling — read before spending a capture

`clk_sys` is 32.5 MHz, so **1024 samples spans only ~31 µs** while the Egret
handshake runs for *milliseconds*. A naive capture closes before anything
happens and looks fine.

* **Storage qualifier**: store only when `dbg_sr_active`, or on a change of
  `dbg_sr_cb1`.
* **Segmented buffer** (e.g. 8 × 128) so one power-up yields several snapshots —
  the user explicitly wants multiple samples across the different failure states.
* First run: trigger on `n_reset` rising, qualify on CB1 change.

**What coalescing looks like:** several `cb1` transitions between consecutive
`fall_pending` clears; `bit_cnt` advancing fewer times than CB1 toggled;
`shift_reg` accumulating a wrong byte. If `handshake_done` never rises and
`memoryOverlayOn` stays high, the prediction is confirmed.

**Caution:** SignalTap changes placement, and SDRAM timing here is
placement-sensitive. Re-check `dram_dq → dout` slack on the capture build. If
the fault *disappears* with probes in, that is information, not luck.

**Preferred workflow:** export captures to CSV (good boot / grey hang / death
chimes) and have the assistant diff them offline.

---

## 7. SCSI — block device proven, but no boot from disk

`Debug: Disk stage` reached **5 (sector delivered)** on hardware. That means the
OS *does* service `target_dataslot_read` at `0x40000000`, the level-until-ack
protocol is right, and 256 words reached the core correctly. **The block device
works end to end.** The Mac still does not boot from the disk.

### ⚠ Two flaws in that readout — fix before trusting it further

1. **It is sticky.** Stage 5 means "delivered at least once" — it cannot tell one
   lucky sector from thousands.
2. **5 masks 6.** The priority chain is `delivered ? 5 : timed_out ? 6 : …`, so
   once 5 latches, later timeouts are invisible. "First sector fine, everything
   after times out" looks identical to success.

**Next step: replace it with a sector-count bucket** (0 / 1 / 2–9 / 10–99 /
100–999 / 1000+) plus an unmasked timeout flag. One build, and it separates the
competing stories cleanly.

### Leading hypothesis: per-sector latency

Every 512-byte read is a full OS round trip (request → ack → SD read → 128
bridge writes → done). At even a few ms, a Mac boot reading thousands of sectors
either takes minutes or trips the driver's own timeouts. Reaching stage 5 and
never booting is that shape. Amiga avoids it because its MPU firmware batches.

If confirmed, the fix is tractable: **fetch several KB per target command**
into a larger buffer and serve many sectors from it. `target_dataslot_length` is
32 bits — nothing forces 512.

---

## 8. Other open items

* **Floppy crashes the core.** Both 800K GCR and 1.44 MB MFM, identically; the
  transfer completes then the machine is dead. Testing paused by the user.
  Reset-on-mount was tried as a workaround and **removed** (it cost hot-insert,
  which the MiSTer CSTIN/DiskChg logic needs). `rtl/floppy.v` fetches a word at a
  time paced by the GCR/MFM encoder, so it **cannot** be served on demand — the
  image must live in SDRAM.
* **Green/blue/grey full-screen colours** are the Ariel palette in an
  indeterminate state, not an overlay. Consequently the **Video Test Pattern is
  only a valid witness while the machine is halted** — it is a palette *index*,
  so a flat programmed palette hides it.
* **Reset PRAM** now genuinely zeroes the Egret's `pram[]`; effect unproven.
* `docs/PORT_STATUS.md` needs a refresh.
* `verilator/sim.v` has not been rebuilt since the machine top gained
  `pram_reset` / `test_pattern` ports.

---

## 9. Working agreement for the next session

The user pushed back — correctly — that too much of this session was guesswork.

**What worked:**
1. **Reference cores for contracts.** Every wrong APF convention was fixed by
   reading `../openfpga-PCXT` or `../Pocket-Amiga`. Do that *first*.
2. **Testbenches for our own logic.** `tb_blockdev` reproduced a hardware bug
   offline and proved the fix in minutes.
3. **Instruments over speculation.** `dbg_stage`, `dbg_boot_bus`, and the chime
   itself are all channels for asking the hardware a question.
4. **Comparing build configurations**, not just RTL — that is what finally found
   the audio bug after two wrong RTL theories.

**What did not work:** reading RTL, forming a plausible theory, and shipping a
6-minute build for the user to flash. **Do not ship a speculative bitstream when
a bench, a reference core, or a build-config diff can answer the question.**
