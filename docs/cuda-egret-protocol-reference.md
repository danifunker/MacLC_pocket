# CUDA/Egret Protocol Reference

Compiled from Linux kernel `drivers/macintosh/via-cuda.c` and MAME `egret.cpp`.

## Signal Definitions

### VIA Port B Bit Assignments
| Bit | Signal | Description |
|-----|--------|-------------|
| 5 | TIP | Transaction In Progress (active LOW for CUDA, active HIGH for Egret on host side) |
| 4 | TACK | Transfer Acknowledge / BYTEACK (toggled per byte) |
| 3 | TREQ | Transfer Request from device (active LOW = device has data) |

**Polarity note:** The Linux driver inverts TIP and TACK for Egret vs CUDA:
- CUDA: assert TIP = set bit LOW; assert TACK = set bit LOW
- Egret: assert TIP = set bit HIGH; assert TACK = set bit HIGH

However, on the **Egret firmware side** (HC05 Port B bit 3 = sys_session), TIP LOW = session active, HIGH = idle. The polarity difference is on the host VIA side, not the Egret side.

### VIA Shift Register
- **SR (register 0xA):** 8-bit shift register for data transfer
- **ACR bit 4-2:** Shift register mode (mode 3 = shift in under external clock CB1)
- **CB1:** Shift clock (driven by Egret in external clock mode)
- **CB2:** Shift data (bidirectional, directly active for shift-out mode)
- **IFR bit 2:** SR interrupt flag, set when 8-bit shift completes

## Transaction Types

### Host-to-Device (68020 sends command to Egret)
1. Host sets VIA SR to shift-out mode (ACR)
2. Host writes first data byte to SR
3. Host asserts TIP to start transaction
4. Host toggles TACK to signal byte is ready
5. Egret clocks 8 bits via CB1 (reads SR data)
6. Egret asserts TREQ when ready for next byte
7. Host detects TREQ, writes next byte to SR
8. Host toggles TACK again
9. Repeat steps 5-8 for each byte
10. When all bytes sent, host negates TIP and TACK

### Device-to-Host (Egret sends data to 68020)
1. Egret asserts TREQ (has data to send)
2. Host detects TREQ, asserts TIP to acknowledge
3. Host sets VIA SR to shift-in mode (ACR)
4. Egret clocks 8 bits via CB1 (shifts data into SR)
5. SR completion sets IFR bit 2
6. Host reads SR to get data byte
7. Host toggles TACK to acknowledge receipt
8. Egret loads next byte, clocks it in
9. Repeat steps 4-8
10. Egret negates TREQ when transfer complete (or last byte flag set)
11. Host negates TIP and TACK

## State Machine (from Linux via-cuda.c)

```
States:
  idle              — Waiting for activity
  sent_first_byte   — First byte of host request sent, awaiting ack
  sending           — Transmitting remaining request bytes
  reading           — Receiving data from device
  read_done         — Data reception complete
  awaiting_reply    — Request sent, waiting for device response

Transitions:
  idle → sent_first_byte:
    - Write first request byte to SR
    - Assert TIP
    - Toggle TACK

  sent_first_byte → sending:
    - SR interrupt: device acknowledged (normal flow)
    - Write next byte to SR
    - Toggle TACK

  sent_first_byte → idle:
    - TREQ asserted unexpectedly = COLLISION
    - Abort: negate TIP and TACK
    - Retry after delay

  sending → sending:
    - SR interrupt for each byte
    - Write next byte, toggle TACK

  sending → awaiting_reply:
    - All bytes sent
    - Negate TIP (end of host send)
    - Wait for device response

  awaiting_reply → reading:
    - Device asserts TREQ with reply data
    - Assert TIP, set SR to shift-in
    - Read first byte

  reading → reading:
    - SR interrupt: byte received
    - Toggle TACK, read SR
    - Continue until TREQ negates

  reading → read_done:
    - TREQ negated = transfer complete
    - Read final SR byte

  read_done → idle:
    - Negate TIP and TACK
    - Process reply
```

## Timing Requirements (Egret-specific)

From Linux kernel `via-cuda.c`:

| Delay | Duration | Purpose |
|-------|----------|---------|
| EGRET_SESSION_DELAY | 450 µs | From SR interrupt to session start |
| EGRET_TACK_ASSERTED_DELAY | 300 µs | Duration TACK is held asserted |
| EGRET_TACK_NEGATED_DELAY | 400 µs | Duration TACK is held negated before next byte |

### Initialization Sequence
- 4 ms delay after disabling interrupts before sync attempts
- 100 µs polling intervals in WAIT_FOR macro (1000 iterations max)
- Sync byte: 0x01 sent repeatedly until device responds

### Clock Rates
- Real Egret: 32.768 kHz × 128 = 4.194304 MHz
- Our simulation: 32 MHz / 8 = 4.0 MHz (4.6% slower)
- 68020: 8 MHz (16 MHz optional)

## Packet Format

### Command Packet (Host → Egret)
```
Byte 0: Packet type
  0x00 = ADB command
  0x01 = Pseudo-command
  0x02 = Error response (from Egret only)

Byte 1: ADB command byte (for type 0x00)
         OR sub-command (for type 0x01)

Byte 2+: Data payload (variable length)
```

### Pseudo-commands (type 0x01)
| SubCmd | Name | Description |
|--------|------|-------------|
| 0x01 | Warm start | Reset Egret |
| 0x03 | Read PRAM | Read parameter RAM (offset in data) |
| 0x07 | Write PRAM | Write parameter RAM |
| 0x09 | Read time | Read real-time clock |
| 0x0B | Powerdown | System power off |
| 0x0D | Set auto-power | Set auto-power time |
| 0x11 | Set power LED | Control power LED |
| 0x12 | Get time | Alternative time read |
| 0x13 | Set time | Set real-time clock |
| 0x21 | Mono stable reset | |
| 0x22 | Set DFAC | Set Display Factory Adjust Code |
| 0x23 | Get DFAC | Read DFAC |

### Response Packet (Egret → Host)
```
Byte 0: Packet type (echo of command type, or 0x02 for error)
Byte 1: Response flags / status
Byte 2+: Response data
```

## Collision Handling

When both host and device start transactions simultaneously:
1. Host asserts TIP to start its transaction
2. Device also asserts TREQ (has unsolicited data)
3. Host detects TREQ while in `sent_first_byte` state
4. Host aborts: negates TIP and TACK
5. Host services the device's request first (reads TREQ data)
6. Host retries its original command after

## Key Implementation Notes

### VIA Shift Register Modes (ACR bits 4-2)
| Mode | Description |
|------|-------------|
| 000 | SR disabled |
| 001 | Shift in under T2 control |
| 010 | Shift in under system clock |
| 011 | Shift in under external clock (CB1) ← **Used by Egret** |
| 100 | Free-run at T2 rate |
| 101 | Shift out under T2 control |
| 110 | Shift out under system clock |
| 111 | Shift out under external clock (CB1) ← **Used by Egret** |

### CB1/CB2 in Egret Mode
- **CB1 (shift clock):** Driven by Egret. Each CB1 falling edge shifts one bit.
- **CB2 (shift data):**
  - Shift-in (mode 3): CB2 is input, Egret drives data on CB2
  - Shift-out (mode 7): CB2 is output, VIA drives data from SR onto CB2
- After 8 CB1 clock edges, IFR bit 2 is set (shift complete)

### Open-Drain TREQ
TREQ (PB3) is open-drain: both VIA and Egret can pull it low independently. It's only high when neither is pulling low. In our design:
```verilog
wire pb3_via_pulling_low = via_pb_oe[3] & ~via_pb_o[3];
wire pb3_cuda_pulling_low = cuda_treq;
wire pb3_open_drain = ~(pb3_via_pulling_low | pb3_cuda_pulling_low);
```

## External References
- Linux kernel: `drivers/macintosh/via-cuda.c`
- MAME: `src/mame/apple/egret.cpp`, `src/mame/apple/egret.h`
- MAME: `src/mame/apple/cuda.cpp`
- MaximumSpatium: `github.com/maximumspatium/CudaFirmware` (disassembly)
- Apple ERS: CUDA/Egret Engineering Reference Specification
- Inside Macintosh Vol VI, Appendix C
