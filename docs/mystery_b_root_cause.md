# Mystery B — root cause: one corrupted byte kills the System 7.1 boot

**Status (2026-08-14): SOLVED AND FIXED.**  Root cause chain proven, the RTL
defect isolated (`scsi_dpram`'s look-ahead prefetch publishes stale data as
valid — [§7](#7-the-defect-scsi_dprams-prefetch-publishes-stale-data-as-valid)),
fix applied to `rtl/scsi.v`, verified in Verilator: the games disk now reaches
**"Welcome to Macintosh." with extensions loading**.

**★ The defect is byte-identical in MiSTer `5a75f9b` — it must go upstream.**
See `~/docs/mister-upstream-fix.md`.

The games-disk crash (`Mac68KColorGames_v1.hda`, System 7.1, bomb dialog
"illegal instruction" ~15-20 s into the boot) is **not** a video, QuickDraw,
geometry, memory-size or Pocket-glue problem.  It is a **single 16-bit word of a
compressed code resource arriving as `$0000` instead of `$2C00`**.  That word is
a 2-byte instruction; losing it desynchronises the instruction stream into an
`-(A6)` predecrement, which unbalances a `LINK`/`UNLK` frame, so the function's
`RTS` returns into the boot-blocks image and executes its `'LK'` signature.

Everything below is measured, not inferred.  Every claim names the instrument
that produced it.

---

## 1. Reproduce it in ~5 minutes

```bash
cd verilator && make
# POST-skip ROM: the 10 MB RAM march costs ~1700 frames of every run and the
# fault is documented as invariant across cold/warm boot.
python3 patch_skip_ramtest.py ../releases/boot0.rom ../releases/boot0_skipramtest.rom

./obj_dir/Vemu --headless --no-cpu-trace \
  --rom ../releases/boot0_skipramtest.rom \
  --scsi0 <copy-of-Mac68KColorGames_v1.hda> \
  --screenshot-every 50 --screenshot-prefix ../scratch/fast/ \
  --heartbeat 50 --stop-at-frame 700
```

- Fault lands at **frame 503**, deterministically (5+ runs, identical).
- Bomb dialog visible by frame ~650; CPU parks at `PC=$A02A38` — the ROM
  SysError wait loop `boot_problems.md` documents from hardware.
- With the **stock** ROM the same fault occurs, just ~1700 frames later
  (the POST march at `$A468xx` dominates: it ends at F429 at 2 MB, ~F1700 at
  10 MB).

Config the harness presents (matches the shipping Pocket): 10 MB RAM,
monitor ID 2 / 512x384, 256K VRAM SIMM, real HC05 Egret.

**★ This alone was the decisive architectural result.** `docs/RESUME.md`'s
leading hypothesis was Pocket-only glue — APF ms-scale block-device serving,
`pocket_sdram` under the 7.1 access pattern.  The Verilator harness has **none
of that**: ideal zero-latency `sim_ram`, no APF bridge, no blockdev sequencer,
its own CPU/bus glue.  RESUME called the shot in advance: a clean sim boot would
have convicted Pocket glue.  It crashed instead, so the fault lives in **shared
RTL or the data path**, and it is a *single-byte data* defect, not a
timing-scale effect.

---

## 2. The failure chain

Each step names the probe (all live in `verilator/sim.v` / `sim_main.cpp`, see §8).

### 2.1 The byte

Disk sector **57,710**, offset **+4** (file offset `0x1C2DC04`) holds `$2C`.
In guest RAM it reads `$00`.

```
disk : 0C 01 5E 20 05 A0 55 2C 00 80 32 02 A6 BC 90 63
RAM  : 0C 01 5E 20 05 A0 55 00 00 80 32 02 A6 BC 90 63
                           ^^   differences over the 16 bytes: exactly 1
```

Nothing shifts — the 15 surrounding bytes are byte-perfect and `32 02 A6` lands
back in step immediately after.  A single byte was zeroed in place.

> Note on framing: the sector's word 2 is `$2C00`, whose **low** byte is `$00`
> anyway.  So RAM alone cannot distinguish "the byte `$2C` was lost" from "the
> whole 16-bit word `$2C00` was lost".  §5 shows the word is intact in the SCSI
> sector buffer, so the loss is on the delivery side either way.

### 2.2 The resource is compressed

That byte is part of a **compressed** code resource living at `$C230+`.  An LZ
decompressor in RAM at `$BB9E-$BBC8` expands it *in place, downward* into
`$C000+`:

```
$BB9E: add.b  D3,D3            ; shift flag bits
$BBA0: bcs    $BBBA            ; flag set -> dictionary match
$BBA2: move.b (A0)+,(A2)+      ; literal byte
$BBA4: move.b (A0)+,(A2)+      ; literal byte
$BBBA: moveq  #0,D0
$BBBC: move.b (A0)+,D0         ; dictionary index
$BBBE: add.w  D0,D0            ; x2
$BBC0: move.w (A1,D0.w),(A2)+  ; indexed word copy
```

(This is why searching the disk image for the expanded code fails — only
fragments match, at inconsistent spacing.)  The decompressor faithfully
propagates the bad byte.

### 2.3 The expanded code

Guest `$C01A` ends up `$0000`; it must be `$2C00` = `move.l D0,D6`.
**191 of the 192 words of `$C000-$C17F` match MAME byte-for-byte** (§4).

Correct stream (what MAME has), decoded:

```
$C016: 2005        move.l D5,D0
$C018: A055        _StripAddress          ; strips D0
$C01A: 2C00        move.l D0,D6           ; <-- WE GET $0000
$C01C: 2078 02A6   movea.l ($2A6).w,A0
$C020: BC90        cmp.l   (A0),D6        ; bounds-check the stripped address
$C022: 6312        bls     $C036
$C024: 2038 02AE   move.l  ROMBase,D0
$C028: A055        _StripAddress
$C02A: B086        cmp.l   D6,D0
$C02C: 6308        bls     $C036
$C02E: 303C EA4F   move.w  #$EA4F,D0      ; error code
$C032: 6000 013E   bra     $C172          ; -> epilogue
```

A Gestalt-family address-range validator.  Semantically airtight: strip the
address, keep it in D6, bounds-check D6.  Every branch target lands exactly
right.

### 2.4 The desync

With `$C01A = $0000`, the 68020 decodes across the hole:

```
$C01A: 0000 2078   ori.b  #$78,D0
$C01E: 02A6 BC90 6312   andi.l #$BC906312,-(A6)    ; ★ predecrements A6 by 4
```

`$BC906312` is garbage-shaped because it *is* garbage — it is the operand bytes
of two unrelated instructions read at the wrong alignment.  The stream
resynchronises at `$C024` by luck, which is why only this one window misbehaves.

### 2.5 The frame corruption — measured, not deduced

`[MYSTB]` probe, dumping the TG68K register file at each step:

```
PC=00BFF8  A6=00400E6C A7=003FF776   ; entry: link A6,#-$c  -> pushes old A6 to $3FF772, A6 := $3FF772
PC=00C172  A6=003FF76E A7=003FF74E   ; ★ A6 is 4 LOW (the -(A6) above)
PC=00C178  A6=003FF76E               ; unlk A6  -> A7 := $3FF76E+4 = $3FF772   (wrong slot)
PC=00C17A  A6=003FF76E               ; rts      -> pops $3FF772
PC=400E6C  A6=00002110 A7=003FF776   ; landed on the boot-blocks signature
```

The genuine return address `$0000C864` was written intact at `$3FF776` by the
caller — the `[WWSP]` write-watcher shows it.  **Nothing overwrote the frame.**
The `RTS` simply read one longword too low.

### 2.6 The death

`$3FF772` holds the *saved old A6* = `$00400E6C`, the boot-blocks image base:

```
400E60: 0000 8C12 0000 009C 00A0 F440 4C4B 6000
400E70: 0086 4418 0000 0653 7973 7465 6D00 ...   ('System')
```

`$400E6C = $4C4B = 'LK'` — the boot-block signature, a genuinely illegal
opcode.  `$400E6E = $6000 0086` is the legitimate entry (`BRA.W $400EF6`), and
the machine had already executed it correctly at frame 418 (`[BBEXEC]` #1-#8).
The fault lands **two bytes early**, on the signature:

```
[F503] BBEXEC #9:  fetch at 400e6c
[F503] VECFETCH:   vector 4 (addr 000010) lastFetchPC=00400e6e lastOp=6000
```

-> illegal instruction -> vector 4 -> `DSErrCode` -> bomb dialog -> ROM parks in
the SysError wait at `$A02A38`.

This reproduces `boot_problems.md`'s hardware decode exactly, including the
`'mach'` Gestalt selector seen in the fatal stack band (`PC=0000C85E` writing
`$6368` = `'ch'`).

---

## 3. Why it is perfectly deterministic

The same sector, the same buffer alignment, the same store, every boot.  That
explains the property that made this so confusing on hardware: invariance across
cold/warm boot, card/JTAG, 2 MB/10 MB, 512K/256K VRAM.  None of those change
which byte is read.

---

## 4. MAME as ground truth

MAME 0.289, `romset maclc is good` at `/Users/dani/repos/mame/roms`.

```bash
mame maclc -rompath /Users/dani/repos/mame/roms -ramsize 10M \
  -hard <copy>.hdv -nothrottle -video none -sound none \
  -seconds_to_run 150 -autoboot_script verilator/mame/patch_scan.lua -autoboot_delay 0
```

`verilator/mame/patch_scan.lua` finds the routine by its body signature
(`2078 02A6 BC90 6312 2038 02AE`) and dumps `$C000-$C17F` laid out against our
addresses.  Diffing that against our dump: **1 difference in 192 words**,
`$C01A: ours=0000 MAME=2C00`.

Two MAME gotchas, both cost time here (documented in the script header):

- **`print` is invisible under `-video none`** — log to a file.
- **The frame notifier must be held in a GLOBAL.**  A local
  `emu.add_machine_frame_notifier(...)` is garbage-collected and the callback
  silently never fires — the same trap `vram_256k.lua` documents for taps.

---

## 5. What is eliminated (each by a measurement)

| Suspect | Verdict | The measurement that killed it |
|---|---|---|
| Pocket-only glue (APF serving, `pocket_sdram`) | **ELIMINATED** | Reproduces in Verilator, which has none of it (§1) |
| VRAM / 256K SIMM geometry | **ELIMINATED** | `ScreenRow($106)=$0200` = 512, the criterion RESUME sets; alias/packing/scanout all consistent (§9) |
| The disk image | **ELIMINATED** | SHA1 `dcd02c6c…` verified; the byte is correct on disk |
| The block-device model | **ELIMINATED** | `[BLK] serving lba 57710 from FILE: 20 05 A0 55 2C 00 …` — serves it correctly |
| The SCSI sector buffer (fill) | **ELIMINATED** | `[BUFCHK] slot 0: word[2]=2C00` — the ring holds the right word |
| The SCSI RTL itself | **ELIMINATED as a divergence** | `scsi.v`/`ncr5380.sv` are byte-identical to MiSTer `5a75f9b` apart from the CD/Toolbox cuts (§6) |
| TG68K decode of `'LK'` | Correct | `$4C4B` genuinely is an illegal opcode |
| Memory size / cold vs warm boot | **ELIMINATED** | Same fault at 2 MB and 10 MB, stock and POST-skip ROM |

---

## 6. The SCSI subset vs MiSTer

Diffed against the working MiSTer core (`git -C ../MacLC_MiSTer show 5a75f9b:rtl/…`):

- **`rtl/ncr5380.sv`** — differences are *only* the removed CD-audio/Toolbox
  ports (`cd_snd_*`, `tb_*`, `cdtb_*`, `dbg_cda*`) and the CD target's
  parameters.  **The pseudo-DMA datapath — `din_pair`/`din_pair_next`,
  `dma_settle`, `dma_ack_holdoff`, the longword second-word capture, the
  `cur_data_pair` mux — is untouched.**
- **`rtl/scsi.v`** — differences are *only* the `cd_audio` -> `cd_toc_stub`
  swap.  The disk read path (ring, `scsi_dpram`, look-ahead prefetch, serve) is
  byte-identical, including `sd_buff_wr & target_bsy[i]`.

So there is **no Pocket-introduced divergence in the SCSI subset** — and §7
resolves this to option (a): a **latent race that MiSTer has too**, in the
prefetch redesign of 2026-07-17, which MiSTer simply has not provoked (it needs
an odd-aligned longword pseudo-DMA drain *and* a differing stale byte).  The fix
therefore belongs upstream verbatim; see `~/docs/mister-upstream-fix.md`.

This is also why the MiSTer diff was the right instinct and the right call: it
proved the bug could not be a Pocket-introduced regression, which is what
redirected the search from "what did we break?" to "what is latent in the shared
design?"

---

## 7. The defect: `scsi_dpram`'s prefetch publishes stale data as valid

`rtl/scsi.v`, module `scsi_dpram`, the look-ahead prefetch controller.

### 7.1 Caught in the act

The `[SDMARD]` probe, dumping the full serve state at the corrupting cycle:

```
[F502] SDMARD a=f06060 d=05a0 dcnt=1 mac=0000 | pair=05a0 next=5500 2nd=5500 supp=0 settle=0 hold=6
       | b0=20 b0n=a0 b0n2=00 b1=05 b1n=55 | pf_st=0 pf_v=1 pf_c=0001 pf_d=0002 ac=0001 ad=0002
```

- `dcnt=1` — the byte offset is **odd**: the misaligned serve path.
- `b0n2` = `buffer0_dout_next2` = the dpram's `q_d` = **`$00`**, while
  `ram_ab[2]` holds **`$2C`**.
- `pf_v=1`, and `pf_c_addr/pf_d_addr` (0001/0002) exactly match the requested
  `address_c/address_d`.  So `pf_stale` is **false** — the controller believes
  it is coherent and **will never refetch**.
- Hence `next = {b1n, b0n2} = {55, 00} = $5500` instead of `$552C`.

### 7.2 The mechanism

```verilog
PF_RDD: begin
    q_d <= q_b;                       // this read may have collided with a port-A write
    if (!pf_snooped && !pf_snoop_hit) begin
        pf_c_addr <= pf_c_tgt; pf_d_addr <= pf_d_tgt; pf_valid <= 1'b1;
    end                               // <-- "discard" is a NO-OP if pf_valid was already 1
    pf_snooped <= 1'b0;
    pf_st      <= PF_IDLE;
end
```

Declining to republish the addresses is only a discard when `pf_valid` was `0`.
If an **earlier** fetch had already published *these same addresses*,
`pf_valid` is still `1` and the addresses still compare equal, so

```verilog
wire pf_stale = !pf_valid || pf_snooped || (address_c != pf_c_addr) || (address_d != pf_d_addr);
```

stays false and no refetch is launched.  The stale bytes captured on that line
become permanent.

**Reachable on every sequential HPS/SD fill:**

1. Fill writes address N.  `pf_snoop_hit` (`address_a == pf_c_addr`) -> `pf_snooped`.
2. `pf_stale` -> refetch launched for the **same** addresses (pf_valid still 1).
3. While that refetch sits in `PF_RDC`, the fill writes N+1 == `pf_d_tgt`.
   The port-B read issued that cycle collides with the port-A write; the
   `no_rw_check` M10K returns **OLD** data, so `q_d` captures the pre-write byte.
   `pf_snoop_hit` fires again -> `pf_snooped`.
4. `PF_RDD`: `q_d` takes the stale byte, the `if` is skipped, `pf_valid` remains
   `1` from step 0, `pf_snooped` is cleared.  -> stale-but-valid, forever.

### 7.3 The fix

```verilog
end else begin
    pf_valid <= 1'b0;   // a discarded fetch must INVALIDATE, not just decline to publish
end
```

Single always block, single driver — Quartus-safe.  It forces exactly the
refetch the surrounding logic already intended.

### 7.4 Why it hid for so long

`q_d` has **exactly one consumer**: the odd-byte-offset pseudo-DMA assembly.

```verilog
din_pair_next = data_cnt[0] ? {buffer1_dout_next, buffer0_dout_next2}   // needs q_d
                            : {buffer0_dout_next, buffer1_dout_next};  // does not
```

Every word-aligned transfer misses it entirely.  To be bitten you need a SCSI
read whose destination buffer is **odd-aligned** — here the ROM drain loop at
`$A092A2` (`move.l (A0),(A2)+`, unrolled x8) running at `data_cnt=1` because the
caller's buffer landed on `$C233` — *and* the stale byte must differ from the
real one.  On a virgin ring slot the stale value is `0`, which is why the
symptom was one word reading `$0000`.

### 7.5 Verification

`--fix-src` (repair just that byte in the source buffer, no RTL change) and the
RTL fix independently produce the same result — the crash disappears:

| run | `$C01A` lands | vector 4 | frame 1500 |
|---|---|---|---|
| before | `0000` | yes, F503 | bomb dialog, ROM parked `$A02A38` |
| `--fix-src` | `2C00` | none | "Welcome to Macintosh." |
| **RTL fix, no sim patch** | **`2C00`** | **none** | **"Welcome to Macintosh." + 5 extension icons, guest code at `PC=$000309B0`** |

`scratch/rtlfix/screenshot_frame_1500.png` is the proof image.

**Not yet validated on hardware** — needs a card trip.  The change is in shared
RTL, so it applies to both tops.

## 8. Instruments added to the harness

All in `verilator/sim.v` (opt-in plusargs) and `verilator/sim_main.cpp` (CLI):

| Probe | What it shows | Enable |
|---|---|---|
| `VECFETCH` | Fault-vector fetches (vectors 2/3/4 only — vector 10 is the Toolbox A-trap dispatcher and floods; `$A46xxx` filtered because the POST march reads low RAM as data) | always |
| `BBEXEC` | Instruction fetch inside the boot-blocks band `$400E00-$400EFF` | always |
| `WWSP` | Writes to the live-stack band `$3FF700-$3FF7BF` + BootGlobals, with writer PC | `+wwsp +wwsp_from=<frame>` |
| `PATCHW` | Writes to `$BF80-$C2FF` (the patch body + its compressed source) | `+patchw` |
| `PATCHPOLL` | Per-frame poll of the RAM array at `$C018-$C01E` — catches stores a bus-level watcher misses | `--patch-watch` |
| `BUFCHK` | Scans the SCSI ring for the sector and prints its first 4 words | `--patch-watch` |
| `SDMARD` | Per-cycle pseudo-DMA serve + NCR5380 internal state | `+sdmard +sdmard_from=<frame>` |
| `MYSTB` / `SRCDUMP` / `VRAMCHK` | Register file at the epilogue; compressed-source dump; ScreenRow/ScrnBase | always (at the fault) |
| `BLK`/`BLKW` | What the block-device model serves for a chosen LBA | `+watch_lba=<n>` |

New CLI options: `--rom`, `--cpu-trace-from`, `--screenshot-every`,
`--screenshot-prefix`, `--heartbeat`, `--patch-watch`.

**Operating note:** a full run is ~5 minutes.  Do *one* run that dumps
everything you might want and analyse the file afterwards — iterating on narrow
greps costs a run each time.

---

## 9. VRAM audit (done in passing — it is correct)

The 256K VRAM SIMM work (`4f81048`, buildAW) was audited end to end because it
was the prior suspect.  It is sound:

- **`ScreenRow($106) = $0200` = 512** — the criterion RESUME sets.  The guest
  ran the ROM wrap test, concluded 256K, and built the 512-byte-stride world.
- The alias (`vram_cpu_offset` bit 18 cleared) makes `+$7FFFC` and `+$3FFFC`
  collide, so the readback answers '256K' — correct missing-A18 behaviour — and
  it drives both the SDRAM mirror and the BRAM packing consistently.
- CPU-side packing (`vram_line`/`vram_colw`, 512-byte stride) and video-side
  `packed_row_start += words_per_line` agree; the stride assumption is confined
  to `addrController_top.v` alone (grepped).
- `selectVRAM` still decodes the full 512K window — correct for a 256K SIMM
  aliasing inside it.

Two unrelated nits found, neither implicated:

1. `vram_bram` is `DEPTH=106496` but `vram_waddr` is 17 bits, so writes to
   off-screen lines >= 416 address outside the array.  Pre-existing (the 512K
   path had the same range); harmless in practice but worth a guard.
2. The comment in `maclc_v8_video.sv` still says "the V8's 1024-byte stride
   gap" — stale since the 256K change.

**★ MAME cannot arbitrate the 256K stride.**  `v8.cpp screen_update` hardcodes
`y * 1024` at every depth and does not model VRAM size at all.  Judge by
`ScreenRow`, never by MAME's picture.

---

## 10. Harness fixes that made this possible

The Verilator harness had been unusable since 2026-08-09.  Three unrelated
things, all now fixed (details in `docs/verilator_differences.md`):

1. **★ The V8 video timing constants were silently zeroed by Verilator 5.x.**
   The Pocket cut collapsed `maclc_v8_video.sv` to one fixed 512x384 mode, which
   left `always @(*) begin h_total = 11'd640; ... end` reading *no* variables.
   Verilator 5 refuses to schedule such a block (`ALWNEVER`), so every timing
   term stayed 0, `vsync` never asserted, and **the frame counter sat at 0
   forever while the guest booted perfectly normally** — `--screenshot N` and
   `--stop-at-frame N` could never fire, and the run looked like a hang.  Now
   `localparam`s.  Quartus folds both forms to the same constants, so this is
   sim-only — no FPGA behaviour change.  `-Wno-ALWNEVER` is deliberately **not**
   in the Makefile so this class fails the build.
2. **macOS/Apple-Silicon build**: `-I/opt/homebrew/include` + `-llz4`
   (Verilator 5's FST writer needs lz4).  Note the `-CFLAGS $(CFLAGS)` on the
   verilate line is *unquoted*, so only its first token is passed — put new
   include paths in the quoted `V_DEFINE` `-CFLAGS "..."` string.
3. **`selectUnmapped` was missing from sim's `dc0`** (restored in
   `mac_lc_pocket.sv` 2026-08-11, never mirrored).  The port defaulted to 0, so
   the open-bus case (`dataController_top.sv:330`) could never fire and unmapped
   reads fell through to stale `memoryDataIn` — which the ROM's RAM-probe XOR
   test reads as "RAM present".  The sim could size memory differently from the
   FPGA.  Now connected in both tops.

Sim config now matches the shipping Pocket by default: **10 MB**
(`configRAMSize = 8'hE4`, `+mem2` for the 2 MB A/B), monitor ID 2, 256K VRAM,
real Egret.

Validation after the fixes: the 2 MB no-disk boot reaches the documented
frame-730 oracle (dither-grey desktop + arrow cursor), and the first
`VRAM->BRAM` write lands at **F148 with wpl=32**, exactly as `CLAUDE.md` records.
