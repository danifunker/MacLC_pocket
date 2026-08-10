# Macintosh LC Hardware Status

Reference: TattleTech report from real Macintosh LC (ID=19g), manufactured 1/2/89.

## Status Key

| Code | Meaning |
|------|---------|
| C | Complete |
| T | In Testing |
| B | Broken / Non-functional |
| (blank) | Not Implemented |

## Real Hardware Summary (from TattleTech)

- **Machine:** Macintosh LC (ID=19g)
- **CPU:** MC68020 @ 16 MHz (instruction cache enabled, no data cache)
- **FPU:** None installed (PDS slot available for 68882)
- **MMU:** None (68020 has no built-in MMU; no external 68851 PMMU installed)
- **RAM:** 10 MB (10,485,760 bytes) - 2 MB soldered + 8 MB SIMM
- **ROM:** 512 KB, version $67C (124), checksum $350EACF0, Universal, 32-bit clean
- **ROM Start:** $00A00000
- **Sound:** Mono only (no stereo), sound input present (built-in mic)
- **Software Power-off:** No (hard power switch on PSU)

## CPU Cores

The core contains **two** CPU implementations, selectable via the OSD menu at `status[14:13]`:

| OSD Option | Value | CPU Core | Description |
|-----------|-------|----------|-------------|
| 68000 | 0 | FX68K (`rtl/fx68k/`) | Cycle-accurate Motorola 68000 in pure Verilog |
| 68010 | 1 | TG68K (`rtl/tg68k/`) | VHDL-based, 68010 mode |
| **68020** | **2** | **TG68K (`rtl/tg68k/`)** | **VHDL-based, 68020 mode (DEFAULT)** |

The default is **68020 via TG68K** (`status_cpu = 2'b10`), which matches the real LC hardware.
Both cores are instantiated simultaneously; a mux in `MacLC.sv:418-431` selects which
core's signals are routed to the rest of the system.

The FX68K core is cycle-accurate but only implements the 68000 instruction set. It cannot
run LC software that uses 68020-specific instructions. The TG68K core supports 68000/68010/68020
variants but is not cycle-accurate.

## Hardware Components

| Component | Real LC | RTL File(s) | Status | Notes |
|-----------|---------|-------------|--------|-------|
| **CPU (68020)** | MC68020 @ 16 MHz | `rtl/tg68k/` (default) | T | TG68K in 68020 mode. Not cycle-accurate but has correct instruction set. FX68K (68000 only) available as fallback. |
| **VIA1** | Yes | `rtl/via6522.sv` | T | Full 6522 implementation with timers, shift register, ports A/B. |
| **VIA2** | No | N/A | C | Correctly absent. LC has no VIA2. |
| **RBV (VISA)** | Yes | `rtl/pseudovia.sv` | T | LC-specific video/interrupt controller. Handles slot/VBlank IRQs, monitor ID, video mode config. |
| **VDAC (Ariel)** | Yes | `rtl/ariel_ramdac.sv` | T | 343S1045 RAMDAC. 256-entry CLUT, 24-bit RGB. Has a palette hack (ignores 0x7F writes). |
| **ASC** | Yes | `rtl/asc.sv` | B | Stub only. Returns version 0xE8 and satisfies ROM boot checks, but no actual sound synthesis. No FIFO, no wavetable. |
| **SCC (Z8530)** | Yes | `rtl/scc.v` | T | Dual-channel serial. TX and interrupt logic need verification. DCD lines used for mouse. |
| **SWIM** | Yes (SWIM) | `rtl/swim.v` | T | IWM + ISM dual-mode. ISM mode switch detection, registers, and FIFO. Read-only. Won't read at 16 MHz CPU speed. |
| **SCSI (NCR5380)** | Yes (no DMA) | `rtl/ncr5380.sv`, `rtl/scsi.v` | T | Dual device support (SCSI ID 5 & 6). Writes experimental. No IRQ handling. |
| **ADB** | Yes (Extended kbd) | `rtl/adb.sv` | T | PS/2 keyboard/mouse converted to ADB. Extended ADB keyboard supported. |
| **Egret (68HC05)** | Yes | `rtl/egret.sv` | T | Microcontroller with real 341S0850 ROM. Handles ADB, RTC/PRAM, reset control. |
| **RTC/PRAM** | Yes | `rtl/rtc.v` | T | 20-byte PRAM, 32-bit seconds counter. Accessed directly and through Egret. |
| **V8 Video** | Yes | `rtl/maclc_v8_video.sv` | T | Supports 1/2/4/8/16 bpp. Multiple monitor configs (12"/13"/15"). |
| **SDRAM** | N/A | `rtl/sdram.v` | T | MiSTer DDR3 interface. Maps ROM, RAM, and disk images. |
| **PS/2 Input** | N/A | `rtl/ps2_kbd.sv`, `rtl/ps2_mouse.v` | T | MiSTer-specific. Converts USB/PS2 input to ADB. |
| **Sound Input** | Yes (built-in mic) | N/A | | Not implemented. LC has built-in microphone input. Low priority. |
| **FPU (68882)** | No | N/A | C | Correctly absent. No FPU was installed in reference machine. |
| **Software Power-off** | No | N/A | C | Correctly absent. LC uses hard power switch. |
| **Ethernet (SONIC)** | No | N/A | C | Correctly absent. LC has no built-in ethernet. |
| **PWM** | No | N/A | C | Correctly absent. |

## Known Issues

### ASC: Sound Chip is a Stub
The Apple Sound Chip implementation (`rtl/asc.sv`) is non-functional beyond satisfying
ROM boot checks. No actual audio output from ASC wavetable synthesis or FIFO playback.

### RAM: 4 MB vs 10 MB
The core currently supports 1 MB / 4 MB configurations. The real LC has 10 MB (2 MB
soldered + 8 MB SIMM). This may limit software compatibility.

### SWIM ISM Mode
The SWIM now supports both IWM and ISM modes. The IWM-to-ISM mode switch sequence is
detected, and ISM registers/FIFO respond correctly. Full ISM data path (clock recovery,
CSM/TSM state machines) is not yet implemented. Floppy is read-only and doesn't work at 16 MHz.

### TG68K Not Cycle-Accurate
The TG68K core in 68020 mode has the correct instruction set but is not cycle-accurate
to a real MC68020. This may cause timing-sensitive software to behave differently.

## Memory Map (Verified via MacsBug on Real LC)

| Address | Device | Verified | Notes |
|---------|--------|----------|-------|
| $000000-$9FFFFF | RAM (10 MB on real LC, 4 MB in core) | YES | All 10MB readable, no bus errors |
| $A00000-$A7FFFF | ROM (512 KB) | YES | Checksum $350EACF0 confirmed |
| $F00000-$F01FFF | VIA1 | YES | 512-byte stride, upper byte of data bus |
| $F04000-$F05FFF | SCC | YES | 2-byte register stride, both channels respond |
| $F06000-$F07FFF | SCSI DRQ Window 1 | **BUS ERROR (2x)** | Confirmed in two sessions - not accessible when SCSI idle |
| $F10000-$F11FFF | SCSI (NCR5380) | YES | 8-byte stride registers |
| $F12000-$F13FFF | SCSI DRQ Window 2 | YES | Returns $0E when idle |
| $F14000-$F15FFF | ASC | YES | FIFO=$80, Version=$E8 at +$800 |
| $F16000-$F17FFF | SWIM | YES | SWIM behavior (not IWM) |
| $F19000 | (outside SWIM) | **BUS ERROR** | Confirms $F18000+ unmapped |
| $F24000-$F25FFF | VDAC (Ariel RAMDAC) | YES | Auto-increment palette reads work |
| $F26000-$F27FFF | PseudoVIA (RBV/VISA) | YES | 4-byte mirror pattern discovered |
| $F40000-$FBFFFF | VRAM (512 KB) | YES | Desktop pixel data visible |

## MacsBug Verification Results (2026-03-03)

Full analysis in `MACSBUG_RESULTS.md`. Key findings:

### Discrepancies Found

1. **PseudoVIA RAM Config ($F26001) = $E6** - Our core returns $04-$07. Real LC returns
   $E6 for 10MB. The register encoding is completely different from our implementation.

2. **PseudoVIA Register Mirroring** - Real V8 mirrors native registers every 4 bytes
   (Group 0: regs $00-$03 at offsets $00-$0F; Group 1: regs $10-$13 at offsets $10-$1F).
   Our core decodes full addr[7:0] with 256 unique registers. Software writing to
   "mirrored" addresses may behave differently.

3. **SCSI DRQ Window at $F06000 = BUS ERROR** - Confirmed in two sessions. Our core
   maps this unconditionally. Real hardware only allows access during active SCSI DMA.

4. **PseudoVIA VIA-compat mode** - Real V8 does NOT have a separate VIA-compat register
   bank. All VIA-compat addresses ($F26100-$F27FFF) return native Group 0 register data.
   Our core implements a separate register space (Port A=$D5, independent IFR/IER) that
   doesn't match real hardware. Confirmed: $F26200, $F27A00, $F27C00 all return Group 0.

5. **ASC FIFO buffer** - Real hardware reads $80 (silence) in the 2x1KB FIFO area.
   Our stub has no FIFO memory at all.

6. **ASC registers** - Real hardware has Mode=$01, Volume=$60, FIFO IRQ=$03.
   Our stub may not track these correctly.

7. **SWIM vs IWM** - Real hardware shows SWIM-specific alternating $72/$3D byte pattern.
   Our core implements IWM only.

### Values Confirmed Correct

- ASC Version register = $E8 (our stub returns this correctly)
- PseudoVIA Slot/VBlank status format matches our implementation
- PseudoVIA 4-byte register mirroring confirmed across two sessions
- PseudoVIA Port B is dynamic (bit 3 = Egret input toggles live: $4F/$47)
- ROM checksum $350EACF0 at $A00000 confirmed
- SCC idle state ($54/$44 for Ch B/A RR0) is normal
- SCSI bus idle (all zeros, Reg 1 Initiator Command = $00) is normal
- VRAM mapped at $F40000 confirmed
- All memory map boundaries confirmed (bus errors at expected locations)

### Real Register Values for Reference

**VIA1:** DDRB=$F7, DDRA=$2F, T1 Latch=$A0FF, PCR=$00, IFR=$C2, IER=$A6
**SCC:** Ch B RR0=$54, Ch A RR0=$44 (both idle)
**ASC:** Version=$E8, Mode=$01, Control=$01, Volume=$60, FIFO IRQ=$03
**PseudoVIA:** PortB=$4F, RAMcfg=$E6, SlotStat=$3F, IFR=$92, VideoCfg=$10, SlotIER=$78, IER=$0A
