# Macintosh LC for the Analogue Pocket

An openFPGA core that emulates the Apple Macintosh LC: 68020 CPU (modified
TG68K), the V8 gate array, the Egret system controller running its original
HC05 firmware, SWIM floppy, SCSI, and ADB. Ported from the
[MacLC MiSTer core](https://github.com/danifunker/MacLC_MiSTer), which is
based on Sorgelig's MacPlus core, originally derived from
[Plus Too](http://www.bigmessowires.com/plus-too/).

Version 1.0.0. Boots System 6.0.8, 7.1, and 7.5.5 to a 256-colour desktop.

## Features

- 2 MB or 10 MB RAM (10 MB default; "Memory" + "Reset & Apply" in the core menu)
- 512×384 video at 1/2/4/8 bpp, 4:3, with Analogue Display Modes
  (the CRT Trinitron profile suits this machine)
- Two SCSI hard disks, readable and writable, plus a read-only ISO CD-ROM
- 1.44 MB MFM floppy images (`.dsk`/`.img`, raw or DiskCopy 4.2), read-only
- Sound, ADB keyboard and mouse via the Pocket's controls, remappable
- RTC set from the Pocket's clock at every launch
- Boots in 256 colours out of the box (a factory PRAM ships in the core)

## SD card setup

```
/Cores/danifunker.MacLC/            <- contents of the release zip
/Platforms/                         <- from the release zip
/Assets/maclc/common/boot0.rom      <- Mac LC ROM, 512 KB (required)
/Assets/maclc/common/maclc.hda      <- hard disk 1 (auto-mounts)
/Assets/maclc/common/maclc2.hda     <- hard disk 2 (auto-mounts)
/Assets/maclc/common/maclc.iso      <- CD-ROM image (auto-mounts)
```

The ROM is required: version `$67C`, checksum `$350EACF0`, 512 KB, named
`boot0.rom`. The core will not start without it.

Disk naming matters. A file named exactly `maclc.hda` attaches to Hard
Disk 1 (SCSI ID 0) at every launch with no menu work; `maclc2.hda` does the
same for Hard Disk 2, and `maclc.iso` for the CD-ROM. Images with other
names can be attached manually through the core menu. Floppy images go
anywhere on the card and mount via the Floppy slot.

Hard-disk images are raw SCSI images (Driver Descriptor Map + partition
map + `Apple_Driver43` + HFS), the same format SCSI2SD and BlueSCSI use
([reference](http://www.codesrc.com/mediawiki/index.php?title=HFSFromScratch)).
Images that boot on the MiSTer core boot here.

Back up your `.hda`. The image is writable, and a crash while the guest is
writing can damage its filesystem.

## Controls

Two input modes, toggled with **Select**. Mouse mode is the power-on
default (configurable in the core menu).

- **Mouse mode**: D-Pad moves the cursor, **A** clicks. Only the D-Pad and
  A are re-purposed — every other button still types its key, so Command
  chords work while pointing.
- **Keyboard mode**: D-Pad = arrow keys, and the buttons type their
  assigned keys.

Default assignments: **A** Return · **B** Space · **X** Shift · **Y** N ·
**L** Esc · **R** Q · **Start** Command.

Every button is remappable in the core's Interact menu. Pick a key from
the button's dropdown, or pick **Custom** and enter a raw keycode in the
button's slider (Y and Start are dropdown-only; the menu is at its
16-entry limit). Sliders take PS/2 Scan Code Set 2 make codes **in
decimal**; arrows are extended codes, entered as 256 + code:

| Key | Hex | Dec | Key | Hex | Dec | Key | Hex | Dec |
|-----|-----|-----|-----|-----|-----|-----|-----|-----|
| A | 0x1C | 28 | N | 0x31 | 49 | 1 | 0x16 | 22 |
| B | 0x32 | 50 | O | 0x44 | 68 | 2 | 0x1E | 30 |
| C | 0x21 | 33 | P | 0x4D | 77 | 3 | 0x26 | 38 |
| D | 0x23 | 35 | Q | 0x15 | 21 | 4 | 0x25 | 37 |
| E | 0x24 | 36 | R | 0x2D | 45 | 5 | 0x2E | 46 |
| F | 0x2B | 43 | S | 0x1B | 27 | 6 | 0x36 | 54 |
| G | 0x34 | 52 | T | 0x2C | 44 | 7 | 0x3D | 61 |
| H | 0x33 | 51 | U | 0x3C | 60 | 8 | 0x3E | 62 |
| I | 0x43 | 67 | V | 0x2A | 42 | 9 | 0x46 | 70 |
| J | 0x3B | 59 | W | 0x1D | 29 | 0 | 0x45 | 69 |
| K | 0x42 | 66 | X | 0x22 | 34 | Up | — | 373 |
| L | 0x4B | 75 | Y | 0x35 | 53 | Down | — | 370 |
| M | 0x3A | 58 | Z | 0x1A | 26 | Left | — | 363 |
| | | | | | | Right | — | 372 |

Space 0x29 · Return 0x5A · Esc 0x76 · Tab 0x0D · Backspace 0x66 ·
Shift 0x12 · Command 0x11 · Control 0x14 · period 0x49 · comma 0x41

## Known limitations

- **800K GCR floppy images** can crash or hang the system. Mounting works;
  sustained use can end in a bomb or a freeze. Use 1.44 MB MFM images or
  the hard disk instead. This is the main open defect.
- **PRAM does not persist.** The factory PRAM boots the machine in 256
  colours; changes you make in control panels (volume, mouse speed, depth)
  last until power-off and then reset.
- **Some boots fail** with an error dialog or a hang during startup.
  Power fully off and boot again. After inserting or rewriting the SD
  card, give the Pocket a minute at its menu before launching. Once the
  Finder is up, the machine is stable for long sessions.
- **Special → Restart does not come back.** Power-cycle instead.
- **Floppies are read-only** (the drive reports write-protected, so the
  OS never attempts a write).
- Not present, by resource budget: 16bpp video, 640×480, the external
  floppy, CD audio, BlueSCSI Toolbox. See `docs/PORT_STATUS.md`.

## Building from source

Quartus Prime Lite 18.1.1, target `5CEBA4F23C8`. Project at
`src/fpga/ap_core.qpf`; `bash scripts/package.sh` produces the card files
in `dist/`. `python scripts/check_hierarchy.py rtl src/fpga` is the
no-toolchain structural check. `docs/PORT_STATUS.md` covers what the port
does; `docs/boot_problems.md` is the measured defect history.

## AI Disclaimer

This core is developed with heavy use of AI tooling, including Claude
(Fable, Opus, Sonnet models) and GPT (Codex), and borrows from MAME. A
physical Macintosh LC was also used throughout development, and the MiSTer
parent core is the continuous reference implementation.

## MAME-sourced components

- SCSI subsystem
- Egret (running the original Egret firmware), including ADB
- Floppy (SWIM)
- V8 (video subsystem)
- ASC (sound subsystem)

## Credits

- MacPlus MiSTer core by Sorgelig
- Plus Too by Steve Chamberlin (Big Mess o' Wires)
- Mac LC MiSTer core and Pocket port by
  [danifunker](https://github.com/danifunker) and
  [alanswx](https://github.com/alanswx)
