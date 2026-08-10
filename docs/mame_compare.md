# Comparing the LC core against MAME (ground truth)

MAME's `maclc` driver is the ground-truth Macintosh LC. When our core diverges
(wrong RAM sizing, a stuck boot, missing video, a peripheral that behaves
differently), the fastest way to find the cause is to run the *same* ROM in MAME
and diff its behaviour against ours. This doc captures the reusable process and
the (many) gotchas. Tooling lives in `verilator/mame/`.

## Prerequisites

- **MAME binary:** `/opt/homebrew/bin/mame` (v0.287+). Source checkout at
  `~/repos/mame` — driver `src/mame/apple/maclc.cpp`, V8 ASIC `v8.cpp`, Egret
  `egret.cpp`, the HLE ADB device `macadb.cpp`.
- **ROMs (verified good):** `/private/tmp/goodroms/maclc/` — `350eacf0.rom`
  (== our `boot0.rom`) plus the Egret HC05 ROMs. Run with `-rompath /private/tmp/goodroms`.
- Our side: `verilator/cpu_trace.log` (68K instruction trace) and
  `./obj_dir/Vemu --screenshot N --stop-at-frame N+1` for framebuffers.
- Default config we validate against: **`-ramsize 2M`** (matches our
  `configRAMSize=$24`, 640x480). Also exercise `-ramsize 10M` before trusting
  the SIMM path.

## The tools (`verilator/mame/`)

| file          | purpose |
|---------------|---------|
| `run_mame.sh` | wrapper: headless `maclc`, correct flags, env for ROMPATH/RAMSIZE. |
| `tap.lua`     | read/write memory tap on a maincpu address range → file (frame/PC/data). |
| `snap.lua`    | PNG snapshots every N frames / at a frame, for framebuffer compare. |
| `trace.dbg`   | debugger script: full `maincpu` execution trace → `/tmp/maincpu.tr`. |

## Recipes

### 1. Framebuffer compare
```bash
verilator/mame/run_mame.sh -autoboot_script verilator/mame/snap.lua \
  -snapname "maclc/f%i" -snapshot_directory /private/tmp/goodroms/snap \
  SNAP_AT=700        # (env before the command, or: SNAP_EVERY=100)
```
Compare `/private/tmp/goodroms/snap/maclc/f700.png` to our
`verilator/screenshot_frame_0700.png` (dump per-pixel B/W/. with PIL in python3).

### 2. What value does MAME's hardware return here? (memory tap)
When our core reads/writes a register differently, tap it in MAME to get the
ground-truth value + the PC doing it:
```bash
TAP_LO=0xf40000 TAP_HI=0xf40003 TAP_MODE=w TAP_OUT=/tmp/vram.txt \
  verilator/mame/run_mame.sh -autoboot_script verilator/mame/tap.lua
```
`TAP_MODE` = `r`, `w`, or `rw`. Example uses: VRAM corner writes (`$F40000`),
VIA shift register (`$F01400`), NCR5380 (`$F10010`), `$17A`/other low-mem globals.

### 3. Full maincpu execution trace (the divergence finder)
```bash
verilator/mame/run_mame.sh -debug -debugscript verilator/mame/trace.dbg \
  -seconds_to_run 12
# -> /tmp/maincpu.tr  (5M+ lines for ~12 s of boot)
grep -c "^00A2FFCC:" /tmp/maincpu.tr      # NB: 8-digit 00Axxxxx PCs
```

### 4. Find the exact divergence (PC-stream diff)
Both traces converge on the same code until one branch differs (driven by a
divergent hardware read). Extract pure PC streams and diff backward from a known
common point:
```bash
# ours (strip "[Fnnn] 00" prefix); mame (strip trailing ":")
sed -n 'A,Bp' verilator/cpu_trace.log | sed -E 's/.*\] 00([0-9A-F]{6}):.*/\1/' > /tmp/ours_pc.txt
sed -n 'C,Dp' /tmp/maincpu.tr        | sed -E 's/^00([0-9A-F]{6}):.*/\1/' | grep -E '^[0-9A-F]{6}$' > /tmp/mame_pc.txt
tail -r /tmp/ours_pc.txt > /tmp/ours_r.txt; tail -r /tmp/mame_pc.txt > /tmp/mame_r.txt   # macOS reverse
paste /tmp/mame_r.txt /tmp/ours_r.txt | awk '$1!=$2{print "DIVERGE @"NR": MAME="$1" OURS="$2}' | head
```
The first divergence's branch input is the hardware value to chase (tap it, §2).

## GOTCHAS (each cost real time — heed them)

1. **macOS has no `timeout`.** Bound MAME runs with `-seconds_to_run N`, not
   `timeout`. (`timeout … mame …` exits 127 and does nothing.)
2. **Video:** use `-video opengl -nowindow`. `-video none` yields **no** snapshot.
3. **The debugger's default CPU is the Egret HC05, not the 68020.** `bpset`/
   `trace`/`wpset` without a CPU target hit the HC05. Target `maincpu`
   explicitly (`trace file,maincpu`). 68020 opcode-PC breakpoints often don't
   fire (prefetch/cache) — **data watchpoints / memory taps do.**
4. **Headless debugger `printf`/`logerror` don't reach any capturable sink.**
   Don't rely on them. Use a **Lua tap that writes a file** (`tap.lua`), or the
   `trace` command (which does write its file).
5. **Lua tap install timing:** install on the **first `register_frame_done`**,
   NOT `register_start`/`machine_reset` — those fire before the autoboot script
   loads, so the tap silently never installs (0 hits). **Keep the tap handle in
   a Lua table** or it gets garbage-collected and stops firing.
6. **MAME maincpu trace PCs are 8-digit `00Axxxxx`.** Grepping `^A01484:` finds
   nothing; use `^00A01484:`. (This one masquerades as "MAME never runs X".)
7. **Address aliasing:** 68020 mask is `global_mask(0x80ffffff)` — bits 30-24 are
   ignored, so `$50F40000` ≡ `$00F40000` (matches our 24-bit decode). Our trace's
   `@`-annotation shows the full 32-bit EA; mask to 24 bits when comparing.
8. **V8 `LOG_RAM` is compile-gated** (`VERBOSE=0` in `v8.cpp`), so `-verbose`
   won't print `ram_size()`. Read RAM sizing via a tap or the debugger instead.
9. **Run our sim ONCE, then analyse logs** (`cpu_trace.log` is ~1.5 GB). Don't
   re-run the Verilator sim repeatedly to "watch" — it's slow; capture and grep.

## Worked examples from this repo's history

- **Rounded corners / stuck boot:** tapped `$F40000` (corner writes), then
  `maincpu` trace + PC-diff located the divergence at `$A0146E` (a status bit),
  traced through the VIA-SR Egret transport and NCR5380 arbitration. Led to the
  ADB open-collector-loopback and SCSI upper-byte-write fixes. See
  `docs/resume_060326_rounded_corners_trace.md`.
- **ADB device bring-up:** tapped the VIA SR (`$F01400`) to capture MAME's exact
  Egret/ADB byte exchange ($2C/$3C Talk, `$80` responses) and matched our
  `rtl/adb_device.sv` enumeration against it.
