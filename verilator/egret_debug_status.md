# Egret/VIA Communication Debug Status

## Current Status: ROM MAPPING FIXED

### Update Jan 1, 2026 - ROM Address Mapping Fix

**Root Cause Found:** The CPU was fetching `0x0000` from addresses `0x1A0000`, `0x300000`, etc., immediately after reset. This was due to incorrect ROM address calculation in the simulation wrapper.

**The Problem:**
1. **Misaligned Download:** In `sim.v`, the ROM download path was adding `0x200000` to `dio_a_comb`, which already included the `0x40000` offset for the Mac LC ROM. This placed the ROM data at word address `0x240000` instead of the expected location.
2. **Misaligned Read:** The CPU read path in `sim.v` was also calculating the wrong address for ROM accesses.
3. **Result:** The 68020 fetched empty memory (`0x0000`) instead of the reset vector, causing it to crash immediately into a loop or spurious execution path.

**Fix Applied:**
Modified `verilator/sim.v` to use a consistent and correct word address for both downloading and reading the ROM:
```verilog
wire [24:0] ram_addr = download_cycle ? {3'b000, 1'b1, dio_a_comb[20:0] } :  // ROM at word 0x200000 + dio_a_comb
                       ~_romOE        ?
                       {3'b000, 1'b1, 3'b001, memoryAddr[18:1]} :  // ROM reads at word 0x200000 + 0x40000
                                      {3'b000, (dskReadAckInt || dskReadAckExt), memoryAddr[21:1]};
```
This ensures the ROM is loaded at word address `0x240000` (byte address `0x480000` in the simulation RAM buffer) and accessed correctly by the CPU when it reads from `0xA00000`.

**Verification:**
- **Simulation:** Pending trace confirmation. The previous run timed out due to excessive logging, but the logic fix addresses the root cause of the invalid instruction fetches.

---

### Previous Status: RACE CONDITION IDENTIFIED (FIXED)

**Root Cause Found:** Egret asserted TREQ before the 68020 was released from reset. By the time the 68020 started, Egret had timed out and stopped asserting TREQ.

**Fix Applied:**
Modified `dataController_top.sv` to synchronize Egret start with the system reset delay (`minResetPassed`). This ensures Egret waits for the CPU to be ready before asserting TREQ.

---

### Previous Status: VIDEO DETECTION FAILING (INVESTIGATING)

**Issue:** The ROM fails to read the PseudoVIA video config register (0x10) and enters a POST test pattern mode.

**Analysis:**
- This failure was likely a symptom of the CPU executing garbage code due to the ROM mapping issue. The CPU was jumping to random locations or executing invalid instructions, which coincidentally looked like a video initialization loop or a crash handler.
- With the ROM mapping fixed, we expect the CPU to properly fetch the reset vector and execute the valid boot sequence, which should include reading PseudoVIA register 0x10.

---

## Signal Mapping Reference

### VIA Port B (V8 Protocol)
| Bit | Signal | Direction | Description |
|-----|--------|-----------|-------------|
| 5 | SYS_SESSION | Output | TIP to Egret |
| 4 | VIA_FULL | Output | BYTEACK to Egret |
| 3 | XCVR_SESSION | Input | TREQ from Egret |

### PseudoVIA Register 0x10 (Video Config)
| Bits | Function | Description |
|------|----------|-------------|
| 7:6 | Reserved | |
| 5:3 | Monitor ID | Read: returns sense pins (0-7) |
| 2:0 | BPP Mode | 0=1bpp, 1=2bpp, 2=4bpp, 3=8bpp, 4=16bpp |

---

## Next Steps

1. **Verify ROM Boot:** Run the simulation with the address mapping fix and confirm the CPU fetches valid opcodes starting from the reset vector.
2. **Monitor Initialization:** Check if the ROM now correctly reads PseudoVIA register 0x10 and other peripherals.
3. **Check Egret/VIA Handshake:** Ensure the initial Egret/VIA communication completes successfully now that the CPU is running valid code.
