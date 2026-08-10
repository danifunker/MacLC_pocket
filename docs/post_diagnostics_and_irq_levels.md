# Mac LC boot POST: diagnostics, "STM", and interrupt levels

Reference notes for the MacLC core, distilled from the boot ROM trace and the
MAME `maclc` ground truth (`v8.cpp`, `pseudovia.cpp`/`pseudovia.h`,
`src/devices/machine/pseudovia.cpp`). The old mac68k.info "Diagnostic Mode"
wiki page is dead (domain now parked/spam, and not in archive.org reach), so
this file is the local record.

## "STM" is NOT the PA0 diagnostic mode

There are two distinct things people call "STM":

1. **PA0 diagnostic mode** (hardware service/burn-in mode). Entered when VIA1
   port A **bit 0 reads 0**. The ROM tests it at **`$A4644C`**:
   ```
   A46446: bclr  #$1, ($1e00,A2)   ; ($1e00,A2) = VIA1 vBufA (port A)
   A4644C: btst  #$0, ($1e00,A2)   ; test PA0
   A46452: bne   $a46494           ; PA0 != 0  -> NORMAL boot
   ```
   MAME drives VIA1 port A as `0xd4 | (diag & 1)` where the "Diagnostic mode"
   config defaults to `0x01` ("Disabled"), i.e. **port A reads `$d5`, PA0 = 1 =
   normal boot**. Our core drives `via_pa_i = 8'h55` (PA0 = 1), so this check
   passes identically to MAME. **We are not in PA0 diagnostic mode.** (Our `$55`
   differs from MAME's `$d5` only in bit 7; harmless, but not hardware-accurate.)

2. **The POST self-test failure reporter** at **`$A498xx`** (and the
   `$A49Fxx` spin). ANY failed power-on self-test subtest jumps here. This is
   the "STM" we kept getting stuck in — it is a *symptom* (a subtest failed),
   not a mode. Each subtest ORs an error code into **D7** and branches to a
   per-test error entry under `$A462xx` (e.g. `$A462AA` ORs `$1100`), then
   `$A4638C` (`bset #$18,D7`) -> `$A498xx`.

   MAME never executes `$A462xx`/`$A4638C`/`$A498xx` on a healthy boot.

## POST flow landmarks (addresses)

| Address | Role |
|---------|------|
| `$A4644C` | PA0 diagnostic-mode check (normal boot if PA0=1) |
| `$A46582` / `$A465B0` | RAM bank-descriptor scan loop |
| `$A46C5C` | per-bank address/data walking subtest |
| `$A46968` / `$A4694C` | the big march (clears RAM via `movem`), `jmp (A6)` dispatch |
| `$A47158`-`$A47166` | install level-1 ISR `$A472CC` at `VBR+$64` (see below) |
| `$A47170`-`$A471C6` | **VIA1 Timer-1 interrupt-timing self-test** |
| `$A472CC` | the level-1 ISR (counts T1/T2 interrupts in D3/D4/D5) |
| `$A4A87C` / `$A4A8A4` | relocation trampoline / config write (remaps `$0`) |
| `$A462xx` | per-subtest error-code entries (OR code into D7) |
| `$A4638C` | `bset #$18,D7` -> jump to the failure reporter |
| `$A498xx` / `$A49Fxx` | POST failure reporter / spin ("STM") |

## Interrupt levels and the vector table (VBR, not $0)

The Mac LC CPU is a 68020 and uses **VBR** for the vector table — it is NOT at
`$0`. During the timer self-test the ROM points VBR into scratch RAM (~`$807F80`
in the 2 MB config) and installs the level-1 ISR itself:

```
A47158: movec VBR, A2        ; A2 = VBR
A4715C: adda.w #$64, A2      ; A2 = VBR + $64  (level-1 autovector slot, vec $19)
A47166: move.l A3, (A2)      ; store ISR $A472CC there
```

So a level-1 (VIA1) interrupt vectors through `VBR+$64`. Our TG68K uses VBR
correctly (`use_vbr_stackframe = CPU[0]`, and `cpu = 11` = 68020), so this works
— the previous "vector table at `$0` is unmapped" theory was a red herring.

Mac LC interrupt priority (encoded in `dataController_top.sv`, active-low IPL):

| Level | Source | `_cpuIPL` |
|-------|--------|-----------|
| 4 | SCC | `011` |
| 2 | PseudoVIA (V8): VBlank, slots, **ASC** | `101` |
| 1 | VIA1 (timers, ADB, etc.) | `110` |

**Higher level preempts lower.** The timer self-test enables level-1 (VIA1 T1)
and counts interrupts; if a level-2 (PseudoVIA) interrupt is spuriously asserted,
it preempts level 1, vectors through `VBR+$68` (a slot the ROM did NOT install
for this test), and the test fails -> `$A462AA` -> STM. See the fix below.

## PseudoVIA interrupt model (must match MAME `pseudovia_recalc_irqs`)

```c
slot_irqs = (~reg[2]) & 0x78 & (reg[0x12] & 0x78);  // VBlank + slots, gated by slot IER ($12)
reg[3] |= (slot_irqs ? 2 : 0);                       // IFR bit 1 = "any slot"
ifr = reg[3] & reg[0x13] & 0x1B;                     // gate by MAIN IER ($13), mask {4,3,1,0}
irq = (ifr != 0);                                    // -> level 2
```

Key facts:
- **ASC is IFR bit 4**, set by `asc_irq_w` — it is *not* a slot-status source and
  is *not* gated by the slot IER (`$12`).
- The final IRQ is gated by the **main IER (`$13`)**, masked to `0x1B`
  (bits 4=ASC, 3=slot, 1=any-slot, 0). The slot IER (`$12`) only gates the
  slot/VBlank summary into IFR bit 1.

### Bug that caused the timer-test failure (fixed)

`rtl/pseudovia.sv` previously (a) folded `asc_irq` into `slot_status[4]` and
(b) drove `irq_out = any_slot_irq` (gated only by slot IER `$12 = $7f`),
ignoring the main IER `$13`. Result: the ASC's FIFO interrupt asserted a
continuous **level-2** IRQ that preempted the level-1 VIA1 T1 interrupt the
timer self-test waits on. The CPU took a level-2 autovector (`VBR+$68`,
uninstalled) instead of the level-1 ISR (`VBR+$64`), D3 never reached 10, and
the test failed into STM.

Fix: remove ASC from `slot_status`, and gate `irq_out` exactly like MAME:
`irq = |(ifr_live & ier & 8'h1B)`. After the fix the level-1 ISR `$A472CC` runs,
the test passes via `$A471C6`, and no `$A462xx`/`$A498xx` STM is reached.

## How to reproduce the diagnosis

- Full MAME maincpu trace (ground truth):
  ```
  cd /Users/dani/repos/mame && mame maclc -rompath /private/tmp/goodroms \
    -ramsize 2M -debug -debugscript /tmp/t.cmd -seconds_to_run 6 \
    -nothrottle -video none -sound none
  # /tmp/t.cmd: "trace /tmp/mame_pc.tr,maincpu" then "go"
  ```
  Note: macOS has no `timeout`; rely on `-seconds_to_run`. MAME opcode-fetch
  *taps* do not fire on the 68020 (prefetch/cache) — use a debugscript trace.
- Verilator IRQ probe: log on `_cpuAS` falling edge `fc7_iack`, `_cpuIPL`, and
  pseudovia internals (`pvia.slot_ier`, `pvia.ifr`) within a frame window.
  A level-2 IACK shows as `addr=fffffff4` (addr[3:1]=010); level-1 is
  `addr=fffffff2` (addr[3:1]=001).

## SWIM byte-lane bug → IWM status poll spun forever (FIXED 2026-06-03)

After the VIA Timer-1 IRQ fix the boot ran to ~frame 1454, then hung in an
infinite loop at **`$A009CE`**:
```
A009C0: btst  #$5, $dd3.w
A009C8: movea.l $1e0.w, A0        ; A0 = low-mem IWM (= SWIM base)
A009CE: move.b #$be, ($c00,A0)    ; IWM register strobes ($200 stride)
A009DA: tst.b ($1c00,A0)          ; reg14 q7L
A009DE: tst.b ($1000,A0)          ; reg8  ENABLE-off
A009E2: tst.b ($1a00,A0)          ; reg13 q6H  (Q6=1,Q7=0 -> status reg)
A009E6: move.b ($1c00,A0), D2     ; D2 = IWM status
A009EA: btst  #$5, D2
A009EE: bne   $a009ce             ; spin while status bit5 set
```
`$01E0` is the **IWM** low-memory global (not a VIA): A0 = `$50F16000`, the V8
SWIM. (The earlier resume mis-read the data address `@50F17C00` as `($c00,A0)`
giving A0=`$50F17000`; it is actually `($1c00,A0)` → A0=`$50F16000`, which
matches MAME — confirmed by `grep -c "^00A009CE:" /tmp/mame_pc.tr` = 1, MAME
falls through on the first read.)

Root cause: `rtl/swim.v` gated every access on `_cpuLDS==0` and returned the
read byte on the **lower** lane (`{8'hBE, dataOutLo}`). But on the LC the V8
peripherals (VIA, SCC, **SWIM**) sit on the **upper** data byte and are reached
with even-addressed byte accesses (`_UDS`), exactly like `viaDataOut[15:8]`
(lower byte `8'hEF`). Consequences:
- `_cpuLDS` was never asserted for SWIM accesses → the IWM bit registers
  (q6/q7/diskEnable/ca/lstrb) never updated → `{q7,q6}` stuck at `00` → the read
  mux always returned the **data latch** (`$FF`, no disk) instead of the status
  register.
- Even so, the CPU latched the **upper** byte, which was the hardwired `8'hBE`
  (`bit5 = 1`) → `bne $a009ce` looped forever.

Fix (`973824b`): gate the SWIM on `_cpuUDS` and present the read byte on
D15-D8 (`{dataOutLo, 8'hBE}`). Writes already use `dataIn[7:0]` (TG68K puts
byte write data on the low lane — see the SCC `wdata` comment), so unchanged.
After the fix `$A009CE` is hit 7× (falls through), the boot reaches the floppy
boot-disk wait loop, QuickDraw init, the cursor, and the **grey desktop
pattern** (screenshot frame ~1490). Frame-350 test pattern unchanged.

Debugging method that worked here: a SIMULATION `$display` in `swim.v` on
`cen && selectSWIM` printing `_cpuRW/_cpuLDS/cpuAddrRegHi/{q7,q6}/enable/dataOutLo`
showed `lds=1` on every access and `dataOutLo=ff` — the smoking gun. (MAME
debugscript `tracelog`/breakpoint/watchpoint **actions do not fire** in the
headless `maclc` build here; only the `dump` command and `trace` file work, and
68020 opcode-PC breakpoints are defeated by prefetch.)

## Three hardware-fidelity checks (2026-06-03)

1. **Egret (68HC05) / chime / ADB.** Present and active. CORRECTION: the **real
   HC05** is used in BOTH sim and FPGA — `USE_EGRET_CPU=1` is set in
   `verilator/Makefile` AND `MacLC.qsf`, and `dataController_top.sv` instantiates
   `egret_wrapper` (real 68HC05 + firmware) unless `EGRET_BEHAVIORAL` is defined
   (it is not). The behavioral SM (`rtl/egret_behavioral.sv`) is only a fallback.
   The ASC is actively programmed during boot (`$F14800`/`$F14804` thousands of
   accesses) and the boot reaches the desktop, so the startup/sound path runs.
   **GAP: ADB is not wired to the Egret.** `dataController_top.sv:684-686` ties
   `.adb_data_in(1'b1)` and leaves `.adb_data_out()` open ("ADB not implemented
   yet"). On the LC the Egret IS the ADB (keyboard+mouse) controller, so with a
   dead ADB bus no device data reaches the CPU → mouse/keyboard non-functional,
   cursor cannot move. The separate `adb adb(...)` module (line 921, fed by
   `ps2_mouse`/`ps2_key`) is the Mac-Plus VIA-ADB transceiver and does NOT apply
   to the LC (those VIA pins are repurposed for Egret comms). Wiring ADB into the
   Egret is the proper fix. Watch the `via6522.sv` SR caveat in `CLAUDE.md`.

2. **V8 bank-sizing.** Confirmed still good on the current build: the SIMM is
   sized from the physical config (`ram_config_phys`, addrDecoder.v:81-99), the
   `$0` motherboard mirror is gated by `ram_configured`, the descriptor table at
   `$9FFFEC` stays single-entry (writes seen at `$9FFFEA`/`$9FFFEE`), and the
   march completes with no clobber (boot reaches the desktop). 10MB (`$E4`)
   still unvalidated — check `mame -ramsize 10M` + `v8.cpp ram_size()` before
   trusting `ram_config_phys` there.

3. **24/32-bit switch (A31).** Gap characterized. MAME uses `M68020HMMU` with
   `map.global_mask(0x80ffffff)` (`maclc.cpp:181/195`): only bit 31 and bits
   23-0 decode; bits 30-24 are ignored. Our `addrDecoder.v` looks only at
   `address[23:0]` and ignores bit 31 entirely, i.e. the core is **always
   24-bit**. The LC ships 24-bit by default and the boot reaches the desktop in
   that mode, so this is sufficient for booting. It remains a future gap: if
   System software (MODE32) or a 32-bit-clean path drives A31=1 expecting the
   32-bit window, our decode aliases it into the 24-bit map. The sim's
   `cpuAddrFullHi`/`HIGH_ADDR` probe should never fire during a healthy 24-bit
   boot — re-check if a future hang appears past the disk-wait loop.
