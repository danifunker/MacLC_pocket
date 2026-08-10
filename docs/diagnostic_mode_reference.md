# Macintosh 68k Diagnostic Mode (TechStep / "STM") — reference

Transcribed from the mac68k.info wiki "Diagnostic Mode" page
(archived 2021-03-10:
`https://web.archive.org/web/20210310172429/https://mac68k.info/wiki/display/mac68k/Diagnostic+Mode`).
The live site is dead, so this is the local copy. Lightly reformatted; tables
and codes reproduced verbatim.

> **Relevance to this core:** "STM" is the on-ROM diagnostic monitor (the `*V`
> command reports `STM Version 2.0, Scott Smyers`). Our boot was getting stuck
> in the POST failure path that feeds this monitor — see
> [post_diagnostics_and_irq_levels.md](post_diagnostics_and_irq_levels.md). The
> machine identifier for the **LC is `D`**, and `30 = Egret error` is relevant
> to our Egret handshake work.

## Overview

Some Macs have a diagnostic mode apparently used at the factory and by the Apple
**TechStep** diagnostic tool.

- Uses the **Modem serial port** at **9600 baud, 8 data bits, no parity, 2 stop
  bits**.
- Depending on the machine and entry method, the port may continuously output
  something like `*APPLE*876543210000*1*` — the `*1*` is a **machine
  identifier**. Otherwise it may output nothing but will still accept and echo
  commands.

## Machine identifiers

| ID | Machine |
|----|---------|
| 1 | Mac II (256kb ROM family) |
| 2 | SE |
| 3 | Plus |
| 4 | LaserWriter NTX |
| 5 | LaserWriter NT |
| 6 | Portable |
| 7 | Mac IIci |
| 8 | IIfx |
| B | Classic |
| C | IIsi |
| **D** | **LC** |
| I | Q700 |
| J | Q900 |
| O | IIvx family — TechStep dumps the byte at `$5FFFFFFC` to differentiate IIvi / P600 |

The machine outputs this string continuously, even while commands are entered.

## Commands

Two classes: `*`-prefixed and `!`-prefixed. Arguments default to **binary**
(`*H`); `*A` switches to ASCII-hex.

| Cmd | Name | Description |
|-----|------|-------------|
| `*V` | Version | Outputs diagnostics + System ROM version, e.g. `STM Version 2.0, Scott Smyers` / `ROM Version 7C12F1` |
| `*S` | Service Mode | Stops the continuous `*APPLE*` output; commands still accepted |
| `*A` | ASCII Mode | Arguments entered as ASCII hex (no auto leading-zero fill) |
| `*H` | Hex (binary) Mode | Arguments are binary. **Default.** |
| `*R` | Return Status | Returns diagnostic status reg (D6) + flags (low word of D7) as 12 hex digits: 8 = 32-bit status, 4 = major error code (table below) |
| `*T` | Run Critical Test | 6 bytes of args: test# (2), iterations (2), options (2) |
| `*N` | Run Non-critical Test | e.g. `*N008400010000` → test `0x84`, 1 iteration; exits on first failure; returns code like `020004030000` (top byte = phase, rest = expected/actual). `0xFFFFFFFF0000` = skipped test |
| `*L` | LoadAddr | Address used by subsequent commands |
| `*B` | ByteCount | Byte count for subsequent command |
| `*D` | GetData | Writes argument data (length from `*B`) to address from `*L`; checksum → D6 |
| `*M` | MemDump | Dumps memory at `*L` for `*B` bytes |
| `*C` | CheckSum | Checksums memory at `*L` for `*B` bytes; result → D6 |
| `*G` | Execute | Jump to 32-bit address arg (via a `BSR6` macro) |
| `*0` | LoadA0 | 32-bit arg → D6, then A0 |
| `*1` | LoadA1 | 32-bit arg → D6, then A1 |
| `*2` | SetCache | 32-bit arg → CACR |
| `*3` | MMUOff | Disables the MMU |
| `*4` | ClearResult | Clears the result of any previous test |
| `*5` | StartBootMsg | Schedules the `*APPLE*` boot message |
| `*6` | CPUReset | Resets the CPU |
| `*7` | PreventSleep | |

### Major error codes (low 16 bits of `*R`, i.e. low word of D7)

| Code | Description |
|------|-------------|
| 1 | ROM CheckSum |
| 2 | Initial RAM failure |
| 3 | RAM Bank A |
| 4 | RAM Bank B |
| 5 | RAM Addressing |
| 6 | VIA1 access |
| 7 | VIA2 access |
| 8 | Data bus error accessing RAM |
| 9 | MMU failure |
| A | NuBus access failure |
| B | SCSI failure |
| C | IWM failure |
| D | SCC failure |
| E | Data Bus test failure |
| 10 | power manager |
| **11** | **Error sizing memory** |
| 12 | SCC IOP failure |
| 13 | Error with dynamic bus sizing |
| 14 | Power Manager Turn On |
| 15 | RAM parity error |
| **30** | **Egret error** |

### `*T` critical test numbers

| # | Description |
|---|-------------|
| 0 | Size Memory |
| 1 | Data Bus Test (writes bit patterns to the 32 bits at A0 (set via `*0`) and reads back) |
| 2 | Mod3 RAM Test |
| 3 | Address Line Test |
| 4 | ROM checksum |
| 5 | RevMod3 RAM Test |
| 6 | Extra RAM Test |
| 7 | ModInv RAM Test |
| 8 | Size video RAM |

`*T` options (bits of the 3rd arg word):

| Bit | Meaning |
|-----|---------|
| 12 | stop on first failure |
| 13 | loop on failure forever |
| 14 | store test results in PRAM (retrievable after boot) |
| 15 | boot after test is done |

### `*N` non-critical test numbers (known)

| # | Description |
|---|-------------|
| 0x84-0x86 | SCC tests |
| 0x87 | VIA test |
| 0x88 | general SCSI test |
| 0x89 | Sound |
| 0x8A | PRAM |
| 0x8B | RBV |
| 0x8C | SWIM |
| 0x8D | FPU |
| 0x8E | PGC |
| 0x8F-0x90 | FMC |
| 0x91-0x92 | OSS |
| 0x94 | Egret |
| 0x95 | more sound |
| 0x96 | CLUT |
| 0x97 | VRAM |
| 0x9A | 53C96 SCSI |
| 0x9B-0x9D | SONIC ethernet |

### Example: run the ROM test

| Input | Echo |
|-------|------|
| | `*APPLE*876543210000*C*` |
| `*V` | `STM Version 2.0, Scott Smyers` / `ROM Version 7C12F1` / `*V` |
| `*A` | `*A` |
| `*T000400010000` | `*T` |
| `*R` | `000000000000*R` |

## Entering Diagnostic Mode

Entered automatically whenever the machine would show a **Sad Mac** at boot.
Forced entry methods (TechStep uses ADB where supported, else SCSI):

### VIA (PA0)

Ground **PA0 of VIA1** (data register A, pin 0). Exposed on the logic-board edge
connector on at least the IIx, IIci, IIsi. Booting with this pin grounded → the
machine chimes but shows **no video**.

> In this core: VIA1 port A reads with PA0 = 1 (normal). The ROM's check is
> `btst #0,($1e00,A2)` at `$A4644C`; PA0 ≠ 0 takes the normal-boot branch.

### ADB (Egret machines, ≥ IIsi?)

Requires a special device (not a normal keyboard). Sequence:

- Start with the machine off.
- Power on via ADB by bringing `POWER.ON` low.
- Once +5V is up, release `POWER.ON` (host pulls it high) — ~200 ms.
- Let it boot ~800 ms.
- Lower `POWER.ON` again.
- Wait for the host to issue a TALK to address 2 (keyboard), register 2
  (modifier keys).
- Respond `0xE6`.
- For the next 10 TALK addr 2 / reg 2 requests, respond `0xEE`.
- The machine gives bad chimes and enters diagnostic mode.

### SCSI

TechStep presents a fake disk at **SCSI ID 6**: 5 × 512-byte blocks (block 0 =
driver descriptor, blocks 1-3 = Apple Partition Map with fake `Apple_HFS` + an
`Apple_Driver`; block 4 = the driver). The driver (captured on a Performa 600)
essentially performs a software NMI:

```asm
movea.w #$4000,a7        ; new stack pointer
move.l  #$8046fc,(a7)+
pmove   (a6),tc          ; disables translation -> 32-bit mode for next insn
movea.l #$50f26000,a7    ; RBV VIA2 vBuf2 address
move.b  #$47,(a7)+
movea.w #9984,a7
move.w  #8193,d0
movec   d0,cacr          ; instruction cache + write-allocate only
move.l  #504462720,d7    ; D7 holds diagnostic-mode flags
move.l  $7c,d0           ; set up trap 15 (NMI) handler
move.l  d0,$bc
trap    #15              ; ~ NMI
movea.w #$4000,a7
move.l  #8388608,(a7)+
```

### NMI

Hitting the Programmer's Interrupt switch shortly after power-on (cursor shown,
before booting) → "chimes of death" + Sad Mac. On machines without the switch,
cmd-power can do the same.

## TechStep transaction notes

- Command arguments are loaded into **D1**. If > 4 bytes, the first four are read
  then moved to another register (D0 for `*T`), and the rest read into D1. So
  `*200000000` (load A1) also leaves the value in D1 as a side effect, usable by
  later argument-less commands (e.g. `*3`).
- TechStep does not send CR/LF (ROM ignores them); it sends them when echoing.

### Preamble (verifies comms before real tests)

| TechStep | Computer | Comment |
|----------|----------|---------|
| `*A` | `*A` | Enter ASCII mode |
| `*H` | `*H` | Enter binary mode |
| `*4` | `*4` | Clear existing status |
| `*000000000` | `*0` | Load 0 into A0 |
| `*T000100010001` | `*T` | Run test #1 (data bus), 1 iteration, option 1 |
| `*R` | `000000000000*R` | Return value (6 bytes of 0 = success) |

### TechStep requests CPUID on IIsi

| TechStep | Computer | Comment |
|----------|----------|---------|
| `*A` / `*H` / `*4` | (echoed) | mode + clear |
| `*L00044000` | `*L` | Load address `0x00044000` |
| `*B0008` | `*B` | Byte count 8 |
| `*D2E7C000E00004ED6` | `*D` | Put 8 bytes at the address. Disassembles to `MOVEA.L #$000E0000,SP` / `JMP (A6)` |
| `*G00044000` | `*G` | Execute (echoes after completion) |
| `*R` | `000001DC0000*R` | `000001DC` = D6 (checksum from `*D`); trailing `0000` = low word of D7 |
