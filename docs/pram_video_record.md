# The LC's saved video-mode record in XPRAM — decoded, and the B&W-boot root cause

**2026-08-14.** This page settles the PRAM colour-boot mystery (RESUME 08-14f
ledger). Every claim below is a measurement, not a theory — the runs live in
`scratch/pram/` and the harness pieces are `verilator/mame/pram_depth.lua`
(MAME side) and the seeded Verilator boots (RTL side).

## The record layout (XPRAM offsets, = Egret HC05 RAM $100+off)

| off | meaning | example |
|-----|---------|---------|
| 0x58 | saved mode ID for the built-in monitor: $80=1bpp, $81=2bpp, $82=4bpp, $83=8bpp, $84=16bpp | $83 |
| 0x59 | $A0 \| match-nibble (validity family + machine match) | $AA |
| 0x5A | match-nibble, raw | $0A |

**match-nibble = montype \| (0x08 if VRAM == 256K else 0)**

montype (monitor sense): 1 = 15" portrait 640×870, 2 = 12" RGB 512×384,
6 = 13" RGB 640×480.

So a record written on a 512K-VRAM machine at the 512×384 monitor reads
`83 A2 02`; the SAME setting on a 256K-VRAM machine reads `83 AA 0A`.
**Bit 3 of the match-nibble is the VRAM size.** That bit was the entire
B&W-boot bug: the shipped seed was captured from a real MiSTer guest
(512K VRAM → `A2 02`), while this fork presents a 256K SIMM (buildAW), so
the ROM saw a foreign record and discarded it every boot.

## ROM behavior at video-driver open (all watched live in MAME 0.289)

The driver open writes the pseudovia Video Config register ($F26010,
pseudovia reg 0x10; our RTL: `rtl/pseudovia.sv` "$10: Video Config",
`data[2:0]` = depth code 0..4 = 1/2/4/8/16bpp) from **PC A4B7BC**:

- **Record matches the machine** → writes mode from 0x58 (e.g. `$13` =
  8bpp) and PRESERVES the record in PRAM.
- **Mismatch** (wrong montype OR wrong VRAM bit) → writes `$10` (1bpp),
  and REWRITES the record to the machine's own identity with mode $80:
  observed `83 A2 02 → 80 A1 01` (portrait run) and `→ 80 AA 0A`
  (256K run).

★ **A diskless boot ends 1bpp either way.** After the driver open, the
flashing-"?" phase writes Video Config `$00` again (PCs A09FE6 then the
A0A08A/A0A0BA blink pair, forever). The acceptance witnesses on a diskless
boot are (a) the transient `$13` write from A4B7BC ~F265-279, and (b) the
record surviving in PRAM afterwards — NOT the final screen. Judging
acceptance by the "?"-screen depth is the trap this page exists to prevent.
The saved depth becomes user-visible only once an OS boots to the desktop.

## The evidence matrix (scratch/pram/, 2026-08-14)

| run | machine | seed 0x59/0x5A | driver-open write | record after |
|-----|---------|----------------|-------------------|--------------|
| mameM1b | 512K, montype 2 | A2/02 (512K) | **$13 (8bpp)** | preserved |
| mameM2 | 256K, montype 2 | A2/02 (512K) | $10 (1bpp) | **rewritten 80/AA/0A** |
| mameM3 | 256K, montype 2 | AA/0A (256K, patched) | **$13 (8bpp)** | preserved |
| (M1) | portrait (montype set wrong) | A2/02 | $10 | rewritten 80/A1/01 |
| runB (Verilator) | Pocket machine, 2 MB, diskless | A2/02 (512K) | 1bpp throughout (wpl=32) | — |
| runC (Verilator) | Pocket machine, 2 MB, System 7.1 on SCSI | AA/0A (patched) | **8bpp — wpl 32→256 between F472 and F513** (sim driver open; MAME's was F265 — sim POST runs the Egret handshake at real pace), sustained through the System handoff (RAM PCs by F960) to the desktop | colour desktop |

Verilator timing note: the two harnesses agree on the DECISION but not the
frame number of the driver open — do not port frame constants between them.
The `EGRET_XPRAM_*`/`EGRET_PRAM_COPY` witnesses (egret_wrapper.sv,
SIMULATION-only) show the startup order directly: HC05 firmware clear at
PC 0f95 zeroes the record bytes, then the post-clear boot-copy lands the
seed (`xpram[58] <= 83, [59] <= aa, [5a] <= 0a`).

MAME notes: montype must be set via `cfg/maclc.cfg` (`:v8:MONTYPE` port
`value=`) — `field:set_value()` from Lua landed the wrong raw value on
0.289. 256K VRAM is modeled with the validated write-alias taps
(`vram_256k.lua` logic, folded into `pram_depth.lua` under `V256=1`).
The romset was rebuilt from repo sources into `/private/tmp/goodroms/`
(boot0.rom → `maclc/350eacf0.rom`; `rtl/egret/egret_rom.hex` →
`egret/341s0851.bin`, SHA-exact vs MAME's manifest, also copied to
`341s0850.bin` since maclc selects that BIOS tag — checksum warning is
expected and harmless, and it means MAME's Egret runs OUR firmware).

## What this exonerates

- **Seed delivery on the Pocket was never broken.** buildBC's bytes reach
  the netlist, buildBD's config-time loader streams them through the
  MiSTer-proven `pram_load_*` port, and `egret_wrapper`'s pram write port
  is unconditional (no reset gate) — all irrelevant, because the guest was
  REJECTING the content, not missing it. The seeded Verilator boot
  reproduces the 1bpp choice with the 512K seed on the exact Pocket
  machine (runB).
- MLAB power-up init: already exonerated by buildBD, doubly moot now.

## The fix

`rtl/egret/egret.pram` bytes 0x59/0x5A patched `A2/02 → AA/0A`.
`scripts/nvr_to_pram.py` now applies the 256K fixup automatically when
baking any future MiSTer `.NVR` capture (`--keep-512k` to opt out), so the
bug cannot silently return through the import path. The V256 JTAG lever /
`vram_force_512k=1` world would want the unpatched record — if 512K VRAM
ever ships as a config, the seed must switch with it.

Open ends tracked in RESUME.md: XPRAM 0x81 (a slot-record byte the ROM
never touched in any diskless run — System-side semantics unknown), and
the buildBE rebuild (no Quartus on this machine).
