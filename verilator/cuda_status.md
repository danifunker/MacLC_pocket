# CUDA/VIA Interface Status

## Completed Fixes

### 1. Port B Pin Mappings (cuda_maclc.sv)
Mac LC V8 protocol uses different port B assignments than Mac Plus:
- PB3: XCVR_SESSION = TREQ from CUDA (input to VIA)
- PB4: VIA_FULL = BYTEACK from VIA (output to CUDA)
- PB5: SYS_SESSION = TIP from VIA (output to CUDA)

### 2. CB2 Timing (cuda_maclc.sv)
CUDA outputs CB2 data on CB1 falling edge (instead of rising edge), giving proper setup time for VIA to sample.

### 3. First Bit Timing Fix (cuda_maclc.sv)
Added condition to NOT shift on the first falling edge (bit_counter == 0). The initial cb2_out_reg is already set to bit 7 in ST_WAIT_SR_READ, and VIA needs to sample bit 7 on the first RISING edge.

### 4. Byte Complete Timing (cuda_maclc.sv)
Fixed the clocking to stop after the 8th rising edge. Condition: `!(cb1_out == 1'b1 && bit_counter >= 4'd8)` ensures we complete the 8th rising edge but no more.

### 5. CB2 Output Enable Timing (cuda_maclc.sv)
Keep cb2_oe_reg=1 in ST_COMPLETE and ST_WAIT_TIP_RISE until TIP actually rises. This ensures VIA sees the correct CB2 value even if its E_falling shift happens several clk8_en cycles after CB1 rises.

### 6. VIA CB2 Sampling (via6522.sv)
Changed VIA to use cb2_i directly instead of ser_cb2_c for shift register input. This avoids timing issues where ser_cb2_c might have an old value due to different clock phases.

### 7. VIA PRB Initialization (via6522.sv)
Changed VIA's Port B Output Register reset value from 0x00 to 0xFF to prevent false TIP assertion at startup.

### 8. TREQ Open-Drain Behavior (dataController_top.sv)
Fixed Port B logic so CUDA can pull TREQ low even when VIA has the bit configured as output.

## Current Status: Working!

The CUDA/VIA serial communication is now functioning correctly:
1. CUDA sends startup message (0x02) via VIA shift register
2. VIA correctly receives all 8 bits
3. SR IRQ fires with correct value (0x02)
4. ROM acknowledges and releases TIP
5. CUDA returns to idle state
6. System shows Mac startup gray screen at frame 600

## State Machine

The CUDA state machine:
- ST_ATTENTION (0) - Startup: assert TREQ to signal presence
- ST_IDLE (1) - Wait for TIP falling edge
- ST_WAIT_CMD (2) - Wait for command byte
- ST_SHIFT_IN_CMD (3) - Clock in command
- ST_WAIT_LENGTH (4) - Wait for length byte
- ST_SHIFT_IN_LENGTH (5) - Clock in length
- ST_SHIFT_IN_DATA (6) - Clock in data bytes
- ST_PROCESS_CMD (7) - Process received command
- ST_PREPARE_RESPONSE (8) - Prepare response data
- ST_WAIT_SR_READ (9) - Wait for ROM to read VIA SR
- ST_SHIFT_OUT_LENGTH (10) - Clock out response length
- ST_SHIFT_OUT_DATA (11) - Clock out response data
- ST_COMPLETE (12) - Transaction complete
- ST_WAIT_TIP_RISE (13) - Wait for TIP to be released

## Port B Bit Assignments (Mac LC V8)

- Bit 0: 5V Sense (input)
- Bit 1: Unused
- Bit 2: Unused
- Bit 3: TREQ/XCVR_SESSION - Transfer Request from CUDA (input to VIA, active LOW)
- Bit 4: BYTEACK/VIA_FULL - Byte Acknowledge (output to CUDA)
- Bit 5: TIP/SYS_SESSION - Transaction In Progress (output to CUDA, active LOW)
- Bit 6: I2C SDA
- Bit 7: I2C SCL

## Files Modified

- `rtl/cuda_maclc.sv` - Major state machine updates, timing fixes, polarity corrections
- `rtl/via6522.sv` - CB2 sampling fix, PRB initialization to 0xFF
- `rtl/dataController_top.sv` - Debug output, TREQ open-drain behavior

## Serial Transfer Timing Diagram

```
CB1:    ____/‾‾‾‾\____/‾‾‾‾\____/‾‾‾‾\____/‾‾‾‾\____  (8 cycles)
CB2:    [b7][b6 ][b5 ][b4 ][b3 ][b2 ][b1 ][b0 ]      (MSB first)
            ^     ^     ^     ^     ^     ^     ^     ^
            R0    R1    R2    R3    R4    R5    R6    R7  (VIA samples on rising)
```

- CB2 is set to bit 7 before first rising edge
- CB2 is updated on falling edges for bits 6-0
- VIA samples CB2 on rising edges
- After 8th rising edge, CUDA stops clocking
