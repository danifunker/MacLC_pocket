# 640×480 (VGA) video — rework plan (parked)

Status: **deferred.** The core ships with **512×384 (12" RGB, monitor_id 0x2)** as the
recommended mode. 640×480 (VGA, monitor_id 0x6) currently renders but at the wrong
refresh rate. This doc captures everything needed to do it properly later.

## Goal

MAME-faithful VGA 640×480 @ ~60 Hz. From MAME `maclc` / `v8.cpp`:

```
m_screen->set_raw(25175000, 800, 0, 640, 525, 0, 480);   // 25.175 MHz, 800x525, 60 Hz
```

i.e. **25.175 MHz dot clock**, h_total 800 (640 active), v_total 525 (480 active),
59.94 Hz. (The 12" RGB / "Eagle" variant uses the 15.6672 MHz master at 704×370 —
that's the 512×384 path we already do.)

## Why the simple approaches fail

The V8 video (`rtl/maclc_v8_video.sv`) runs entirely in the **clk_sys (32.5 MHz)**
domain and the framework hookup is `CLK_VIDEO = clk_sys`, `CE_PIXEL = v8_ce_pix`
(`MacLC.sv:185-186`). The pixel enable is `pix_div` = clk_sys/2 = **16.25 MHz**.

- **clk_sys/2 for all modes (current):** 16.25 MHz × (800×525) → **38.7 Hz**. Stable
  but too slow; judders through the scaler, won't sync on analog out.
- **Fractional (Bresenham) CE_PIXEL targeting 25.175 MHz — TRIED & REVERTED
  (2026-06-05):** with `CLK_VIDEO` fixed at clk_sys, a non-uniform CE_PIXEL makes the
  clk_sys-cycles-per-line jitter; the scaler renders it as a **"super shakey"** image.
  A stable raster requires a *uniform* pixel clock, i.e. a real clock, not an enable.

## The three layers of work

### Layer 1 — pixel clock (easy)
Add a **25.175 MHz output** (or 50.35 MHz = 2× for a clean /2 CE) to the PLL.
- PLL is `rtl/pll/pll_0002.v` (`altera_pll`, 50 MHz refclk, fractional VCO). Only
  **2 of up to 9 outputs used** (65 MHz clk_mem, 32.5 MHz clk_sys) — plenty of room,
  and the fractional VCO can hit 25.175. Regenerate via the Quartus IP editor (or
  hand-edit `number_of_clocks` + `output_clock_frequencyN` + add the port), then add
  `outclk_2`/`clk_pix` to the `pll.v` wrapper and `MacLC.sv`.

### Layer 2 — clock-domain crossing (medium, real rewrite)
The scanout must run on `clk_pix` while the VRAM **fetch stays on clk_sys** (it reads
the SDRAM bus via `videoBusControl`/`memoryLatch`). Standard fix: a **line buffer**
(dual-port RAM, clk_sys write side / clk_pix read side). The fetch fills the buffer for
the line; the scanout reads it out at 25.175 MHz and drives `VGA_*`/HS/VS/DE. The line
buffer IS the CDC. `CLK_VIDEO` becomes `clk_pix`, `CE_PIXEL` a clean divide of it.
For 512×384, keep the existing clk_sys/2 path (clock-mux per `monitor_id`).

### Layer 3 — fetch bandwidth (the real ceiling, risky)
This is the fundamental limit and why "just add a clock" doesn't get color VGA.
Bus arbitration (`rtl/addrController_top.v`): video gets **only busCycle 0 of 4**
(`videoBusControl = busCycle == 0`), one word per `memoryLatch` per busCycle =
**1 word / 16 clk_sys ≈ 2 M words/s ≈ ~64 words per line** at 60 Hz. Already flagged
in `maclc_v8_video.sv:~223` (1bpp only renders 8 of 16 px today).

| 640×480 @ 60 Hz | words/line needed | fits in ~64? |
|---|---|---|
| 1bpp | 40  | ✅ |
| 2bpp | 80  | ❌ |
| 4bpp | 160 | ❌ |
| 8bpp | 320 | ❌ |

So with Layers 1+2 only, **640×480@60 works at 1bpp B&W**; 2/4/8bpp underflow
(right-edge garbage). For color VGA, video needs more bus slots — e.g. grant
`busCycle == 0 || busCycle == 2` to video. But busCycle 2 is `extraBusControl`
(SCSI-DMA / `extra_slot_advance`), and `cpuBusControl` is busCycle 1|3, so stealing a
slot touches **CPU / SCSI / DRAM-refresh timing** — the risky part. Needs the boot +
SCSI + floppy regression checks after.

## Suggested order when resumed
1. Layer 1: add `clk_pix` (25.175 MHz), prove it locks (probe `pll_locked`).
2. Layer 2: line-buffer scanout on `clk_pix`; clock-mux `CLK_VIDEO` per `monitor_id`.
   Verify **1bpp** 640×480@60 is stable on hardware (deploy + screenshot).
3. Layer 3: rework bus arbitration for an extra video slot; re-verify boot/SCSI/floppy
   and 2/4/8bpp 640×480.

## Notes / gotchas
- Keep 512×384 on the existing clk_sys/2 path — don't regress the working mode.
- A non-uniform CE_PIXEL on a fixed CLK_VIDEO is a dead end (see "shakey" above).
- See [clock-audit memory] for the wider clock comparison vs MAME (VIA/E-rate, etc.).
- Test loop: `scripts/build.sh` → `scripts/deploy_screenshot.sh` (or the inline
  deploy + `/api/screenshots`) → inspect at 640×480 default and 512×384.
