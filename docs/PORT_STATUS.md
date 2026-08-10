# MacLC → Analogue Pocket port status

**As of 2026-08-09. The project does not compile yet.** One file is missing:
`src/fpga/core/mac_lc_pocket.sv`. Everything else described below is written.

Source: `../MacLC_MiSTer` @ `5a75f9ba59f8f13a48e527e291877d8838400923`
(branch `ariel-ramdac-m10k`). Imported as a flat snapshot — no upstream git
history. To diff any file against upstream:

```bash
git -C ../MacLC_MiSTer show 5a75f9b:rtl/swim.v
```

---

## The budget this port exists to satisfy

| | DE10-Nano (5CSEBA6U23I7) | Pocket (5CEBA4F23C8) |
|---|---:|---:|
| ALMs | 41,910 | **18,480** |
| M10K blocks | 553 | **308** |
| DSP | 112 | 66 |

Last MiSTer fit (`output_files/MacLC.fit.summary`, 2026-08-09): 28,459 ALMs
(68%), 502/553 M10K (91%), 53 DSP. The `emu` module alone was 29,580 ALUTs
≈ 20,900 ALMs — **113% of the Pocket** before adding any APF framework. The
cuts below are load-bearing, not optimisation.

Estimated after cuts: ~15,400 ALMs (83%) and ~252 M10K (82%), including the
APF framework. **Unverified — no synthesis has been run.**

---

## Done

### The three cuts

**Video → 512×384, 8bpp max** (`698d9af`)
- `vram_bram` 196,608 → 98,304 words (384 KB → 192 KB). This is the big one:
  the 16bpp framebuffer was 384 M10K blocks, more than the Pocket has in
  total, and 76% of the entire MiSTer design's block RAM.
- 16bpp mode removed from `maclc_v8_video` (bits_per_pixel, the shift cases,
  and the X-5-5-5 direct-colour output path with its `video_data` pipeline).
- Monitor timing hardwired to 12" RGB 512×384. The 640×480 VGA mode is gone —
  at 8bpp it would have been 300 KB, over budget on its own.
- Scanline line buffer halved (512 → 256 words per buffer).
- `pseudovia` clamps the guest-writable depth field to 3, so a guest asking
  for 16bpp reads back what it will actually get instead of scanning past the
  end of the framebuffer.
- **Bonus:** 512×384 needs a 15.664 MHz dot clock, and committing to a single
  monitor mode lets the Pocket drop `pll_video` **and** the `pll_cfg` reconfig
  block MiSTer needed to retune the pixel clock (~960 ALUTs + a PLL).

**Single floppy drive** (`698d9af`)
- `floppyExt` instance deleted from `swim.v`. The ISM path could never reach
  it (`ism_devsel_ext` was already hardwired 0 — "no external drive on the
  LC"); only the legacy IWM `selectExternalDrive` path could, and that now
  reads the floating-bus value a real LC shows with nothing plugged in
  (`FF` ⇒ sense high ⇒ no disk). The Sony driver's benign startup poll of the
  absent drive expects exactly this.
- All `{ext,int}` disk bus pairs collapsed to single bits through `swim.v` and
  `dataController_top.sv`; the external drive's SDRAM fetch channel and its
  `$700000` image region are gone from `addrController_top.v`.
- The extra-slot rotation modulus was left alone on purpose so the internal
  drive keeps the fetch cadence the GCR/MFM delivery timing was validated
  against.

**CD-ROM + BlueSCSI Toolbox** (`bb4b8f9`) — the biggest logic saving
- `cdrom_target` was 7,762 ALUTs / 17 M10K / 768 MLAB cells, of which
  `cd_audio` alone was 3,076 ALUTs. Nothing else in the design is close.
- Cut at the **instantiation boundary**, not inside `scsi.v`. That file is
  171 KB of heavily validated SCSI target and is already parameterised
  (`CDROM` / `TOOLBOX_ENABLE` / `CDCHANGER_ENABLE`), so the bodies fold away
  at 0. Deleting the instances gets 100% of the saving with none of the risk.
- Both disk targets → `TOOLBOX_ENABLE(0)`, `TB_ADDRW(8)` (was 12 on the boot
  disk): drops two 4 KB Toolbox dprams, ~8 M10K.
- `cd_audio.sv` + `cd_vol_lut.vh` deleted. **`asc.sv` instantiates `cd_sdp`,
  which lived inside `cd_audio.sv`** — so `cd_sdp`/`cd_sdp_mlab` were
  extracted verbatim into `rtl/sdp_ram.sv` with their inference comments
  intact (the forced-M10K `ramstyle` is load-bearing).
- The one edit inside `scsi.v`: the `generate if (CDROM != 0)` branch that
  instantiated `cd_audio` is deleted and its `else` tie-offs made
  unconditional. A generate branch naming a deleted module is a build hazard
  even when never taken.

### Pocket chassis

| File | What it does |
|---|---|
| `src/fpga/apf/` | openFPGA framework, verbatim from `open-fpga/core-template`. **Off-limits**, same rule as MiSTer's `sys/`. |
| `src/fpga/core/core_top.v` | APF top. Complete: bridge mux, option registers, data-slot sessions, video/audio contracts, clocks, SDRAM pins. |
| `src/fpga/core/mf_pllbase/` | PLL retargeted from the template's 12.288/133.12 MHz to 65 / 65@90° / 32.5 / 15.667 MHz. |
| `src/fpga/core/pocket_sdram.v` | SDRAM controller, adapted from `rtl/sdram.v`. |
| `src/fpga/core/pocket_input.v` | Gamepad → `ps2_key`/`ps2_mouse`. |
| `src/fpga/core/apf_bridge_loader.v` | Bridge writes → the MiSTer-shaped `dio_*` download stream. |
| `*.json` | Core metadata, one 512×384 4:3 scaler mode, 5 data slots, 4 options. |
| `src/fpga/ap_core.qsf` | Device `5CEBA4F23C8`, full RTL file list, SignalTap removed. |

**Clock plan** (reference is `clk_74a` = 74.25 MHz):

| Output | Freq | Use |
|---|---|---|
| outclk_0 | 65.000 MHz | `clk_mem` — SDRAM. Must be exactly 8× the 8.125 MHz bus clock. |
| outclk_1 | 65.000 MHz +90° | driven onto `dram_clk` |
| outclk_2 | 32.500 MHz | `clk_sys` — everything. `v8_clocks`' Bresenham limit is literally 32500. |
| outclk_3 | 15.667 MHz | `clk_pix` — 512×384 (target 15.664, within ~0.02%) |

**`pocket_sdram.v` — what changed and what deliberately did not.** The cycle
state machine, init ladder, RAS/CAS timing, CAS latency and address mapping
are byte-for-byte from `rtl/sdram.v`; that machine is what the whole core's
memory timing was validated against. Changed: the Pocket's 512 Mbit part is
driven as a **subset** (12 row bits, 9 column bits, 2 banks = 16 MB of the
64 MB available) so the address mux needs no re-derivation; `dram_clk` comes
from a phase-shifted PLL output instead of an in-module `altddio_out`; `cke`
is now a real driven pin.

**`pocket_input.v` — the seam that makes input tractable.** Everything to the
right of `ps2_key`/`ps2_mouse` (`adb_device` → Egret → Mac) is identical on
both platforms, so porting input means only synthesising those two buses.
Select toggles keyboard mode (D-pad → arrows, A/B/X/Y → Shift/Space/Return/
Escape) and pointer mode (D-pad → mouse with a hold-to-accelerate ramp, A →
the Mac's single mouse button). Every held key is released and the button
cleared on a mode flip so nothing can stick.

---

## Not done

### 1. `src/fpga/core/mac_lc_pocket.sv` — the machine top. **Blocking.**

`core_top.v` instantiates it; it does not exist. This is the port of
`docs/mister_reference/MacLC.sv.reference` (2,302 lines, kept precisely
because it is the specification for this file).

Keep, adapting only the edges:
- reset sequencing incl. the `rom_loaded` latch (without it the 68k runs on
  whatever the previous core left in SDRAM at the ROM window)
- `tg68k` instantiation + VPA/DTACK/BERR/overlay glue, incl. `periph_din_reg`
  (the registered peripheral read that fixed the fit-marginal SCSI CSR bit-6
  dice-roll boot) and the `slot_space` → `$FFFF` open-bus convention
- `addrController_top` / `dataController_top` / `ariel_ramdac` /
  `maclc_v8_video` / `vram_bram` / `asc` wiring
- the SDRAM address/data/strobe mux between the CPU, the floppy fetch and the
  download path, including `extra_rom_data_demux` (select on the **live**
  `dskReadAddr[0]`, not `memoryAddr[0]`) and `sdram_out_patched` (the
  warm-boot `bne.w`→`bra.w` patch at word `$52322F`)
- the DC42 header-skip logic in the floppy download path
- the SDRAM re-init pulse: edge-triggered, gated on `rom_loaded` and
  `!dio_download` — the reverted MiSTer attempts that tied `.init` to a
  level held through the download broke cold boot

Drop: `CONF_STR`/`hps_io`, `video_freak`, `pll_video`/`pll_cfg`, `dbg_probes`
and the JTAG/ISSP decks, the UART, `status[]` (replaced by the `opt_*`
inputs), the CD/Toolbox slots, the second floppy.

Hardwire `v8_monitor_id = 4'h2` (12" RGB) — it is now the only timing.

### 2. `apf_blockdev` — SCSI disks. **Blocking for anything but floppy boot.**

MiSTer's `hps_io` block-device protocol (`sd_lba`/`sd_rd`/`sd_wr`/
`sd_buff_*`/`img_mounted`/`img_size`) has no APF equivalent. On the Pocket the
core must *ask* the OS to move data using `target_dataslot_read` /
`target_dataslot_write` with slot offset, bridge address and length, then wait
for `target_dataslot_done`. A 256 MB `.hda` cannot be preloaded, so this is
the only path.

`core_top.v` currently holds all the target-command registers idle. Writing
this is a self-contained subsystem: translate one 512-byte LBA request into a
target command, land the payload in a buffer the SCSI target can read, and
handle the write direction for save-back.

### 3. Smaller, non-blocking

- **`clk_pix_90`** is currently just `clk_pix`. `mf_pllbase` outclk_4 is free
  and should be configured as clk_pix + 90°.
- **Data-slot `parameters` bitfields in `data.json` are guesses.** The APF
  spec's bit meanings are not documented in the core template and were not
  available offline. Verify before trusting save-back on the SCSI/PRAM slots.
- **`verilator/sim.v` is broken** — it still wires the removed
  `dataController_top` ports (11 references: `cd_snd`, `dbg_cda*`, `cdtb_*`,
  `cd_io_*`, `tb_lba`, `dskReadAddrExt`). The Verilator harness is the most
  valuable verification asset in the repo (boot check, screenshot oracle,
  `tb_disk_swap`, the GCR/MFM benches) and fixing it is probably the highest
  value-per-hour task after `mac_lc_pocket.sv`.
- **PRAM save-back** (MiSTer slot `SC2`) needs the same target-command path as
  the disks.

---

## Verification available here

Neither Quartus nor Verilator is installed on this machine, so **nothing in
this port has been compiled, simulated, or fitted.** The only automated check
that ran is:

```bash
python scripts/check_hierarchy.py rtl
```

a regex pass confirming every instantiated module still exists (37 files, 42
modules, clean). It is a heuristic, not a parser, and it does not check port
widths, connectivity, or syntax.

Treat every "estimated" number above as arithmetic on the MiSTer fit report,
not as a result.
