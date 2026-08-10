# SCC Wiring Gaps — MacLC MiSTer Core

Analysis comparing our SCC (Z8530) implementation against MAME (`src/mame/apple/maclc.cpp`, `src/devices/machine/z80scc.cpp`) and SuperMario ROM source (`Drivers/IOP/SCCIOP.aii`, `SCCIOPSysEqu.aii`, `SCCDefs.aii`).

## What's Correct

| Aspect | Our Core | MAME / SuperMario | Status |
|--------|----------|-------------------|--------|
| Address range | `$F04000-$F05FFF` (8 KB) | `0xf04000-0xf05fff` | Match |
| Register select bits | rs[0]=A/B, rs[1]=D/C from CPU A2:A1 | `dc_ab` format: bit 0=A/B, bit 1=D/C | Match |
| Interrupt level | IPL level 4 (highest) | V8 routes SCC IRQ to level 4 | Match |
| Interrupt priority | SCC(4) > PseudoVIA(2) > VIA1(1) | Same | Match |
| Read data bus | `{sccDataOut, sccDataOut}` mirrored | `(result << 8) \| result` | Match |
| Autovector | VPA asserted on IACK (FC=111) | Mac LC uses autovectors | Match |
| Unified R/W address | Same address for read and write | Mac LC uses unified (not split like Plus) | Match |
| Chip select | `selectSCC && (LDS==0 \|\| UDS==0)` | Triggers on any valid bus cycle | Match |

## Gaps

### 1. Mouse Connected to SCC DCD — Wrong for Mac LC
- **Priority: HIGH**
- **Files:** `rtl/dataController_top.sv` (lines 868-869)
- **Problem:** `dcd_a` and `dcd_b` are driven by `mouseX1`/`mouseY1`. This is correct for Mac Plus/SE (which uses SCC DCD for mouse quadrature), but **Mac LC uses ADB for mouse** (via Egret). Mouse movement injects noise into the SCC DCD pins, which can trigger spurious external/status interrupts (RR0 bits 3/5, WR15-gated).
- **Fix:** Set `dcd_a(1'b1)` and `dcd_b(1'b1)` (idle/deasserted). Mouse input is already handled by ADB/Egret in this core.
- **Risk:** Low — mouse already works via ADB. This just removes a noise source.

### 2. CTS Idle State Not Guaranteed
- **Priority: HIGH**
- **Files:** `MacLC.sv` (wherever `serialCTS` is defined), `rtl/dataController_top.sv` (line 873)
- **Problem:** If `serialCTS` floats or defaults to 0 (asserted), the SCC sees CTS active. When the ROM initializes the SCC and enables external/status interrupts (WR15), a CTS transition could fire a spurious interrupt. MAME's RS-232 ports default to deasserted.
- **Fix:** Verify `serialCTS` defaults to `1'b1` when no serial device is connected. If it comes from an active-low user I/O pin, add an inversion or default.
- **Risk:** Low.

### 3. Byte Lane for Writes — CPU-Core Dependent
- **Priority: MEDIUM** (blocks FX68K switch)
- **Files:** `rtl/dataController_top.sv` (line 865)
- **Problem:** MAME's Mac LC `scc_w()` does `data >> 8` — the real SCC sits on D15-D8 (upper byte lane). Commit `1263304` switched to `cpuDataIn[7:0]` because TG68K always puts byte data on the lower bus half. This is correct for TG68K but will break when switching to FX68K, which models real 68000 byte-lane behavior.
- **Fix:** Add a conditional mux:
  ```verilog
  `ifdef USE_TG68K
      .wdata(cpuDataIn[7:0]),
  `else
      .wdata(cpuDataIn[15:8]),
  `endif
  ```
  Or restructure so the byte-lane normalization happens once at the CPU wrapper level rather than per-peripheral.
- **Risk:** Medium — wrong byte lane means all SCC register writes are garbage.

### 4. Only One Serial Channel Exposed
- **Priority: MEDIUM**
- **Files:** `rtl/scc.v` (module ports), `rtl/dataController_top.sv` (lines 870-874), `MacLC.sv`
- **Problem:** The SCC has two independent channels (A = printer, B = modem). Our module exposes only one set of `txd/rxd/cts/rts` signals. MAME connects both channels independently with separate RS-232 ports, each with TxD, RxD, DCD, CTS.
- **Current wiring:**
  - `txd` / `rxd` / `cts` / `rts` — unclear which channel (appears to be channel A based on scc.v internals)
  - Channel B serial I/O is unconnected
- **Fix:** Expose per-channel signals: `txd_a`, `rxd_a`, `cts_a`, `rts_a`, `txd_b`, `rxd_b`, `cts_b`, `rts_b`. Route to MiSTer USER_IO or directly to UART bridge as needed.
- **Risk:** Low — doesn't affect boot. Only matters for actual serial communication.

### 5. Missing 3.6864 MHz RTxC/TRxC Clocks
- **Priority: LOW**
- **Files:** `rtl/scc.v`
- **Problem:** MAME configures `SCC85C30(config, m_scc, C7M)` with PCLK = 7.8336 MHz and `configure_channels(3'686'400, 3'686'400, 3'686'400, 3'686'400)` for all four RTxC/TRxC inputs. Our SCC module has no RTxC/TRxC pin inputs — the baud rate generator uses the 8 MHz clock enable frequency internally. If the ROM uses WR11 to select RTxC as a clock source (common for async serial), baud rates will be wrong.
- **Fix:** Add a 3.6864 MHz clock input (can be generated from a counter dividing clk32) and wire it to the BRG/DPLL where WR11 selects RTxC.
- **Risk:** Low — only affects actual serial I/O accuracy, not boot.

### 6. SCC Chip Variant
- **Priority: LOW**
- **Problem:** Mac LC uses Z85C30 (CMOS). Our implementation is a generic Z8530-style. The Z85C30 has minor differences (e.g., enhanced baud rate generator, additional WR7' register). These are unlikely to matter unless the ROM specifically accesses Z85C30-only features.
- **Fix:** No action needed unless a specific register access fails.

## Reference Files

### MAME
- `src/mame/apple/maclc.cpp` — Mac LC machine: address map (line 186/200), byte-lane handlers (lines 114-122), SCC config (lines 378-392)
- `src/mame/apple/v8.cpp` — V8 system controller: `scc_irq_w()` (line 309), `field_interrupts()` priority (line 279)
- `src/devices/machine/z80scc.cpp` — Z8530 device: `dc_ab_r/w` register decoding (lines 903-941)

### SuperMario ROM Source
- `Drivers/IOP/SCCIOP.aii` — SCC IOP kernel (6502): interrupt dispatch, channel init, reset sequence
- `Drivers/IOP/SCCIOPSysEqu.aii` — Clock configs: PCLK 3.9/7.8 MHz, RTxC 3.6864 MHz options
- `Drivers/IOP/SCCDefs.aii` — Register addresses at IOP level: B_Ctl=$F040, A_Ctl=$F041, B_Data=$F042, A_Data=$F043

### Our Core
- `rtl/scc.v` — SCC module (955 lines)
- `rtl/dataController_top.sv` — SCC instantiation (lines 854-875), data bus mux (lines 278-292), interrupt encoding (lines 266-270)
- `rtl/addrDecoder.v` — Address decode: bits [19:12] = `0000_010x` selects SCC (line 134)
- `MacLC.sv` — CPU wrapper, `cpuAddrRegLo = cpuAddr[2:1]` (line 1016)
