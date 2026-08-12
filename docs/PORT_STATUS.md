# MacLC → Analogue Pocket port status

**As of 2026-08-10. The core builds, loads on hardware, and BOOTS to the
"insert disk" screen.** The 68020 executes the real ROM, POST completes, the
Egret answers, video is correct and the mouse cursor renders. What it does not
yet do is boot an OS — there is no SCSI (`apf_blockdev` is unwritten) and
floppy mounting is unverified on hardware.

Source: `../MacLC_MiSTer` @ `5a75f9ba59f8f13a48e527e291877d8838400923`
(branch `ariel-ramdac-m10k`). Imported as a flat snapshot — no upstream git
history. To diff any file against upstream:

```bash
git -C ../MacLC_MiSTer show 5a75f9b:rtl/swim.v
```

---

## Toolchain

| | Version | Notes |
|---|---|---|
| **Quartus Prime Lite** | **18.1.0** (build 625) | Runs in WSL. Note: this is 18.1.0, NOT the 18.1.1/646 the docs used to demand — 18.1 Update 1 is not offered for Linux. The hazard 18.1.1 was supposed to avoid (an IP upgrade prompt regenerating `mf_pllbase` and discarding the clock plan) **does not occur**: the PLL builds at 65 / 65 / 32.5 / 15.66265 MHz as intended. Verified in the fit report on every build. |
| **Verilator** | **5.020** | For `scripts/lint.sh` and the sim harness. |

Full build, ~5m30s:

```bash
export PATH=/home/dani/intelFPGA_lite/18.1/quartus/bin:$PATH
cd src/fpga && quartus_map ap_core && quartus_fit ap_core && quartus_asm ap_core && quartus_sta ap_core
cd ../.. && bash scripts/package.sh && cp info.txt dist/Cores/danifunker.MacLC/
```

## Current fit (2026-08-10)

| | used | available |
|---|---:|---:|
| ALMs | 10,135 | 18,480 (55%) |
| M10K | 248 | 308 (81%) |
| DSP | 12 | 66 (18%) |
| Pins | 224 | 224 (100%) |

**Timing: zero negative slack across all four corners** — and as of the SDRAM
constraint work below, that statement finally *includes* the memory interface.
It did not before.

---

## ★ The SDRAM timing hole (fixed 2026-08-10) — read this before touching memory

This was the single largest defect in the port and it hid behind a green light
for weeks. **The `dram_*` pins had no timing constraints of any kind.** The APF
core-template ships `src/fpga/core/core_constraints.sdc` as a stub; MiSTer's
equivalent lived in `sys/sys_top.sdc`, which the port did not carry over.

Consequences, all of which were observed on hardware:

- The Fitter had no timing goal for the SDRAM pins and placed them freely.
- **STA never analysed them.** "0 negative slack" was *silence*, not health.
  Four consecutive builds were reported as clean while the read path was
  failing by 5 ns.
- Every recompile reshuffled placement into different pin delays, so the
  interface was marginal in a way that **changed build to build**. Video
  corruption appeared, vanished and returned after rebuilds that touched
  nothing in the memory path. That build-to-build instability is the
  fingerprint — if you ever see it again, suspect constraints, not logic.
- The old SDC additionally declared all four PLL outputs **mutually
  asynchronous**, including `clk_mem` and the clock driving `dram_clk`. Those
  are two phase taps of one VCO; cutting them would have voided the I/O
  constraints even if they had existed.

What the fix consists of (all in `core_constraints.sdc` unless noted):

1. `set_input_delay` / `set_output_delay` on `dram_dq` and the command group,
   adapted from Pocket-Amiga (same SDRAM part, same board — the delay figures
   are board/chip properties, not frequency dependent).
2. `general[0]` (clk_mem) and `general[1]` (dram_clk) moved into **one** clock
   group.
3. `-add_delay` on the second of each min/max pair. Without it Quartus
   *replaces* the previous delay on that port instead of adding to it. The
   reference core omits this and silently loses half of every pair.
4. `set_multicycle_path ... -hold -end 1` to accompany the `-setup -end 2`.
   **This is not optional.** The setup multicycle moves the latch edge out one
   period, which drags the hold check a full period tighter. Adding only the
   setup line took the same paths from −5.1 ns setup to −6.6 ns *hold*. The
   reference core omits this too.
5. `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` on the `dram_*` pins in
   `ap_core.qsf` — there were none, so capture flops sat in core fabric.
6. `dram_clk` phase **90°** (`phase_shift1 = 3846 ps`), not 180°.

On that last point: 180° was tried, on the reasoning that MiSTer's
`altddio_out(datain_h=0, datain_l=1)` produced an inverted clock. That is
reasoning by analogy and it made things worse. With constraints in place it is
measurable. At 65 MHz (T = 15.38 ns):

| φ | read budget `T − φ − tAC` | command budget `φ − 2.0` |
|---|---|---|
| **90°** | **5.63 ns** | 1.85 ns |
| 180° | 1.79 ns | 5.69 ns |

Every failing path was `dram_dq[*] → pocket_sdram|dout[*]` (reads); no command
path failed. 90° spends the budget where it is needed. **Treat the phase as a
measured quantity — re-check that slack in `ap_core.sta.rpt` after any change
to the PLL, the controller, or the pin assignments.**

---

## Descriptor / packaging lore (learned the hard way on hardware)

The Pocket rejects the whole core descriptor on any violation and reports only
`Load error in 'core': General error` **with a blank About screen**. The blank
info screen is not a second bug — it is the same rejection. `scripts/check_json.py`
encodes every rule below; run it before every flash.

- **`shortname` is used to build filesystem paths.** It must match the core
  half of the `Cores/<author>.<shortname>` directory name, and must not contain
  spaces. `"Macintosh LC"` against a directory of `danifunker.MacLC` was almost
  certainly the load error that blocked first boot; `"MacLC"` fixed it.
- Persisted interact values live at `/Settings/<author>.<shortname>/Interact/`.
- **Option registers must be at `0xF0000000`, not `0xF1000000`.** With the
  registers at `0xF1xxxxxx` **no interact write ever reached the core** — every
  menu item was inert. Moving them to `0xF0` (matching Pocket-Amiga) fixed all
  of them at once. The template documents only `0xF8xxxxxx` as reserved, so the
  mechanism is not understood; it is empirical but reproducible.
- `.rbf_r` means bit-REVERSED, not renamed. `scripts/package.sh` does it.
  Known-good header: 128 bytes of `0xFF`, then `56 56 56 56 6c 2f`.
- Interact writes are **read-modify-write**: mask bits set to 1 are *preserved*,
  bits set to 0 are writable. The core needs working read support at each
  address — returning one register's value for the whole window is wrong.
- `"messages": []` in `interact.json` **is legitimate** — the core-template
  ships it. An earlier note here claimed otherwise; that was wrong.
- Interact variable ids should ascend.
- `reset_n` (the APF host reset) is held low while the OS loads data slots and
  writes interact defaults, and released with the `[0011 Reset Exit]` host
  command. It was declared at import and wired to nothing but `status_running`,
  so the machine ran before setup finished. It is now in the machine's reset.

## Verification actually performed

| check | result |
|---|---|
| `scripts/lint.sh` (Verilator over rtl + core) | clean |
| `scripts/check_hierarchy.py` | 52 files, 60 modules, no dangling refs |
| `scripts/check_json.py` | clean |
| Quartus fit + STA | clean, incl. SDRAM (see above) |
| **Hardware** | **boots to the "?" floppy screen with mouse cursor** |

Files audited byte-for-byte against MiSTer upstream and found **identical** —
useful because it rules them out: all of `rtl/egret/` (12 files, incl.
`egret_wrapper.sv`, `m68hc05_core.sv`, firmware), `rtl/via6522.sv`,
`rtl/ariel_ramdac.sv`, and `rtl/addrDecoder.v` (its apparent diff is CRLF only).

---

## Not done

### 1. `apf_blockdev` — SCSI disks. **Blocking for booting an OS.**

MiSTer's `hps_io` block-device protocol has no APF equivalent. The core must
*ask* the OS to move data with `target_dataslot_read`/`_write` and wait for
`target_dataslot_done`. A 256 MB `.hda` cannot be preloaded, so this is the
only path. `core_top.v` currently holds all the target-command registers idle.
PRAM save-back needs the same machinery.

### 2. Audio — silent on hardware, cause not yet found

The chain is wired (`asc_sample_l/r` → `AUDIO_L/R` → `mac_audio` → I2S), but
nothing has ever been heard except an initialisation click.

**The prime suspect is the I2S shifter in `core_top.sv`.** The core-template's
`audgen` block is a **stub** — it generates MCLK/SCLK/LRCK but hardwires
`audgen_dac` to 0 and never shifts any data. The shifter in this core was
therefore written from scratch and has never been validated against anything.
Known issue in it: I2S expects data to start **one SCLK after** the LRCK edge;
this implementation starts data on the same edge, which is left-justified
format, not I2S. Also `mac_audio` crosses from `clk_sys` into the `audgen_sclk`
domain unsynchronised.

### 3. Floppy — unverified on hardware

Mounting a disk on hardware appeared to hang the core; not yet reproduced or
diagnosed. Supported images (from the MiSTer core, all **read-only** — there is
no write datapath, and the drive reports write-protected deliberately):
800K GCR and 1.44 MB MFM, raw or DiskCopy 4.2 (the DC42 header-skip lives in
the download path). `data.json` accepts `.dsk` and `.img` up to 1,474,560 bytes.

### 4. Smaller

- **`clk_pix_90`** is still just `clk_pix`; `mf_pllbase` outclk_4 is free.
- **Data-slot `parameters` bitfields are now documented**, not guesses:
  bit 0 user-reloadable, bit 1 core-specific (vs platform-common), bit 2
  filename-from-slot-0, bit 3 read-only, bit 5 init nonvolatile to 0xFF,
  bits [25:24] platform index. Our slots use `1` = user-reloadable, common
  lookup in `/Assets/maclc/common/`.
- **Cold-boot ROM load was unreliable** before `reset_n` was wired; re-verify.
- `verilator/sim.v` has not been rebuilt since the machine top gained
  `pram_reset` / `test_pattern` ports.

## Debug facilities added during bring-up

- **Video Test Pattern** (interact id 104): drives `maclc_v8_video`'s built-in
  synthetic pattern generator, whose control pins were left unconnected at
  import. ★ **It is a palette INDEX**, not direct RGB — the path is
  `v8_video → palette_addr → ariel_ramdac → palette_data → VGA_*`. Once the
  guest programs a flat palette the pattern maps to a single colour and
  disappears. **It is only a valid witness while the machine is halted.**
- **Reset PRAM** (interact id 102): genuinely zeroes the Egret's `pram[]` via
  `pram_load_*`. Those ports were tied off at import (`pram_ready` hardwired 1),
  so the menu item previously did nothing but an ordinary reset. `egret_wrapper`
  requires loads to land *before* `pram_ready` rises, so the FSM drops it for
  the ~8 µs of zeroing, well inside the ~2 ms reset stretch.

## Suggested order from here

1. **`apf_blockdev`** — without it the machine can never boot an OS.
2. **Audio** — start from the I2S framing offset above.
3. **Floppy on hardware** — reproduce the hang with a known-good 800K image.
4. Rebuild `verilator/sim.v` against the current machine top.
