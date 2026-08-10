# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Macintosh LC emulation core **for the Analogue Pocket (openFPGA)**.
It emulates a 68020 and the LC's V8 ASIC, Egret, SWIM, SCSI and ADB.

It is a **fork of the MiSTer core** at `../MacLC_MiSTer`, imported as a flat
snapshot (no upstream history) from commit `5a75f9b` on branch
`ariel-ramdac-m10k`. That core is in turn based on MacPlus by Sorgelig, which
originated from Plus Too. To diff any file against upstream:

```bash
git -C ../MacLC_MiSTer show 5a75f9b:rtl/swim.v
```

**Read [docs/PORT_STATUS.md](docs/PORT_STATUS.md) first.** It records what the
port has and has not done, and why. As of 2026-08-09 the project **does not
compile** — `src/fpga/core/mac_lc_pocket.sv` (the machine top) is not written.

### What this fork cut, and why

The Pocket's Cyclone V 5CEBA4F23C8 has 18,480 ALMs and **308 M10K blocks**
against the DE10-Nano's 41,910 and 553. The last MiSTer fit used 28,459 ALMs
and 502 M10K; `emu` alone was ~20,900 ALMs = 113% of the Pocket. So:

- **Video is 512×384, 8bpp max.** No 16bpp, no 640×480. The 16bpp framebuffer
  was 384 M10K blocks — more than the Pocket has in total.
- **One floppy drive.** The external drive is gone.
- **No CD-ROM and no BlueSCSI Toolbox.** `cdrom_target` was 7,762 ALUTs.

Do not re-add any of these without redoing the budget arithmetic in
`docs/PORT_STATUS.md`.

## Build Commands

### FPGA Build (Quartus)
openFPGA cores build with **Quartus 17.1** (not the 17.0.2 the MiSTer core
used), targeting `5CEBA4F23C8`.

- Project: `src/fpga/ap_core.qpf`
- Top-level entity: `apf_top` (in `src/fpga/apf/`), which instantiates
  `core_top`
- Output: `src/fpga/output_files/ap_core.rbf` → rename to `bitstream.rbf_r`
  and place in `dist/Cores/<author>.<core>/`

`BUILD.md` still describes the MiSTer flow and does not apply here.

### Structural check (no toolchain needed)
```bash
python scripts/check_hierarchy.py rtl src/fpga
```
Regex pass confirming every instantiated module exists. It is a heuristic, not
a parser — it does not check port widths, connectivity, or syntax. It is the
only automated check that runs without Quartus or Verilator.

### Verilator Simulation

> **BROKEN in this fork as of 2026-08-09.** `verilator/sim.v` still wires the
> `dataController_top` ports the CD/Toolbox and second-floppy cuts removed
> (`cd_snd_*`, `dbg_cda*`, `cdtb_*`, `cd_io_*`, `tb_lba`, `dskReadAddrExt` —
> 11 references). It will not build until sim.v is updated.
>
> Fixing it is high value: this harness is the only functional verification
> the project has (boot check, screenshot oracle, `tb_disk_swap`, the GCR/MFM
> benches, MAME comparison). The Pocket has no HPS, so there is no on-target
> introspection to fall back on. Everything below describes the harness as it
> worked on MiSTer and should work again after the port.

```bash
cd verilator
make        # Build simulator
make clean  # Clean build artifacts
./obj_dir/Vemu  # Run interactive simulator (requires SDL2, OpenGL)
```

#### Simulator Command Line Options
```bash
./obj_dir/Vemu --help                    # Show all options
./obj_dir/Vemu --screenshot 360          # Take screenshot at frame 360
./obj_dir/Vemu --stop-at-frame 400       # Exit after frame 400
./obj_dir/Vemu --screenshot 360 --stop-at-frame 361  # screenshot
```

Key options:
- `--screenshot <frame>` - Save PNG screenshot at specified frame number
- `--stop-at-frame <frame>` - Exit simulation after reaching frame count
- `--trace` - Enable FST waveform tracing (outputs to `trace.fst`)

Note: Boot takes approximately 360 frames to reach the Mac desktop.
Note: No hard drive is configured in the simulator, so the desktop won't fully load.

#### Boot Verification
```bash
cd verilator
./check_boot.sh              # Analyze existing cpu_trace.log
./check_boot.sh --run        # Run 30 frames + analyze
./check_boot.sh --run 100    # Run N frames + analyze
```
Exit codes: 0=PASS, 1=FAIL, 2=missing log. Suitable for pre-commit hooks.

#### Simulation Logs
- **CPU trace log:** `verilator/cpu_trace.log` - Contains 68K CPU instruction trace
- **Console output (stderr):** Contains HC05 (Egret) traces, VIA/peripheral debug messages
- **Important:** Do NOT re-run the simulator multiple times when diagnosing. Run once, then analyze the log files.

#### Comparing against MAME (ground truth)
When the core misbehaves, diff it against MAME's `maclc` running the same ROM.
Tooling: `verilator/mame/` (`run_mame.sh`, `tap.lua`, `snap.lua`, `trace.dbg`).
Full process + gotchas: **`docs/mame_compare.md`** (memory tap, maincpu trace,
PC-stream divergence diff; macOS has no `timeout`, debugger defaults to the Egret
HC05 not the 68020, MAME PCs are 8-digit `00Axxxxx`, etc.).

## Framework Files Are OFF-LIMITS (`src/fpga/apf/`)

**NEVER modify files under `src/fpga/apf/`** (the openFPGA framework:
`apf_top.v`, `io_bridge_peripheral.v`, `io_pad_controller.v`, `common.v`,
`mf_datatable`, `apf_constraints.sdc`). The only permitted change is a
wholesale update taken directly from `open-fpga/core-template`. If a fit,
timing, or resource problem traces into the framework, reconcile it from OUR
side — `rtl/`, `src/fpga/core/`, `ap_core.qsf` — never by patching the
framework in place.

This rule is inherited from the MiSTer core, where it was learned the hard way
(2026-07-17): a night of framework edits produced STA-met builds with dead
video and confounded every hardware A/B for hours. Framework internals have
invariants that are not visible from this repo; local edits there create
failure modes that pass STA and only show up on hardware. The reasoning
transfers directly to APF.

`src/fpga/core/core_bridge_cmd.v` came from the template too and should be
treated the same way, even though it lives outside `apf/`.

## Architecture

### Top-Level Modules
- `src/fpga/apf/apf_top.v` — framework top (off-limits)
- `src/fpga/core/core_top.v` — **our** APF chassis: bridge, data slots, video
  and audio contracts, gamepad, clocks, SDRAM pins. Not the machine.
- `src/fpga/core/mac_lc_pocket.sv` — the Macintosh itself. **Not yet written.**
  Its specification is `docs/mister_reference/MacLC.sv.reference`, the MiSTer
  top kept verbatim for exactly this purpose.

### Pocket glue (`src/fpga/core/`)
- `pocket_sdram.v` — SDRAM controller, adapted from `rtl/sdram.v`. The state
  machine is deliberately byte-for-byte identical; only the chip and the clock
  output changed.
- `pocket_input.v` — gamepad → `ps2_key`/`ps2_mouse`. This is the whole input
  port: everything right of those two buses is platform-independent.
- `apf_bridge_loader.v` — bridge writes → the MiSTer-shaped `dio_*` stream.

### RTL Structure (`/rtl`)

**CPU Core:**
- `tg68k/` - TG68K CPU core (68000)

**Memory & Storage:**
- `sdram.v` - MiSTer SDRAM controller. **Not built in this fork** — kept as the
  reference `src/fpga/core/pocket_sdram.v` was adapted from. Diff the two
  before touching either.
- `scsi.v`, `ncr5380.sv` - SCSI hard drive interface. `scsi.v` still contains
  all the CD-ROM/Toolbox code, gated off by `CDROM`/`TOOLBOX_ENABLE`/
  `CDCHANGER_ENABLE` = 0; it folds away at synthesis. Left in deliberately —
  it is 171 KB of heavily validated target and stripping it was not worth the
  risk.
- `floppy.v`, `floppy_track_encoder.v` - Floppy drive emulation (one drive)
- `sdp_ram.sv` - `cd_sdp`/`cd_sdp_mlab` simple-dual-port RAMs, extracted from
  the deleted `cd_audio.sv` because `asc.sv` uses `cd_sdp` for FIFO A. The
  forced-M10K `ramstyle` in them is load-bearing.

**I/O Peripherals:**
- `via6522.sv` - Versatile Interface Adapter (parallel I/O, timers)
- `pseudovia.sv` - VIA emulation for LC models
- `swim.v` - SWIM floppy controller (IWM + ISM personalities)
- `scc.v` - Serial Communication Controller
- `adb.sv` - Apple Desktop Bus
- `adb_device.sv` - translates `ps2_key`/`ps2_mouse` to ADB. **The platform
  seam**: everything downstream of it is identical on MiSTer and Pocket.
- `ps2_mouse.v` - PS/2 mouse decode (`ps2_kbd.sv` was dropped — no PS/2 port)
- `egret/` - Egret system controller (68HC05 + 341S0851 firmware): ADB, RTC, PRAM
- `uart/` - UART TX/RX modules (used by `scc.v`)

**Video Subsystem:**
- `maclc_v8_video.sv` - Mac LC Video Engine (V8)
- `ariel_ramdac.sv` - Video DAC (256-entry palette — exactly 8bpp)
- `vram_bram.sv` - on-chip framebuffer, 192 KB / ~192 M10K blocks
- `addrController_top.v`, `addrDecoder.v` - Address generation
- `dataController_top.sv` - Data control

### System Framework (`src/fpga/apf/`)
openFPGA framework from `open-fpga/core-template`. See the OFF-LIMITS rule above.

## Key Technical Details

- **Target FPGA:** Cyclone V `5CEBA4F23C8` (Analogue Pocket) — 18,480 ALMs,
  308 M10K, 66 DSP
- **Clocks** (from `clk_74a` = 74.25 MHz via `mf_pllbase`):
  65 MHz `clk_mem` · 65 MHz +90° for `dram_clk` · **32.5 MHz `clk_sys`** ·
  15.667 MHz `clk_pix`
  - 32.5 MHz is not negotiable: `v8_clocks.sv` has `PCLK_LIM = 32500` literally
    in its Bresenham divider, and the VIA/Egret timings assume it.
  - 65 MHz must stay exactly 8× the 8.125 MHz bus clock or `pocket_sdram`'s
    state-machine wrap breaks.
- **Memory:** 2 MB / 10 MB RAM configs in the Pocket's SDRAM (driven as a
  16 MB subset of the 64 MB part). No DDR3 — there is no HPS.
- **Video modes:** 1/2/4/8 bpp at 512×384 only
- **CPU speeds:** 8 MHz (original) or 16 MHz. Note the inherited limitation:
  **floppy won't read at 16 MHz.**

## File Locations

- `src/fpga/ap_core.qsf` - Quartus project settings **and** the RTL file list
  (this fork has no `files.qip`; the list is inline in the .qsf)
- `docs/PORT_STATUS.md` - what the port has and has not done. Start here.
- `docs/mister_reference/MacLC.sv.reference` - the MiSTer top, kept as the
  specification for `mac_lc_pocket.sv`. Not compiled.
- `dist/` - the SD-card tree; `output/` - the packaged bitstream
- `scratch/` - **(gitignored) ALL session scratch goes here**: screenshots,
  build/launch logs, captures, analysis dumps. Never leave scratch work in the
  repo root and never commit it.

## CPU Conversion Notes

When working with CPU cores, see `how-to-convert-cpu.txt` for GHDL-based VHDL to Verilog conversion process using:
```bash
ghdl synth -fsynopsys -fexplicit --latches --out=verilog
```

## Verilator vs Quartus Compatibility

**Critical:** Verilator allows multiple `always` blocks to drive the same `reg`, but Quartus does not (Error 10028: "Can't resolve multiple constant drivers"). When writing or modifying RTL:

- Each `reg` must be driven from exactly **one** `always` block for Quartus synthesis
- If timer logic, PRAM loading, or other hardware needs to write the same register as a CPU write path, **merge them into a single `always` block**
- Use `if/else if` priority within the block to handle the different write sources
- Verilator builds (`make` in `verilator/`) will succeed even with multiple drivers — always verify the design is Quartus-clean before targeting FPGA

**Conditional compilation:** `SIMULATION` is defined in `verilator/Makefile`. Guard simulation-only code (`$display`, debug counters) with `` `ifdef SIMULATION ``. (`USE_EGRET_CPU` is gone — the real HC05 Egret is unconditional as of 2026-08-09; `EGRET_BEHAVIORAL` remains as an opt-in debug fallback.)

**Top-level split:** the Verilator top is `verilator/sim.v` (`module emu`), NOT `MacLC.sv`. It has its **own** CPU instantiation and bus glue (VPA/DTACK/BERR/overlay); peripheral RTL is shared via `dataController_top`. CPU-glue/top-level fixes must go in **both** files or sim and FPGA silently diverge. Tracked differences (and a maintenance checklist) live in **`docs/verilator_differences.md`** — update it when you add a top-level signal or hardwire a sim config.

## VIA Shift Register — Simulation Sensitivity

**Critical:** Changes to the VIA SR logic in `rtl/via6522.sv` can break Egret communication and stall the boot. After any SR change, verify simulation still boots:

```bash
cd verilator && make clean && make
./obj_dir/Vemu --screenshot 450 --stop-at-frame 451 2>/dev/null 1>/dev/null
```

Check `screenshot_frame_0450.png` — it must show the **50% dither grey desktop
with the arrow cursor top-left** (boot reached cursor-visible state). A uniform
flat grey at 450 means the boot stalled — Egret communication is the first
suspect. Corroborate with `bash check_boot.sh` (stages + ADVANCING).
(Re-calibrated 2026-08-05: the old criterion was the memory-test line pattern
at frame 350, timed against VIA timers that counted 2× slow — the via6522.sv
timer fix moved every timer-paced boot delay earlier, so the pattern now
passes before frame 180 and 350 lands in a featureless VRAM-fill phase.)

**SR edge-detection patterns (history + FPGA caveat):**
- `cb2_latched` (shift-in: capturing CB2 at the CB1 rising edge) — **removed; do not re-introduce.** Shift-in uses live `cb2_i`. Re-introducing it hung the 4th Egret SR transfer in Verilator (CPU stuck polling IFR bit 2 at `0xA14E5E`).
- `ext_fall_edge_pending` (shift-out: latching CB1 falling edges in external-clock mode) — **currently IN USE in `via6522.sv`.** It was reverted in `a8f9f33`, then deliberately re-added in `e067857` ("switching to fake egret"). It boots in Verilator only because the behavioral Egret drives CB1 slowly, so edges never coalesce. It is the **suspected cause of the FPGA overlay-stuck bug**: the real HC05 toggles CB1 far faster than the VIA's E-rate (only one pending edge is consumed per E-falling phase), so edges coalesce, SR bytes corrupt, the boot ROM's Egret handshake never completes, and the ROM overlay never clears. Do NOT assume it is FPGA-safe — prefer rate-limiting CB1 in `egret_wrapper` over re-touching this SR path.

Re-verify boot (the screenshot check above) after ANY SR change.

## Known Limitations

- Floppy disks are read-only (**no write datapath exists** in `rtl/floppy.v`;
  the drive reports `WRTPRT=0` = write-protected so the OS never tries. That
  is load-bearing: the ROM's write primitive polls handshake b7 in an
  UNBOUNDED loop, so an attempted write would hang the machine, not fail.)
- **BOOTING FROM FLOPPY WORKS** (user-confirmed on hardware 2026-08-05,
  bench build `78a46cf2`). The old "Welcome to Macintosh" retry loop and the
  ~39 KB-then-UNDERRUN freeze are gone. Several fixes contributed and no
  single one was isolated: the constant-300-RPM MFM tach (`62aee5c`, which
  targeted the Welcome loop directly), the ISM drive-select fix, the INDEX
  pulse, VIA1 PA7, and the VIA timer half-rate fix (`33ebdd1` — the driver's
  install-time drive-speed check is timer-paced, so a 2x timer error would
  also have corrupted it).
- **800K GCR disks WORK END-TO-END as of 2026-08-05** — mount, catalog, and
  **file reads**: on a cold boot a 482K application was launched off an 800K
  GCR floppy and copied to a SCSI disk with zero driver errors (head seeking,
  `step_cnt` 1 -> 311). Two fixes got here:
  1. `2804d02` — "This disk is unreadable" (`-69 badCksmErr`). The IWM
     read-data latch clear was retriggered from the LEVEL `iwmRead` instead of
     firing once at the END of the access: the LC's E-paced VPA accesses (~1.23
     us) plus the ROM's ~2.5 us GCR poll loop left less gap than the 13-cen
     reload, so the latch never cleared and the CPU re-read each disk byte ~6
     times — duplicates shift a field and break its checksum.
  2. **MEDIA CHANGES — FIXED AND HW-VALIDATED 2026-08-06** (`887ebba` +
     `dbb736e`; MISSION COMPLETE: a full System 6.0.8 install from its two
     1.44 MB floppies ran end to end — installer ejects, both OSD disk swaps,
     install onto a fresh SCSI vhd, installed system boots). The ghost-volume
     class ("mounts and lists but every call fails with NO driver error and
     zero disk I/O") was the guest never being told the medium changed. Three
     inseparable pieces, all MAME-runtime-grounded (tap_swapB/tap_qscreen):
     - **SWITCHED sense reg** (read reg 6 = MAME DiskChg = `!m_dskchg`):
       reset 0, SET on any media removal (fall of `insertDisk`), survives the
       next insert, cleared ONLY by the guest's DskchgClear strobe
       (`strobeCmd == 4'hC`). The Sony driver polls NoDiskInPl+DiskChg as a
       PAIR every ~0.8 s and strobes the clear itself — watched live on HW
       (HUD w7 `dskchg_clears` increments). Landing the CSTIN transition
       WITHOUT this register was the reverted-`ebbdac6` regression.
     - **CSTIN reports `~insertDisk`** + the MacLC.sv/sim.v empty-hold (drop
       media at download START, hold 2.06 s past the end).
     - **ISM eject re-enabled** under `(!ism_active || ism_sel)` — the MAME
       devsel-forwarding condition. The old blanket `!ism_active` gate made an
       MFM installer structurally unable to eject; the phases-walk phantom
       ejects it guarded against all run with Mode b7 CLEAR, so the qualifier
       blocks them and passes genuine ejects (installer ejects seen on HW).
     ALSO fixed en route (`dbb736e`): **Main packs the matched extension of a
     multi-extension F entry into the upper `ioctl_index` bits** (.dsk = 8'h01,
     .img = 8'h41); the flag latches compared the full byte, so every `.img`
     mount was a silent no-op (downloaded, never presented) since day one —
     compare `dio_index[5:0]` only. `verilator/tb_disk_swap.v` covers the full
     protocol (incl. walk-must-not-eject and the 8'h41-index mount) — run it
     after any `insertDisk`/`CSTIN`/eject edit. HUD row 7 = the media witness
     (`floppy.v` dbg_media; decode in `scripts/parse_hud.py`).
     ★ Swap-under-a-live-volume (no eject) is HOSTILE ON A REAL MAC TOO —
     MAME 6.0.8 bombs ("Disk Initialization package not present") when the
     boot floppy is yanked: drives only eject under software control, so the
     OS has no graceful path. The Mac-authentic flow is guest-eject-first
     (or the installer's own eject), THEN mount the next image.
     ★ OSD/bench lore from the validation (ops crib additions): the in-core
     OSD opens with the cursor ON "Mount Pri Floppy" after a FRESH CORE LOAD
     but remembers its row and browser position across opens within a
     session; the screenshot-filename oracle names the LAST file downloaded
     this core session — it proves a pick happened, NOT which slot took it.
  ★ `byte_cnt` frozen + `$142` all-benign means **no read was attempted** — do
  not read it as "reads returned bad data". (And `byte_cnt` alone is NOT proof
  of internal-drive reads — the GCR delivery counter also churns on garbage
  with no disk in; corroborate with w7 `insertDisk`/`CSTIN`.)
  The old 2026-07-07 floppy-controller park is RESOLVED (doc removed); its
  "SDRAM region != image" theory was never confirmed and its JTAG chain no
  longer works (dead hub). Offline instruments that settled all of this in
  minutes: `verilator/tb_gcr_read.v` (`+track/+side/+ncap`, seeks via the real
  drive-register protocol; **always pass `+acclen=40 +pollgap=40`** or the
  stream is garbage), `scripts/gcr_census.py` (address fields),
  `scripts/gcr_data_census.py` (DATA fields verified against the standard 800K
  layout offset — every zone boundary clean, refuting the `soff` suspicion) and
  `scripts/hfs_check.py` (walks an image's catalog/extents trees offline so a
  broken source image can't fake an RTL bug).
- **1.44 MB MFM read works, and the Finder whole-disk COPY was FIXED
  2026-08-05** (`33ebdd1`): the real defect was **`rtl/via6522.sv` counting
  T1/T2 at half rate** — a `/2` prescaler stacked on enables that were already
  at VIA phi2 rate (`E_div=1'b1`), so every guest VIA-timer interval ran 2.0×
  long since June. That doubled the Sony driver's Time-Manager sleep between
  read attempts and phase-locked its re-arm one sector late (stride-2 over 18
  sectors ⇒ a closed 9-sector cycle ⇒ `-81 sectNFErr`). HW: 5 dialogs → **0,
  twice**, copy ~2 min → ~55 s. Full write-up + the SCAN-WITNESS evidence in
  **`docs/sony_driver_mfm_read_reference.md`** — read it before any floppy or
  VIA-timer work; it also decodes every Sony error code (`-65` is benign
  polling of the absent second drive) and lists **seven theories tested and
  refuted**, several of which were built before that page existed.
  Instruments: `USE_DBG_HUD` + `scripts/parse_hud.py` (rows 7/8 = SCAN-WITNESS),
  `verilator/mame/floppy/sonyvars_watch.lua` (driver retry budgets from MAME),
  `verilator/tb_mfm_idcensus.v` (full-disk ID census), `tb_ism_sony +postgap=N`.
  ★ `USE_DBG_HUD` is currently OFF (commented out) in `MacLC.qsf` — flip it
  on for debug fits only; it must be OFF in release fits.
- SCSI writes validated 2026-07-29 (word-pairing fix f38c06f/ceaec45; 14.5 MB
  in-guest duplicate byte-identical). SCSI/CD reads validated same day
  (look-ahead boundary fix 082dcc4; CD copies byte-identical to ISO
  reference). Release fits no longer carry the JTAG probe decks — an
  always-on anchor in MacLC.sv (4dfb463, extended 2026-08-03 with per-disk
  read-ring words after the 11-word anchor proved insufficient on the
  post-floppy netlist) pins the SCSI capture + ring-serve cones; do
  not remove it (comment block explains), and gate every new fit in the
  FINDER on colour icons — `scripts/icon_gate.py` on frames captured with
  `scripts/grab_fresh.sh` (stock grab.sh serves STALE frames when video is
  dead), plus a >=2-boot Finder soak (see the probes-off anchor comment in
  MacLC.sv).
- Floppy won't read at 16 MHz CPU speed
- Bus retry via HALT signal not implemented
- ~~"Original" aspect was 256:171~~ FIXED 2026-08-08: that was the Mac Plus
  512x342 screen, inherited at import — it drew ~12% wide and OVERFLOWED
  integer scaling on 1280x1024 panels (V-Integer requested 1437 px → blank
  screen). Now true 4:3 (both LC monitor modes are 4:3). Offline gate:
  `scripts/aspect_check.py` (faithful model of sys/video_freak.sv
  `video_scale_int`; also demos the old failures with `--show-broken`).
- ~~CD-ROM (SCSI ID 3)~~ **REMOVED in the Pocket fork.** The CD target,
  cd_audio, the AppleCD command set and the BlueSCSI Toolbox / CD Changer are
  all gone -- 7,762 ALUTs and 17 M10K the Pocket does not have. The MiSTer
  core's CD work (SCSI-2 dialect on the CDU-8004 identity, mode page 0x0E
  volume, sub-channel formats, the Main_MiSTer `maclc_cd` translation layer)
  is intact upstream at 5a75f9b if it ever needs to come back; see
  docs/PORT_STATUS.md for what it would cost.
- ~~"Original" aspect 256:171~~ moot here: the Pocket declares a single
  512x384 4:3 scaler mode in video.json and Analogue's scaler handles fitting.
  `sys/video_freak.sv` and `scripts/aspect_check.py` do not exist in this fork.
