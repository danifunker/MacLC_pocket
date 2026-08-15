# Macintosh LC for the Analogue Pocket (openFPGA)

An emulation core for the **Apple Macintosh LC** running on the Analogue Pocket.

This is a port of the [MacLC MiSTer core](https://github.com/danifunker/MacLC_MiSTer),
which is based on the MacPlus MiSTer core by Sorgelig, originating from the
[Plus Too project](http://www.bigmessowires.com/plus-too/). The core emulates a
Motorola 68020 CPU (via a modified TG68K core), the V8 gate array (video/glue), the
Egret (HC05) system controller with its original firmware, SWIM, SCSI, and ADB.

> **Beta** (v0.9.0, 2026-08-15). The core boots System 6.0.8 and System 7.1
> to the desktop and plays games — with the known issues listed below, the
> headline one being that **PRAM does not save**: the machine starts
> black-and-white every launch, and you set 256 colours in Monitors after
> boot.

## Status (2026-08-14, beta)

### Working (verified on hardware)

- **Boots to the desktop** from a cold start with no menu work:
  `boot0.rom` and `maclc.hda` auto-load at launch, the machine POSTs, and
  System comes up. The desktop starts black-and-white — open **Monitors**
  and pick 256 Colors; the setting lasts until power-off (see Known
  issues). Games like Prince of Persia run.
- **Controller setup menu** (new in this beta) — "Startup input mode"
  (mouse mode is now the power-on default) and per-button key assignment
  (dropdown choices plus raw-keycode sliders) in the core's Interact menu
- **SCSI hard disks** — two slots, reads and writes, hot-mount via the menu
- **CD-ROM (ISO)** — read-only data discs on SCSI ID 3, `maclc.iso`
  auto-mounts
- **Floppy: 1.44 MB MFM images** — mount and read via the Floppy slot
  (`.dsk`/`.img`, raw or DiskCopy 4.2)
- **Video** — 512×384 at 1/2/4/8 bpp, true 4:3, plus Analogue **Display
  Modes** (the CRT Trinitron profile suits this machine well)
- **Sound**, **keyboard/mouse** via the Pocket's controls (ADB model),
  **2 MB / 10 MB** memory configurations, RTC set from the Pocket's clock
  at launch

### Known issues (beta)

- **800K GCR floppy images crash or hang the system** — mount works, but
  use can end in an F-Line bomb or a freeze; ejects can crash the Finder.
  1.44 MB MFM images can very occasionally do the same. Under active
  investigation; prefer MFM images or the hard disk meanwhile.
- **Restart from the Special menu does not come back** — power the Pocket
  off and on instead.
- **Not every boot reaches the Finder** — in this beta roughly one boot in
  four fails during startup (an error dialog, a bomb, or a hang at the
  extensions bar). Power the Pocket fully off and boot again — a full
  power cycle is more reliable than relaunching the core — and once the
  Finder is up, the machine is stable for hours of use.
- **PRAM does not save** — in-guest settings (colour depth, volume, mouse
  speed, clock) reset every launch, and the machine always starts
  black-and-white. Set 256 Colors in Monitors after boot (it sticks until
  power-off), or drop a depth-switching utility into the Startup Items
  folder of your boot disk to make it automatic.
- **Rare video glitching** — a transient artifact inherited from the
  MiSTer lineage, under investigation.
- **Floppies are read-only** (by design for now — the drive reports
  write-protected, so the OS never attempts a write).

### Cut from the MiSTer core (Pocket resource budget)

The Pocket's FPGA is roughly half the size of the DE10-Nano's. The following
MiSTer-core features are **not present** and are not planned unless the budget
math changes: 16bpp video, 640×480 mode, the second (external) floppy drive,
CD audio / bin+cue (the ISO data CD-ROM above is what fits), and the BlueSCSI
Toolbox file transfer. See `docs/PORT_STATUS.md` for the arithmetic.

## SD card setup

```
/Cores/danifunker.MacLC/            <- contents of dist/Cores/danifunker.MacLC/
/Platforms/                         <- maclc.json + _images/maclc.bin
/Assets/maclc/common/boot0.rom      <- 512 KB Mac LC ROM (required)
/Assets/maclc/common/maclc.hda      <- hard disk 1 (optional, auto-mounts)
/Assets/maclc/common/maclc2.hda     <- hard disk 2 (optional, auto-mounts)
/Assets/maclc/common/maclc.iso      <- CD-ROM ISO (optional, auto-mounts)
```

- **`boot0.rom`** — the 512 KB Macintosh LC ROM, version `$67C`, checksum
  `$350EACF0`. Required; the core will not start without it.
- **`maclc.hda`** — if a file with exactly this name exists, it is automatically
  attached to **Hard Disk 1** (SCSI ID 0) at every core launch — no menu work.
- **`maclc2.hda`** — same, for **Hard Disk 2** (SCSI ID 1). Leave the file off
  the card to leave the slot empty ("only one disk" = only one file).
- Disk images with other names (`.hda` / `.img` / `.vhd`) can be attached
  manually through the core's menu (Hard Disk 1 / Hard Disk 2 slots).
- Floppy images (`.dsk` / `.img`, raw or DiskCopy 4.2) go anywhere on the card
  and are attached via the Floppy slot.

*(A practical beta note: the hard-disk image is writable, and a crash while
the guest is writing can damage its filesystem — after which boots may
become inconsistent. Keep a backup of your `.hda` and restore it if the
machine stops reaching the Finder reliably.)*

Hard-disk images use the raw SCSI format (as used by SCSI2SD / BlueSCSI,
documented [here](http://www.codesrc.com/mediawiki/index.php?title=HFSFromScratch)):
an Apple Driver Descriptor Map, partition map, `Apple_Driver43` driver
partition, and an HFS volume. Images that boot on the MiSTer core are the
right kind.

## Memory

**2 MB** (motherboard only) or **10 MB** (2 MB + 8 MB SIMM), selectable in the
core menu ("Memory", applied by "Reset & Apply"). The choice persists across
launches. A 10 MB cold boot runs the ROM's full destructive RAM march and takes
noticeably longer — that is the real machine's behavior.

## Building from source

Built with **Intel Quartus Prime Lite 18.1.1** (build 646) targeting the
Pocket's Cyclone V `5CEBA4F23C8`:

- Project: `src/fpga/ap_core.qpf` (top: `apf_top` → `core_top` → the machine)
- Package for the card: `bash scripts/package.sh` → `dist/Cores/danifunker.MacLC/`
- Structural check without a toolchain: `python scripts/check_hierarchy.py rtl src/fpga`

Start with `docs/PORT_STATUS.md` for what the port has and has not done, and
`docs/boot_problems.md` for the measured history of every boot/SCSI defect
found and fixed (it is quite a story).

## AI Disclaimer

This core is developed with heavy use of AI tooling, including Claude (Fable,
Opus, Sonnet models) and GPT (Codex), and borrows from MAME. A physical
Macintosh LC was also used throughout development, and the MiSTer parent core
is the continuous reference implementation.

## MAME-sourced components

- SCSI subsystem
- Egret (using the original Egret firmware, baked into the core), including ADB
- Floppy (SWIM)
- V8 (video subsystem)
- ASC (sound subsystem)

## Credits

- **MacPlus MiSTer** core by Sorgelig
- **Plus Too** by Steve Chamberlin (Big Mess o' Wires)
- Mac LC MiSTer core and Pocket port by
  [danifunker](https://github.com/danifunker) and
  [alanswx](https://github.com/alanswx)

## Controls

Two modes, toggled with **Select**:

- **Mouse mode** (the power-on default, configurable): the D-Pad moves the
  cursor and **A** is the mouse button. **The toggle only re-purposes the
  D-Pad and A** -- every other button keeps typing its key, so Command
  chords work while pointing. Feedback is implicit: if the cursor moves,
  you are in mouse mode.
- **Keyboard mode**: D-Pad = arrow keys, **A** = Return, **B** = Space,
  **X** = Shift, **Y** = N, **L** = Escape, **R** = Q, **Start** = Command.

The classic Mac mouse has one button, so nothing is missing from a single
click button.

**Remapping** (new in this beta, lightly tested): the core's Interact menu
has "Startup input mode" (which mode is active at power-on) and a
"Button ... key" dropdown per button. Picking **Custom** in a dropdown
makes that button send the raw keycode from its "... custom code" slider,
for keys not on the dropdown list (Y and Start are dropdown-only in this
beta). The **Interrupt (NMI)** action had to sit out this beta (core-menu
size limit); it returns in a future build.

Custom-code sliders take PS/2 Scan Code Set 2 "make" codes (single-byte
keys only — the arrow keys are extended codes and can't be entered yet):

| Key | Code | Key | Code | Key | Code | Key | Code |
|-----|------|-----|------|-----|------|-----|------|
| A | 0x1C | J | 0x3B | S | 0x1B | 1 | 0x16 |
| B | 0x32 | K | 0x42 | T | 0x2C | 2 | 0x1E |
| C | 0x21 | L | 0x4B | U | 0x3C | 3 | 0x26 |
| D | 0x23 | M | 0x3A | V | 0x2A | 4 | 0x25 |
| E | 0x24 | N | 0x31 | W | 0x1D | 5 | 0x2E |
| F | 0x2B | O | 0x44 | X | 0x22 | 6 | 0x36 |
| G | 0x34 | P | 0x4D | Y | 0x35 | 7 | 0x3D |
| H | 0x33 | Q | 0x15 | Z | 0x1A | 8 | 0x3E |
| I | 0x43 | R | 0x2D | 0 | 0x45 | 9 | 0x46 |

Space 0x29 · Return 0x5A · Esc 0x76 · Tab 0x0D · Backspace 0x66 ·
Shift 0x12 · Command 0x11 · Control 0x14 · period 0x49 · comma 0x41
