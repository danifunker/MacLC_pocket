# How to Analyze `boot0.rom`

This is a practical guide for reverse-engineering the Mac LC boot ROM
(`releases/boot0.rom`) — the exact commands, flags, and techniques used
during the 2026-04 boot-hang investigation. You should be able to
reproduce and extend any analysis in `docs/bootproblems.md` using this
file.

## 1. Prerequisites

- **Disassembler:** `m68k-elf-objdump` (part of a 68k cross-binutils).
  Installed via Homebrew on macOS:
  ```bash
  brew install --cask gcc-arm-embedded   # NO — that's ARM
  # Use: https://github.com/gnu-mcu-eclipse or build from binutils source.
  ```
  On this machine it lives at `/opt/homebrew/bin/m68k-elf-objdump`.
  To confirm: `which m68k-elf-objdump`.

- **Python 3** for decoding byte-tables (built-in on macOS).

- **Ripgrep or grep** for searching the saved disassembly text.

## 2. ROM address map

- The Mac LC ROM maps at virtual address `$A00000`–`$AFFFFF`
  (see `rtl/addrDecoder.v:13`).
- `boot0.rom` is 524288 bytes (`0x80000`).
- **Conversion:** `file_offset = virtual_addr - 0xA00000`. E.g.
  virtual `$A46462` → file offset `0x46462`.

## 3. Disassembling the whole ROM

```bash
m68k-elf-objdump \
    -D \
    -b binary \
    -m m68k \
    --adjust-vma=0xA00000 \
    releases/boot0.rom \
    > /tmp/disasm.txt
```

**Flags explained:**
| Flag | Meaning |
|------|---------|
| `-D` | Disassemble the **whole** file, not just exec sections (required for raw binary) |
| `-b binary` | Input is a flat binary, not ELF |
| `-m m68k` | Use the Motorola 68k architecture |
| `--adjust-vma=0xA00000` | Shift addresses so they match the virtual address on the bus (default would be 0) |

Output is ~7 MB / 100k lines. Saving to a file makes repeated searches cheap:

```bash
grep "a46462" /tmp/disasm.txt
```

## 4. Disassembling a specific region (inline)

For quick inspection around a known address, pipe through `awk`:

```bash
m68k-elf-objdump -D -b binary -m m68k --adjust-vma=0xA00000 \
    releases/boot0.rom 2>/dev/null \
    | awk '/a46420:/,/a46470:/'
```

The two `awk` addresses bracket the range. Useful for pasting into
notes without pulling the whole 7 MB file.

**Tip:** the trailing `2>/dev/null` hides `objdump`'s chatter about the
binary format.

## 5. Reading the disassembly

Each line looks like:

```
  a46452:	6640           	bnes 0xa46494
  │         │              │
  │         │              └── mnemonic + operands (branch if not equal)
  │         └── raw bytes
  └── virtual address (already adjusted by --adjust-vma)
```

Notes on 68k syntax used by GNU objdump:
- `%fp` = A6 (frame pointer). The ROM uses `lea (target,pc), %fp` + `jmp`
  as a "call with return-address in A6" idiom.
- `%sp` = A7 (stack pointer).
- Suffixes: `.b`/`.w`/`.l` for byte/word/long.
- `bnes`, `beqs`, `bras` are short-form (8-bit displacement) branches;
  `bnew`, `beqw`, `braw` are word-form (16-bit displacement).
- `a3@(2)` means `(A3 + 2)` — memory access.
- `a3@(2,d3:l)` means `(A3 + 2 + D3)` — indexed.
- `pc@(0xa49f78)` is PC-relative with the computed absolute target
  objdump kindly resolved for you.

## 6. Searching the saved disassembly

### Find every reference to an address

To see everywhere a function is called or branched to:

```bash
grep -n "a498a0" /tmp/disasm.txt
```

Or with the repo's Grep tool (ripgrep under the hood):

```bash
rg "a498a0" /tmp/disasm.txt
```

The output distinguishes the *definition* line
(`  a498a0:	4DFA  lea ...`) from *references*
(`  a48d04:	6000 0b9a      	braw 0xa498a0`).

### Find all instances of an instruction

```bash
rg "bset #26,%d7" /tmp/disasm.txt      # where is d7 bit 26 set?
rg "bclr #16,%d7" /tmp/disasm.txt      # where is it cleared?
```

### List every entry point for a target

To find all branches into STM (`$A498A0`) in the 2026-04-15 session we used:

```bash
m68k-elf-objdump -D -b binary -m m68k --adjust-vma=0xA00000 \
    releases/boot0.rom 2>/dev/null \
    | grep -E "(a498|a499|a49a)" \
    | grep -v "^ *00a49"
```

The `grep -v "^ *00a49"` filters out *definition* lines (which start with
the address `00a49...:`), leaving only *references from elsewhere*.

## 7. Decoding embedded byte tables

ROM jump/dispatch tables often look like garbage instructions in the
disassembly. Pull the raw bytes with Python:

```bash
python3 -c "
data = open('releases/boot0.rom','rb').read()
base = 0xa49948 - 0xa00000              # file offset
for i in range(0, 0x70, 4):
    b = data[base+i:base+i+4]
    if b[0:2] == b'\\x00\\x00':
        print(f'+{i:04x}: end marker'); break
    word1 = (b[0]<<8)|b[1]
    word2 = (b[2]<<8)|b[3]
    ch = chr(b[1]) if 0x20 <= b[1] < 0x7f else '?'
    # word2 is a signed offset relative to (table_base + slot + 2)
    off = word2 if word2 < 0x8000 else word2 - 0x10000
    target = 0xa49948 + i + 2 + off
    print(f'+{i:04x}: flags={b[0]:02x} char={ch!r} offset={word2:04x} target=0x{target:08x}')
"
```

Adapt `base`, the step size (4 here because entries are 4 bytes), and
the stop condition (`00 00` terminator) to the table you're decoding.

The target-address formula depends on **how** the code reads the table
— look at the dispatcher. For STM it was:

```
a4991c: lea %pc@(0xa49948), a5    ; a5 = table start
a49920: movew a5@+, d2             ; read word1, advance a5 by 2
a4992e: movel a5, d5                ; (save pointer past word1)
...
a49942: movew a5@, d0               ; read word2 (offset) — but a5 still points at word2
a49944: jmp a5@(0, d0:w)            ; target = a5 + d0
```

So `target = (table_base + slot + 2) + word2`. Different dispatchers use
different schemes (base-relative, absolute, PC-relative) — always read
the dispatcher first.

## 8. Cross-referencing with the CPU trace

The verilator simulator writes `verilator/cpu_trace.log` — every executed
instruction. Useful for:

- Confirming a branch **was** taken in practice
- Finding the first time a region executes
- Seeing the dynamic call chain that led to a hang

Format:

```
3875129:[F129] 00A498A0: 4DFA  lea     ($6,PC), A6; ($a498a8)  @50F01200
│        │     │         │    │                                │
│        │     │         │    │                                └── last data-bus address
│        │     │         │    └── decoded instruction
│        │     │         └── opcode
│        │     └── PC of this instruction
│        └── frame counter
└── line number in the log
```

### Find the first entry into a region

```bash
# First instruction at or above $A498A0
grep -n "00A498A0:" verilator/cpu_trace.log | head -3
```

**Caveat:** the trace contains `@A498A0`-style annotations as *data*
references (right side after `@`). To search for PC values only, anchor
with the colon: `00A498A0:`.

### Read surrounding context

Once you have a line number (e.g. 3875129), use the `Read` tool or
`sed`:

```bash
sed -n '3875115,3875135p' verilator/cpu_trace.log
```

This shows the ~20 lines around that point — usually enough to see the
call chain that reached it.

### When the trace is too large

`cpu_trace.log` grows to hundreds of MB on a multi-frame run. Reading
it top-to-bottom is wasteful. Strategy:

1. `grep -n` to find the first occurrence of the address of interest.
2. Read the 20-30 lines around each hit with `sed -n '...,...p'`.
3. For repeated patterns (hang loops), `grep -c` gives occurrence counts.

The simulator also samples PC every ~10M cycles into `sim_err.log` —
use that as a coarse timeline before opening `cpu_trace.log`.

## 9. Typical workflow (from the STM investigation)

1. **Observed symptom** in `sim_err.log`: `Cycle 310000000: PC=00A49F0E Op=67F0`
   repeating — CPU stuck at `$A49F0E`.
2. **Disassemble around** `$A49F0E`:
   ```bash
   m68k-elf-objdump -D -b binary -m m68k --adjust-vma=0xA00000 \
       releases/boot0.rom 2>/dev/null | awk '/a49ef0:/,/a49f20:/'
   ```
3. **Understand the loop** by reading the instructions — turned out to
   be `btst #0, a3@(2); beqs` (poll-then-loop).
4. **Find who calls this function** — search for `jmp %pc@(0xa49ef6)`
   and similar:
   ```bash
   rg "0xa49ef6|a49ef6," /tmp/disasm.txt
   ```
5. **Find what routes us here** from boot entry — chase callers upward
   until you hit a known entry point.
6. **Verify with the CPU trace** that the dynamic path matches the
   static disassembly.

## 10. File offsets cheat sheet (Mac LC ROM)

Useful constants when hand-computing offsets:

| Virtual | Offset | What |
|---------|--------|------|
| `$A00000` | `0x00000` | ROM base / reset vector area |
| `$A46000` | `0x46000` | Early boot / POST region |
| `$A467A6` | `0x467a6` | Sub used by several init paths (bit transfer to D2) |
| `$A46AF0`–`$A46AF8` | `0x46af0` | ROM checksum loop (visible at boot start in trace) |
| `$A48CDA` | `0x48cda` | Main boot dispatcher |
| `$A498A0` | `0x498a0` | **STM entry point** |
| `$A49948` | `0x49948` | STM command dispatch table |
| `$A49EF6` | `0x49ef6` | STM send-byte |
| `$A49F0E` | `0x49f0e` | "All Sent" poll loop (our hang) |
| `$A49FCA` | `0x49fca` | STM Snd (receive byte) |

## 11. Things that are easy to get wrong

- **Data vs PC in the trace:** the `@XXXXXXXX` suffix is a *data-bus*
  address, not an instruction address. Always match on the `PC=` or
  `NNNNNNNN:` column.
- **Signed 16-bit offsets:** word-form branches and jump-table offsets
  are signed. A value `0xFFFFCF22` in a `lea` is really `-0x30DE` —
  don't add as unsigned.
- **`%fp` is not the hardware frame pointer you expect:** it's A6, used
  here as a return-address register (the ROM doesn't use BSR/RTS; it
  rolls its own via `lea ..., %fp; jmp ...`).
- **Multiple `braw 0xa498a0` sources:** STM is reached from three
  different places. Don't assume you've found "the" entry path without
  checking all three.
- **`m68k-elf-objdump` will happily disassemble data as code.**
  Garbage-looking instructions often mean you're inside a jump-table or
  string. Cross-check with a hex view (`xxd releases/boot0.rom | less`)
  when in doubt.
