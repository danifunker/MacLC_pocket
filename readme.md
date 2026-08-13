# Macintosh LC for the Analogue Pocket (openFPGA)

An emulation core for the **Apple Macintosh LC** running on the Analogue Pocket.

This is a port of the [MacLC MiSTer core](https://github.com/danifunker/MacLC_MiSTer),
which is based on the MacPlus MiSTer core by Sorgelig, originating from the
[Plus Too project](http://www.bigmessowires.com/plus-too/). The core emulates a
Motorola 68020 CPU (via a modified TG68K core), the V8 gate array (video/glue), the
Egret (HC05) system controller with its original firmware, SWIM, SCSI, and ADB.

> **Work in progress.** This core is under active development and is not yet
> a usable computer — see the status below before flashing expectations.

## Status (2026-08-12)

### Working (verified on hardware)

- **Cold boot to the flashing-`?` screen** — power on, launch the core, the machine
  runs its full ROM POST (including the cold RAM march) and waits for a boot disk
- **ROM loading** — `boot0.rom` is auto-loaded from the SD card at every core launch
  and lands in SDRAM byte-perfect (verified by an on-fabric read-back oracle)
- **Video** — 512×384 at 1/2/4/8 bpp through the Pocket's scaler, true 4:3
- **Sound** (startup chime and death chimes have been heard many times…)
- **Keyboard/mouse** via the Pocket's controls (ADB device model)
- **Memory** — 2 MB or 10 MB configurations, selectable in the core menu
- **SCSI hard disk, most of the way**: disks mount, the ROM finds them, reads
  sectors correctly, loads and runs the Apple driver partition, shows the
  **happy Mac**, and begins loading System 6.0.8 — see below for the last gap

### Not working yet

- **SCSI hard disk boot** — the System load crashes at a deterministic point
  shortly after the happy Mac. Actively under investigation (the failure is
  reproducible and instrumented; see `docs/boot_problems.md` for the full
  forensic history).
- **Floppy disks** — the image-loading path is ported but has not been validated
  on Pocket hardware yet
- **PRAM persistence** — settings do not survive a power cycle (the clock is
  still always correct: it is set from the Pocket's own RTC at launch). A
  "Reset PRAM" action is available in the core menu.

### Cut from the MiSTer core (Pocket resource budget)

The Pocket's FPGA is roughly half the size of the DE10-Nano's. The following
MiSTer-core features are **not present** and are not planned unless the budget
math changes: 16bpp video, 640×480 mode, the second (external) floppy drive,
the CD-ROM drive, and the BlueSCSI Toolbox file transfer. See
`docs/PORT_STATUS.md` for the arithmetic.

## SD card setup

```
/Cores/danifunker.MacLC/            <- contents of dist/Cores/danifunker.MacLC/
/Assets/maclc/common/boot0.rom      <- 512 KB Mac LC ROM (required)
/Assets/maclc/common/maclc.hda      <- hard disk 1 (optional, auto-mounts)
/Assets/maclc/common/maclc2.hda     <- hard disk 2 (optional, auto-mounts)
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

*(Remember: SCSI boot does not complete yet — the disks mount and read, but the
System crashes during startup. The filenames above are the intended stable
interface and already work for the mount/read stages.)*

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
