# USB keyboard & mouse through the Dock — scope

2026-08-16. What it would take to accept a real USB keyboard and mouse from
the Analogue Dock, and what can be borrowed from the Amiga core (`../Analogue-Amiga`).

## The good news: nothing in the framework has to change

The Dock's HID data arrives on the **existing controller ports**, not through
a new interface. `src/fpga/core/core_top.sv:237-247` already declares them:

```
cont3_key, cont3_joy, cont3_trig     keyboard
cont4_key, cont4_joy, cont4_trig     mouse
```

They are wired through `apf_top` today and simply unused. That matters a lot:
`src/fpga/apf/` is OFF-LIMITS, and this needs no edit there.

`dist/.../core.json` also already declares what's required:

```json
"version_required": "2.1",  "dock": { "supported": true }
```

So the JSON side is done too. **The entire job is one new RTL module plus
wiring.**

## The wire format (confirmed from two independent sources)

Verified against `open-fpga/core-example-kbmouse-targetdata` and cross-checked
against the Amiga core's driver (`src/MPUBIOS/drivers/KMIO/inputs.cpp`), which
agree exactly.

**Mouse — controller 4**
| field | meaning |
|---|---|
| `cont4_key[31:28] == 4'h5` | device is a mouse |
| `cont4_key[15:0]` | report counter — a CHANGE means a new report |
| `cont4_joy[31:16]` | buttons: bit0 left, bit1 right, bit2 middle |
| `cont4_joy[15:0]` | relative X, signed |
| `cont4_trig[15:0]` | relative Y, signed |

**Keyboard — controller 3**
| field | meaning |
|---|---|
| `cont3_key[31:28] == 4'h4` | device is a keyboard |
| `cont3_key[15:8]` | modifiers, standard USB HID order: LCTRL, LSHIFT, LALT, LGUI, RCTRL, RSHIFT, RALT, RGUI |
| `cont3_joy[31:24] [23:16] [15:8] [7:0]` | scancodes 0-3 |
| `cont3_trig[15:8] [7:0]` | scancodes 4-5 |

Six-key rollover, USB HID usage codes. A key is *released* by disappearing
from the array — there is no release event.

## What the Amiga core gives us, and what it doesn't

**Borrowable:** the wire format above, the modifier bit assignments, and the
report-counter idiom for detecting new mouse reports. Its `inputs.h` constants
(`LCTRL 0x000100` … `RGUI 0x008000`) confirm modifiers sit in `cont3_key[15:8]`.

**NOT borrowable:** the translation itself. The Amiga core does **no HID
decoding in RTL**. `substitute_mcu_apf.v` exposes cont3/cont4 as
memory-mapped registers (offsets 0x28/0x2C/0x38/0x3C/0x48/0x4C) to a RISC-V
soft CPU, and `inputs.cpp` translates HID → Amiga keycodes in C firmware.

We have no soft CPU and no reason to add one. Our path is pure RTL:

```
cont3/cont4 -> [NEW] -> ps2_key / ps2_mouse -> adb_device -> Egret -> Mac
```

`adb_device` is the platform seam the port was built around; everything to its
right stays untouched, exactly as with the gamepad.

## The work

**1. `rtl/pocket_hid.v` (new, ~300 lines)**

Mouse: latch `cont4_key[15:0]`, and on a change emit one `ps2_mouse` report.
Our format is already established in `pocket_input.v` — 9-bit two's complement
deltas with the sign as bit 8 in the status byte, and a TOGGLE strobe. HID's
8-bit signed relative values drop straight in. **Y sign needs care**: PS/2
positive dy is UP, and `pocket_input.v` documents that getting this backwards
inverted the cursor on hardware.

Keyboard: hold the previous 6-code array plus the modifier byte; on each new
report, diff against it and emit one `ps2_key` event per change, one per
clock, exactly as `pocket_input`'s scanner does. Releases are implicit
(a code vanishing from the array), so the diff must synthesise key-up itself.
**Get this wrong and keys stick down on the Mac forever** — the same hazard
`pocket_input`'s clean-release-on-mode-flip logic exists to prevent.

**2. USB HID → PS/2 Set 2 translation table (~120 lines)**

The bulk of the tedium and the only part with no shortcut. ~100 entries,
mechanical, well documented publicly. Translating to PS/2 Set 2 rather than
straight to ADB is deliberate: it reuses the entire validated
`adb_device` decode path instead of opening a second, untested one. The E0
extended-prefix convention (bit 8 of our 9-bit codes) is already plumbed
end-to-end and verified.

**3. Arbitration in `core_top` (~40 lines)**

Both `pocket_input` (gamepad) and `pocket_hid` want to drive `ps2_key` and
`ps2_mouse`. Simplest correct approach: last-event-wins on the toggle strobes,
with each source owning its own toggle and a small merge that forwards
whichever changed. The gamepad path MUST keep working — undocked is the
normal case for a handheld, and this feature is Dock-only.

## Risks

- **Dock-only, and untestable without the hardware.** Needs a Dock plus a USB
  keyboard and mouse. There is no simulation path: the Verilator harness has
  been broken since 2026-08-09.
- **Report rate.** The Amiga README warns its mouse "needs refinement for
  high-sensitivity devices". A 1000 Hz gaming mouse will produce reports far
  faster than a 90 Hz ADB mouse is polled; deltas must be accumulated between
  ADB polls, not dropped.
- **Counter wrap and missed reports.** Detect *change*, never equality, and
  do not assume increments of one.
- **Fit lottery.** Adding ~300 lines is a new netlist and therefore a new
  roll. Budget for seed re-rolls; per §8 of BUILD_INSTABILITY_MEASUREMENTS
  the observed good rate is about 1 in 3.

## Estimate

| piece | size | risk |
|---|---|---|
| mouse decode | ~80 lines | low — format proven twice |
| keyboard decode + rollover diff | ~150 lines | medium — release synthesis is the trap |
| HID→PS/2 table | ~120 lines | low, tedious |
| core_top arbitration | ~40 lines | medium — must not regress the gamepad |
| build + seed rolls | 1-3 compiles | the usual lottery |

One focused session for the RTL. The real gate is hardware access, since none
of it can be verified without a Dock.
