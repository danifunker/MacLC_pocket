# What happened with the builds — and how we proceed

Written 2026-08-17, the morning after. This is the plain-language record
of the 08-15 → 08-17 instability arc: what failed, what was proven, what
remains unknown, and the concrete plan. RESUME.md carries running state;
this document is the explanation.

## TL;DR

- **v1.0.1 (released) ships buildBP's exact archived bytes** — the one
  build that survived every test. It is safe regardless of the mystery,
  because it is not a new compile.
- **Every build compiled after BP is broken the same way**: screen
  corruption once the Finder loads, then F-line crashes. Deterministic
  per build, on every disk, every card state, every test.
- We ruled out (with measurements): the disk images, the SD card, the
  Settings, the Pocket, the build machine, and every specific RTL
  change we made. No single code change separates good from bad.
- The surviving explanation is **placement (fit) marginality**: each
  compile places identical logic differently, and some placements have
  a weak path that only heavy OS-era load trips. Three attempts to fix
  this class failed, so it remains a hypothesis — the best one left,
  not a proven one.
- The plan: re-land the alert fix as one small change on the BP base,
  then run one designed experiment that can *prove or kill* the
  placement theory. Details at the bottom.

## The cast of builds

| build | contents (delta from previous) | hardware verdict |
|-------|-------------------------------|------------------|
| BO    | BB base + colour-boot PRAM seed | good (colour, floppy) |
| **BP** | + per-button keyboard mapper | **good — the survivor; both card slots today; = v1.0.1** |
| BQ    | + "Startup input mode" (rung 3) | icons garbled |
| BR    | BQ re-fit, different seed | same garbling |
| BS    | + partial MiSTer "anchor" | good for ~2 days (icons clean, released as v1.0.0), F-line rate in the field, then failed the clean-state retest |
| BU    | + completed anchor + ASC sound pin | F-line + corruption, every boot |
| BW    | + the CPU↔SDRAM timing fix | same failures — **but the alert-sound fix worked** |
| BX    | − rung 3 (startup mode removed) | same failures |

Read the last column top to bottom and the pattern is stark: **BP is
the boundary.** Nothing compiled after it has been healthy, regardless
of whether the change was a feature, a fix, a removal, or a constraint.

## What we ruled out, and how

Each of these was a live theory at some point. Each died to a
measurement, not an argument:

- **Disk image content / corruption.** Failures reproduced on a
  SHA-verified pristine image, twice reseeded, and finally on your own
  fresh minimal disk with no games at all. (Image *wear* is still real
  — crashes do damage disks over time — but it was a consequence and
  amplifier, not the cause.)
- **The SD card.** The prev-slot core (BP) boots perfectly from the
  same card, same disk, same session in which the new builds fail.
  A dying card cannot spare one folder.
- **The Settings / Analogue OS state.** Parked and rebuilt cleanly;
  failures unchanged. (Discovery along the way: a corrupted-build
  session once caused the OS to persist garbage menu values — bad
  builds can poison Settings. Parking them is now standard recovery.)
- **The Pocket itself / firmware.** Same hardware boots BP flawlessly.
- **The build machine and toolchain.** BP's exact source tree was
  recompiled from scratch and compared byte-for-byte against the
  archived binary from its good day: identical except 327 bytes in two
  clusters — the file header and the build-date ROM the flow stamps on
  every compile. The toolchain is deterministic; the machine is sound.
- **Any specific RTL change.** The video/machine logic is byte-identical
  between BP (good) and the corrupt builds. The startup-mode feature was
  audited twice, found clean, and removing it (BX) changed nothing. The
  anchor additions were present in good BS and bad BU alike. No code
  delta separates the two populations.
- **A real constraint bug we did find.** The CPU↔SDRAM clock crossing
  was excluded from timing analysis by a mis-declared constraint —
  genuinely wrong, proven with a −5.5 ns path on a bad build, fixed in
  BW. Necessary engineering, but the failures survived it, so it was
  not the mechanism. (The fix stays; timing reports are now honest.)

## What we know about the failure itself

Your observations localized it precisely:

1. On a bad build, the diskless **"?" screen is clean** — CPU, ROM,
   RAM, SDRAM, VRAM writes all fine at 1-bit depth, indefinitely.
2. **"Welcome to Macintosh" is clean at full colour depth** — so colour
   alone is not the trigger.
3. Corruption appears **only once the Finder is up** — when the OS
   starts doing byte-masked read-modify-write drawing (icons, windows)
   concurrently with disk serving, all through the SDRAM controller.
4. Screen corruption comes **first**, F-lines **after** — consistent
   with bad writes landing visibly in video memory and invisibly in
   program memory, which then gets executed.
5. Per build, the behavior is **deterministic** — a bad build fails
   every boot the same way; a good build is good.

## The surviving explanation (and its honest status)

Every compile places and routes the same logic differently (and any
source change, however unrelated, reshuffles the whole placement). The
theory: some placements produce a marginal path in the cone that
handles VRAM-shadow read-modify-write traffic through the SDRAM
controller — a path that idle screens and simple ROM drawing never
stress, but Finder-grade load does. Static timing analysis passes
either way because the marginal behavior lives in something the
constraints don't model.

Status: **hypothesis of last resort.** It fits every observation, and
its competitors are all measured dead — but three fixes aimed at this
class (two anchor variants, one constraint repair) failed to cure it,
so it has not earned "proven." What HAS changed is that we now know
exactly where to aim, which is what the plan below does. The honest
alternative reading — some environmental factor common to all
post-BP compiles that we haven't imagined — has no remaining candidate
we can name, but the experiment below discriminates anyway.

One genuinely open question: why did BS behave for two days before
failing its retest? Candidates: its fit is marginal-but-rare rather
than deterministic (the field F-line rate supports this), and its good
era ran a different disk (the games image, System 7.1) than the fresh
disk it failed on. Related open fact worth capturing: **which System
version is on the fresh test disk?** If it is 7.5.5 or 6.0.8 rather
than 7.1, the System version is an untested variable in the retest.

## How we proceed

In order, one variable per build, each gated by the one-boot damn-test
(a bad fit declares itself on the first boot — no long tallies needed)
plus the icon/corruption check:

1. **buildBY = BP base + the ASC alert fix, alone.** The fix is small,
   proven to cure the stuck-alert on BW, and the alert bug is v1.0.1's
   headline known issue. If BY's fit rolls bad, re-roll the seed until
   the damn-test passes — we know one boot decides, so rolls are cheap.
   Ships as v1.0.2 when it passes.
2. **The mechanism experiment, on a condemned build.** Take BX exactly
   as it failed, add explicit timing constraints (or a registered
   pipeline stage) on the VRAM-shadow RMW cone — the address and
   byte-enable paths into the SDRAM controller — and rebuild. If the
   corruption vanishes on a netlist that reliably corrupts, the
   mechanism is *proven*, the constraint goes into every future build,
   and the fit lottery ends permanently. If it doesn't, the placement
   theory takes its fourth and probably fatal hit, and the next lever
   is compiling the identical tree on a different machine/Quartus
   install purely to vary the fitter environment.
3. **Then features, one rung at a time on whatever base is proven:**
   mouse-default reimplemented as a simple sampled-at-reset register,
   PRAM persistence, GCR floppy work, the hang-rate investigation.

Standing discipline that this arc earned (do not regress on these):
- One variable per shipped build; archive every .sof; the exact bytes
  of anything validated must be recoverable.
- The one-boot damn-test; both-slot A/A symmetry when packaging
  changes; icon gate in the Finder.
- Park Settings on every bad-fit recovery; SHA-verify every image
  before trusting it; keep a known-good build in the prev slot at all
  times — it was the control that cracked this case.
