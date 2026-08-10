# Egret Implementation Progress & Debug Plan

## Overview

Mac LC uses **Egret** (not CUDA) as its ADB/PRAM/RTC microcontroller. This document tracks the implementation of the real Egret using the m68hc05_core CPU (from OpenCores) and the actual Egret ROM (341S0851).

## Clock Configuration

### Reference: MAME maclc.cpp
| Signal | Frequency | Source |
|--------|-----------|--------|
| C32M | 31.3344 MHz | Master XTAL |
| C15M | 15.6672 MHz | C32M/2 - 68020, V8, ADB, SWIM |
| C7M | 7.8336 MHz | C32M/4 - SCC |
| Egret | 4.194 MHz | 32.768 kHz × 128 (M68HC05E1) |

### Current Implementation
| Component | Clock | Implementation |
|-----------|-------|----------------|
| System | 32 MHz | sim.v clk_sys |
| 68020 CPU | 16 MHz | TG68K with cpu=11 (68020 mode), status_turbo=1 |
| Egret HC05 | 4 MHz | 32 MHz / 8 divider in egret_wrapper.sv |
| VIA/V8 | 8 MHz | clk8_en_p/n from busPhase |

### Clock Divider Details
```verilog
// addrController_top.v - generates clock enables from 32 MHz
busPhase <= busPhase + 1;  // 2-bit counter
clk8_en_p = (busPhase == 2'b11);  // 8 MHz pulse
clk16_en_p = !busPhase[0];         // 16 MHz pulse

// egret_wrapper.sv - generates 4 MHz for HC05
reg [2:0] clk_div;
wire cen = (clk_div == 3'b000);  // 4 MHz pulse (32/8)
```

## Current Status (2024-12-30)

### Working Features
- Egret ROM loads correctly (4352 bytes)
- Egret CPU runs at 4 MHz with proper clock enable
- CB1 gating - only passes through when TIP=0 (transaction active)
- Reset_680x0 logic correctly controlled by Port C bit 3
- System reset waits for ROM download to complete
- Egret waits for n_reset before starting initialization
- **PRAM loading correct** - uses offset 0x70 to match MAME, no stack overlap
- **68020 released from reset** at cycle 278529
- **TIP signal working** - VIA asserts TIP, Egret detects it
- **TIP/BYTEACK polling passes** - firmware reaches 0x12B2 (rts)
- **RTS returns correctly** - stack reads valid return addresses (0x0ff0, 0x1dfa, etc.)
- **Firmware reaches main loop** at 0x120A/0x1228 polling for TIP

### Current Issue: VIA ↔ Egret Communication

The Egret is in the main loop polling for TIP, but the communication protocol
between VIA and Egret isn't completing properly:
1. VIA is polling IFR (checking for SR completion)
2. Egret is at 0x120A polling Port B bit 3 (TIP)
3. TIP is sometimes asserted (0) but communication doesn't progress
4. TREQ not being asserted after 68020 release

The boot is stuck at a white screen because the 68020 needs PRAM values from
Egret, but the shift register communication isn't working correctly.

## Bug Fixes History

### Fix 1: reset_680x0 Logic Bug (2024-12-28)
The reset_680x0 signal was using incorrect logic:
```verilog
// BEFORE (wrong):
reset_680x0 = reset_680x0_override & ~pc_out[3];

// AFTER (correct):
reset_680x0 = reset_680x0_override | pc_out[3];
```
Per MAME egret.cpp: Port C bit 3 = 1 means ASSERT reset, bit 3 = 0 means RELEASE reset.

### Fix 2: ROM Download Timing (2024-12-28)
The 68020 was being released from reset before ROM download completed (~frame 9).
System reset now waits for ROM download:
```verilog
// sim.v - n_reset stays low until download completes
if(~pll_locked || reset || dio_download) begin
    rst_cnt <= '1;
    n_reset <= 0;
end
```

### Fix 3: Egret Boot Timing (2024-12-28)
Egret was being released from reset before n_reset went high. This caused Egret
to time out waiting for 68020 response (before ROM was even loaded).
```verilog
// dataController_top.sv - wait for _systemReset before releasing Egret
always @(posedge clk32) begin
    if (!_systemReset) begin
        egretBootCounter <= 0;  // Keep counter at 0 while system reset active
    end
    else if (egretBootCounter < 10'd512) begin
        if (clk8_en_p) egretBootCounter <= egretBootCounter + 1'b1;
    end
end
```

### Fix 4: Port C DDR for Reset Release (2024-12-29)
When firmware makes Port C bit 3 an INPUT (DDR[3]=0), it expects to read 0
(reset released). Without this fix, the latch value (1) was returned, keeping
the 68020 in reset forever.
```verilog
// pc_in returns 0 for bit 3 when DDR makes it an input
wire [7:0] pc_in = {pc_latch[7:4], (pc_ddr[3] ? pc_latch[3] : 1'b0), pc_latch[2:0]};
```

### Fix 5: BYTEACK Signal (2024-12-29)
The BYTEACK (Port B bit 2) was HIGH due to via_pb_o[4] connection. Tied LOW
temporarily so firmware's BYTEACK polling at 0x12AF passes.
TODO: Implement proper BYTEACK based on VIA shift register state.

### Fix 6: PRAM Loading Wrong Offset (2024-12-30)
**Root Cause:** PRAM loading used wrong RAM base offset (0x50 instead of 0x90).
The stack at addresses 0x00FE and 0x00FF was being zeroed during PRAM init,
causing RTS at 0x12B2 to pop 0x0000 and jump to error handler at 0x1F89.

**Debug Process:**
1. Added HC05 CPU state machine debug for RTS instruction
2. Found state3 read 0x00 from stack, state4 also read 0x00
3. Traced that stack should have contained 0x10 0x04 (return addr 0x1004)
4. Found PRAM loading at cycle 272713 overwrote stack locations
5. Initial workaround: skip indices 64-79 during PRAM loading
6. Investigated MAME source: `write_internal_ram(0x70 + byte, data)`
7. Found code used offset 0x20 (from 0x70-0x50) but RAM base is 0x90, not 0x50!

**Real Fix:** Change PRAM offset from 0x20 to 0x70 to match MAME:
```verilog
// Per MAME: write_internal_ram(0x70 + byte, data)
// intram[x] = CPU addr 0x90+x, so PRAM goes to CPU 0x100-0x1FF
for (pram_idx = 0; pram_idx < 256; pram_idx = pram_idx + 1) begin
    intram[pram_idx + 16'h70] = pram[pram_idx];  // Offset 0x70, not 0x20
end
```
With correct offset, PRAM at CPU 0x100-0x1FF does NOT overlap stack (0xF0-0xFF).

## Memory Map (68HC05)

| Address Range | Size | Description |
|---------------|------|-------------|
| 0x0000-0x001F | 32B | I/O Registers (Ports A, B, C, DDR, Timer) |
| 0x0090-0x01FF | 368B | Internal RAM (intram[0-367]) |
| 0x0F00-0x1FFF | 4352B | ROM (Egret firmware 341S0851) |

### RAM Layout (verified against MAME)
| CPU Address | intram Index | Usage |
|-------------|--------------|-------|
| 0x0090-0x00EF | 0x00-0x5F | Variables, scratch |
| 0x00F0-0x00FF | 0x60-0x6F | Stack (16 bytes) |
| 0x0100-0x01FF | 0x70-0x16F | PRAM (256 bytes) |

### ROM Mapping
```
CPU Address    ROM Offset   Content
0x0F00-0x0FFF  0x000-0x0FF  Copyright notice
0x1000-0x1FFF  0x100-0x10FF Main code
0x1FFE-0x1FFF  0x10FE-0x10FF Reset vector (0x0F71)
```

### I/O Register Map (M68HC05E1)
| Address | Register | Description |
|---------|----------|-------------|
| 0x00 | PORTA | Port A data |
| 0x01 | PORTB | Port B data |
| 0x02 | PORTC | Port C data |
| 0x04 | DDRA | Port A direction (1=output) |
| 0x05 | DDRB | Port B direction |
| 0x06 | DDRC | Port C direction |
| 0x07 | PLL | PLL control / timer prescale |
| 0x08 | TCR | Timer control |
| 0x09 | TSR | Timer counter (free-running) |
| 0x12 | One-second | 1-second timer control |

## Port Mapping (from MAME egret.cpp)

### Port A ($00) - ADB and System Control
| Bit | Dir | Function |
|-----|-----|----------|
| 7 | O | ADB data line out |
| 6 | I | ADB data line in |
| 5 | I | System type (1 = Egret controls power) |
| 4 | O | DFAC latch |
| 3 | O | 680x0 reset pulse |
| 2 | I | Keyboard power switch |
| 1-0 | O | PSU control |

### Port B ($01) - VIA Interface
| Bit | Dir | Function | Notes |
|-----|-----|----------|-------|
| 7 | O | DFAC clock (I2C SCL) | |
| 6 | I/O | DFAC data (I2C SDA) | Tied high |
| 5 | I/O | CB2 - Shift register data | |
| 4 | O | CB1 - Shift register clock | Gated by TIP |
| 3 | I | TIP from VIA (SYS_SESSION) | PB5 from VIA |
| 2 | I | VIA_FULL (BYTEACK) | PB4 from VIA |
| 1 | O | TREQ to VIA (XCVR_SESSION) | Active LOW |
| 0 | I | +5V sense | Always 1 |

### Port C ($02) - 68000 Control
| Bit | Dir | Function |
|-----|-----|----------|
| 3 | O | 680x0 reset (active high = ASSERT reset) |
| 2-0 | O | IPL2-0 (active low) |

## VIA Shift Register Protocol

1. Egret asserts TREQ (PB1=0) to request transfer
2. VIA sets TIP (PB5=0) to acknowledge
3. Egret clocks CB1 8 times to shift data via CB2
4. VIA sets SR interrupt flag when byte complete
5. Process repeats for each byte

## Files

```
rtl/egret/
├── egret_wrapper.sv    # Main wrapper with port handling, 4MHz clock, CB1 gating
├── m68hc05_core.sv     # CPU core with cen input
├── m68hc05_alu.sv      # ALU for CPU
├── egret_rom.hex       # ROM in hex format (4352 bytes)
├── egret.pram          # PRAM data (loaded on 680x0 reset)
├── convert_firmware.py # ROM to hex conversion
└── convertpram.py      # PRAM conversion script

verilator/
├── sim.v               # Top-level with TG68K in 68020 mode
├── sim_main.cpp        # Testbench with cfg_cpuType=2 (68020)
├── sim_output.txt      # Latest simulation log
└── Makefile            # USE_EGRET_CPU, SIMULATION defines
```

## Next Steps

1. **Debug VIA ↔ Egret shift register communication**
   - Egret is in main loop at 0x120A polling for TIP
   - VIA is polling IFR for SR completion (bit 2)
   - Need to understand why communication isn't progressing
   - Check if 68020 initiates communication by asserting TIP via VIA PB5

2. **Implement proper BYTEACK**
   - Add VIA shift register completion signal
   - Connect to Egret Port B bit 2 instead of current constant LOW
   - BYTEACK should go HIGH when VIA receives 8 bits

3. **Verify CB1/CB2 clocking**
   - When TIP is asserted and communication starts
   - Egret should clock CB1 to shift data via CB2
   - VIA should respond with SR interrupt flag

4. **Check 68020 boot ROM code**
   - Understand what the 68020 is waiting for
   - It may need Egret to respond with PRAM values before proceeding

## References

- MAME source: `mame/src/mame/apple/egret.cpp`
- MAME CPU: `mame/src/devices/cpu/m6805/m68hc05e1.cpp`
- MAME Mac LC: `mame/src/mame/apple/maclc.cpp`
- Egret ROM: 341S0851 (4352 bytes)
- 68HC05E1 datasheet for timer and port behavior
