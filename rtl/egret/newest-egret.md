# Egret 68HC05 CPU Implementation - Session Summary

## What We Accomplished ✅

### 1. **Complete Egret CPU Implementation**
- Converted `m68hc05_core.sv` from VHDL (Ulrich Riedel's jt6805)
- Created `egret_wrapper.sv` as drop-in replacement for old `egret.sv`
- Implemented full 68HC05 instruction set with 12-state FSM
- Added ALU components (fadd, add8, add8c, mul8)

### 2. **ROM and Memory Configuration**
- **ROM**: 4KB Egret firmware (341S0851.bin) converted to hex format
- **ROM Path**: `rtl/egret/egret_rom.hex`
- **ROM Mapping**: Accessible everywhere except I/O (0x00-0x0F) and RAM (0x50-0x1FF)
- **Reset Vector**: 0xFFFE/FFFF → points to 0x0F71
- **Critical Fix**: ROM reads must be **combinational** (not registered) to avoid 1-cycle data delay

### 3. **Port Configuration (Working Values)**
```systemverilog
// Port A inputs - CRITICAL VALUES:
wire [7:0] pa_in = {
    pa_out[7],   // Bit 7: output readback
    1'b0,        // Bit 6: ADB in = 0
    1'b1,        // Bit 5: system type = 1 (Egret controls power) *** KEY ***
    pa_out[4],   // Bit 4: output readback  
    1'b0,        // Bit 3: = 0
    1'b0,        // Bit 2: keyboard = 0
    1'b1,        // Bit 1: PSU/chassis = 1 *** KEY ***
    1'b0         // Bit 0: control panel = 0
};

// Port B inputs:
wire [7:0] pb_in = {
    pb_out[7],   // Bit 7: DFAC clock readback
    1'b1,        // Bit 6: DFAC data
    via_cb2_in,  // Bit 5: CB2 from VIA
    pb_out[4],   // Bit 4: CB1 readback
    via_tip,     // Bit 3: TIP from VIA
    1'b1,        // Bit 2: VIA_FULL
    pb_out[1],   // Bit 1: TREQ readback
    1'b1         // Bit 0: +5V sense *** IMPORTANT ***
};
```

### 4. **Clock Configuration**
- **For Simulation**: `wire cen = 1'b1;` (always enabled) with clock divider
- **For Hardware**: Use dedicated 4.194304 MHz PLL clock with `wire cen = clk8_en;`
- CPU runs every cycle when cen is high

### 5. **68020 Reset Release Solution**
**Problem**: Chicken-and-egg deadlock:
- Egret waited for VIA communication before releasing 68020
- VIA waited for 68020 to program it
- 68020 held in reset

**Solution**: Auto-release timer
```systemverilog
reg [15:0] reset_release_counter;
// Releases 68020 after ~8192 cycles regardless of Port C
// Allows 68020 to boot and initialize VIA
```

### 6. **VIA ↔ Egret Connections** (Verified Working)
```systemverilog
// CB1/CB2 properly connected in dataController_top.sv:
.cb1_i(via_cb1_in)              // VIA receives CB1 from Egret
.cb2_i(cuda_cb2_oe ? cuda_cb2 : cb2_i)  // Bidirectional CB2
.cb2_o(cb2_o)                   // VIA CB2 output
.via_cb2_in(cb2_o)              // Egret receives VIA CB2
.cuda_cb1(cuda_cb1)             // Egret drives CB1
```

## Key Discoveries 🔍

1. **Port A bit 5 must be 1** - Indicates "Egret controls power" (Mac LC configuration)
2. **Port A bit 1 must be 1** - Chassis power switch on
3. **ROM data timing critical** - Must be combinational, not registered
4. **CPU has no clock enable** - Runs every cycle, peripherals must sync with `cen`
5. **Egret won't release 68020** without VIA handshake in normal operation - needed override

## Current Status 🎯

- ✅ Egret CPU running and executing firmware
- ✅ Port A initialized (DDR = 0xFF)
- ✅ 68020 released from reset (auto-timer working)
- ✅ 68020 CPU now starting
- ⚠️ **New Issue**: VIA communication problems (next focus area)

## Files Delivered 📁

All at `/mnt/user-data/outputs/`:
- `m68hc05_core.sv` - 68HC05 CPU core
- `m68hc05_alu.sv` - ALU components  
- `egret_wrapper.sv` - **LATEST VERSION with auto-reset**
- `egret_clock_gen.sv` - Optional clock divider (not needed if using PLL)

## Next Steps 🚀

1. Debug VIA communication issues
2. Verify VIA shift register operation
3. Check TREQ/TIP/CB1/CB2 handshake sequence
4. Monitor VIA←→Egret data exchange
5. Ensure proper initialization sequence

## Important Notes 📝

- RAM reads also made combinational for consistency
- All simulation debug can be disabled by removing `SIMULATION` define
- The auto-reset timer (0x2000 cycles) may need tuning based on actual boot timing
- Port B DDR and Port C initialization happen after 68020 boots (normal operation)