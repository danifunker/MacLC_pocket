# RESUME — MacLC Pocket (2026-08-24 eve: blockdev refill PIPELINED (§-10, bench-green, HW A/B owed on `1.2.0-bd-s12`); restart §-9 + time fixes §-8 HW-validated; v1.2.0 released-ready)

## -10. 08-24 eve: apf_blockdev pipelined — the Case-5 root fix (bench-green, HW A/B owed)

**Status: MERGED to main (`229e3e3`, ff from `blockdev-pipeline`), BUILT
(seed 12: STA met all corners, worst setup +2.039, 14,304 ALMs, 261/308 M10K
— the results doc's ZERO M10K delta held), ON CARD as `1.2.0-bd-s12`
(rbf_r sha1 7381fd5b…), .sof archived. UNCOMMITTED here: qsf seed-12 +
build_id (commit with the HW verdict).** The macOS box ran the whole
bench-gated mission — `docs/blockdev_pipeline_results.md` is the authority:
tb_scsi_face **first successful run anywhere** (3 bench-side fixes, none in
the DUT) = **face CLEAN at stock AND real refill cadence** ⇒ starvation
confirmed ⇒ pipeline path: rdbuf 128×32→256×32 (two 512 B halves, same
M10K), thin job layer, sequential-HDD-only speculation posted at drain
start, one-rule invalidation + mount kill, mailbox-ordered CDC. Zero port
changes; scsi.v/ncr5380.sv untouched. tb_blockdev REWRITTEN (old oracle
predated buildAA little-endian face and failed against known-good RTL).
All gates green there: scsi_face (stock+real cadence), tb_blockdev,
scsi_ring, tb_disk_swap, check_hierarchy.

**HW A/B owed (this box's half of the contract):** repeated 7.5.5 + Easy
Open boots — COLD and WARM restarts (this fit is the first with both the
restart soft reset AND the pipeline); whole-disk Finder copy; PoP2 launch;
subjective disk speed vs MiSTer (sequential streams should feel markedly
faster — bench measured 48 µs hit-serve vs 133 µs demand). The RTL verdict
is bench-proven; what HW answers is the placement-marginality question —
the pipeline removes how OFTEN reads sit on the starved boundary, not the
boundary's existence (results doc caveat). Seed-lottery patience applies.

**★★ 20:30-21:00 FINAL TONIGHT — the ledger closes at 0-for-4 seeds (12, 4,
7, 6) and the verdict shifts:** bd-s6 with FRESH disks = cold boots CLEAN,
warm restart worked TWICE then bus error, and after that crash even core
reloads hung ("no safe boot") — which is — ★ CORRECTED ~21:15: NOT disk corruption. User: **quit-the-core +
relaunch recovers fully, no power-off, and "the volume didn't get damaged"**
— a corrupt volume would hang the reload too. The unsafe-boot state is
STALE SESSION STATE that survives the OSD/core-restart path but not a full
core teardown. Prime suspect located: `apf_blockdev` HAS `reset_n` (line
46) but carries state DELIBERATELY outside it (the buildY dataslot-update
latch, apf_blockdev.v:274 — must not clear on reset because Analogue sends
updates during reset) and, since tonight, the pf_* speculation state; and
the req/done TOGGLE PAIRS span two clock domains — a reset that clears one
domain's phase but not the other's desyncs the handshake permanently
(every later transfer pairs wrong ⇒ hang) until a full reload re-inits
both. So the warm-restart crash AND the post-crash OSD-restart hang are
one family: PARTIAL STATE SURVIVAL at the blockdev seam across each reset
flavor. Fix mission (Mac bench first): make every reset flavor leave the
seam phase-consistent — guest soft reset ⇒ quiesce/abort + clear
speculation; core reset_n ⇒ atomic toggle-pair handling (preserving the
buildY update-latch exemption); tb_blockdev gains BOTH cases
(reset-mid-transfer for each flavor). Recovery procedure until then:
after any crash, QUIT the core and relaunch (documented, cheap).
bd-s7 = F-line on restored 7.1.
Reading the whole night: (1) the intermittent warm-restart crash tracks the
apf_blockdev cross-restart state gap (NO reset flavor reaches it; in-flight
transfer + speculation survive the guest RESET — the afternoon audit
covered scsi.v/ncr but missed this); (2) the extension-parade crash class
survived the pipeline across four placements with varied faces ⇒ the
starvation-dwell theory is NOT the whole story — placement marginality in
the SCSI cones remains the standing explanation, and the structural answer
is LOGICLOCK-PINNING those cones (queued since 08-20 as the M10K-relief/
placement mission); (3) the pipeline's digital contract is bench-proven —
keep it, but its HW benefit is unprovable until the marginality and the
corruption loop stop destroying evidence. NEXT SESSION ORDER: [a] disposable
-image test discipline (restore before every verdict); [b] blockdev quiesce
on soft_periph_rst — small, tb_blockdev-benchable on the Mac (add the
guest-reset-mid-transfer case); [c] LogicLock pin the SCSI/host-face/CDC
cones from the best fit and END the lottery; [d] only then re-judge the
crash class. v1.1.3 main slot remains the stable daily driver; v1.2.0's
validated wins (clock, dates, restart-mostly-works) are real and keep.

**Seed ledger (blockdev netlist):** s12 (`1.2.0-bd-s12`, rbf 7381fd5b) —
**user 08-24 ~19:15: "same error as before"**; screenshot
`scratch/20260824_191513.png` = the EXACT fingerprint again (Bus Error
$A02000 `_InternalWait+C00` `CLR.W CurApRefNum`, A0=$50F06060,
A1=$50F10050, A3=$50F00000 — SP differs: $4FE9A2 vs the earlier $779Bxx,
so different RAM layout, same crash site). s4 rolled ~19:20.

**★ 19:30-19:45 EVIDENCE CORRECTION (control run):** bd-s4's only strike
was on 7.1 (`scratch/20260824_192636.png`, same fingerprint) — but the
control experiment (byte-identical rst-s7 re-flash, sha 464b4073) showed
7.1 misbehaving there too, and the user then established: **the 7.1 disk
image is CORRUPT** (a casualty of the day's crash loops with live SCSI
writes) while **the 7.5.5 image is HEALTHY** (works on the v1.1.3 main
slot). Therefore: (a) the "7.1 newly affected ⇒ pipeline regression"
inference is RETRACTED — contaminated evidence; (b) 7.5.5-on-control
(rst-s7) still crashes = that fit's known Case-5 marginality, consistent
with the afternoon; (c) **bd-s4 has never had a fair trial** — its 7.5.5
verdict is UNKNOWN. Re-staged bd-s4 from the archived .sof (sha match
a958edfe) for the fair trial: healthy 7.5.5 image, cold + warm boots +
Easy Open. Clean ⇒ pipeline exonerated AND promote candidate; the same
fingerprint on a healthy disk ⇒ a genuine golden-seed strike on the
pipelined netlist ⇒ structural escalation (LogicLock pinning /
first-fill coverage / no_rw_check+hit-drain timing review on the Mac
bench). The 7.1 image needs Disk First Aid or replacement before it
counts as evidence again (user has backups, will restore when needed).

**★ Screenshot decode (scratch/20260824_19{3338,4131,5954}.png) — the
failure is VARIED-SITE now, not one wedge:** 19:33 = Finder RUNNING then
`Unimplemented Instruction` at $13CD7E on `DC.W $F6FF` garbage, regs full
of $AAAAAAAA (boots-then-garbage shape; corrupt-7.1-disk era). 19:41 = the
canonical Bus Error `_InternalWait+C00` **with MacsBug itself printing "(It
looks like 'Macintosh Easy Open' was loading.)"** — the Case-5 context is
now self-documented. 19:59 (bd-s4, HEALTHY 7.5.5) = `Unimplemented
Instruction at 00000003` during **"Foreign File Access"** load — wild jump
to $3, A0=$FFFFFFFF. Same disk-heavy extension-parade phase, three
different crash faces ⇒ intermittent corrupted READ DATA reaching the
guest, not one deterministic wedge. Variance across boots on one fit+disk
argues timing-dependent intermittency (marginality or alignment-dependent
staleness), not a systematically-wrong-sector protocol bug.

**~19:55: bd-s4 fair trial ⇒ user ordered more rolls** ("lets re-roll a
couple more times" — read as the same crash on the healthy 7.5.5 disk,
exact outcome not itemized). That IS a golden-seed strike on the pipelined
netlist per the agreed criterion; the user chose dice over escalation for
now — s7 rolled ~19:55, s6 queued behind it. If both fail 7.5.5 the same
way, the structural path (LogicLock pinning / no_rw_check + hit-drain
review / first-fill coverage) has four-strikes standing and should not be
deferred again.
**Escalation criterion agreed:** if s4 AND s7 also express it (3 strikes on
the PIPELINED netlist), starvation-dwell stops being the dominant
explanation — next levers are STRUCTURAL, not dice: LogicLock-pin the
marginal SCSI cones (the queued M10K-relief/placement mission),
first-fill speculation coverage (prefetch at command receipt), and/or
dma_settle hardening — plus note the fingerprint's instruction-level
determinism keeps the 08-22 "stale/wrong FETCH vs SCSI data" ambiguity
alive (A0 expected -$400(A6)=RAM, holds the SCSI pDMA port).

## -9. 08-24: Special ▸ Restart fix ported — RESET-instruction peripheral soft reset

**Status: ★ HW-VALIDATED on seed 7 (user 08-24 ~16:20: "the build seems to be
working"; the twice-in-a-row Restart gate was not explicitly itemized —
re-confirm opportunistically). Seed ledger below: s4 bad fit, s7 good.**
Port of MiSTer `fc73a58` (branch
pds-enet-icache-fix, HW-validated there 08-24; same set independently
HW-validated on MacIIvi `e653e74`). Root cause: both guest restart flavors
(Special ▸ Restart and the shutdown screen's Restart button) execute the
68020 RESET instruction + jump — NO Egret reset — so the warm ROM inherited
the dying OS's peripheral state. Three stacked wedges:

| piece | what |
|---|---|
| soft_periph_rst | `mac_lc_pocket.sv`: 16-clk stretched pulse off `tg68_reset_n` (new block after `_cpuReset_o`) |
| via6522 + TIP | `dataController_top.sv`: VIA full reset on the pulse (real 6522 /RES); `via_tip_latched` → idle |
| pseudovia | new `soft_rst` port clears INTERRUPT state ONLY (ifr/slot_ier/ier/irq_out/vbl flag) — ram_cfg/video_config SURVIVE or the ROM's own T+4s RESET would unmap RAM mid-cold-boot. Was the black-screen wedge #1: inherited live slot_ier + every-frame vblank ⇒ eternal slot-interrupt handler probing $F1xxxx |
| pseudovia model | MAME-exact VBL flag (edge-driven reg, guest-ackable via reg $02 bit-6 — the ack was a NO-OP before) + ASC IFR bit 4 edge-latched with guest W1C (was auto-tracking the level). SCSI bits STAY LEVEL (LBMacTwo edge-model deadlock lesson) |
| ASC | joins the soft reset (chime-phase quiet-wait wedge) |
| SWIM | `._reset(_cpuReset && !softRst)` — THE decisive wedge: early ROM's ISM→IWM switch-back poll never exits against inherited ISM state (eternal loop $A009CE, video blanked). Media/mount state lives in floppy.v — untouched, tb_disk_swap-class behavior preserved |

**Deliberately NOT reset: NCR/SCC** — the ROM sets up SCSI ~T+2.8s, RESETs
~T+4s, and expects survival; resetting them regressed MiSTer cold boot to a
blinking «?» (2026-06-12 lesson).

**Pocket seam notes:** `rtl/pseudovia.sv` is now byte-identical to MiSTer
post-fix except our pre-existing 8bpp video_config clamp. dataController
hunks applied in the diverged Phase-B/C file at the same three sites (VIA
reset, TIP latch, SWIM reset); the port comment here states the FINAL truth
(SWIM included) where MiSTer's carries a stale pre-2dfcd1a clause.
`verilator/sim.v` deliberately NOT touched (harness unported, §-6).

**★ Item 5 of the mission (force-cold ROM patch removal) is a NO-OP here:**
this tree has NO active ROM patch of either polarity — the inherited
force-cold patch was found dormant (address typo, never fired) and the
buildU forced-WARM patch was retired 08-12 ("honest branch runs on clean
code", comment at mac_lc_pocket.sv ~2104). Restarts already take the genuine
warm ROM path — which is exactly why they wedged — so this port alone is the
complete fix AND delivers the fast warm restart (MiSTer measured
Restart→Finder 55-65 s). Nothing to remove, no second commit needed.

**Gates:** the ROM's own T+4s RESET exercises the soft-reset path on EVERY
cold boot ⇒ a clean cold boot to desktop is a true regression gate, not a
smoke test (sim boot gate unavailable here — MiSTer's passed). HW: cold boot
to Finder, mouse alive, then **Special ▸ Restart to the desktop TWICE in a
row** (once is not a verdict on a timing-dependent class). Fit-lottery
caveat applies (fresh netlist): a boot that looks clean then crashes with
garbage instructions at differing addresses on first interaction is a bad
FIT — reseed before suspecting this RTL (twice this session: §-8).

**Seed ledger (this netlist):** s4 (`1.2.0-rst-s4`, rbf_r 534271f7, STA met,
14,110 ALMs/261 M10K) — **user verdict 08-24 ~15:55: bad, "reseed"**
(signature not recorded). s7 rolled ~15:57. Remember the §-8 lesson cuts
both ways: an identical failure on s7 would NOT yet prove the RTL guilty,
but two bad rolls is where we pause and get the failure signature before
burning a third.

## -8. 08-24: ALL guest-time fixes ported (frozen clock, 1960 dates) — v1.2.0

**Status: ★ HW-VALIDATED ON POCKET (same day).** User verdict on the seed-12
fit (`MacLCtest` "1.2.0", rbf_r sha1 f312a6d9…): **"clock seems to be ticking
correctly and the date is set correct"** — both headline defects confirmed
fixed on hardware. Same build: **7.5.5 fails to boot, 7.1 fine** — that is the
Case 5 discriminator exactly (7.5.5's Easy Open scan vs 7.1's lighter SCSI
load, see the cpuperf status memory + `docs/F-Line_Build_Errors.md` Case 5),
i.e. the KNOWN pre-existing residual: even the parked rc1 (same hd32b ring,
same seed 12, no Egret change) booted 7.5.5 only 3-of-4. Not attributed to the
time fixes — the Egret change is nowhere near the SCSI/ring path. Per the
user's call, one SEED-ONLY re-roll (seed 7; next would be 4; 11 has failed
twice historically) was launched 08-24 ~09:02 to hunt a cleaner placement.

**★ s7 verdict (same day, ~09:40): SAME failure — and now the diagnosis is
photographic.** User reports 7.5.5 crashing **consistently at beginning of
boot** (worse than rc1's 3/4; 7.5.5 always on HD1, so the hd32b-protected
ring); Pocket screenshots `20260824_094040/095902.png` (byte-identical pair,
archived to scratch/) show MacsBug: `Bus Error at 00A02000 _InternalWait+C00`,
insn `CLR.W CurApRefNum`, **A0=$50F06060 / A1=$50F10050 / A3=$50F00000** —
the EXACT documented Case-5 register fingerprint (cpuperf memory 08-22 shot
was `+C08 CLR.L $12(A0)`, 8 bytes later in the same sequence, same regs).
**Two seeds (12, 7), same crash ⇒ mechanism, not placement.** Why consistent
now when v1.1.3 was "fine" (3/4): prime suspect is the DATE FIX AS AMPLIFIER,
not a new defect — the volume's clock jumped 1960→2026, which plausibly makes
Easy Open/Desktop Mgr rescan or rebuild desktop state EVERY boot, i.e. a
larger sustained SCSI read burst inside exactly the window Case 5 lives in
(the documented crash was "during Macintosh Easy Open load" — also
boot-time). Discriminator/unblocker to try on guest: **Shift-boot 7.5.5
(extensions off)** — Easy Open never loads; if it boots clean, rebuild the
desktop once (Cmd-Opt held at boot), then retry normal boots. Also prudent:
Disk First Aid over the 7.5.5 volume from 7.1 (repeated crashes mid-scan
with live SCSI writes can leave FS damage that mimics an RTL bug). Seed 4
rolled anyway at user request (~10:04). Root fix unchanged: pipeline
apf_blockdev refill, gated on tb_scsi_face.
Fit s12 for the record: 14,250 ALMs (77%), 261/308 M10K (85%), worst setup
+2.041 ns, TNS 0 everywhere. `.sof` archived
`scratch/builds/2026-08-24-v1.2.0-egret-time-s12.sof`.

Verbatim port of the
MiSTer fixes (branch `pds-enet-icache-fix`, commits `8c62ccf` + `97b7928`),
which ARE HW-validated there (menu clock ticks, lowmem Time `$20C` advances
1/s). Full mechanism + gates: the 2026-08-24 handoff (MiSTer commit `47e392d`,
`docs/` there). Version bumped 1.1.3 → 1.2.0 (root core.json — the release.sh
version source; dist stays 1.1.3 until this build is promoted). First HW try
went to the card's MacLCtest slot labeled "1.2.0".

Four defects, one subsystem (Egret one-second delivery — the Mac LC has **no
VIA1 CA2 one-second wire**; the HC05 firmware sends a TIMER packet `[00 03]`
over the VIA SR channel each second, enabled by the ROM's `[01 1B 03]`):

1. **`rtl/egret/m68hc05_core.sv` — interrupt deadlock (THE frozen clock).**
   onesec/timer interrupts were edge-detected and an edge landing inside the
   firmware's SEI windows was dropped; the line stays asserted until the
   never-run ISR acks `$12` bit 6 ⇒ permanent deadlock, mouse keeps working.
   Now LEVEL-sensitive (real 68HC05/MAME semantics), latched only at opcode
   fetch (`mainFSM == 4'h2`); ext IRQ pin (tied high) keeps edge semantics via
   `ext_irq_pending`.
2. **`rtl/egret/egret_wrapper.sv` — `$12` reads expose the fired flag in
   bit 6** (MAME m68hc05e1 parity) so firmware RMW bit ops can't spuriously
   ack a pending second.
3. **`ONESEC_PERIOD` 4,000,000 → 4,062,499.** Verified for THIS fork's clock
   tree, not copied blind: dataController_top instantiates egret_wrapper with
   `.clk(clk32)` = `clk_sys` = 32.5 MHz, `cen = clk/8` = 4.0625 MHz —
   identical to MiSTer, so `cen_Hz − 1` is the same constant. (Counter spans
   `0..PERIOD` inclusive; old value ran the guest wall clock 1.56% fast.)
4. **RTC seed now in the Mac epoch:** `mac_seconds = timestamp + 2,082,844,800`
   (1904↔1970 offset) seeds intram `$AB-$AE`. Was raw Unix ⇒ guest lived in
   1960 (offset is exactly 24,107 days; same leap-day count 1904→1970 as
   1960→2026, so wall time was right and only dates showed it). The MiSTer
   DST half of the handoff **does not apply here**: the seed is APF
   `rtc_epoch_seconds` (core_bridge_cmd `host_20`), which Analogue OS derives
   from the user-set LOCAL wall clock with no timezone math — already what
   Mac Time wants.

**Port fidelity:** both Egret files diff clean against the MiSTer post-fix
blobs except the pre-existing buildAN `dbg_pc`/`dbg_hc05_pc` taps and two
Pocket-adapted comments. `check_hierarchy` PASS. The handoff's sim gates
(tick cadence, FIRE/ACK witness — the witness is in the wrapper under
`SIMULATION`) are **not runnable here** — the Verilator harness is still
unported (§-6) — so this leans on MiSTer's sim A/B (pre-fix sends collapse
`…316, 325, 2, 1, 0…` after the enable; post-fix ~470/s to end of run,
FIRE==ACK 8970/8970) plus shared-RTL byte identity.

**HW gates:** ✅ menu clock advances (user-confirmed); ✅ dates correct
(user-confirmed); ✅ mouse/ADB alive (implied — 7.1 runs fine on the same
build). Still open: the §-7 I-cache gate (7.5.5 @ 8bpp + 32-bit), blocked
behind the 7.5.5/Case-5 boot residual above, and the long-run drift check
(the old constant ran the clock 1.56% fast — a multi-hour session should now
hold wall time). Trap from the handoff, kept for the record: the deadlock was
probabilistic per tick — "clock right at boot, then frozen" is the tell, and
the boot-time re-seed masks a frozen HC05 RTC between core loads. Note the
seed overwrites the guest clock at EVERY core load (host-wins policy, kept
deliberately — guest-set Date & Time lasts only until the next load).

## -7. ★★★ 08-22: the I-cache 8bpp+32-bit Finder crash — `.enable` must not be a constant

**Status: FIX APPLIED, NOT YET HARDWARE-VALIDATED ON POCKET.** Ported from the
MiSTer handoff of the same day, where it IS hardware-validated.

### The defect

The I-cache release crashes the Finder — Illegal Instruction / Bus Error, wild
jumps into `$079xxxx`, **heap intact** (a control-flow smash, not a memory
corruption) — on **both** MiSTer (`MacLC_20260819.rbf` = md5 `65332d3b`,
commit `454429e`) **and this Pocket port**. Two independent boards, two
independent fitters ⇒ this is a **functional defect in the shared RTL**, not
the fit lottery of `docs/BUILD_INSTABILITY.md`. Prince of Persia 2 failing to
launch (6.0.8 and 7.1) is the same defect.

### Why it hid for so long

It only expresses with the video at **8 bpp (256 colours) AND 32-bit
addressing ON**. In 1-bit it does not express at all — and a PRAM reset drops
the machine back to 1-bit, silently masking it. Most "can't reproduce" rounds
were 1-bit rounds.

### The fix (one line, structural)

`fetch_cache`'s `.enable` must be a **non-constant net that still evaluates to
1**. MiSTer: `.enable(~status[11])` (status[11] defaults 0). Here:

| | |
|:--|:--|
| `src/fpga/core/mac_lc_pocket.sv` | new `input icache_en`; `.enable( icache_en )` replaces `.enable( 1'b1 )` |
| `src/fpga/core/core_top.sv` | new `reg opt_icache_off = 1'b0` at bridge address **0xF0000064** (read + write decoded), 2FF-synced to clk_sys as `icoff_s1/s2`, connected as `.icache_en( ~icoff_s2 )` |

**No interact.json row was added** — the menu is at its measured ceiling of 13
vars + 5 data slots (`docs/interact_envelope.md`, 08-20: a 14th var silently
drops a row on hardware), and no row is needed: a bridge-decoded register is
already non-constant to Quartus because `bridge_wr_data` arrives on a pin. The
address doubles as a **bench A/B lever** — write 1 to turn the answer path off
without a rebuild.

**Mechanism.** Inside `rtl/fetch_cache.sv`, `enable` is registered
(`enable_r <= enable`) and `enable_r` is in the fanin of *both* `hit` (the
registered answer feeding `_cpuDTACK` and the CPU din mux) and `hit_now_comb`
(the `sdram_oe` request suppression). Against a constant the fitter folds
`enable_r` and every `enable_r &&` term away, collapsing both cones into a
structure whose fast hit answer races a downstream consumer. Against a real
net `enable_r` survives and the cones synthesise into a form that does not
race. **The value is 1 either way — the fix changes how the logic is BUILT,
not what it computes.**

### What the offline A/B could and could NOT show (08-22, measured here)

Both variants were run through `bash scripts/build.sh --check` (Analysis &
Synthesis only) and their "Registers Removed During Synthesis" tables diffed:

| | `.enable( icache_en )` | `.enable( 1'b1 )` |
|:--|:--|:--|
| A&S result | 0 errors | 0 errors |
| removed-register table | 454 lines, no `fetch_cache` entry | 454 lines, **no `fetch_cache` entry either** |
| Total registers | 9,548 | 9,546 |

**★ This A/B is NOT diagnostic, and no one should read it as confirming the
mechanism.** `enable_r` is absent from the removed list in BOTH builds, so its
absence in the fixed build proves nothing. The +2 register delta is consistent
with several explanations (the three new regs `opt_icache_off`/`icoff_s1/s2`
minus optimisation, with or without `enable_r` surviving) and does not resolve
which. The handoff attributes the folding to the **fitter**, and `--check`
stops before the fitter — so the stage that does the damage was never run.
The A&S report also never enumerates *surviving* registers by name, so grepping
it for `enable_r` can only ever return the removed case.

To actually measure this, a full compile is required, and then the post-fit
netlist (fitter reports / node finder) must be inspected for `enable_r` — not
the A&S report. **Do not repeat the `--check` A/B expecting an answer.**

### ✅ Post-fit confirmation (seed 12, 08-22)

Done properly, by querying the fitted timing netlist rather than reading a
report:

```bash
quartus_sta -t q_enable.tcl     # get_registers *icache|enable_r* etc.
```

```
*icache|enable_r*   -> 1  core_top:ic|mac_lc_pocket:machine|fetch_cache:icache|enable_r
*opt_icache_off*    -> 1  core_top:ic|opt_icache_off
*icoff_s*           -> 2  core_top:ic|icoff_s1, icoff_s2
```

**`enable_r` survives into the fitted netlist** — the fix does what it is meant
to do structurally. This is the right instrument for this question; reuse it
(`get_registers <pat> -nowarn` + `get_register_info -name`) rather than
grepping reports.

★ Still NOT measured: the counterfactual — that `.enable(1'b1)` *removes*
`enable_r` at fit. That needs a second full compile of the control. Until it is
run, "the fitter folds it" remains the handoff's account, not this fork's
measurement. It does not block the hardware gate (which tests the fix, not the
theory), but it is the one experiment that would close the mechanism.

**Fit (seed 12):** 14,191 / 18,480 ALMs (77 %), **275 / 308 M10K (89 %)**,
10,429 registers, timing met — worst slack **+0.118 ns**, zero negative paths.
★ 89 % M10K is the density band where the 08-20 lottery ran ~3-of-4 bad on
first roll, so a bad hardware verdict here is NOT automatically evidence
against the fix — re-roll the seed once before drawing any conclusion, and
remember the second half of the rule: two failures of ONE netlist means stop
rolling and build a control (`docs/BUILD_INSTABILITY.md`).

### ★ Honest caveat — this is why the HW gate is not optional

Because the fix is structural rather than a root-cause logic change, its
robustness on a *different* fitter/placement is **not guaranteed by the value
change alone**. MiSTer's isolated proof is `MacLC_varA.rbf` = md5 `8896c2b2`,
commit `ad53af0`, seed 4, STA met (worst slack +0.627), user-confirmed on
hardware in the crashing config. The Pocket needs its own.

### Reproduce (the gate this fix must pass)

1. System 7.5.5: Monitors ▸ **256 colors**; Memory ▸ **32-bit addressing ON**.
   (This core can also force the latter from the **32-Bit Memory** menu row.)
2. **Special ▸ Shut Down** — this is what writes 8bpp+32-bit to PRAM. In-core
   Restart is separately broken; do not rely on it.
3. Reload the core and let it boot.
4. Open a few Finder windows / normal window traffic.

→ release bombs, fixed build stays clean. **A core reload alone cold-boots to
1-bit if PRAM was never written — that will look like "can't reproduce."**

Also worth running: Prince of Persia 2 launch (6.0.8 and 7.1), and Speedometer
3.23 (expect ~3.59 mix / ~97% — the fix keeps the immediate hit answer, so
there should be **no** perf regression; a regression means the answer path
changed, not just its structure).

### Offline gates (from `verilator/`, Verilator 5.x — currently unported here)

- `tb_icache_transient` — truth invariant, every CPU-consumed word == memory.
  PASS = 747 checks, 0 errors.
- `tb_icache_seam` — done-birth discipline. Run normal (PASS) **and** the
  negative control `+define+SDRAM_NO_DONE_LEVEL_FIX` (must FAIL).
- `tb_fetch_cache` — hit-data currency. Run normal (PASS) **and**
  `+define+FETCH_CACHE_HOSTILE_RDW +define+FETCH_CACHE_NO_RDW_FIX` (must FAIL).

These live on the MiSTer tree; this fork's Verilator harness is still stale
(§-6). They gate the cache's *function*, which this change does not touch —
the Pocket gate here is the hardware repro.

### ★★★ The law this leaves behind

**Do not "simplify" `.enable( icache_en )` back to `1'b1`.** It is not dead
configurability. Same class as `pocket_sdram`'s `t == 3'd1` start
quantization: RTL that is provably equivalent on paper and not equivalent in
silicon. Comments marking it are in both files.

## -6. ★★ 08-19: the MiSTer CPU-perf mission ported (Phase B + C + I-cache)

**What:** the full three-layer CPU-performance stack from
`../MacLC_MiSTer` branch `cpu-icache` (which measured **97.0% of a real
Mac LC** on Speedometer 3.23, mix 2.771 → 3.591, HW-validated there
2026-08-19) is ported onto this tree in one pass. Mission spec:
`../MacLC_MiSTer/docs/Pocket_Port_CPU_Perf_Prompt.md`; running log with
every mechanism and defect: `../MacLC_MiSTer/docs/CPU_Perf_Log.md`.

| Layer | What | Files here |
|:--|:--|:--|
| B | collapsed bus FSM (S_IDLE/S_WAIT/S_TAIL1/S_TAIL2/S_ENDC), `addr_early` | `rtl/tg68k/tg68k.v` (verbatim copy from cpu-icache) |
| C | demand-start SDRAM service + dedicated `dl_*` download port + explicit refresh + `flp_win`/`flp_guard` floppy windows + `flp_present` gate | `src/fpga/core/pocket_sdram.v` (engine), `rtl/addrController_top.v`, `rtl/dataController_top.sv` (dskReadDataIn), `src/fpga/core/mac_lc_pocket.sv` (glue: DTACK via `~sdram_cpu_done`, ROM-write ack-and-discard, clk_sys request-bundle registration `ram_*_q`) |
| I-cache | 1 KB direct-mapped word-granular fetch cache, RDW-immune, gen-flush, `hit_now` request gate, **always on** | `rtl/fetch_cache.sv` (verbatim) + 4 glue points in the top |

All **seven laws** and **five traps** from the mission doc were applied
(single-owner completion signals; every unserved access class terminated;
no CPU-vs-non-CPU shared muxes — the `download_cycle` mux and the ROMV
oracle's request legs are GONE; no ack-rate "optimizations"; RDW immunity
by construction; done-birth guard `&& oe`; `hit_now` per-access snapshot).
SDC: kernel/periph multicycle justifications rewritten for the Phase-B
gating; explicit DO-NOT-ADD note on the clk_sys→sequencer request paths
(core_constraints.sdc) — the registration exists instead.

**Retired with this port:** the ROMV retention oracle (romv_* + its
cp_romv/cp_rvsu/cp_rvax probes + `dout_stb`) — JTAG is retired, its lever
was tied 0, and its free-run-oe protocol is meaningless under demand-start.
The buildT one-shot-accept survives, re-keyed to the new `dl_ack`
handshake; the buildR/S row-crossing-tear protections carry over by
construction (latched dio_a/dio_data + freeze-at-ACTIVE in the controller).

**★ verilator/sim.v is NOT ported** (user directive 2026-08-19: sim is
stale, go hardware-first). It still instantiates the old-shape
addrController/dataController ports and will not compile until the MiSTer
`verilator/sim.v` changes are ported. The MiSTer TBs
(tb_fetch_cache/tb_icache_seam/tb_dl_cpu_seam) remain the reference gates.

**HW gates owed** (in order): reload-to-"?" acceptance first, then boot to
Finder desktop, cursor liveness, colour icons, floppy mount + read
(Fetch GCR800K-class), SCSI soak, Speedometer 3.23 vs
`../MacLC_MiSTer/docs/Speedometer_3-23_Benchmarks.md` (expect ≈ MiSTer:
mix ~3.59). **If FP tests regress while tight loops improve → Law 7
(request gate). If it hangs on floppy mount → Law 3/6 seams.** A bad fit
is not evidence about the port (fit lottery, §-5) — but repeated failure
across seeds IS evidence about the netlist.

**Card:** staged as **v1.1.0** into the `MacLCtest` third slot.

## -5. ★★★ 08-17: Dock keyboard+mouse shipped, and the instability explained

**Card at close:** `MacLCtest` = **buildCG** (5fbb203a) — HW-validated:
Dock USB keyboard and mouse working, clicks correct, stable session.
`MacLC` = v1.0.2 (BP bytes), `MacLCprev` = same. CG is the **v1.0.3
candidate** pending a soak (buildBS ran clean for two days then failed a
retest — one good session is not proof).

### ★★★ THE FIT LOTTERY IS PROVEN (and so is its inverse)

**buildBY (seed 2) F-lined; buildBY2 (seed 11) worked. RTL byte-identical.**
First clean isolation of placement in the whole arc — every earlier
experiment moved netlist and placement together. Full write-up:
`docs/BUILD_INSTABILITY_MEASUREMENTS.md` §8.

Permanently exonerated, because the netlist did not change between them:
the marginality anchor · rung 3 / startup input mode · the SDC clock-group
change · the ASC pin · design density · any specific RTL edit. STA cannot
predict it either — BP, BY and BY2 had near-identical green gates.

**★ THE ASC ALERT FIX WAS NEVER NEEDED.** buildCG plays and stops the alert
with `rtl/asc.sv` byte-identical to BP and no `dbg_asc`/`anchor_asc0`. The
stuck alert — v1.0.1's headline known issue — was fit-expressed, like the
icon garbling and the F-lines. The queued "BP + ASC fix" build is dropped.

**★★ BUT: repeated failure of ONE netlist is NOT the dice.** buildCD failed
at seeds 11, 23 AND 37; buildCF at 41; while CC was good at 11 and CE (CC's
exact RTL) good at 41. Four card trips were spent re-rolling because
"a bad fit is not evidence about your change" was applied past its range.
Both halves of the rule now live in the measurements doc. Cost: two wasted
card trips and a false conviction of the fitter.

### USB keyboard + mouse (buildCA → CG) — the wire format, learned the hard way

Nothing in `src/fpga/apf/` changed and `core.json` needed no edit —
`core_top` already declared `cont3_*`/`cont4_*` and ignored them.
`src/fpga/core/pocket_hid.v` decodes them into the existing
`ps2_key`/`ps2_mouse` buses, so adb_device → Egret → Mac is untouched.

Three facts that cost builds to learn — **read before touching the mouse**:

1. **The delta is an 8-bit SIGNED value at bits [15:8], not 16 bits at
   [15:0].** Reference: `../Analogue-Amiga`
   `src/MPUBIOS/drivers/KMIO/inputs.cpp:93-96` masks `0x0000FF00` and keeps
   the value scaled by 256 so its divide holds precision. Reading [15:0]
   gives delta*256 plus low-byte junk: saturation on nearly every report
   (uniformly far too fast) and a corrupted sign on Y (Y not tracking).
2. **`adb_device` OVERWRITES its mouse register and never accumulates**
   (`adb_device.sv:680-692`), and the ADB register is 7-bit signed
   (-64..+63). MiSTer forwards each PS/2 report and so silently DISCARDS
   intermediate motion — that lossiness is the feel users are calibrated to.
   Accumulating loses nothing and therefore over-delivers by a CONSTANT
   factor (report_rate/tick_rate). Forward one event per report.
3. **The button needs its own trigger.** APF's report counter does not
   necessarily advance for a press or release on a still mouse, so a button
   riding only the motion report arrives late — a menu that opens on click
   and will not close until the mouse moves.

Menu: **Dock mouse speed** (Normal/Half/Quarter/Eighth, id 131 @0xF0000054).
Modifiers land in Mac positions: Alt → Command, GUI → Option.

### ★ NEW INSTRUMENT: verilator/tb_pocket_hid.v (ModelSim, no Quartus)

There is no Verilator on the build machine; ModelSim ships with Quartus Lite
and needs none of the broken full-machine harness. `run_tb_pocket_hid.sh`
takes any DUT path, so old commits can be benched.

It found two real defects offline that four card trips had missed: a
**forward reference** (`btn_now` used `hid_btn` 17 lines before its
declaration — Quartus accepted it silently, ModelSim rejected it, and under
`` `default_nettype none `` it should never have compiled) and the wire-format
error above. It also REFUTED the event-storm theory by measurement.

★ It also shows buildCD's module was FUNCTIONALLY CLEAN — identical to CG on
every test both support. **So why CD failed three times is still unknown.**
Left labelled rather than explained.

### interact.json — the size ceiling, bisected at last

The 08-15 note said the killer axis "was never isolated". It is **FILE
SIZE**: >7,793 bytes fails, ≤10,407 fails, and the shipped v1.0.2 menu at
7,793 loads. **9-option lists are fine** and **15 variables are fine** (the
Amiga core ships 15) — both were suspects and both are innocent.
Full data: `docs/interact_envelope.md`.

Current menu: 12 vars, **7,471 bytes, 322 to spare**. Memory stays removed
(10 MB hardwired), Reset PRAM stays out (no value), the clicks-OFF
diagnostic option is removed. L/R/Start are fixed; the readme documents how
an advanced user can trade an entry to remap them.

★ **defaultval semantics stay OPEN.** The card's persist files prove the
hex-string defaults are delivered as VALUES (id 110 = 90 = 0x5A Return), so
do NOT "fix" them to indices — that would send scancode 0 and kill all seven
buttons.

### Process rules this day earned

- **Commit as you go.** `git checkout interact.json` destroyed the only
  load-verified menu, which existed solely in the working tree and on the
  card. Recovered from `scratch/staging`. Load-verified config belongs in git.
- **Never chain commits into a backgrounded compile** (`... && git commit &&
  ... &` ). One failed commit aborted the chain and the build never started,
  invisibly.
- **Re-serialising JSON is not editing it.** `json.dumps(indent=4)` rewrote
  6,848 bytes to 10,591 and blew the ceiling. Insert as text.
- Archive **output_files AND db** per build — the db is the post-fit netlist
  and the only path to a placement comparison later.

### Next

1. Soak buildCG (power-off boots, Finder work, icon gate), then **ship
   v1.0.3**: mouse default, NMI, arrow keys, Dock HID + speed, no alert bug.
2. ~~Retest GCR 800K~~ **DONE 2026-08-17 — GCR WORKS.** User: 800K disks are
   fine on buildCG. No floppy-path change was made; the old F-line/hang
   reports were bad-fit artifacts. That closes what the postmortem called the
   headline open defect, and it is the fourth symptom (after icon garbling,
   F-lines and the stuck alert) that turned out to be the fit rather than a
   defect. **Supported floppy formats: 400K/800K GCR and 720K/1.44 MB MFM**
   (`mac_lc_pocket.sv:1753-66` classifies 409600/819200/737280/1474560 plus
   the DiskCopy 4.2 variants). 800K and 1.44 MB are HW-verified; 400K and
   720K share those paths but nobody has run one.
3. Then either the Verilator harness or the marginal-cone constraint work
   (postmortem step 2, still unrun; nine labelled builds with databases are
   archived to aim it).

Deferred by decision, with reasoning: `TODO.md`.

(previous header below)
# RESUME — MacLC Pocket (2026-08-17: ★★★ v1.0.1 RELEASED — BP bytes)

## -4. ★★★ v1.0.1 SHIPPED (2026-08-17, morning after the all-nighter)

**★ READ docs/BUILD_INSTABILITY.md FIRST** — the plain-language
postmortem of the 08-15→08-17 build arc: verdict table, eliminations
with evidence, the surviving theory and its honest status, and the
ordered plan (BY = BP+alert fix; the BX constraint experiment).


https://github.com/danifunker/MacLC_pocket/releases/tag/v1.0.1
Ships **buildBP's exact bytes** (6b2ee6ec…, sof archived + on-card
backup; RTL = main-history commit f85739a) — the only build that
survived the night's clean-state gauntlet (user: "works 100% fine",
re-verified same morning in BOTH card slots). Packaging: 14-var menu
(id-130 trimmed), corrected info.txt (package.sh now propagates it),
keyboard-mode power-on documented, honest notes incl. the ALERT
WORKAROUND (alert volume 0 = menu-bar flash — the stuck-beep bug is
in these bytes; its fix exists but only ever rode condemned builds).
- ★ DETERMINISM TEST PASSED: BP's exact tree recompiled = rbf differs
  from the archived rbf by 327 bytes in 2 clusters = header + the
  build_id timestamp ROM (PRE_FLOW build_id_gen.tcl). Toolchain
  deterministic, BUILD MACHINE EXONERATED. The fit-marginality story
  stands alone, with the -3 section's localization (Finder-load-only,
  ?-screen and Welcome clean) painting the target: constrain/harden
  the VRAM-shadow RMW cone, prove on condemned netlist BX.
- Post-release queue, in order: (1) re-land the ASC alert fix alone on
  the BP base (buildBY candidate = f85739a + dbg_asc/anchor_asc0 ONLY),
  (2) the VRAM-shadow constraint experiment on BX, (3) mouse-default
  as sampled-at-reset, (4) the standing opens (GCR, hangs, PRAM,
  restart). ONE variable per build; the one-boot damn-test + both-slot
  A/A symmetry are the cheap gates now.
- Card at close: BOTH slots = BP bytes (main = v1.0.1 set, prev =
  original); user's fresh minimal disk as maclc.hda; games-image
  pristine copies parked on card; Settings clean.

(previous header below)
# RESUME — MacLC Pocket (2026-08-16: ★★★ v1.0.0 RELEASED)

## -3. ★★★ 08-16 EVENING STATE: BW falsified the SDC theory; BX in flight

Scoreboard of the evening's builds (all on CLEAN card state - pristine
image, parked Settings):
- buildBW (timed interface, all gates + witness +2.0 ns): cold = F-line
  + screen corruption, warm = corruption only. THE SDC FIX IS REAL
  ENGINEERING BUT WAS NOT THE MECHANISM - prediction falsified as
  stated. KEEP the merged clock groups regardless (the interface must
  be timed; "green" is now honest).
- ★ ALERT-SOUND BUG FIXED on BW (user-verified: alert plays and
  stops). The ASC FIFO status cone pin (anchor_asc0 + dbg_asc) and/or
  the timed interface cured it. Carry forward forever.
- Settings poisoning discovered: a corrupt-fit session made Analogue OS
  persist garbage interact readbacks (all button dropdowns = 0).
  PROTOCOL: park Settings\danifunker.MacLC on every bad-fit recovery.
- Empirical read that drives BX: every rung-3-family netlist except BS
  produced corrupt fits (BQ/BR/BU/BW = 1 good roll in 5); every
  pre-rung-3 netlist clean on its day. Two RTL audits of rung 3 found
  nothing - withdrawn on the record, not a mechanism.
- buildBX (compiling at write time) = BW minus rung 3: colour + floppy
  + mapper + full anchor + ASC pin + timed SDC; power-on = keyboard
  mode. BX clean => ship as v1.0.1 (trim interact id-130 from dist
  first); BX corrupt => the curse is not rung 3, prime suspect becomes
  what BX still shares with the bad family (the anchor deck itself).
- ★★ LATE 08-16, user-driven LOCALIZATION of the bad-fit failure (BX
  corrupted too; v1.0.1 retreated to BP): on a bad fit, the diskless
  "?" screen (1bpp idle) is CLEAN and "Welcome to Macintosh" at FULL
  8bpp depth is CLEAN — corruption begins only once the FINDER is up.
  So depth alone is insufficient and base fabric operation is fine;
  the failure needs Finder-grade activity: QuickDraw byte-masked RMW
  VRAM traffic concurrent with disk serving through pocket_sdram.
  TARGET for the fix build: explicitly constrain/harden the CPU-side
  VRAM-shadow RMW cone (address + byte-enable paths into pocket_sdram)
  — set_max_delay the cone or register the shadow path — so every
  future fit must close what the bad fits fumble. Test = a condemned
  netlist (BX) + the constraint: corruption gone => mechanism proven.

## -2. ★★★ RELEASED: v1.0.0 (2026-08-16)

https://github.com/danifunker/MacLC_pocket/releases/tag/v1.0.0
Ships **buildBS** (sha1 43576712…, sof scratch/builds/2026-08-16-
buildBS-anchor.sof): the ladder tree (BB base + colour graft + BF
mapper + startup-input-mode + arrow menu) **+ the ported MiSTer
marginality anchor** — HW-validated same-day: icons clean, mouse
default at power-on, 6.0.8/7.1/7.5.5 boot. Branch of record:
`ladder/release-rebuild` (fc7efe9). ANCHOR VALIDATION = the icon
garbling (BQ/BR) cured by the anchor alone at BQ's own seed; the
boot_problems ★★★ 08-16b mechanism is CONFIRMED ON HARDWARE. The
anchor is permanent structural RTL — never remove/ifdef/fold; icon-
gate every future netlist in the Finder.
★ BRANCH OF RECORD = **main** as of c394e54 (tree == v1.0.0; the
stale 712cbe3 snapshot retired via ours-merge). RELEASE POLICY (user,
2026-08-16): **releases are cut from main ONLY** — release.sh enforces
it (--publish refuses off-main). new-start-point and
ladder/release-rebuild are historical lines; develop on main.
Post-1.0 queue: GCR floppy (the headline open defect), hang base-rate
(serving-timing class; wait-at-menu mitigates), PRAM persistence
(slot 220 + save bench), Special→Restart. ★ User's card still carries
the pre-1.0 core.json (0.9.0 label) — sync the full 1.0.0 dist on the
next card touch. ★ THIS MACHINE RETIRES — scratch/builds/ (A→BS sof
chain) is copied to the card at D:\Backup\maclc-builds\ (through BS);
verify before decommissioning.

## -1. ★★★ LADDER STATE (2026-08-16, history of the release rebuild)

Full story: docs/boot_problems.md ★★★ 2026-08-16 section (taxonomy,
fit families, image wear, the ladder). Ladder branch:
`ladder/release-rebuild` (worktree ../MacLC_BBcolor), base BB 02fb297.

| rung | build | contents | HW verdict |
|---|---|---|---|
| 1 | BO | BB + colour graft seed (1a4844c pram) | **PASS** — colour desktop from seed, floppy OK |
| 2 | BP | + BF mapper RTL (9f26625) | **PASS** — 6.0.8/7.1/7.5.5 boot; defaults+dropdown+custom(`a`,`` ` ``) typed |
| 3 | BQ | + startup-input-mode (from bcf0302) + arrow codes in menu (max 388) | feature PASS (mouse default works); netlist GARBLES icons |
| 3b | BR | same netlist, seed 4 re-roll | GARBLES icons IDENTICALLY ⇒ synthesis-alignment class, not placement |
| 3c | BS | + **the ported MiSTer marginality anchor** (seed 2, pure A/B vs BQ) | COMPILING at handoff — see boot_problems ★★★ 08-16b |

- ★★★ 08-16b THE HEADLINE: the icon garbling led to the discovery that
  the Pocket port SEVERED MiSTer's always-on marginality anchor at
  import (MacLC.sv.reference:1238-96 documents our exact symptom:
  "Finder colour-icon noise → error-11/F-Line", ring-stale serving,
  STA-blind). Anchor now ported (buildBS). If BS is clean this likely
  retires the whole fit-family F-line class; icon-gate every future
  netlist in the Finder. Full write-up: boot_problems.md ★★★ 08-16b.
- Card: main core = BR + reseed-3 pristine maclc.hda (damaged image
  parked as maclc-icons-garbled-20260816.hda — user saves inside;
  fsck error InvalidCnidRange = write-back damage from the garbling
  era); `MacLCprev` second core = BP fallback. ★ CORRECTION: both
  cores share the ONE maclc.hda (the earlier "duplicate image at
  Assets/maclcprev/" note was wrong; free space fine at 25.4 GB).
- ★ WAIT-AT-MENU CONFIRMED HELPING (user): power on → ~60 s at Pocket
  menu → launch = fewer boot failures. Standing tally protocol + readme
  note. (Pocket OS card-indexing contention.)
- Arrow/nav keys: PS/2 Set-2 EXTENDED codes E0xx map to 0x100|xx in
  adb_device (Up=373, Down=370, Left=363, Right=372, Home=364, End=367,
  PgUp=375, PgDn=378, Del=369) — menu sliders now reach 388. UNTESTED
  on HW until BR round.
- Open questions for user: did BQ's mouse-at-power-on work before the
  glitch? Which failure class was the residual instability (hang vs
  F-line)?
- Next: BR gates → card → rung-3 tally (mouse default, live-follow,
  arrow custom code 373, glitch gone?) → rung-4 decision (scrub:
  optional; power-cycle workaround documented) → release assembly
  (readme Controls+beta notes, trim dist, release.sh re-zip, publish on
  user's word). PRAM persistence stays post-release (gated on slot-220
  re-add + save-flow bench; colour-at-boot is PROVEN fine on clean
  fits).

## 0.0 ★★★ 08-14d: THE PORT WORKS. PROBES WERE THE POISON.

buildAZ (d04b8a2: ZERO probes — no sld hub in the fabric, all levers tied
off) + pristine maclc.hda (SHA-restored from zip): user played Prince of
Persia and "everything" on System 7.1 from a cold card boot, no OSD
touch (auto-mount buildAY working), no JTAG cable. The nondeterministic
late-boot faults (bus error @~217 / F-line @~800 / fast-restart deaths,
all post-scsi_dpram-fix) do NOT occur on the probe-less fit. The A/B vs
the same morning's buildAY cold boot (probed fit, pristine image, bus
error at first extension) isolates the instrument deck as the variable.
Treat ISSP debug fits as SUSPECT INSTRUMENTS from now on: they perturb
the machine they observe (hub + hot levers + placement pressure).
Re-enable instruments ONE at a time via USE_ISSP_<X> qsf macros
(per-instrument guards shipped in buildAZ; see ap_core.qsf).

Open items (user list 08-14d), status end-of-day:
- ~~floppy~~ FIXED buildBB (02fb297): apf_blockdev now presents the
  ONE-PAST end address at download fall (MiSTer hps_io.sv:677 contract);
  the size classifier matched nothing before, so picks silently no-oped.
  Bench-proven (full copy through the real bridge protocol); HW pending.
- ~~PRAM color~~ SEEDED buildBC: rtl/egret/egret.pram baked from a REAL
  MiSTer guest session (scripts/nvr_to_pram.py, source .nvr SHA
  d6209b2a…, copy in scratch/). ★ DOCUMENTED: the LC's saved video mode
  ID lives at XPRAM 0x58 ($82=4bpp -> $83=8bpp), monitor-match bytes at
  0x59/0x5A, slot-PRAM record at 0x81. Full persistence + the slot-220
  save-req stall (landmine #2) remain FUTURE work.
- ~~debug menu~~ REMOVED buildBA (interact 104/105 + RTL).
- ~~display modes~~ ADDED buildBA (video.json 0x10/0x20/0x30/0x40).
- ROM patch (forced-warm POST skip): RECOMMENDED AGAINST (breaks true
  cold boots — see mac_lc_pocket.sv:1944 retirement note); safe
  POST-shortening variant = future research if wanted.
- per-key input remapping: future feature build (interact-driven
  keycode table into pocket_input). NOTE the Pocket OS has a built-in
  remap layer (Settings/<core>/Input/input_persist.json id→remap pairs)
  — part of the wish may be an input.json richness job, not RTL.
- ★ 08-14f PRAM colour — ★★★ ROOT CAUSE FOUND + FIXED 08-14 (harness
  machine; MAME A/B + seeded Verilator; full decode in
  **docs/pram_video_record.md**, runs in scratch/pram/). The ROM
  validates the saved record against the MACHINE, and the match bytes
  encode VRAM SIZE: XPRAM 0x5A = montype | (0x08 if 256K VRAM),
  0x59 = $A0 | same. The MiSTer-captured seed said $A2/$02 (512K
  world); this fork presents a 256K SIMM (buildAW), so the ROM
  discarded the record at driver open (PC A4B7BC: match → pseudovia
  video cfg $13 = 8bpp; mismatch → $10 = 1bpp + record REWRITTEN to
  $80/$AA/$0A). It was NEVER a delivery problem — buildBC's bytes,
  buildBD's loader and MLAB init all fully exonerated (the guest was
  rejecting the content, not missing it; buildBD's loader can stay as
  harmless redundancy). FIX: rtl/egret/egret.pram 0x59/0x5A → $AA/$0A;
  scripts/nvr_to_pram.py now applies the 256K fixup automatically on
  any future .NVR import (--keep-512k to opt out). PROOF: MAME maclc
  @256K+montype2 sets 8bpp with the patched seed (M3) and keeps the
  record; seeded sim 7.1 boot switches to wpl=256 (runC, colour
  desktop). ★ TRAP for future depth work: a DISKLESS "?" boot ends
  1bpp even when the record is accepted (the blink loop re-writes cfg
  $00) — judge acceptance by the transient $13 write / record
  survival / an OS-boot desktop, never by the ? screen. XPRAM 0x81
  (slot-record byte, $A2 in the seed) was untouched by the ROM in
  every run and did not block the colour desktop; semantics still
  unknown. NEEDS: buildBE fit on the Quartus machine (none here) —
  data-only change (readmemh + buildBD's M10K copy read the same
  file), no RTL edit required. Egret XPRAM access witness added to
  egret_wrapper.sv under SIMULATION for future PRAM work.
  ★ Special→Restart soft reboot remains its own standing bug (below).
- ★ 08-14f SOFT REBOOT BROKEN (standing bug, user-reported): guest
  Special→Restart does not come back up. Not newly regressed — never
  worked on the Pocket. Suspects: the machine reset path
  (user_reset/sdram_reinit interplay, rom_loaded latch semantics on
  warm resets). Needs its own investigation; blocks all warm-restart
  PRAM diagnostics meanwhile.
- ★★ 08-14h BOOT INCONSISTENCY ROOT (probable) — THE WARM-PATH LEAK:
  boots were inconsistent on buildBE with BOTH the worn and PRISTINE
  image (image exonerated), battery/heat fine — but the user observed
  full power-off boots behave BETTER than core relaunches. Mechanism:
  SDRAM survives a relaunch, so the ROM sees the previous session's
  'WLSC' warm signature ($CFC) + half-stale RAM and takes the warm
  path — the same fragile path Special→Restart dies on. Randomness =
  whatever the last session left behind. This also retro-suspects
  every "unstable build" verdict made on relaunch-heavy test loops
  (buildBF's conviction included — its fit may have been fine).
  FIX in buildBG: launch scrub — 8 zero words over $CF8-$D07 injected
  through the dio write path (scrub_busy rides download_cycle routing
  only) before rom_loaded releases the CPU; forces the cold path on
  every launch. Soft reboot stays broken (in-guest warm path is its
  own bug); scrub covers LAUNCHES only. buildBG also carries: mapper
  re-fit (CDC slimmed to resolve-before-crossing, 128 sync flops),
  "Startup input mode" (Mouse default, live-follow until first
  Select), seed 3. TRUST GATE: repeated RELAUNCH boots on HW — the
  actual failure mode — not just cold boots.
- 08-14f display modes: user verdict — Trinitron is REALLY good; GB
  DMG/GBP/GBP-light do nothing visible on this source (they are 160x144
  handheld colourisation profiles). Catalog fact: 0x10 Trinitron is the
  ONLY computer-CRT profile Analogue ships. video.json trimmed to
  0x10/0x20/0x30/0x40 (Trinitron + the three real LCD technologies).
  User leaning Trinitron-only — one further JSON trim if decided.
- ★★★ 2026-08-17: **GCR IS RESOLVED — user reports 800K working fine on a
  good fit.** Nothing was changed in the floppy path to fix it; the failures
  below were bad-fit-era artifacts, exactly like the icon garbling, the
  F-lines and the stuck alert. The "headline open defect" is closed. The
  entry below is kept as history — do NOT reopen it without a fresh
  reproduction on a known-good fit.
- ~~★ 08-14e GCR floppy (open, HW)~~ (HISTORY): 800K GCR use → nondeterministic
  F-line bomb OR hard hang; eject attempts crash the Finder. MFM 1.44M
  fully working (envelope fix validated). Offline sweep so far: byte
  demux == MiSTer ✓, bulk-copy content-exact in bench (22/22) ✓.
  Remaining suspects need the FULL-MACHINE sim (copy-under-live-SDRAM
  contention; GCR chain configs MiSTer never tested). NO MORE JTAG —
  user directive; sim/bench only. Also: the Pocket has NO OSD-unload
  announcement path (an OSD unassign tells the guest nothing) — design
  gap, fix with the GCR package.
  ★ NEW LEAD 08-14 (harness machine, PRELIMINARY — needs the guest's
  real poll cadence quantified before blaming RTL): tb_gcr_read (port
  surface re-synced to single-drive swim.v; it had not built since the
  cut) shows POLL-PACING-MARGINAL delivery on TRACK 0 (the 12-sector
  zone): +pollgap=80 → 15/15 address fields CLEAN; +pollgap=40 (the
  blessed value) → 3/15 corrupt, PERIODIC every 5th field; +pollgap=20
  → 4/15. Track 3 clean at 40. Same damage class as the HW F-line/hang
  reports, and an offline dial for the copy-under-SDRAM-contention
  theory (contention shifts the guest's polls toward the unsafe
  region). Repro: /tmp/obj_gcr/Vtb_gcr_read +acclen=40 +pollgap=N
  +ncap=12000 → scripts/gcr_census.py. tb_disk_swap: PASS on this
  machine (full media protocol, post-migration).
- ★ 08-14e video glitch (open, HW): intermittent glitching seen on
  Pocket for the first time — user says same occasional glitch exists
  on MiSTer MacLC. MiSTer FB=SDRAM vs Pocket FB=BRAM ⇒ common cause is
  UPSTREAM shared RTL (V8 engine / CPU-write-vs-scanout arbitration),
  not the framebuffer memory. Need characterization (appearance,
  duration, workload).
- RELEASE: HELD by user (no push/publish). Tooling ready: case fixes
  committed (1f26e32), scripts/release.sh builds a case-asserted
  updater-safe zip (v0.9.0 built locally), gh authenticated. Publish =
  `bash scripts/release.sh --publish` when the user says go.
dist = buildBC (floppy fix + UI cleanup + display modes + color PRAM);
card carries buildAZ until the next trip. Attribution on the next card
boot: color at desktop = seed; floppy mount = envelope fix; menu/display
modes = UI batch; games regressing = suspect the batch, bisect via git.

(2026-08-14b header below: mystery B narrowed to ONE HASH; 256K VRAM SIMM shipped)

Paste into a fresh session: **"Resume docs/RESUME.md — §1-NEXT: fix the
Verilator harness, align it with mac_lc_pocket.sv (10 MB RAM, 256K VRAM,
real Egret), and reproduce the games-disk System 7.1 crash in
simulation."** boot_problems.md ★★★ sections carry deep history; this
file is current state. §2 down is the 08-13 ops crib (still accurate).
The 08-14 daytime QuickDraw/blit theory is DISPROVEN — history in
scratch/2026-08-14-autonomous-session.md and the session transcript.

---

## 0. ★ READ FIRST — AUTONOMY IS UNBLOCKED (buildAR+, 08-14)

The memory-register deception is FIXED: `opt_mem_size` RTL default is now
**1 (10 MB)** (core_top.sv) and interact.json defaultval matches, so a
JTAG fabric push boots HONEST 10 MB — no menu toggle-dance needed. And
**JMNT** (scripts/jmnt.tcl) replays the OSD mount from the PC, so a
pushed fabric needs no physical interaction:
`jmnt.tcl 310 <bytes>` then jboot. Known sizes: maclc.hda=41992192,
Mac68KColorGames_v1.hda=786473472. Full autonomous round:
push → romc_poll (OS auto ROM re-push) → romv (verify) → jmnt → jboot.
★ jboot is EDGE-fired on ANY source change and the script writes a LEVEL:
alternate `jboot.tcl` / `jboot.tcl 0`, or back-to-back same-value calls
are SILENT NO-OPS (cost this session two phantom rounds).

Card launches were never affected. The old toggle-dance is obsolete.

## 0.02 ★★★ 08-15 MORNING-2 (LIVE): DISCRIMINATOR FIRED — DISARM INDICTED; RELEASE RUN ON BI

**The overnight discriminator answered: SYSTEMATIC.** User: BM still
F-lines after the night off — thermal/environment candidate (d) is DEAD.
**User decisions this morning:** ~3/4 boot rate is ACCEPTABLE for the
beta; make the release and document "PRAM doesn't save"; JTAG re-offered
if wanted later (held in reserve — zero-probe rule stands, sim/bench
remain the debug path).

**DISARM INDICTED by triangulation** (desk evidence, this morning):
- git: BI seed == BM seed BYTE-IDENTICAL (diff c54034f..1ee54b7 on
  egret.pram is EMPTY). So BM's only deltas vs base-rate BI = the
  slot-220 disarm RTL (7985134: `pram_save_req_o = 1'b0`) + a NEW FIT.
- Tally pattern: every 0/N build carries the disarm (BJ colour 0/3, BM
  MONO 0/2+N deterministic); every base-rate build lacks it (AZ 3/4,
  BB 4/6, BI 3/4). BM failing at MONO breaks the colour-explains-all
  reading and leaves disarm/fit as the live suspect.
- Card state DEMOTED as suspect: live Settings persist files read from
  the card and decoded — Memory=1 (10 MB default), startup input=Mouse
  default, video=Trinitron; only A/X/R button dropdowns off-default
  (val=0, matching NO current option — stale persists from yesterday's
  16-option menu revisions; input-press path only, cannot touch an
  untouched boot; may leave those buttons dead in keyboard mode until
  reset in the menu). Image fsck was already CLEAN (rb-cli).
- The tie-0 itself looks mechanically safe ⇒ if BI base-rates, suspect
  the disarm's RE-FIT (placement) or an unmodeled consumer of
  pram_save_req_o in apf_blockdev — investigate via bench before any
  re-disarm; do NOT re-ship the disarm without its own tally.

**ACTION TAKEN: card bitstream swapped BM→BI** (one variable; JSONs/
Settings/assets untouched): D: bitstream.rbf_r 08C9A78D… (BM, proves the
morning failures were true-BM bytes) → 3E274A9F… (= scratch/
bisect_buildBI_monoseed.rbf_r, previously verified bit-exact vs its
.sof). User tallying 4+ POWER-OFF boots now.
- BI ≥3/4 → RELEASE = BI bytes: copy the staged rbf_r into dist, commit,
  `bash scripts/release.sh` (zip), publish ONLY on the user's word.
  readme.md ALREADY REWRITTEN for the mono-boot story (PRAM-doesn't-save
  headline, ~1-in-4 boot-retry note, mouse-default + remap menu Controls
  incl. PS/2 Set-2 code table verified vs adb_device.sv: 0x11=Command,
  0x14=Control, Option is extended-only = not sliderable).
- BI 0/N deterministic → bitstream exonerated → card-state round 2:
  park Settings\danifunker.MacLC (one variable), then image content
  (rb-cli get diff vs maclc-worn.hda / pristine swap — ASK first, live
  image carries user saves).

**BI TALLY VERDICT (mid-morning): 1/3 + CONSISTENT VIDEO CORRUPTION —
BI DISQUALIFIED for release.** User: cold boot hang, warm boot hang,
warm boot works, "this build has video corruption now". Matches
yesterday's log line (shared-RTL glitch CONSISTENT on BI in Finder) ⇒
the whole SEED-3 PLACEMENT FAMILY (BG..BM) is the suspect now — boot
marginality + strong glitch expression are family traits, which SOFTENS
the disarm-only indictment (BM's failures may be family, not disarm).
The glitch itself remains shared-RTL (MiSTer shows it) — placement only
modulates expression; post-release investigation via sim/MAME, NOT JTAG
(probes change placement = rewrite the experiment; user offered JTAG,
declined for this class).
**IN FLIGHT: buildBN = BI's exact RTL (disarm retired — restored
pram_save_req_o = pram_save_req_r with retirement comment; landmine #2
live-and-accepted as on every base-rate build) + fitter SEED 5** (fresh
roll; 3 = the bad family; 2 was the AZ/BB era but seeds don't transfer
across netlists — any new value is an honest roll). One variable vs BI.
Gates: hierarchy CLEAN, bench TB PASS; STA/SDRAM-paths/zero-probe on
compile completion → package → card (already in the PC) → 4+ POWER-OFF
boot tally + video-cleanliness check. If BN rolls bad: next seed is
cheap (4, 6, ...); if several seeds all fail the video check, the
glitch has gotten worse in the netlist era and needs the sim hunt
BEFORE release.

**BN first boot: F-LINE. Then two USER CORRECTIONS that re-sort everything:**
1. ★★ FAILURE-CLASS TAXONOMY (user, load-bearing): the historical ~1/4
   base-rate failures were HANGS; **F-lines were NEVER part of normal
   operation** — they appeared only with probed fits, colour-at-depth
   boots, and now BM/BN. So BI's day (hang/hang/works + glitch) = the
   OLD failure mode; BM/BN F-lines = a DIFFERENT, serious class. My
   first-boot-after-insert curse conflated the two classes.
2. ★★ IMAGE CONTENT THEORY promoted (user ordered reseed): hang-class
   crashes kill the guest MID-WRITE and accumulate content damage that
   fsck cannot see (structure-only) — executing damaged content IS an
   F-line. Explains F-lines across unrelated RTLs/seeds + apparent
   determinism (same damaged file read every boot). Supporting find:
   the on-card Mac68KColorGames_v1.hda extract had DRIFTED from
   pristine (2478A8E5… vs DCD02C6C…) — something wrote to it since
   08-14; renamed …-DRIFTED.hda (kept for forensics, do NOT use as a
   reference).
**RESEED DONE (user-ordered): card maclc.hda = pristine from zip**,
SHA1 DCD02C6C… VERIFIED ON CARD after copy. Old live image parked as
maclc-saves-20260815.hda (user saves intact; rb-cli get to recover
files). Card at handoff = BN bitstream + pristine image + untouched
Settings.
**TEST MATRIX for the next boots (BN + pristine):**
- F-lines GONE, hangs ≤~1/4 → content damage was the F-line source; BN
  releasable IF video clean (seed-5 verdict still pending). The
  hang→disk-wear→F-line cycle becomes the documented beta reality
  (readme already advises image backups).
- F-line STILL on first boot with a pristine image → image exonerated
  for good → core/fit/serving class → seed re-roll or HOLD release for
  the sim hunt. (First-boot-after-insert timing effect still unresolved
  — the wait-90s-at-menu discriminator remains queued.)

**Also done:** full .sof chain + exact-bitstream stages backed up to the
card at D:\Backup\maclc-builds (72 files, 167 MB) — the retiring-machine
gap is covered. PENDING USER (unchanged): the 4bpp question (was BI's
second-session F-Line after a MANUAL Monitors 4bpp set, or a spontaneous
4bpp boot?) — still decides the depth-work reading, ask when convenient.

**★★★ FINAL STATE OF THE HUNT + THE PLAN OF RECORD — see
boot_problems.md ★★★ 2026-08-15 (late morning) (the full write-up: failure taxonomy,
eliminations, fit-family finding, image-wear cycle, ladder).** Short
form: AZ-exact booted CLEAN in the exact environment BN F-lined in ⇒
regression confirmed INSIDE the AZ→BN netlist era, fit-expressed
(STA-blind); everything else exonerated by measurement. User directive:
re-assemble the release ONE FEATURE PER BUILD from the BB base (last
F-line-free state with floppy) — the REBUILD LADDER, each rung
hardware-gated (2-3 power-off boots, hang-vs-F-line scored, video
noted). Rung 1 IN FLIGHT at handoff: BB tree + minimal colour graft
seed (1a4844c pram; init-only ⇒ reproduces BB's blessed placement),
worktree ../MacLC_BBcolor, compiling. Rung 2 = +BF mapper (the CDC
suspect; include the never-run input validation). Rung 3 = +startup
input mode. Rung 4 (optional) = +scrub. Never silently re-take: seed 3,
the disarm, bundled builds. Colour-collapse evidence is CONTAMINATED
(measured only on bad-era fits + worn image) — rung 1 is its clean
retest. Card at this moment: AZ bitstream + PRISTINE maclc.hda (user's
old image parked as maclc-saves-20260815.hda; drifted extract kept as
…-DRIFTED.hda — do not trust it).

**★★★ RUNG 1 (buildBO) HW PASS — COLOUR-AT-BOOT WORKS; collapse verdict
DEAD.** User 08-15 midday: "color works, cold boot works fine. warm
boot hung once, but recovered the next boot. MFM floppy worked fine."
So: colour desktop FROM SEED on a clean fit + floppy fix confirmed;
the one warm hang = the known base-rate class. Colour + floppy are IN
the release. THE LADDER IS NOW A GIT BRANCH: **ladder/release-rebuild**
(pushed; worktree ../MacLC_BBcolor) — rung 1 = 17d4aeb (BO), rung 2 =
f85739a (buildBP = + 9f26625's mapper RTL ONLY: core_top +79,
pocket_input +69; dist hunks dropped, seed 2, one variable = the
mapper CDC suspect). BP compiling at handoff. BP's HW check = boots +
colour + INPUT VALIDATION (defaults type A=Return B=Space X=Shift Y=N
L=Esc R=Q Start=Command; one dropdown remap; one custom-code remap).
★ Card-load hygiene for BP: park Settings\danifunker.MacLC\Interact\
_core\interact_persist.json (stale A/X/R=0 persists from dead menu
revisions become LIVE registers on BF+ fabric = dead buttons; not a
machine variable, log it). Startup-input-mode var 130 is INERT on BP
(BG feature, rung 3) — power-on default is keyboard mode this rung.
Rungs left: 3 = +startup-input-mode (unbundle from bcf0302), 4
(optional) = +scrub (5144455 form). buildBO sof/rbf archived; BO =
the fallback release candidate if the ladder stalls.

**★★★ RUNG 2 (buildBP) HW PASS — MAPPER CDC EXONERATED.** User 08-15
afternoon: "boots are working great", and the build booted **System
6.0.8, 7.1 AND 7.5.5** (first 7.5.5 datapoint ever — readme-worthy).
Colour intact. The observed "always keyboard at power-on + setting
does nothing" is the PREDICTED rung-3 gap (var 130 writes into the
void on BP fabric), NOT a bug. Custom-code map untested — blocked by
a UX gap the user found: **sliders display/edit in DECIMAL 0-300**
while all docs were hex, and max 300 makes the extended arrow codes
(363-373) unreachable.
**RUNG 3 (buildBQ) = f124909**: opt_ptr_default @0xF0000050 (write +
readback, mouse default) + own 2FF pair beside the kmap bus (BF idiom
— NOT BG's slimmed kmap carrier) + pocket_input live-follow logic
from bcf0302 verbatim. NOT taken: CDC slim (unneeded — original
passed rung 2), scrub (rung 4), seed 3 (bad family). Extended-key
plumbing verified end-to-end (9-bit bit8 = E0 prefix throughout) —
arrows work on existing fabric, the limit was JSON-side only.
**INPUT UX fixes staged on the ladder branch** (39d832a + fb59258):
slider max 300→388 + adjust_large 2→10 (arrows reachable; SINGLE-AXIS
change vs the Issue-B proven envelope — if the next boot shows "Load
error in interact", revert interact.json and re-trim); readme codes
table now hex+DECIMAL incl. ready-made arrows (Up 373 Down 370 Left
363 Right 372); root JSONs synced into the worktree so package.sh
cannot clobber (BB-era gitignore replaced by main's; dist JSONs
force-tracked on the branch). Next card trip = BQ bitstream +
interact.json + readme checks: mouse at power-on, menu change
live-follows until first Select, custom-code with decimal (Q=21),
one arrow map. Then the rung-4 (scrub) decision + release assembly
FROM THE LADDER BRANCH (it now carries bitstream lineage, card JSONs,
and readme — self-contained).

## 0.05 ★★★ 08-15 EVENING: BOTH ISSUES CRACKED — READ THIS, THEN 0.1's history

**ISSUE B (interact menu) RESOLVED — deep-envelope method.** Three surgical
theories failed on HW (final newline; combined interact+data cap — ROM slot
parameters 1->0, kept, harmless; defaultval index-vs-value semantics — kept,
string-hex form). What worked: a file with EVERY measurable axis at or under
a hardware-proven maximum (our loading 4-entry file + the on-card
Mazamars312 Amiga files as the proof corpus): 15 vars (=Amiga), 5-option
lists (proven 8), 6219 B (proven 6271/6636), max line 33, string-hex list
defaultvals, string slider defaultvals, slider max 300. LOADS + mouse-mode
default CONFIRMED on HW. The killer axis was never isolated (one of: 16-opt
lists / 16th var / 22KB size / slider max 511 / numeric slider defaultval) —
bisect-up ladder = restore one axis at a time from interact_full16.json
(kept at repo root). Reference bytes: scratch/settings-forensics-2026-08-15/
(both Amiga cores' dists + our Settings tree; interact_persist.json proved
benign). Y/Start custom sliders + NMI still sacrificed; one menu slot free.

**ISSUE A (boot instability) ROOT-CAUSED to BOOT-AT-DEPTH; ship = mono boot.**
The 08-15 tally matrix (per-boot Finder-load success, ~30 user boots):
  AZ 3/4 · BB 4/6 · BI(=BH RTL+mono seed) 3/4   <- base rate ~75-90%
  BH 0/N · BJ(=BH+save-req disarm, colour) 0/3 · BK(=import seed+3-byte
  record graft 83/AA/0A, colour CONFIRMED on screen) 0/3  <- collapse
Triangulation: fabric chain BA..BH exonerated (BI base-rate on newest RTL);
the five non-video seed bytes exonerated (BK==BJ); the slot-220 disarm is
not the colour cure (BJ==BH). ★ THE REFRAME (user fact): every colour
session ever — incl. the AZ marathon — was booted 1bpp then set to 256
colours MANUALLY in Monitors. 8bpp RUNTIME is proven solid for hours;
BOOTING at 8bpp (seed accepted -> whole startup+Finder-build at depth)
collapses ~100% with F-Line/hang at the desktop-build phase. BE-morning
"colour validated" = small-sample luck; there was never a stable
boot-at-depth era. Failure class (F-Line = executing garbage) says
corrupted READS more than video-write contention; vram_bram is structurally
innocent (true dual-port, no arbitration); prime suspects = the CPU-side
VRAM-shadow READ path through pocket_sdram (8x RMW traffic at 8bpp;
sim_ram can't see it — sim runC boots 8bpp clean) and the colour boot's
different disk-read pattern (icl8 resources; Mystery-B lineage).
  Diagnostic staged, not run: buildBL = 4bpp graft seed (commit 952c5ad;
  0x58=82) — depth-proportional vs colour-path-binary discriminator.
  ALSO: shared-RTL video glitch (MiSTer too) was CONSISTENT on BI in
  Finder — same placement family for BI/BJ/BK; log which builds show it.
  First-boot-after-card-insert failed 3/4 times on base builds (weak
  long-off-decay signal; unresolved).

**Fixes landed on the way (all in the tree):** buildBH launch-scrub gate
(504us post-lock delay + private scrub_pend flag — the BG scrub was VOID in
the init-ladder window AND its ioctl_wait use could false-ack a producer;
also fixed BG's dropped 8th word). buildBJ slot-220 save-req DISARM
(landmine #2 made live: every guest PRAM write burst fired a doomed save at
a nonexistent slot and wedged the SCSI-serving sequencer ~450ms+ — fires
every session incl. manual Monitors sets). Dist JSONs byte-clean + ROM slot
parameters:0.

**SHIP = buildBM** (compiling at handoff): current RTL (scrub gate + disarm)
+ import-era mono seed = the battle-tested 1bpp boot; users set colours in
Monitors per session (or drop a depth-setting utility into Startup Items on
the games disk — runs post-Finder, past the fragile window). Tally + soak
before dist/release.

**08-15 SESSION CLOSE.** User ended testing after ~30 boots (fatigue — the
tally protocol is heavy; respect it next session). LAST OBSERVATION, logged
verbatim: on the BI card's first boot of its second session, "at 4bpp,
finder loaded but after everything loaded up I got a bad F-line". OPEN
QUESTION: manually-set 4bpp (user had been setting depths in Monitors all
day) or a SPONTANEOUS 4bpp boot? BI's staged rbf_r re-verified bit-exact
against its archived .sof (quartus_cpf regen), and the machine hardwires
v8_monitor_id=4'h2 + 256K ⇒ the import record (a6/06) should be REJECTED
to 1bpp per the MAME-verified model — a spontaneous 4bpp boot would mean
the REAL fabric's acceptance path diverges from that model (and would
retroactively make BI's 3/4 tally a 4bpp datapoint = depth-response
evidence). Ask the user before trusting either reading. F-Line-after-full-
load at 4bpp leans toward collapse-follows-colour-path (not pure 8bpp
bandwidth) if the boot was genuinely 4bpp-from-seed.
CARD AT CLOSE = full dist = buildBM (all 10 files hash-verified). BM is
GATED but UNTALLIED — next session's first HW act: BM stability tally
(4+ boots) + the still-pending mapper INPUT tests (defaults type / one
dropdown remap / one custom-code remap; mouse-mode already confirmed).
PENDING USER ANSWER: the 4bpp question above.
★ 08-15 LATE: BM's first two boots both F-Lined ("same exact error"
twice — DETERMINISTIC, a different signature from the morning's varied
probabilistic failures). Disk-structure damage RULED OUT on the spot:
rb-cli fsck --checkonly on the card's live maclc.hda = CLEAN (2702
files/422 dirs, exit 0; APM + bless + System Folder tree all intact).
[rb-cli = "Rusty Backup", C:\Users\owner\AppData\Local\Programs\
Rusty Backup\bin\rb-cli.exe — the user's tool of choice for image
inspection; fsck/ls/get/cp verbs, APM-aware, partition @N addressing.
scripts/hfs_check.py can NOT walk APM images (MDB sig 'PM' bail) —
prefer rb-cli.] Tonight's 3-failure cluster (BI-4bpp F-Line + BM x2)
is UNEXPLAINED; candidates: (a) content-level damage inside
structurally-clean files (Desktop DB / System resource fork — diff
vs maclc-worn.hda via rb-cli get would test), (b) session-persistent
state (Settings/interact_persist now carries the day's remap tests),
(c) the base bug presenting differently, (d) long-session environment
(thermals — machine ran/crash-looped for hours). DISCRIMINATOR queued:
next session's FIRST cold boot of BM after a night off — boots fine =>
environmental; same F-Line => systematic, then content-diff the image.

**PRAM PERSISTENCE (user wants it): feasible, GATED on boot-at-depth.**
Plumbing exists: apf_blockdev's MiSTer-derived PRAM FSM (pram_rd_todo=0
"was 1: load once at power-up" — re-enable), re-arm pram_save_req_r (one
line in mac_lc_pocket.sv, comment marks it), declare slot 220 + ship a
256-byte pram file in dist. BLOCKED because persisted depth makes every
boot a colour boot = today's collapse. Sequence: BM ship -> crack
boot-at-depth (BL first) -> persistence + a Reset PRAM menu action (menu
has one free slot) + save-flow bench.

## 0.1 ★★ 08-15 MORNING: THE TWO OPEN ISSUES (history; superseded by 0.05)

**ISSUE A — BOOT INSTABILITY DURING FINDER LOAD (the real problem).**
Random error class per boot (Unimplemented Trap / bad F-Line / blank
never-filling dialog) — user: the CLASS is noise, the instability is the
signal, and "many of yesterday's builds were not having this error."
Facts: buildAZ was marathon-stable (hours of games). buildBE validated
colour in the morning, then the SAME BYTES went boot-inconsistent in the
evening on BOTH worn and pristine images (image/battery/heat excluded).
buildBG (scrub+mapper+seed3) shows traps at Finder load. User
observation: FULL POWER-OFF boots behave better than core RELAUNCHES.
Hypotheses, ranked:
 1. WARM-PATH LEAK (0.0/08-14h): SDRAM survives relaunch; ROM warm-boots
    on stale RAM. buildBG's scrub may NOT BE LANDING: it fires at config,
    inside pocket_sdram's init-ladder window where we/oe are IGNORED but
    the dio retire handshake still completes = writes silently VOID
    (mac_lc_pocket.sv ~1770 documents the window; the ROM loader survives
    it only because the OS stream arrives ms later). FIX CANDIDATE: gate
    scrub start on memory-live (delay until the init ladder completes —
    e.g. run scrub AFTER rom download starts/or a ~200us post-lock delay)
    — then relaunch boots become the test.
 2. Fit/seed marginality — ONLY IF power-off boots also fail (the
    pending discriminator the user hasn't answered: does buildBG trap on
    power-cycle boots too, or only relaunches?).
 3. A BC→BE-era regression (PRAM seeder etc.) — bisect via archived
    builds: every .sof in scratch/builds; exact shipped bitstreams
    recoverable from git dist commits (buildAZ staged:
    scratch/bitstream_buildAZ_exact.rbf_r, sha d3c62ce1…).
Note: sim CANNOT see the init-window void (sim.v uses sim_ram, not
pocket_sdram) — this one is desk-analysis + hardware A/B. Soft reboot
(Special→Restart broken) is the same warm-path family.

**ISSUE B — INTERACT/MAPPER MENU: ROOT CAUSE FOUND, AWAITING THE BOOT.**
The evening's "Load error in 'interact' general error" was a MISSING
FINAL NEWLINE: Windows Python json.dump wrote CRLF files with no
trailing newline; package.sh's old `sed 's/$/\r/'` shipped a final lone
`}\r`, which the parser rejects. Proven by controlled test (same buildBG
fabric: original JSON loads, mapper JSON fails) + byte forensics (every
loading file ends 7d0d0a). FIXED: package.sh JSON conversion now
byte-deterministic; all repo JSONs normalized. dist ships the FULL
16-var mapper menu byte-clean. PENDING: copy dist interact.json to the
card (buildBG fabric is already on it), then: menu renders 16 entries →
defaults type, R=Q, one dropdown remap, one custom-code remap, mouse
mode at power-on. buildBF exonerated on both charges retroactively.

Operational: card loop = copy/cmp to D:\Cores\danifunker.MacLC\, eject
via PowerShell Shell.Application; gates = STA 0-neg-slack +
check_sdram_paths + zero sld/altsource + verilator/modelsim_bench/run.sh;
archive every .sof; NO JTAG (retired). Release v0.9.0 zip built + HELD
(`bash scripts/release.sh --publish` when the user says go; gh authed).
This Windows machine is retiring — keep everything in-repo.

## 0.5 ★ 08-14c: AUTO-MOUNT FIXED (buildAY); MYSTERY B IS NOW A BUS ERROR

- **Launch auto-mount SHIPPED + HW-VALIDATED** (buildAY = 69f48c9, on card
  AND the card-loaded fabric): core_top scans the framework data slot
  table once after dataslot_allcomplete and synthesizes mounts for slots
  310/311/320/210 with nonzero size (openFPGA docs: 0x008A is sent only
  for user re-loads; a deferload slot's launch assignment is table-only).
  Cold card boot auto-boots maclc.hda with ZERO OSD touches (user-
  confirmed). AMNT probe in read_bdst.tcl is the witness (HW read:
  fired=1 armed=1 state=7). JTAG pushes still need JMNT — reconfig wipes
  the table. Bench: scratch/amnt_bench (ModelSim; the block extracted
  verbatim, driven through the real core_bridge_cmd + mf_datatable +
  apf_blockdev; 15 checks incl. one-shot + OSD-pick regression).
- **Mystery B changed class**: with b389e16 (scsi_dpram prefetch fix) the
  games-disk death is now a BUS ERROR "after the first extension loads" —
  at the SAME dlv=+217 as the old II. IIOP did NOT fire at the death
  (vector 2 dispatches via $8, not $10): the bomb text and the silent
  IIOP independently confirm the class change. User: the Verilator run
  (other machine) did not show this — consistent with §1-NEXT's
  "sim boots clean => suspect Pocket-only glue/serving timing".
- **★ The machine SELF-RESTARTS after the bomb** (SysError re-fire
  escalation) — corpses are PERISHABLE. The restart's POST RAM test
  sweeps RAM with ascending AAAA fills (writer PC A4686E; read/XOR loop
  at A468D2-D8, fetches 241A/B592), so WWSP/WW40 "AAAA" evidence in any
  post-restart corpse is POST, not the killer — and IIOP fires
  SPURIOUSLY on POST's data read of $10. Old frozen-at-II captures stay
  valid (IIOP freezes on first trigger, which was the true death).
- Bus-error capture protocol: freeze BEFORE the restart. FRZE's compare
  is a raw 8-bit >= (landmine #3) — from a high count: release, poll
  until the counter wraps, then arm ABSOLUTE (scratch/buserr/roundA.sh
  automates this). Round A freezes late-boot to read the System's
  vector-2 handler from RAM ($8); Round B stages `frze trig +217` +
  `pcrb arm 0 <handler>` so the ring freezes at handler entry = the 64
  pre-fault PCs, then manual `frze on` preserves the format-$A/B bus
  fault frame (fault address at frame+$10).

## 1-NEXT ★ USER DIRECTIVE: REPRODUCE MYSTERY B IN VERILATOR

Goal: make the games-disk System 7.1 crash happen inside the Verilator
harness, where visibility is unlimited (per-instruction cpu_trace.log,
$display probes on anything, FST waves, MAME PC-stream diffing). The
next agent figures out the alignment details; this section is everything
known that they need.

### Why this is feasible
- The crash lands ~15-20 GUEST-seconds in ≈ 900-1200 video frames at the
  Pocket's 512x384 timing — same order as the routine 730-frame
  screenshot runs. Reasonable wall-clock.
- It is deterministic and invariant across cold/warm boot, card/JTAG,
  2/10 MB, 512K/256K VRAM — a software-visible divergence a full-trace
  sim should catch red-handed.
- MAME 0.264 boots the same image+ROM clean → docs/mame_compare.md's
  PC-stream divergence diff (sim trace vs MAME maincpu trace, same disk,
  same ROM) can mechanically find the FIRST divergent instruction.

### Harness status (verilator/) — BROKEN since 2026-08-09, fix first
- sim.v still references dataController ports deleted by the CD/Toolbox
  + second-floppy cuts: cd_snd_*, dbg_cda*, cdtb_*, cd_io_*, tb_lba,
  dskReadAddrExt (~11 refs). Delete/tie exactly as mac_lc_pocket.sv does
  (it is the reference consumer of dataController_top).
- Some later port syncs WERE kept: cd_* tie-offs (08-13) and buildAW's
  addrController `vram_force_512k` is already tied 0 (= 256K SIMM) in
  sim.v. The 256K alias + 512-B stride live in SHARED RTL — nothing to
  port there.
- ★ sim.v is its OWN top (`module emu`) with its OWN CPU instantiation
  and bus glue (VPA/DTACK/BERR/overlay) — NOT mac_lc_pocket.sv.
  docs/verilator_differences.md is the tracked-differences checklist:
  read it BEFORE editing, update it after. CPU-glue divergence between
  the two tops is exactly the class of bug that could make the sim NOT
  reproduce — aligning them IS the job (user: "make sure it matches
  what we have on the main maclc top, including the 10 MB RAM and
  such").
- Verilator tolerates multiple always-drivers; Quartus does not — any
  fix flowing BACK to FPGA must stay single-driver (CLAUDE.md).

### Config the sim must present (match the crashing hardware)
- **10 MB RAM**: the machine samples the memory config at reset;
  mac_lc_pocket gets cfg from core_top (opt_mem_size default 1 = 10 MB).
  Find sim.v's hardwired config and set 10 MB (SIMM 8 MB + motherboard
  2 MB). Fallback: the crash also fires at 2 MB — matching EITHER
  crashing config exactly is acceptable, but match one.
- **256K VRAM**: already default (vram_force_512k=0). Fast sanity: once
  booted, guest word $106 (ScreenRow) must read $0200 = 512.
- **Real HC05 Egret** (unconditional since 08-09). Do NOT enable
  EGRET_BEHAVIORAL for this hunt — VIA/Egret timing is part of the
  environment under test.
- **ROM**: releases/boot0.rom (SHA1 6bef5853ae736f3f06c2b4e79772f65910c3b7d4
  = MAME's verified 350eacf0.rom).
- **Disk**: a copy of Mac68KColorGames_v1.hda with SHA1
  dcd02c6c31335b87397af2c1944ebbea70cf4e26 (786,473,472 bytes).
  ★ NOT ON THIS PC — get it from the SD card (Assets/maclc/common/,
  card currently in the Pocket; the zip beside it holds the same file)
  or from the MAME box (its copy was restored from that zip). VERIFY the
  SHA1 before burning hours of simulation. (C:/repos/MacAtrium-7.1.hda
  is a DIFFERENT, older 256 MB image — not the reproducer; also
  Apple-partitioned, which scripts/hfs_check.py cannot walk yet.)
- How sim.v mounts a SCSI HD: it has its own dio/download plumbing
  (sim_main.cpp, `--help`). Watch image-size plumbing at 750 MB.

### Instrumentation once it boots (the whole point)
- $display on completed writes to $3FF700-$3FF7BF and $400E00-$400EFF
  with the current fetch PC = buildAX's WWSP with unlimited depth, one
  line of sim code.
- Trap the death directly: on fetch at $400E6C (or the vector-4 read of
  $10), dump A7, the $C000-$C17B patch frame, the BootGlobals band, and
  stop with a trace window around it.
- cpu_trace.log across the fatal window vs MAME maincpu trace of the
  same boot → first-divergence diff (docs/mame_compare.md; MAME PCs are
  8-digit 00Axxxxx; MAME's debugger defaults to the Egret HC05 — switch
  to the 68020).
- ★ If the sim boots the games disk CLEAN, that is ALSO decisive: the
  divergence then lives in Pocket-only glue (core_top/mac_lc_pocket/
  pocket_sdram/apf_blockdev serving timing), not shared RTL — diff
  sim.v's glue vs mac_lc_pocket.sv and suspect the ms-scale APF serving
  latencies the sim doesn't model.

### The fault signature to hunt (three identical HW captures + cold-card)
- ~15-20 s in: System 7.1 late boot (post-"Welcome", pre-Finder; GrayRgn
  unbuilt, CurApName unset), DSErrCode ($AF0) = 3.
- The Gestalt-family RAM patch $C000-$C17B (8-byte {selector,proc}
  records off ExpandMem+$5C; 'mach' selector visible in the fatal stack
  band) exits via its clean LINK/UNLK epilogue; the RTS at $C17A pops
  **$400E6C = the boot-blocks image base** ('LK' $4C4B, then BRA $6000
  0086, bbVersion $4418, bbSysName "\x06System") → executes the
  signature → II vector 4.
- The machine's last write before the fatal fetches: **AAAA → $3FF76E**
  (live stack). BootGlobals fields $400E60-66 churn AAAA/3400 values.
- CurStackBase = $3FF7BE; BootGlobals ptr table $3FF7AE-B9 =
  {$400BFC, $400E6C, $3FFBBE}; boot-handoff CODE executes at $3FF7BE+
  (move.l a3,-(sp); _ReleaseResource; movea.l ROMBase,a0; ...).
- The fault RE-FIRES periodically during the SysError wait (parked at
  ROM A02A38-3E polling $172) — in sim, the FIRST occurrence is the one
  with the clean trace.

## 1B. MYSTERY B DOSSIER — what is eliminated (all measured)

MAME 0.264 maclc (verified romset; our boot0.rom byte-identical) boots
the SAME image (SHA1-verified both ends) to desktop at 10 MB in BOTH
VRAM worlds. The card's copy hashes dcd02c6c… exactly, mtime untouched
since build — disk exonerated. Eliminated by direct measurement: the
image, the ROM, memory size (2/10 MB), VRAM size (512K/256K), the JTAG
boot path (cold card boot crashes identically), machine-identity bits
(VIA1 PA $D5 = MAME's $D4|config), analog RAM marginality
(deterministic, same PC 5+ rounds), TG68K decode ('LK' is genuinely
illegal; kernel byte-identical to MiSTer). Remaining suspects: Pocket
glue / timing-scale effects the shared RTL never sees (APF ms-scale
serving, SDRAM controller behavior under the 7.1 boot's access pattern)
— or a shared-RTL bug both FPGA tops exercise but MAME's model doesn't.

**A (maclc.hda +59):** still NOT re-run at true 10 MB. Bind maclc.hda to
slot 310 (card boot auto-mounts since buildAY; after a JTAG push use
jmnt), then push+jmnt(41992192)+jboot.

### Parallel hardware thread (PAUSED mid-compile — resume any time)
buildAX (WWSP writer-PC watcher, committed 83472dd) was COMPILING at
pivot time — check src/fpga/output_files, STA-gate all corners, archive
as scratch/builds/2026-08-14-buildAX-wwsp.sof. Round: push → romc_poll →
romv → jmnt 310 786473472 → jboot (EDGE-fired! alternate `jboot.tcl` /
`jboot.tcl 0`) → await II (~90 s, dlv +217) → scripts/wwsp.tcl +
iiop.tcl. Newest WWSP slots = the II exception-frame pushes (pinpoints
A7-at-fault); behind them, the AAAA writer WITH ITS PC. The Pocket sits
FROZEN on a buildAW card-boot corpse (`frze off` before any new round;
card now carries buildAW).

**The fault, fully decoded** (three identical captures incl. a cold card
boot): System 7.1's late boot handoff (code executing in the BootGlobals
area at CurStackBase $3FF7BE; 'mach' Gestalt selector in the fatal stack
band) calls into a Gestalt-family RAM patch ($C000-$C17B, 8-byte
{selector,proc} records off ExpandMem+$5C). The patch's clean
LINK/UNLK/RTS epilogue at $C172-$C17A returns THROUGH a return-slot that
holds $400E6C = the BOOT-BLOCKS IMAGE base ('LK' $4C4B, BRA $6000 0086,
bbVersion $4418, bbSysName "\x06System" — every field textbook) →
executes the signature → II vector 4 → DSErrCode 3. IIOP's last-write
capture: AAAA → $3FF76E (live stack) immediately before the fatal
fetches; WW40 sees AAAA/3400 churn in the BootGlobals fields $400E60-66.
So either the frame/return slot was overwritten mid-call (buildAX's
target), or the code/pointers loaded FROM DISK were corrupt (the hash's
target). The fault also RE-FIRES periodically during the SysError wait,
which is why PCRB match-rings on $400E6A/$400E6C freeze full of the
A02A38-3E wait loop — the delivery trigger stages at quiescence (the
crash itself), so match-rings can only ever catch the post-death
re-execution, not the first death. Dead theories with their disproofs:
wild-QuickDraw-blit (cold-boot POST-fill tracer shows no blit ever
touched $400E00-53), unresolved-jump-table (same), 16bpp/'scrn' geometry
(crash identical at ScreenRow=512), machine identity (VIA1 PA $D5 =
MAME's $D4|config bit).

**A (maclc.hda +59):** still NOT re-run at true 10 MB. Bind maclc.hda to
slot 310 (fresh card boot auto-mounts since buildAY — fixed 08-14c;
after a JTAG push use jmnt), then push+jmnt(41992192)+jboot.

## 1.5 SHIPPED THIS SESSION (buildAW, committed; dist/card = buildAV)

- **256K VRAM SIMM presentation** (4f81048 + this session): the LC ROM
  sizes VRAM by wrap test ('512K'@+$7FFFC then '256K'@+$3FFFC, readback —
  ROM $A04BC38, observed live in MAME at PC $A4BC4C/58). We now alias the
  CPU-side VRAM window mod 256K (A18 of a 256K SIMM is unconnected) and
  switch the CPU-side line map 1024→512-byte stride to match the 256K
  layout the driver then builds (ScreenRow=512 CONFIRMED on HW 3/3 and in
  MAME). Honest hardware: a 256K LC's own ROM refuses >8bpp, so the
  16bpp mode this fork cut can never be offered. **V256 JTAG lever**
  (scripts/v256.tcl, source_clk=clk_sys like FRZE — the clk_74a-sourced
  2-bit levers are the broken ones) restores 512K for A/B, no rebuild.
  buildAW sof archived (scratch/builds/2026-08-14-buildAW-vram256k.sof),
  STA all corners positive, ON THE FABRIC NOW. The card still carries
  buildAV — package buildAW for the next card trip.
- **verilator/mame/vram_256k.lua** — the same experiment as a MAME Lua
  write-alias tap, VALIDATED on MAME 0.264 (three API gotchas documented
  in its header; the display shears in alias mode because MAME's
  screen_update hardcodes the 1024 stride — judge by ScreenRow, not
  pixels). scratch/mame_agent_prompt.md = the full remote-agent protocol.
- Corpse-forensics craft: cold-boot POST fill (B6DB…) = a virgin-RAM
  write tracer; ramv bulk sweeps SMEAR (GDevice tail, trap table both
  faked corruption — single-word majority-of-3 for anything load-bearing;
  ramv_dump nw arg is DECIMAL).
- MAME-side caveat for future runs: attach disks as CHD (raw .hda/.hdv
  attaches READ-WRITE and the guest modifies the file; the agent's copy
  was restored from zip after SHA drift).

Full detail: scratch/2026-08-14-autonomous-session.md + this session's
transcript (mame_agent_prompt.md results in the chat).

## 2. WHAT SHIPPED 08-13 (all committed; dist/card = buildAV as of 08-14, fabric = buildAW)

- **Write path FIXED, two root causes, on-card proof**: C_FILL off-by-one
  (apf_blockdev sampled sd_buff_din a cycle early) + bridge readback lag
  (OS pairs bulk-read responses with the PREVIOUS transaction; serve
  wrbuf[widx-1] compensates). Proof: 3,846 corrupt sectors diffed on the
  card, MDB fingerprint matched the composed transform; maclc.hda
  RESTORED from the user's zip and re-verified. boot_problems ★★★.
- **ISO CD-ROM at SCSI ID 3** (buildAB, in dist): scsi.v CDROM target +
  rtl/cd_toc_stub.sv (single-data-track TOC, cd_audio's no-blob fallback
  byte-for-byte). Slot 320, maclc.iso auto-mounts; the 6.0.8 image
  already carries the Apple CD-ROM extension. CDA1/CDPH probes.
  HW status: answers the ROM scan politely every round; disc mount
  untested (needs a maclc.iso on card).
- **16 KB read-ahead confirmed** already present (RING_LOG=5 per disk).
- **Red herrings buried with measurements**: every SCSI data face
  byte-perfect (incl. SDCP full-burst 512/512); the Egret PRAM-write
  transaction healthy mid-flight (EGS1/EGS3: HC05 caught mid-bit in its
  receive loop); "PRAM-poisoning" was BootMask/eject semantics — the ROM
  boot-search giving up on purpose; scsi_irq tie-off CORRECT per MAME;
  repeat OSD mounts are invisible to the guest (only 0→1 registers).
- **Seed 2** (seed-7 buildAL had a -33 ps clk_sys fast-hold; qsf tail
  also repaired — a newline-less stray SEED 7 line was eating appends).

## 3. THE INSTRUMENT SUITE (buildAV = pushed fabric; scratch/builds has all A→AV)

| lever/probe | what | script |
|---|---|---|
| JMNT | replay a dataslot_update mount from the PC (slot,bytes) — no OSD | `jmnt.tcl <slot> <bytes>` |
| IIOP | last 4 fetches {pc,data} + 2 any-cycles, frozen at the vector-4 read of $10 (kernel-view data, full-32b addr); WW40 = last 4 writes to $400E6x; IIO2 = PDS-probe witness + ring top-bytes | `iiop.tcl` / `iiop.tcl rearm <v>` |
| JMEM | ⚠ memory-size override — WRITES but does NOT APPLY (§4.0); readback works | `jmem.tcl 2\|10\|off` |
| FRZE | manual freeze / auto at ABSOLUTE dlv count / `trig` = fire-only (stages PCRB) | `frze.tcl` on/off/arm/trig/cycle |
| PCRB/PCRS | 64-PC ring; triggers: delivery (via trig) or **PC-match** (source[23:0], two-stage: the delivery trigger stages it); K countdown ×16 writes; **spin-filtered** (A07840-7F, A14870-83 suppressed → the ring spans the whole death corridor as a call trail) | `pcrb.tcl arm <K> [matchPC]` / dump |
| EGS1/EGS2/EGS3 | Egret SR+handshake snapshot at freeze / windowed CB1-BYTEACK-TIP counters / HC05 PC at freeze | `read_bdst.tcl` |
| PSN1/PSN2 | SCSI bus + per-target snapshot at freeze | same |
| SDCP | full last pseudo-DMA burst (512 beats) | `sdcp.tcl` + `scratch/evidence/burst_id.py` |
| ROMV v4 | arbitrary-SDRAM sums/peeks/dumps (machine resets per scan unless FRZE holds) | `ramv_sum/ramv_dump/ramv_sweep/romv.tcl` |
| BDST/BDW0/BDLB/BDWR/BDWW/CDA1/CDPH/SDW0/SDCT/SCS1/SCS2 | serving/write/CD/burst deck | `read_bdst.tcl` |

**Canonical capture** (buildAP+ semantics): `frze off` → `frze trig +59`
→ `pcrb arm <K> [matchPC]` → `jboot` → poll `pcrb` frozen → `read_bdst`
+ `pcrb` dump. The delivery trigger STAGES the PC-match when both armed
(the first match fetch after the round's last delivery fires). Byte-mode
PDMA duplicates each byte on both bus halves (5050 4D4D for 'PM' is
CORRECT, not corruption). ROM PC → disasm line = 40800000 + (pc & 7FFFF)
in docs/MacLC_ROM_disasm.txt; HC05 PCs → rtl/egret/egret_rom_disasm.md.

**Illegal-instruction trace plan (mystery B), zero new builds:**
1. Boot the games disk at true 10 MB, let the dialog appear, `frze on`
   (manual freeze — RAM and vectors intact).
2. `ramv_dump 8 2` → RAM words 8-9 = the LONG at byte address $10 = the
   Illegal Instruction vector target (a RAM address once the System owns
   vectors).
3. `frze off`; re-run the round with `pcrb arm 0 <that PC>` staged
   (`frze trig +N`, N picked from BDLB near the round's end — games-disk
   rounds deliver far more than 59) → the ring freezes ON the handler
   entry holding the 64 spin-filtered PCs BEFORE the fault = the faulting
   code and its callers. Cross-check against docs/tg68kmissing.md before
   suspecting the image.

## 4. LANDMINES / CLEANUPS (each small; none block the mysteries)

1. ~~opt_mem_size JTAG-push reset~~ **FIXED 08-14** (§0): RTL default → 1
   (10 MB), interact.json defaultval → 1. Pushed fabrics boot honest.
0. **★ NEW 2-bit-source levers don't APPLY downstream** (JMEM memory
   override, IIOP machine-freeze). Source WRITE works (JMEM readback:
   enable/value both settable) but the consuming logic ignores it —
   `jmem 2`+jboot still boots 10 MB; `iiop rearm 3` never holds reset
   though iiop_frozen=1 & src[1]=1. Single-bit sources (jboot, iiop
   rearm-bit0) and the 11-bit FRZE all work. Leading theory: the raw
   altsource_probe `source` outputs feed a DIFFERENT clock domain
   UNSYNCHRONIZED (FRZE's ext_freeze is synced in core_top first). Fix:
   2-FF sync jmem_src/iiop_src into their consuming domain. Until then:
   NO JMEM 2 MB control round and NO machine-freeze — use the
   SysError-wait freeze (the bomb dialog parks in a WaitMouseButton loop
   at ROM A02A3x WITHOUT unwinding the fault frame; `frze on` there =
   stable fault-time corpse).
2. **pram_save_req fires at a NONEXISTENT slot 220** on every guest PRAM
   write (dirty-tracking → apf_blockdev save → OS error/timeout wedges
   the shared sequencer ~450 ms, stalling SCSI serving exactly when the
   System writes PRAM). Disarm the save-req until PRAM persistence
   returns, or re-add slot 220 to data.json and re-arm the path.
3. FRZE/BDLB delivery counters are 8-bit and wrap — mind thresholds
   (frze.tcl's +K handles it; absolute arms near 255 do not).
4. tb_blockdev.v needs a write-path test + the post-buildAA endian
   expectation fix (bench stale on both).
5. CD transient-wedge theory: UNCONVICTED (CDPH read idle at every
   sample). Keep CDPH in view during any flaky-round session.
6. verilator/sim.v remains broken (pre-existing); dataController port
   additions were kept in sync (cd_* tied off, dbg outputs omitted).

## 5. WORKING AGREEMENTS (unchanged, plus today's lesson)

One behavioral variable per SHIPPED build (instrument builds may stack
passive probes); archive every .sof (scratch/builds/ has the full A→AQ
chain); controls before conclusions — this session's four exonerations
(SCSI data, Egret handshake, PRAM-poisoning, IRQ tie-off) each died to a
measurement, not an argument; the screen is the final oracle and the
user narrates it. MiSTer @ 5a75f9b remains ground truth for Mac
behavior — but the Pocket's ms-scale serving and JTAG-push workflow
create conditions MiSTer never sees: async windows that become real,
and fabric registers that silently reset behind a menu that says
otherwise. When a setting matters, verify it AT THE FABRIC.
