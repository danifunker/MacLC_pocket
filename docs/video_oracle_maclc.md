# MAME video oracle — what the OS actually writes to VRAM per depth

**Purpose.** We have a bpp-dependent video "cut" on the FPGA core (1/2bpp full;
4bpp@640 ≈ 20%; 4bpp@512 all-white). A gradient diagnostic proved the fetch +
display + scaler pipeline is fine, so the cut is in the **data**: either the OS
writes a narrow framebuffer on our core, or our read/write addressing drops it.
Three different memory backends (SDRAM / DDR3 / BRAM) all show the identical cut,
which points upstream of the video engine.

This doc records the **ground truth from MAME `maclc`** (faithful LC hardware +
the same boot ROM + System 6.0.8): for each display depth, how wide/tall the OS
*actually* draws the framebuffer, and what a correct desktop looks like. If MAME
draws full-width 4bpp, then our core diverges and the bug is in what our core
reports to the OS at depth-set time (not the video datapath).

See also `docs/mame_compare.md` (the general MAME-compare process) and
`docs/handoff_video_bram_2026-06-07.md` (the cut investigation).

---

## Hardware scan layout (from MAME `v8.cpp::screen_update`, authoritative)

The V8 ASIC scans VRAM starting at **offset 0**, **fixed 1024-byte stride** for
1/2/4/8bpp; 16bpp uses an `hres`-word stride:

| depth | bytes read per line        | @640 (montype 6/1) | @512 (montype 2) | stride |
|-------|----------------------------|--------------------|------------------|--------|
| 1bpp  | `hres/8`                   | 80 B  / 40 w       | 64 B  / 32 w     | 1024 B |
| 2bpp  | `hres/4`                   | 160 B / 80 w       | 128 B / 64 w     | 1024 B |
| 4bpp  | `hres/2`                   | 320 B / 160 w      | 256 B / 128 w    | 1024 B |
| 8bpp  | `hres`                     | 640 B / 320 w      | 512 B / 256 w    | 1024 B |
| 16bpp | `hres*2` (vram16[y*hres+x])| (not a real mode)  | 1024 B / 512 w   | hres*2 |

Because the hardware scans these widths, a coherent MAME desktop **requires** the
OS to write at least this many bytes/line. Our core's CPU-write packing
(`addrController_top.v`) and video read (`maclc_v8_video.sv`) both assume exactly
this 1024-byte-stride layout, so the packing math matches MAME. → If our screen is
still cut, the OS must be writing less on our core.

---

## How the oracle is measured

Tooling in `verilator/mame/`:

- `run_mame_windowed.sh` — **interactive** boot (windowed) to set the depth via
  *Apple menu → Control Panel → Monitors → pick a depth*. The choice persists
  (MAME `nvram/maclc/egret` + the CHD `diff/`), so the next headless run comes up
  at that depth.
- `vram_extent.lua` — taps every CPU write to `$F40000..$FBFFFF` and reports the
  **framebuffer width** the OS draws. Method: the one-time boot VRAM clear writes
  *every* column uniformly (baseline); the *displayed* columns get written many
  more times (redraws/pattern/cursor). `FB_WIDTH` = last column whose write count
  clearly exceeds baseline. Timing-independent (no fragile frame windows).
- `snap.lua` — PNG snapshot of the rendered desktop at a frame (visual check:
  full-width? correct colors?).

### Selecting the DISPLAY SIZE (512×384 vs 640×480) — it's a machine-config, not the OS

The display resolution is the monitor **sense** value (`v8.cpp` PORT_CONFNAME
"Connected monitor", field tag `:v8:MONTYPE`): `0x06`=13″ RGB 640×480 (default),
`0x02`=12″ RGB 512×384, `0x01`=15″ Portrait 640×870. It persists in
`cfg/maclc.cfg` as:
```xml
<input>
  <port tag=":v8:MONTYPE" type="CONFIG" mask="15" defvalue="6" value="2" />
</input>
```
`value="2"` selects 512×384. (We set this directly; MAME accepts and re-saves it.
A Lua `field:set_value()` works at runtime — `set_montype.lua` — but does NOT
persist to cfg, so the cfg edit is what carries into an interactive session.)

Gotchas:
- MAME's screen bitmap stays **640×480**; a 512×384 montype renders into the
  **top-left 512×384**, rest black. Snapshots are 640×480 — read only the
  top-left active area.
- Switching montype makes the OS **reset depth to 1bpp** (depth is stored per
  monitor configuration). So after changing to 512×384 you must re-pick the depth
  in Monitors for each capture.
- 16bpp ("Thousands") ONLY fits VRAM at 512×384 (512·384·2 = 384 KB < 512 KB);
  at 640×480 it needs 600 KB and is not offered. So 16bpp ⇒ montype must be 512.

Run (headless capture, after the depth is set):
```bash
# extent
EXT_OUT=/tmp/vram_extent_4bpp.txt MAX_FRAME=2700 \
  verilator/mame/run_mame.sh -hard /private/tmp/goodroms/hd608.chd \
    -autoboot_script verilator/mame/vram_extent.lua
# snapshot
SNAP_AT=2600 MAX_FRAME=2650 \
  verilator/mame/run_mame.sh -hard /private/tmp/goodroms/hd608.chd \
    -autoboot_script verilator/mame/snap.lua \
    -snapname "maclc/depth4_f%i" -snapshot_directory /private/tmp/goodroms/snap
```

> Note: `FB_WIDTH` reads a few bytes short of the table value because the
> right-edge framebuffer columns receive fewer redraw writes than the interior —
> the histogram's "excess over baseline" stopping point is the reliable read.

---

## Results

### 1bpp — 640×480 (montype 6), VALIDATION baseline
- **Snapshot:** full-width B&W System 6.0.8 Finder desktop (`OpenRetroSCSI` vol).
- **Extent:** `FB_WIDTH ≈ 77–80 bytes/line` (≈ 40 words). Excess-over-baseline
  confined to cols 0–127; cols ≥128 at baseline (clear only). **Matches the table
  (80 B / 40 w).** Confirms the tap + the 1024-byte-stride model.

### 4bpp — 640×480 (montype 6), 16 Colors — **FULL WIDTH** ✅
- **Snapshot:** full-width 640px color Finder desktop (menu bar gains a "Color"
  menu). `depth4_f0000.png`.
- **Extent:** `FB_WIDTH = 317 bytes/line` → excess-over-baseline confined to cols
  0–319 (buckets 0–4), drops to clear-baseline at col 320 (bucket 5).
  **= 320 B / 160 words — exactly the table value. The OS draws full-width 4bpp.**
- **Decisive:** faithful LC hardware DOES draw full-width 4bpp. Our FPGA core
  shows only ~32 words at 4bpp@640 → **our core diverges**. And our CPU-write
  packing provably maps the OS's exact write pattern (offsets `L*1024 + (0..319)`)
  to `packed = L*160 + colw`, all visible — so the cut is NOT in the packing /
  read / display. On our core the OS must be writing narrow (config/depth-set) or
  the VRAM writes are dropped at commit. → next: instrument OUR core at 4bpp.

### 8bpp — 640×480 (montype 6), 256 Colors — **FULL WIDTH** ✅
- **Snapshot:** full-width 640px color desktop (green pattern, menu bar + Trash +
  volume icon span the full width). `depth8_f0000.png`.
- **Extent:** `FB_WIDTH = 637 bytes/line` → excess confined to cols 0–639
  (buckets 0–9), drops to clear-baseline at col 640 (bucket 10).
  **= 640 B / 320 words — exactly the table value. The OS draws full-width 8bpp.**
- Same conclusion as 4bpp: faithful HW draws full width; our core's cut is a
  divergence upstream of the (proven-correct) packing/read/display.

## 512×384 results (montype = 0x02, persisted in cfg/maclc.cfg)

The all-white symptom on our FPGA core is specifically **4bpp@512**, so the
512-wide oracle is the important one.

### 512×384 1bpp — Black & White — VALIDATION ✅
- **Snapshot:** 512×384 B&W desktop in the top-left of a 640×480 bitmap.
- **Extent:** `FB_WIDTH = 61 bytes/line` → excess confined to cols 0–127, baseline
  at col 128. **= 64 B / 32 words — exactly the table value.** Tap works at 512.

### 512×384 4bpp — 16 Colors — **FULL WIDTH** ✅  (our core = ALL WHITE ❌)
- **Snapshot:** full-width 512px color desktop (gray pattern + "Color" menu)
  filling the 512×384 active area. `v512_d4_f0000.png`.
- **Extent:** `FB_WIDTH = 253 bytes/line` → excess confined to cols 0–255
  (buckets 0–3), drops to clear-baseline at col 256. **= 256 B / 128 words —
  exactly the table value. The OS draws full-width 4bpp@512.**
- **Decisive for the worst symptom:** our FPGA core is ALL-WHITE at 4bpp@512, yet
  faithful HW writes the full 128 words/line. So nothing data-side is missing on
  the OS's part — the all-white is purely our divergence (narrow write or dropped
  commit), at exactly the width (128 w) our packing/read are sized for.
### 512×384 8bpp — 256 Colors — **FULL WIDTH** ✅
- **Snapshot:** full-width 512px color desktop filling the 512×384 active area.
  `v512_d8_f0000.png`.
- **Extent:** `FB_WIDTH = 509 bytes/line` → excess confined to cols 0–511
  (buckets 0–7), drops to clear-baseline at col 512. **= 512 B / 256 words —
  exactly the table value. The OS draws full-width 8bpp@512.**
### 512×384 16bpp — Thousands — **FULL WIDTH** ✅
- **Snapshot:** full-width 512px direct-color desktop filling the 512×384 active
  area. `v512_d16_f0000.png`.
- **Extent:** the framebuffer is 512 px × 2 B = **1024 B/line — it fills the ENTIRE
  1024-byte stride**, so there is NO off-screen column and the auto `FB_WIDTH`
  number is meaningless here. The tell is the histogram: **all 16 buckets are
  uniformly elevated (~85k–96k)**, including cols 960–1023 (84,575 vs the
  clear-only 57,344 seen in the 1/4/8bpp modes). **⇒ full 512-word / 1024-byte
  width.** (16bpp scans `vram16[y*hres+x]`, hres=512, so stride = 512 words = the
  same 1024 bytes — matches our 16bpp `words_per_line = 512`.)

---

## Summary table — MAME oracle (faithful LC hardware), ALL full width

| montype | depth | FB_WIDTH measured | table value | result |
|---------|-------|-------------------|-------------|--------|
| 640×480 | 1bpp  | ~77–80 B          | 80 B / 40 w   | full ✅ |
| 640×480 | 4bpp  | 317 B (→col 320)  | 320 B / 160 w | full ✅ |
| 640×480 | 8bpp  | 637 B (→col 640)  | 640 B / 320 w | full ✅ |
| 512×384 | 1bpp  | 61 B (→col 128)   | 64 B / 32 w   | full ✅ |
| 512×384 | 4bpp  | 253 B (→col 256)  | 256 B / 128 w | full ✅ |
| 512×384 | 8bpp  | 509 B (→col 512)  | 512 B / 256 w | full ✅ |
| 512×384 | 16bpp | all 16 buckets hi | 1024 B / 512 w| full ✅ |

(FB_WIDTH reads a few bytes short because the right-edge columns get fewer
redraw writes; the histogram drop-to-baseline column is the exact width. 16bpp
fills the whole stride so it has no baseline — uniform histogram = full width.)

## VERDICT

**Faithful LC hardware draws the framebuffer FULL WIDTH at every depth and both
resolutions.** There is nothing depth-dependent about how much the OS writes — at
4/8/16bpp the OS fills exactly the `h_active*bpp/16` words/line our packing and
fetch are already sized for.

Therefore our FPGA symptoms are a **pure divergence in our core**, NOT OS
behaviour and NOT (per the gradient diag) the fetch/display/scaler pipeline:
- 4bpp@640 ≈ 20% (≈32 of 160 words), 8bpp@640 cut, **4bpp@512 ALL-WHITE** while
  the OS writes the full 128/160/256/320/512 words.

So on our core, at >2bpp, the CPU's VRAM writes to the higher columns are **not
landing in the framebuffer the video reads** — either:
1. the OS, on *our* core, computes a narrower rowBytes (it reads some
   geometry/config from our hardware that differs from MAME) and never issues the
   high-column writes; or
2. the writes are issued but **dropped on our write/commit path** for >2bpp
   (`addrController_top.v` `vram_we`/packing, or the `vram_bram` byte-lane commit)
   — note 1/2bpp (≤128 words/line @512, ≤80 @640) work and 4bpp@512 (128 w) is
   the first to fully break, which smells like a per-cycle write-throughput or
   address-aliasing limit, not a width-math error (the math matches MAME).

### Next step (instrument OUR core, not MAME)
Re-run the **same extent measurement on our core** to decide (1) vs (2):
- In Verilator: tap CPU writes to `$F40000..$FBFFFF` (the `vram_we`/`vram_waddr`
  path in `addrController_top.v`) and log max column per line at 4bpp. If our OS
  only writes ~32 cols → case (1) (chase what geometry/config the OS reads from us
  that diverges from MAME — e.g. a Slot Manager / sResource / `via2`-readback the
  Monitors driver consults). If our OS writes all 128/160 cols but the video still
  shows ~32 → case (2) (the write is dropped between CPU and BRAM read).
- Reproducing 4bpp in sim needs a 4bpp PRAM + SCSI-HD boot (see handoff §9). The
  MAME `nvram/maclc/egret` PRAM captured here (depth bytes) can seed our egret PRAM.
