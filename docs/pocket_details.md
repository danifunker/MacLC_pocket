# Porting MacLC to the Analogue Pocket (openFPGA)

High-level planning notes for moving this Mac LC core from MiSTer to the
Analogue Pocket. Conceptual only — not a file-by-file plan yet.

## Core idea

This is mostly a **framework swap plus a hardware-budget reckoning**, not a
logic rewrite. The `/rtl` content (TG68K, V8 video, Ariel, VIA, IWM/SWIM, SCSI,
Egret HC05, ASC, ADB) is preserved almost untouched. What changes is everything
around it — the top wrapper, file I/O, memory, video, audio, input, and the
options menu.

| Concern            | MiSTer (today)                          | Analogue Pocket (openFPGA)                                |
|--------------------|------------------------------------------|------------------------------------------------------------|
| Top wrapper        | `sys/sys_top.v` + `MacLC.sv` (`module emu`) | `core_top.v` + APF "bridge"                              |
| File I/O / images  | HPS_IO download (Linux ARM)             | openFPGA **data slots** (microSD), declared in JSON        |
| Menu / options     | `CONF_STR` OSD                          | `interact.json` → values arrive over the bridge            |
| Big memory         | DDR3 via HPS (1 GB) + optional SDRAM    | **SDRAM only** (one chip, no DDR3, no HPS)                  |
| Video out          | framework scaler → HDMI/analog          | pixel stream to Analogue's display controller (2nd FPGA)   |
| Audio              | framework I2S                           | APF `audio` I2S interface                                  |
| Input              | HPS USB joystick/keyboard/mouse         | `cont1_key` gamepad bits (no native kbd/mouse)             |
| Toolchain          | Quartus 17.0.2 Lite                     | Quartus 17.1 (openFPGA target), Cyclone V                  |

## High-level steps

1. **Set up the openFPGA scaffold.** Start from Analogue's core template
   (`core_top.v`, the APF bridge, `Cores/<author>.<core>/` with `core.json`,
   `video.json`, `audio.json`, `data.json`, `interact.json`, `input.json`).
   Get a trivial core booting on Pocket first so the framework is known-good.
2. **Re-host the RTL** under `core_top.v` instead of `module emu`. The
   peripheral RTL is portable; the work is re-wiring the *edges* (clocks, reset,
   memory, video, audio, input) to APF signals.
3. **Clocks/PLL.** Regenerate `pll.v` for the Pocket reference clocks
   (`clk_74a`/`clk_74b`). Reproduce 8/16 MHz CPU clock + pixel clock from those.
4. **Memory budget — the big risk.** Map the SDRAM layout (ROM + motherboard
   RAM + SIMM + VRAM + floppy buffers, up to ~16 MB word space) onto the
   Pocket's single SDRAM chip. Port `sdram.v` to the Pocket controller/pinout
   and **confirm size + bus width actually fit** the 2 MB/10 MB RAM configs,
   512 KB ROM, 512 KB VRAM, and floppy regions. Most likely to bite.
5. **Disk/ROM loading via data slots.** Replace HPS_IO downloads with openFPGA
   data slots: declare slots for ROM, SCSI HD images, floppy images in
   `data.json`; translate `dio_download`/`dio_index` streaming to the bridge's
   slot-write protocol.
6. **Video bridge.** Drive the APF video interface with the V8/Ariel pixel
   stream (sync/blanking/clock per Analogue's contract). Validate 1/2/4/8/16 bpp
   and the 640×480 mono case.
7. **Audio bridge.** Wire ASC mono output to the APF I2S audio interface
   (sample-rate clocking, not per-clock).
8. **Input.** Map the Pocket gamepad to ADB (see input section below).
9. **Options menu.** Recreate `CONF_STR` toggles (CPU speed, RAM size, model
   config) as `interact.json` entries.
10. **Build + test on hardware.** No HPS Linux = less on-target introspection;
    Verilator stays valuable for logic, framework/memory/video are hardware-loop.

## The parts that will actually hurt

- **Memory fit** — the design assumes generous SDRAM; the Pocket is tighter and
  single-chip. Verify first.
- **No native keyboard/mouse** — addressed below; this is a UX design problem,
  not a blocker.
- **HPS dependencies** — anything leaning on Linux (file browser, RTC seeding,
  NVRAM save-back) needs an openFPGA equivalent (data-slot read/write-back).
- **Egret HC05 + ADB timing** — clock-rate sensitive; new PLL means re-verify
  Egret SR / ADB autopoll timing.
- **Third top-level** — already maintaining `sim.v` vs `MacLC.sv`; a Pocket port
  adds `core_top.v`. Keep shared peripheral RTL as the single source of truth.

## Input: how MiSTer does it vs what the Pocket needs

### How the Amiga (Minimig) core does it on MiSTer

It leans entirely on the **HPS** (ARM Linux). A real USB keyboard/mouse is
plugged in; the HPS decodes USB HID and forwards two standard buses to the core:
`ps2_key[10:0]` (scancode + pressed/released + toggle strobe) and
`ps2_mouse[24:0]` (signed X/Y deltas + button bits + toggle). Minimig translates
those into Amiga-native form (keyboard serial MCU + quadrature mouse counters).

**This Mac core already works the same way.** The same `ps2_key`/`ps2_mouse`
buses come out of `hps_io` in `MacLC.sv` and feed `adb_device`
(`rtl/dataController_top.sv:685`), which translates them to ADB instead of Amiga
keycodes. So there's nothing to "borrow" from Minimig — it's the same pattern,
and the dependency is the *HPS*, which the Pocket doesn't have. The Amiga
approach doesn't transfer because it's a platform capability, not a core trick.

### The seam that makes the Pocket port tractable

```
[input source] ──► ps2_key[10:0] / ps2_mouse[24:0] ──► adb_device ──► Egret ──► Mac
```

Everything right of those two buses is identical on MiSTer and Pocket. Porting
input = **generating `ps2_key`/`ps2_mouse` from the APF gamepad** instead of from
the HPS. ADB, Egret, and the Mac side are untouched.

Crucially, **no real keyboard is needed to send keystrokes.** For a
keyboard-driven game (Prince of Persia = arrows + Shift), just emit synthesized
`ps2_key` events: D-pad → arrow scancodes, a face button → Shift/Return. A small
"gamepad → ps2_key map" module is the whole job for D-pad games.

## MacOS 7 front-end / launcher idea

A custom System 7 launcher app with a D-pad-navigable game list. Strategy:

- **Auto-launch via System 7 Startup Items** so boot bypasses the mouse-driven
  Finder entirely — the user never has to point-and-click to get going.
- **D-pad navigable list** (reads arrow keys / Return, which we already
  synthesize). It picks a game and launches it.
- Ship a **per-game button→key profile** (PoP = arrows+Shift; others differ).

Where it stays "good for D-pad games":
- **Mouse-native games** (point-and-click) still need a usable mouse — can be
  synthesized but clunky.
- The **Finder/desktop** is mouse-driven, which is why auto-launching the
  front-end matters: it keeps users out of the part that needs a mouse.

## D-pad ⇄ pointer toggle mode

A small toggle/mux module at the Pocket top, in front of the `ps2_key`/
`ps2_mouse` seam. Zero changes to Mac RTL.

```
cont1_key (Pocket gamepad bits)
        │
        ├── toggle button ──(rising-edge)──► mode flip-flop ──► [ KBD | PTR ]
        │
        └── mode mux:
              KBD mode → D-pad → arrow-key ps2_key events
                         A/B   → key scancodes (Shift, Return…)
              PTR mode → D-pad → ps2_mouse X/Y deltas
                         A     → ps2_mouse left-button (click)
```

**Pieces:**
1. **1-bit mode register**, flipped by a *rising-edge* detect on the toggle
   button (press = flip; press again = flip back). "Same button toggles in/out."
2. **Mode mux** in front of the two buses:
   - KBD: D-pad → arrow `ps2_key` events; A/B → game keys.
   - PTR: D-pad held → small `ps2_mouse` X/Y deltas per mouse report (digital
     velocity, optionally ramping with hold time); A → mouse button bit.
3. Output feeds the unchanged `adb_device → Egret → Mac` path.

**Two details to get right:**
- **Dedicated toggle button, not A/B** (those are click/action). Use **Select**
  (or Start, or a hold-combo) so the toggle never collides with input.
- **Clean release on every switch.** On a mode flip, emit key-up for any held
  arrow and button-up for the mouse so the Mac never sees a stuck key/click.

**Nice fits for the classic Mac:**
- The classic Mac mouse is **one button**, so a single click button (A) is all
  that's needed — no right-click.
- **Feedback is free:** in PTR mode the cursor visibly moves; in KBD mode it
  doesn't. No on-screen indicator needed (harder on openFPGA).
- The **analog stick** (dock controllers) can later drive a true analog pointer
  in PTR mode with the D-pad as digital fallback — same mux, second source.

## Net assessment

Input is probably the *easiest* part of this port for the target use case: one
small gamepad→`ps2_key`/`ps2_mouse` mux module plus a System 7 launcher, with the
entire ADB/Egret stack untouched. The hard parts remain **SDRAM fit** and
**video/framework bring-up** on openFPGA.
