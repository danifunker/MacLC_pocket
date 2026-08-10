# CUDA Debug Status

## Date: 2025-12-27 (Updated)

## Summary

CUDA/VIA serial communication is now working for multi-byte transactions. Boot progresses past the white screen and multiple CUDA commands are being processed. All known CUDA commands are now implemented.

## What's Working

### CUDA Communication Protocol
- Multi-byte packet receive (ROM→CUDA) ✓
- Multi-byte packet send (CUDA→ROM) ✓
- Proper handling of TIP release/re-assertion between bytes
- VIA shift register completes correctly with 9 CB1 edges
- Spurious shift cleanup in IDLE state

### CUDA Commands Implemented
| Command | Value | Status | Description |
|---------|-------|--------|-------------|
| CUDA_AUTOPOLL | 0x01 | ✓ | Enable/disable ADB autopoll |
| CUDA_GET_TIME | 0x03 | ✓ | Get RTC time |
| CUDA_SET_TIME | 0x09 | ✓ | Set RTC time |
| CUDA_GET_PRAM | 0x07 | ✓ | Read PRAM byte |
| CUDA_SET_PRAM | 0x0C | ✓ | Write PRAM byte |
| CUDA_SEND_DFAC | 0x0e | ✓ | Send to Digital Filter Audio Chip (I2C) |
| CUDA_RESET_SYSTEM | 0x11 | ✓ | Reset 680x0 |
| CUDA_SET_IPL | 0x12 | ✓ | Set interrupt priority level |
| CUDA_SET_AUTO_RATE | 0x14 | ✓ | Set ADB autopoll rate |
| CUDA_GET_AUTO_RATE | 0x16 | ✓ | Get ADB autopoll rate |
| CUDA_SET_DEV_LIST | 0x19 | ✓ | Set ADB device list |
| CUDA_GET_DEV_LIST | 0x1a | ✓ | Get ADB device list |
| CUDA_SET_ONE_SEC | 0x1b | ✓ | Set one-second interrupt mode |
| CUDA_GET_SET_IIC | 0x22 | ✓ | I2C read/write |
| Unknown | 0x1c | OK | Unknown command (returns success) |

### Command Sources
- [Linux kernel cuda.h](https://raw.githubusercontent.com/torvalds/linux/master/include/uapi/linux/cuda.h)
- [Apple AppleCudaCommands.h](https://github.com/apple-oss-distributions/AppleCuda)

### Boot Progress
- Boot passes CUDA initialization
- Video system is being configured
- Screen shows diagonal pattern (video mode test or RAM test)

## Key Fixes Made

### 1. Multi-byte Receive (ROM→CUDA)
**Problem:** ROM releases TIP between bytes to check TREQ. CUDA was timing out after first byte.

**Solution:**
- Clock 9 CB1 edges per byte (8 data + 1 for VIA completion)
- Clear sr_write_seen on edge 8→9, not edge 7→8
- Handle sr_write_seen with TIP re-assertion check
- Wait counter only increments when bit_counter >= 9

### 2. Multi-byte Send (CUDA→ROM)
**Problem:** CUDA waited for SR read edge before sending, but ROM reads SR *after* shift completes.

**Solution:**
- Start sending when VIA is in external clock INPUT mode (no SR read wait)
- In SEND_DONE, wait for TIP re-assertion instead of immediately going to FINISH
- Simplified AUTOPOLL response to 2 bytes (ROM expectation)
- Added timeout in SEND_DONE for robustness

### 3. Spurious VIA Shift After Transaction
**Problem:** After transaction, ROM reads SR to get last byte, which auto-triggers a new shift in mode 3. CUDA in IDLE doesn't clock, so shift never completes. ROM polls IFR forever.

**Solution:**
- In ST_IDLE, continue providing CB1 clocks if VIA is in external clock mode
- Clock until bit_counter reaches 9, then stop
- This clears any pending shift and allows ROM to proceed

### 4. CUDA Commands (Latest)
**Problem:** Commands 0x0e, 0x1b were returning PKT_ERROR without OK status.

**Solution:**
- Implemented CUDA_SEND_DFAC (0x0e) - acknowledges I2C audio chip commands
- Implemented CUDA_SET_ONE_SEC (0x1b) - one-second interrupt mode
- Implemented CUDA_GET_DEV_LIST (0x1a) - returns empty device list
- Unknown commands now return PKT_ERROR + 0x00 (success) to not block boot

## Protocol Details

### ROM→CUDA (Receive) Sequence
1. ROM asserts TIP
2. ROM configures VIA to mode 7 (shift OUT, external clock)
3. ROM writes byte to SR (starts shift)
4. CUDA clocks CB1 9 times (8 data + 1 completion)
5. VIA sets IFR SR bit
6. ROM toggles BYTEACK
7. ROM releases TIP to check TREQ
8. If CUDA has more data (TREQ asserted), ROM re-asserts TIP
9. Repeat for more bytes

### CUDA→ROM (Send) Sequence
1. CUDA asserts TREQ
2. ROM asserts TIP
3. ROM configures VIA to mode 3 (shift IN, external clock)
4. CUDA clocks CB1 and puts data on CB2 (8 clocks)
5. VIA sets IFR SR bit
6. ROM reads SR to get byte
7. ROM releases TIP to check TREQ
8. If CUDA has more data (TREQ still asserted), ROM re-asserts TIP
9. After last byte, CUDA de-asserts TREQ
10. ROM sees TREQ de-asserted, transaction complete

## Files Modified

### /rtl/cuda_maclc.sv
- Added via_sr_dir input for checking VIA shift direction
- Fixed RECV_WAIT to provide 9 CB1 edges
- Fixed sr_write_seen clearing timing
- Removed SR read wait requirement for SEND_WAIT
- Added TIP re-assertion handling in SEND_DONE
- Added CB1 clocking in ST_IDLE for spurious shift cleanup
- Simplified AUTOPOLL response to 2 bytes
- Added timeout handling throughout
- Added command handlers for 0x0e, 0x1a, 0x1b, 0x14, 0x16, 0x12, 0x22

### /rtl/dataController_top.sv
- Added via_sr_dir connection to CUDA

### /rtl/via6522.sv
- Debug output improvements

## Debug Commands

```bash
# Run simulation with screenshot
timeout 300 ./obj_dir/Vemu --screenshot 400 --stop-at-frame 450 2>&1 | tee sim_output.log

# Check CUDA commands processed
grep "PROCESS packet" sim_output.log

# Check specific commands
grep -E "AUTOPOLL|DFAC|ONE_SECOND|DEV_LIST" sim_output.log

# Check state transitions
grep -E "state.*->" sim_output.log

# Check for unknown commands
grep "Unknown CUDA" sim_output.log

# Check VIA shift completion
grep "SR shift complete" sim_output.log
```

## Next Steps

1. **Investigate video pattern:**
   - Check if video mode is being set correctly
   - Verify RAM contents if this is a RAM test pattern

2. **Continue boot debugging:**
   - Monitor for any stuck states
   - Investigate command 0x1c if it's blocking boot

3. **Add ADB device support:**
   - Currently returning empty device list
   - May need to implement keyboard/mouse for full boot

## Unknown Command 0x1c

Command 0x1c is NOT documented in:
- Linux kernel cuda.h
- Apple's AppleCudaCommands.h (which goes up to 0x1b)

Possible explanations:
- Firmware-version specific command
- Vendor extension for specific Mac models
- Undocumented internal command

Current handling: Returns success (PKT_ERROR + 0x00) to avoid blocking boot.

## Screenshot

Frame 480/750 shows diagonal line pattern - video initialization is occurring but Mac startup screen not yet visible.
