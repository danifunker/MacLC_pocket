# RESUME — MacLC Pocket, session handoff (rewritten 2026-08-12, end of the marathon)

Paste into a fresh session: **"Resume docs/RESUME.md — we are waiting on the
ROMV v3 oracle build, then running the v3 protocol."** Read this file fully,
then `docs/boot_problems.md` (the complete corrected investigation history —
every theory, every control that killed it, every trap). Where they disagree,
boot_problems.md wins on history; this file wins on current state.

---

## 0. THE IMMEDIATE STATE (what "resume" means right now)

A **ROMV v3 build** was compiling in the background when the session ended
(map/fit/asm/sta chain on branch `instr/stm-console` @ `ae8248e`, launched as
background task `b1aj4z15s`; its log:
`C:\Users\owner\AppData\Local\Temp\claude\C--repos-MacLC-Pocket\39fb82c6-08ba-4e38-bd25-08f811201e91\tasks\b1aj4z15s.output`).

First actions in a fresh session:
1. Check that log for `STA_OK` (or check
   `src/fpga/output_files/ap_core.fit.summary` mtime is AFTER the v2.1 build).
   If absent/stale: rebuild — `cd src/fpga && quartus_map ap_core && quartus_fit
   ap_core && quartus_asm ap_core && quartus_sta ap_core` (~20 min, works with
   the standard PATH exports in §6).
2. Archive: `cp src/fpga/output_files/ap_core.sof scratch/builds/2026-08-12-buildR-oracle-v3.sof`
3. Push: `quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "p;src/fpga/output_files/ap_core.sof"`
4. Run the **v3 protocol** (§3).

---

## 1. WHAT THIS PROJECT IS, ONE PARAGRAPH

Macintosh LC core for the Analogue Pocket, forked from the released, fully
working MiSTer core at `../MacLC_MiSTer` @ `5a75f9b` (which is ground truth
for "how the Mac works" — when in doubt, diff against it). The Pocket port
boots to a grey screen with working audio/video on good runs but has never
completed a cold boot; the best historical state ("golden", 2026-08-11 ~10:00)
reached the flashing-"?" floppy screen after 2-3 manual ROM reloads. The user
(Dani Sarfati <dani@funkervogt.com>, handle danifunker, they/them) wants:
boot reliably, SCSI disks detected, eventually lock the core to 10 MB
(recorded decision — blocked on the RAM march passing), floppy deferred.

## 2. GIT STATE (all committed, trees clean)

| branch | head | contents |
|---|---|---|
| `instr/stm-console` ← CURRENT | ae8248e | golden base + full instrument suite (this is the working branch) |
| `recon/golden-0811` | 1444697 | the golden-build source reconstructed edit-by-edit from session transcripts; PROVEN to fail on today's hardware → code exonerated |
| `wip/2026-08-12-debug-state` | ff9b11d | complete snapshot of the previously-uncommitted debug state |
| `main` | c0e77da | stale pushed state; its ROM loader predates the fix that makes downloads work — **main is unbootable by construction, do not test it** |

Every bitstream built today is archived: `scratch/builds/2026-08-12-buildA..Q*.sof`
(A=135° revert, B=golden-anchor, D=recon-golden, F=instr+forced-warm,
K=jboot, M=diag-on-demand, N=console-speed, Q=oracle-v2.1; v3 = R when built).
`git log --oneline` on instr/stm-console narrates the whole day.

## 3. THE ROMV v3 PROTOCOL (the pending experiment)

ROMV v3 = completion-paired SDRAM read-back oracle: `pocket_sdram` now exports
`dout_stb` (toggles once per served read); the scanner holds each address until
a confirmed completion (8-cycle settle windows absorb in-flight machine-era
reads). This kills the stale-dout mirage that produced two false "corruption"
verdicts (see boot_problems.md "THE ORACLE'S MIRAGE"). Full scan now takes
~0.5 s of hardware time.

Protocol (after pushing the v3 build):
1. **Post-push scan, NO reload**: `quartus_stp_tcl -t scripts/romv.tcl` —
   ⚠ romv.tcl still uses the v1 single-bit trigger; EITHER fix it to write
   the v2 source encoding (24-bit: bit23=go rising edge, bits22:5=start word,
   bits4:0=log2len; full ROM = write 0x000012 then 0x800012) or use
   romv_search.tcl which encodes correctly. Expected sums for the intact ROM:
   **sum=350F8EEE axsum=F486F3D8** (single scan; v3 counters reset per scan).
   This scan measures decay across the reconfig refresh-gap + any real errors.
2. **User does ONE OSD reload of boot0.rom** (fresh content).
3. **Post-reload scan ×3** (repeatability). If ≠ reference: REAL content
   errors exist → run `scripts/romv_search.tcl` (binary search; needs
   `scratch/rom_words.tcl`, regenerate with
   `python scripts/gen_rom_words.py "../MacLC_MiSTer/releases/boot0.rom" "scratch/rom_words.tcl"`)
   → analyze the bad-address bit pattern. If = reference: SDRAM content is
   CLEAN and the decay/corruption thread closes; go to §4.
4. Also available: `scripts/romv_peek.tcl <hexaddr>...` — isolated single-word
   reads (v3 makes these trustworthy).

## 4. THE PRIME OPEN LEAD — reset-hold duration

**The tightest reproducible discriminator that survived every control:**
jboot boots (instant ~4 µs reset strobe, then the machine's normal
8 ms + 129 ms sequence) fail into the EARLY wedge **11/11**, while OSD ROM
reloads (which hold reset for the multi-second download) frequently reach the
late stages (grey screen / 138k IRQs / late sad-mac). Something needs TIME IN
RESET (or time-without-bus-activity) to settle: Egret state, PLL, SDRAM bank
state, V8...

**Next experiment (one small build): make the jboot hold configurable** —
widen the JBOO source to carry a hold-duration field (e.g. 0.1 s → 5 s sweep),
then binary-search the threshold hands-free. If long holds rescue jboots, the
fault is settling-time-dependent and the threshold's magnitude points at the
subsystem (ms → SDRAM/PLL; ~1 s → Egret's ONESEC timer).

## 5. THE INSTRUMENT SUITE (all on instr/stm-console, all JTAG, no user hands)

ISSP instances (read by name via `get_insystem_source_probe_instance_info`;
**sources reset to 0 at every JTAG session start** — protocol below):

| id | dir | meaning |
|---|---|---|
| JBOO | src[0], probe | ANY write that toggles the source fires one boot: forces `rom_loaded` (ROM persists in SDRAM) + 31-clk8 reset strobe. Fresh session: write 1 fires. |
| DIAG | src[0] level | 1 = ground VIA1 PA0 → the ROM enters the **STM diagnostic monitor** at next boot (sanctioned entry, no failure needed). Must be held in the SAME session as the JBOO strobe (`scripts/diag_boot.tcl` does both). |
| STMC | src[8:0], probe=sent count | serial injector into SCC ch A. **RISING edge of bit8 sends bits[7:0]** ({1,byte} then {0,0} to re-arm — session resets are silent by design). |
| SCCR | src[7:0]=ring index, probe[19:0]={count[7:0], entry[11:0]} | 256-deep ring of ALL CPU SCC accesses. Entry: [11]=1 read/0 write, [10:9]=port (0 ctlB,1 ctlA,2 dataB,3 dataA), [7:0]=byte. Idle-poll entries (read-ctlA-04) are filtered in fabric. |
| SCCS | probe[15:0] | live SCC state: [15:12] rxuart delivered count, [11:8] frame errors, [7]=post_loopback [6]=sync [5]=tx_empty [4]=tx_full [3]=tx_busy [2]=tx_line [1]=loopback [0]=rx_queue_nonempty |
| ROMV | src[23:0] {go,start,log2len}, probe=status (2=done) | the v3 oracle trigger |
| RVSU / RVAX | probe[31:0] | ROMV result sums (single-scan, reset per scan) |
| BOOT/ROMC/FLPC/BRGC/POPC/DLST/CPUC/CPUA/VIDS/SDMA/IRQS/RSUM/RAXS | probes | the original deck — decoded by `scratch/tools/read_boot_probes.sh` + `scratch/tools/cpu_probe.tcl` + `scratch/tools/boot_state.tcl` (copies live in scratch/tools because the scripts/ versions vary per branch; run boot_state directly, the .sh wrapper has a path bug on this branch) |

Scripts (scripts/): `diag_boot.tcl` (DIAG+JBOO one session), `jboot.tcl`,
`stm_console.tcl "<cmd>"` (send + full tagged transcript — THE conversation
tool), `read_sccs.tcl`, `romv*.tcl`, `stm_spam.tcl`/`jboot_spam.tcl`
(superseded), `rx_live_test.tcl`.

**The STM console** (ROM's TechStep monitor, docs:
`../MacLC_MiSTer/docs/diagnostic_mode_reference.md`): `*V` version, `*R`
status+error code (12 hex digits; major codes: 2-5 RAM/addressing, 6 VIA1,
B SCSI, 11 memory sizing, 30 Egret), `*T00TT00II0000` critical tests
(00 Size Memory, 01 Data Bus, 02 Mod3 RAM, 03 Address Line...). Full duplex
is PROVEN working (echo captured) after three scc.v truth fixes + the
console-speed shim (§7). To interrogate: `diag_boot.tcl` (needs fresh-ish ROM
→ if the fabric was just pushed, have the user OSD-reload first), then
`stm_console.tcl "*R"` etc. The monitor at the sad-mac ALSO listens (RR0
polling) — interrogation works there too.

## 6. ENVIRONMENT CRIB (this Windows box)

- Quartus **18.1.0/625** at `C:\intelFPGA_lite\18.1`; Bash:
  `export PATH="/c/intelFPGA_lite/18.1/quartus/bin64:$PATH"`.
- Python 3.12: `export PATH="/c/Users/owner/AppData/Local/Programs/Python/Python312:$PATH"`;
  for JSON-heavy python set `PYTHONIOENCODING=utf-8` (cp1252 crashes on →).
- Build: `cd /c/repos/MacLC_Pocket/src/fpga && quartus_map ap_core && quartus_fit ap_core && quartus_asm ap_core && quartus_sta ap_core`
  (~20 min; run as background task; use ABSOLUTE cd — session cwd persists).
- JTAG: `jtagconfig` → `02B050DD 5CE(BA4|FA4)`. "No JTAG hardware available"
  = the 25.1std `JTAGServer` Windows service grabbed the cable — stop it
  (boot_problems §8). "chain broken" = Pocket is off.
- Push: `quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "p;<sof>"`.
  ⚠ **Pushing reconfigures the FPGA: SDRAM loses ~1-2 s of refresh** (decay
  exposure — unmeasured but plausible) and the machine loses its OS-session
  ROM; after a push either jboot (stale content) or ask the user for an OSD
  reload (fresh content).
- SD card: `D:\Cores\danifunker.MacLC\` when in the PC; workflow when needed:
  `bash scripts/package.sh` → copy → `cmp` verify → PowerShell eject. The
  Pocket needs the card to LAUNCH a core; after launching, JTAG pushes can
  swap the fabric under the live OS session and OSD reloads still work.
- User-phrase decoder: "I reloaded the core" is ambiguous — VERIFY via probes
  (if the new instances answer, the fabric survived = they meant the ROM; if
  "No ISSP instance", they re-launched from the menu = fabric is the SD
  build → re-push).
- Tcl traps: `scan %x` is SIGNED (mask with `& 0xFFFFFFFF`); ISSP sources
  reset at session start; `write_source_data` wants `-value_in_hex` for hex.
- quartus_stp one-liners via `--tcl_eval` get mangled by bash — always use
  script files.

## 7. INSTR-BRANCH DIVERGENCES (must be re-evaluated before ANY release)

1. **Forced-warm ROM patch** (mac_lc_pocket ram_do_patched): NOPs the
   warm-vs-cold `bne.w` at ROM byte $4655E (words $5232AF/B0) — every boot
   takes the warm path, skipping the cold RAM march. WORKAROUND that gets
   grey-screen boots; the inherited MiSTer version of this patch aimed at
   $52322F and NEVER FIRED anywhere (address typo — upstream should be told).
2. **scc.v truth fixes ×3**: RX chars no longer dropped post-loopback
   (one-shot flush instead), RR0 RxAvail truthful, ch-A TxEmpty truthful.
   MiSTer never used this port; these shims were invisible there.
3. **Console-speed shim**: for the STM's WR12=0A config, both UARTs run at
   baud_divid=100 (~325 kbaud) because the monitor's All-Sent poll budget
   (~200 µs) cannot span an honest 9600-baud character — answers died at one
   byte otherwise. `STM_BAUD_DIV` in mac_lc_pocket must stay matched.
4. `SCSI_DISABLE_DIAG=1` (media hidden — golden parity), `serialCTS=0`
   (golden parity; MiSTer uses 1 and the wiring is verified identical — flip
   back as its own step), `USE_BOOT_ISSP=1`, BIST_ENABLE=0 (BIST RTL absent
   on this branch — stripped in recon), cold_rst generator disconnected.
5. `pocket_sdram` additions: `sdram_ready` output (inert), `dout_stb`
   completion strobe (v3 oracle dependency).

## 8. STATE OF KNOWLEDGE (details in boot_problems.md — trust its "RESULTS" sections)

PROVEN: ROM arrival byte-perfect every load (accumulators exact ×N loads);
CPU-path reads reliable enough for deep boots; code exonerated to golden
(recon build fails identically → the regression was never code); OS-session /
SD-flow / power-cycle / 135°-vs-180° phase / CB1 coalescing / SDRAM init
ladder / loader FIFO all excluded by direct test.
REFUTED-AS-MEASURED (instrument artifacts): the "8% corruption" and the
"decay proof" — both were the oracle reading stale dout (mostly the machine's
own post-reset word-0 fetch, hence the 350E signature). v3 re-measures
honestly.
UNKNOWN: the actual root cause of the early-fail-vs-late-fail race. Best
handle: the reset-hold-duration determinism (§4). Second thread: the late
sad-mac (post-grey, stages 16-18) — interrogable via the STM console (*R).
The user's standing instinct: "it's memory-related" — the SDRAM address-space
map audited clean (mb $000000 / SIMM $100000-$4FFFFF / ROM $500000 / VRAM
shadow $580000 / floppy $600000, at both 2 MB and 10 MB), but the SDC's
set_input/output_delay numbers are BORROWED from Pocket-Amiga and remain
unvalidated against this board — treat every STA margin as advisory.

## 9. WORKING AGREEMENTS (hard-won today; keep them)

1. ONE behavioral variable per shipped build; passive probes may ride along.
2. Archive EVERY .sof to scratch/builds/ before pushing the next.
3. Commit every tested state; the day's incremental-commit discipline is why
   nothing was lost.
4. CONTROLS BEFORE CONCLUSIONS: today produced three confident root-cause
   announcements that control tests then killed (phase, decay, corruption).
   An instrument's first job is to survive its own cross-examination:
   repeat-scan stability, known-good references, slow-vs-fast agreement.
5. Anchor bisects at the GOOD end first.
6. The reload-to-"?"/boot-depth check is the acceptance test for anything
   touching boot, memory, or timing.
7. Transcript mining works: every uncommitted historical state can be
   reconstructed from `C:\Users\owner\.claude\projects\C--repos-MacLC-Pocket\*.jsonl`
   (timestamps are UTC; local = UTC−7).
