# Plan (Option B): DDR3 video channel — 16bpp + full CPU/video decouple

Status: **DEFERRED / future phase.** 256-color (8bpp) is solved by Option A+
(SDRAM burst-2 + video-priority arbiter — see `docs/plan_060526.md` and the
2026-06-05 commits). This doc scopes the *next* step: moving the video
framebuffer fetch off the shared 16-bit SDRAM onto the MiSTer **DDR3** so that
(1) **16bpp / "thousands of colors" @ 512×384 becomes possible**, and (2) the CPU
never contends with video at *any* depth. It is modelled directly on the
**X68000 MiSTer** core, which already does this.

## Why Option A+ can't reach 16bpp (the wall)

The shared SDRAM gives one 16-bit word per bus slot, 4 slots / bus cycle. Even
with burst-2 (2 words/slot) the per-line ceiling is:

| mode | needed (words/line) | burst-2 @ 2 video slots | burst-2 @ 4 slots (CPU starved) |
|---|--:|--:|--:|
| 8bpp @ 640×480 | 320 | **400 ✓** | 800 |
| 8bpp @ 512×384 | 256 | **320 ✓** | 640 |
| 16bpp @ 512×384 | 512 | 320 ✗ | 640 (only by starving CPU) |

512×384 line = 80 bus cycles. 16bpp needs 512 words/line; burst-2 with a CPU
floor tops out at 320–480. The only single-controller way to clear it is
**burst-4** (4 words/access), which does **not** fit our 8-state, 65 MHz SDRAM
slot. → a wider/cached memory is required. That is what DDR3 provides.

## How the X68000 core does it (reference architecture)

Verified by reading `C:\Temp\mistercore\X68000_MiSTer`:

1. **Video lives in / is served from a wide, cached external path.** Graphics
   chips 2/3 are backed by **DDR3 via `rtl/ddram.sv`** — an **8-way
   set-associative cache**, **64-bit** DDR3 bus, **4-qword (16-word) burst** per
   miss (`ddram.sv:281–288`, `ram_burst<=8'd4`). On a hit the read is ~1 cycle;
   a miss pulls 16 words at once. Chips 0/1 instead sit in on-chip **dual-port
   BRAM** (`gvram_bram.vhd`) — CPU on port A, video on port B, **zero
   contention**.
2. **Line buffers** — ping-pong dual 1024×16 scanline BRAMs (`VLINEBUF.vhd`) plus
   per-plane 512-word row-prefetch caches (`gvram_ctrl.vhd` `CACHEMEMWN`).
3. **Coherency via CDC** — CPU writes (sysclk) invalidate the video-side cache
   through a toggle-synchroniser into the RAM clock domain
   (`gvram_ctrl.vhd:253–287`).
4. **Headroom** — 80 MHz DDR3 × 64-bit vs ~8 MHz pixel × 16-bit ≈ **10–40×**.

Key takeaway: **the bandwidth-hungry layer is moved off the CPU's memory bus
entirely**, and a small cache + bursts amortise DDR3 latency. We already have
its cheap counterpart (the ping-pong line buffer, commit `c273246`); Option B
adds the wide cached channel.

## Mac LC adaptation

The DDR3 port is **available and currently unused** in our core — `MacLC.sv:29`
ties `{DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD,
DDRAM_WE} = 0`. So we can light it up without fighting the framework.

Today VRAM is a 512 KB window in SDRAM (`addrController_top.v`: CPU
`$F40000…`→ word `$580000+`, video fetch `vid_sdram_word = $580000 +
v8_video_addr[21:1]`). The plan:

### Data path
```
CPU VRAM write ─┐
                ├─► DDR3 (master copy of VRAM) ──► video read cache ──► line buffer ──► pixel shifter
CPU VRAM read ──┘        (ddram.sv, ported)        (per-line/prefetch)   (existing)      (existing)
```

### Steps
1. **Port `ddram.sv`** from X68000 (it is self-contained: cache + burst + the
   `DDRAM_*` framework handshake). Wire the real `DDRAM_*` ports in `MacLC.sv`
   (replace the `=0` tie). Add the DDR3 clock to the PLL if needed (X68000 runs
   its DDR3 controller ~80 MHz; we can reuse `clk_mem`/a new tap).
2. **Relocate VRAM to DDR3.** Route the CPU VRAM decode (`selectVRAM`) and the
   video fetch to the new controller instead of the SDRAM `$580000` region.
   Free the SDRAM `$580000…$5BFFFF` window (or leave it dead). Update the
   download/clear path accordingly.
3. **Video fetch from the DDR3 cache.** `maclc_v8_video` already requests words
   via the line buffer; point its fetch at the DDR3 read port. Because the read
   is cached + bursts 8–16 words, one miss fills many line-buffer entries — this
   is where 16bpp's 512 words/line comes from. Keep the burst-2 SDRAM path as-is
   for everything else (RAM/ROM/disk).
4. **Coherency (the hard part).** CPU VRAM writes must reach video. Two options,
   easiest first:
   - **Write-through, no video cache of dirty lines:** CPU writes go straight to
     DDR3; the video read cache is *invalidated per scanline* (we re-fetch each
     line into the line buffer every frame anyway, so a whole-line invalidate at
     `hblank` is cheap and avoids fine-grained CDC). Verify against MAME that a
     1-frame-stale pixel never appears (line buffer is filled the line *before*
     display — a CPU write to the line being prefetched could tear; gate by
     filling from DDR3 which already has the write).
   - **X68000-style fine invalidate:** port the toggle-synchroniser CDC if
     per-line invalidate proves too coarse.
5. **16bpp enablement.** With the wide channel, raise the `maclc_v8_video`
   16bpp gate (currently treated as out-of-scope). Confirm the X-5-5-5 unpack
   (`maclc_v8_video.sv:338–342`) against MAME `v8.cpp` mode 4 and the 1280-byte
   stride.
6. **Sim model.** `verilator/` has no DDR3 model. Add a behavioural `sim_ddram`
   (latency + burst return) so the cache/fetch logic is exercisable; otherwise
   the whole channel is HW-only (worse than Option A+, which is at least
   arbiter-testable in sim).

### Bandwidth check (why it works)
16bpp @ 512×384 needs 512 words/line over an 80-bus-cycle line. A single DDR3
16-word burst (X68000's miss size) covers 16 line-buffer words; ~32 bursts/line
fill 512 words. At 80 MHz / 64-bit that is a rounding error of the available
bandwidth — the same 10–40× headroom the X68000 enjoys. The CPU's SDRAM bus is
**untouched** (video no longer competes for it at all).

## Risks / why this is deferred
- **Coherency bugs** are the classic failure mode (stale or torn VRAM). Needs
  careful MAME diffing.
- **Big HW-only surface** — both the DDR3 controller timing *and* the
  CDC/coherency are hard to fully validate without the `sim_ddram` model above.
- **DDR3 is shared with the HPS/framework.** Confirm the core's DDR3 budget and
  that `DDRAM_BUSY` backpressure is handled (X68000's `ddram.sv` has a watchdog
  + reset-drain we should keep).
- Effort: multi-day vs Option A+'s ~1 day. Only worth it for 16bpp or to fully
  remove video from the CPU bus.

## When to pick this up
- A user explicitly wants **"thousands of colors" (16bpp)**, OR
- Option A+'s 8bpp CPU-cost / disk-throttle-during-video proves unacceptable on
  HW and we want video completely off the SDRAM bus.

Reference files in `C:\Temp\mistercore\X68000_MiSTer`: `rtl/ddram.sv`,
`rtl/VIDEO/` (`vidcont.vhd`, `VLINEBUF.vhd`, `VTIMINGX68.vhd`),
`rtl/memory/`/`gvram_ctrl.vhd`/`gvram_bram.vhd`, `rtl/X68mmapCV.vhd`.
