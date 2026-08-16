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

Two input modes, toggled with **Select**. The core powers on in keyboard
mode; press Select once for mouse mode.

- **Mouse mode**: D-Pad moves the cursor, **A** clicks. Only the D-Pad and
  A are re-purposed — every other button still types its key, so Command
  chords work while pointing.
- **Keyboard mode**: D-Pad = arrow keys, and the buttons type their
  assigned keys.

Default assignments: **A** Return · **B** Space · **X** Shift · **Y** N ·
**L** Esc · **R** Q · **Start** Command.

Every button is remappable in the core's Interact menu. Pick a key from
the button's dropdown, or pick **Custom** and enter a code from the
tables below in the button's slider (Y and Start are dropdown-only; the
menu is at its 16-entry limit).

Codes select key *positions* on a US keyboard; what a position types is
decided by the keyboard layout of the System software you boot, so on a
non-US System the symbol keys may differ from the US characters shown
here. The extra `<>` key of ISO (international) keyboards has no code.

**Letters** (Shift types the capital):

| Key | Code | Key | Code | Key | Code | Key | Code |
|-----|------|-----|------|-----|------|-----|------|
| a | 28 | h | 51 | o | 68 | v | 42 |
| b | 50 | i | 67 | p | 77 | w | 29 |
| c | 33 | j | 59 | q | 21 | x | 34 |
| d | 35 | k | 66 | r | 45 | y | 53 |
| e | 36 | l | 75 | s | 27 | z | 26 |
| f | 43 | m | 58 | t | 44 | | |
| g | 52 | n | 49 | u | 60 | | |

**Numbers and symbols** (US layout):

| Key | Shift | Code | Key | Shift | Code |
|-----|-------|------|-----|-------|------|
| 1 | ! | 22 | 0 | ) | 69 |
| 2 | @ | 30 | ` | ~ | 14 |
| 3 | # | 38 | - | _ | 78 |
| 4 | $ | 37 | = | + | 85 |
| 5 | % | 46 | [ | { | 84 |
| 6 | ^ | 54 | ] | } | 91 |
| 7 | & | 61 | \ | \| | 93 |
| 8 | * | 62 | ; | : | 76 |
| 9 | ( | 70 | ' | " | 82 |
| , | < | 65 | . | > | 73 |
| / | ? | 74 | | | |

**Whitespace, editing, modifiers:**

| Key | Code | Key | Code |
|-----|------|-----|------|
| Space | 41 | Shift (left) | 18 |
| Return | 90 | Shift (right) | 89 |
| Tab | 13 | Control | 20 |
| Backspace (Mac Delete) | 102 | Command | 17 |
| Esc | 118 | Command (right Alt) | 273 |
| Caps Lock | 88 | Option (Windows key) | 287 |

**Arrows and navigation:**

| Key | Code | Key | Code |
|-----|------|-----|------|
| Up | 373 | Home | 364 |
| Down | 370 | End | 361 |
| Left | 363 | Page Up | 381 |
| Right | 372 | Page Down | 378 |
| Forward Delete | 369 | Help (Insert) | 368 |

**Function keys** (F12 is not available):

| Key | Code | Key | Code | Key | Code |
|-----|------|-----|------|-----|------|
| F1 | 5 | F6 | 11 | F11 | 120 |
| F2 | 6 | F7 | 131 | F13 | 380 |
| F3 | 4 | F8 | 10 | F15 | 382 |
| F4 | 12 | F9 | 1 | | |
| F5 | 3 | F10 | 9 | | |

**Numeric keypad:**

| Key | Code | Key | Code | Key | Code |
|-----|------|-----|------|-----|------|
| KP 0 | 112 | KP 5 | 115 | KP . | 113 |
| KP 1 | 105 | KP 6 | 116 | KP + | 121 |
| KP 2 | 114 | KP 7 | 108 | KP − | 123 |
| KP 3 | 122 | KP 8 | 117 | KP × | 124 |
| KP 4 | 107 | KP 9 | 125 | KP ÷ | 330 |
| KP Enter | 346 | Clear (Num Lock) | 119 | | |

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
