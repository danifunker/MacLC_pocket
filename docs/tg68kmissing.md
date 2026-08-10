# TG68K Instruction & Signal Coverage Analysis

Analysis date: 2026-03-21
Source: ROM disassembly (`docs/MacLC_ROM_disasm.txt`), TG68K core (`rtl/tg68k/`)

## Instruction Coverage

### Standard 68000 — All Supported

Every standard 68000 instruction used by the Mac LC ROM is implemented in TG68K:

ABCD, ADD, ADDA, ADDI, ADDQ, ADDX, AND, ANDI, ASL, ASR, Bcc (all conditions),
BCHG, BCLR, BSET, BTST, BRA, BSR, CHK, CLR, CMP, CMPA, CMPI, CMPM, DBcc,
DIVS, DIVU, EOR, EORI, EXG, EXT, JMP, JSR, LEA, LINK, LSL, LSR, MOVE, MOVEA,
MOVEM, MOVEP, MOVEQ, MULS, MULU, NBCD, NEG, NEGX, NOP, NOT, OR, ORI, PEA,
RESET, ROL, ROR, ROXL, ROXR, RTE, RTR, RTS, SBCD, Scc, SUB, SUBA, SUBI, SUBQ,
SUBX, SWAP, TAS, TRAP, TRAPV, TST, UNLK

### 68010+ Instructions

| Instruction | Supported | Notes |
|-------------|-----------|-------|
| MOVEC       | Yes       | Move to/from control registers (VBR, SFC, DFC) |
| RTD         | Yes       | Return and deallocate stack |
| MOVE from CCR | Yes     | Separate from MOVE from SR (privileged on 68010+) |
| MOVES       | **No**    | Alternate address space access — trapped as illegal. Not needed (no MMU on LC) |
| BKPT        | **No**    | Debugger breakpoint — trapped as illegal. Not used by ROM |

### 68020+ Instructions

| Instruction | Supported | ROM Uses | Notes |
|-------------|-----------|----------|-------|
| BFCHG       | Yes       | 18       | Bit field change |
| BFCLR       | Yes       | 3        | Bit field clear |
| BFEXTS      | Yes       | 5        | Bit field extract signed |
| BFEXTU      | Yes       | 326      | Bit field extract unsigned (heavily used) |
| BFFFO       | Yes       | 9        | Bit field find first one |
| BFINS       | Yes       | 131      | Bit field insert (heavily used) |
| BFSET       | Yes       | 14       | Bit field set |
| BFTST       | Yes       | 9        | Bit field test |
| CAS         | Yes       | 5        | Compare and swap |
| CMP2        | Yes       | 11       | Compare register against bounds |
| DIVSL       | Yes       | 3        | Signed long divide |
| DIVUL       | Yes       | 6        | Unsigned long divide |
| EXTB        | Yes       | 3        | Sign extend byte to long |
| PACK        | Yes       | 131      | Pack BCD (many are likely data misinterpreted as code) |
| UNPK        | Yes       | 296      | Unpack BCD (many are likely data misinterpreted as code) |
| TRAPcc      | Yes       | 4        | Conditional trap |
| CALLM       | **No**    | 6        | Call module — trapped as illegal. Only ever on 68020, removed from later CPUs. ROM uses are data misinterpretation |
| RTM         | **No**    | 8        | Return from module — same as CALLM |

### Exception Handling

| Feature               | Supported | Notes |
|-----------------------|-----------|-------|
| F-line exception ($2C)| Yes       | All FPU/MMU opcodes ($Fxxx) trap correctly. ROM handles FPU emulation and MMU detection via this vector |
| A-line exception ($28)| Yes       | Mac Toolbox trap dispatch |
| Bus Error ($08)       | Yes       | BERR input signal with full state machine (make_berr/trap_berr) |
| Address Error ($0C)   | Yes       | Odd-address word/long access |
| Privilege Violation   | Yes       | SVmode checks on privileged instructions |

### Unsupported Instructions — Impact Assessment

None of the unsupported instructions (MOVES, BKPT, CALLM, RTM) are actually needed by the Mac LC.
MOVES requires an MMU (LC has none). BKPT is for debuggers. CALLM/RTM were only on the 68020 and
no shipping software used them. The ROM occurrences are objdump misinterpreting data tables as code.

---

## Hardware Signal Coverage

### Signals Present (Real 68000/68020 vs TG68K)

| Signal         | Real CPU  | TG68K      | Connection in MacLC.sv |
|----------------|-----------|------------|------------------------|
| CLK            | Yes       | Yes        | `clk_sys` |
| RESET (in)     | Yes       | Yes        | `!_cpuReset` |
| RESET (out)    | Yes       | Yes        | `tg68_reset_n` |
| D[15:0]        | Yes       | Yes        | `dataControllerDataOut` / `tg68_dout` |
| A[31:0]        | Yes       | Yes (32b)  | `tg68_a` |
| AS             | Yes       | Yes        | `tg68_as_n` |
| UDS / LDS      | Yes       | Yes        | `tg68_uds_n` / `tg68_lds_n` |
| R/W            | Yes       | Yes        | `tg68_rw` |
| DTACK          | Yes       | Yes        | `_cpuDTACK` |
| BERR           | Yes       | Yes        | `cpuFC == 3'b111` |
| IPL[2:0]       | Yes       | Yes        | `_cpuIPL` |
| FC[2:0]        | Yes       | Yes        | `tg68_fc2/fc1/fc0` |
| BR             | Yes       | Yes        | Tied to `1'b1` (inactive) |
| BG             | Yes       | Yes        | Unconnected |
| BGACK          | Yes       | Yes        | Tied to `1'b1` (inactive) |
| VPA            | Yes       | Yes        | `_cpuVPA` |
| VMA            | Yes       | Yes        | `tg68_vma_n` |
| E clock        | Yes       | Yes        | Generated internally |
| AVEC (68020)   | Yes       | Partial    | `IPL_autovector` on kernel |

### Signals Missing

| Signal           | Real CPU | Impact     | Details |
|------------------|----------|------------|---------|
| **HALT**         | Bidir    | **Significant** | See below |
| **DSACK[1:0]**   | 68020    | **Moderate** | See below |
| **SIZ[1:0]**     | 68020    | Moderate   | Transfer size indicator, paired with DSACK |
| ECS / OCS        | 68020    | Negligible | Early/operand cycle start — timing signals |
| DBEN             | 68020    | Negligible | Data buffer enable — board-level signal |
| IPEND            | 68020    | Negligible | Interrupt pending status |
| CDIS             | 68020    | Negligible | Cache disable — no cache in TG68K anyway |

### HALT — Significant Gap

The real 68000/68020 HALT pin is **bidirectional**:

- **As input:** External hardware halts the CPU. Used with BERR for **bus retry** — the Mac
  asserts BERR+HALT simultaneously to make the CPU retry the faulted bus cycle instead of
  taking an exception.
- **As output:** CPU asserts HALT on **double bus fault** (two consecutive bus errors).

TG68K has no HALT signal. This is a known limitation (also noted for FX68K in CLAUDE.md).

**Mac LC uses BERR+HALT for:**
- Memory/hardware sizing during boot (probe addresses, retry on timeout)
- NuBus/PDS slot timeout recovery
- Potentially SCSI bus error recovery

**Current workaround:** BERR alone generates a bus error exception. The ROM's exception handler
must deal with the error in software rather than getting an automatic retry. This may cause
issues with hardware detection routines that expect retry behavior.

### DSACK / SIZ — Moderate Gap

The real 68020 replaces DTACK with DSACK[1:0] for **dynamic bus sizing**:
- `DSACK = 00` → 32-bit port
- `DSACK = 01` → 16-bit port (CPU does two cycles automatically)
- `DSACK = 10` → 8-bit port (CPU does four cycles automatically)

The Mac LC's 68020 uses this to transparently talk to 8-bit peripherals (VIA, SCC, IWM)
on its 32-bit bus.

**Current workaround:** The TG68K bus wrapper (`tg68k.v`) operates as a 16-bit bus, so all
accesses are already broken into 16-bit transfers by the wrapper. The address decoder in
`addrController_top.v` / `dataController_top.sv` handles byte lane routing for 8-bit
peripherals. This works but means the core never does native 32-bit transfers.

---

## Summary

**Instructions:** Full coverage for everything the Mac LC ROM actually needs. The 4 unsupported
instructions (MOVES, BKPT, CALLM, RTM) are not used by any Mac software.

**Signals:** Two meaningful gaps:
1. **HALT** (bus retry) — no workaround in hardware, ROM must handle via exception. May affect
   boot-time hardware probing.
2. **DSACK/SIZ** (dynamic bus sizing) — worked around by 16-bit bus wrapper and software
   byte-lane routing. Functional but not cycle-accurate to real hardware.
