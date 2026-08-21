# interact.json — the load envelope, measured

The Pocket's interact parser rejects some valid JSON files with
`Load error in 'interact' general error`. The 2026-08-15 investigation found a
file that loads by shrinking **every** axis at once, and recorded that "the
killer axis was never isolated (one of: 16-opt lists / 16th var / 22 KB size /
slider max 511 / numeric slider defaultval)".

2026-08-16 isolated it, by accident of having changed two axes and then
trimming only one of them.

## The three data points that matter

| file | vars | options/list | bytes | result |
|---|---|---|---|---|
| shipped v1.0.2 | 14 | 5 | 7,793 | **loads** |
| NMI + arrows (08-16) | 15 | **9** | 10,407 | **Load error** |
| ABXY trim (08-16) | 10 | **9** | 6,383 | **loads** |
| Amiga reference core | 15 | 8 | 6,271 | loads (other author) |
| `interact_full16.json` | 16 | 16 | 21,809 | Load error |

## What that proves

- **9-option lists are fine.** The failing file and the passing trim both have
  them. Option count is eliminated — it was the leading suspect and it is
  innocent up to at least 9.
- **15 variables are fine.** The Amiga core ships 15 and loads.
- **The killer is FILE SIZE**, and it is bounded:
  **> 7,793 bytes fails somewhere at or below 10,407.**

Everything else on the 08-15 suspect list (slider max, numeric slider
defaultval, the 16th variable) is unnecessary to explain any observation.

## The practical budget

Stay under ~7.8 KB. From the current 6,383-byte menu that is roughly **1.4 KB
of headroom** — about two more 9-option button lists, or the Memory variable
(~250 B) plus one list. Restoring everything at once (L/R/Start + Memory +
arrows on all seven) is what overflowed.

If a tighter bound is ever wanted, bisect between 7,793 and 10,407 by padding
a loading file with option entries — but the number above is already enough to
budget against.

## defaultval semantics — NOT settled, and one theory is disproven

A list's `defaultval` looked like a 0-based **index** (the Amiga core's
`Memory: Slow` uses `0` with 4 options, and its other list defaults only land
on sensible options when read as indices). Ours carry the option's **value**
as a hex string, e.g. `"0x5a"`.

The card's persist files disprove the index reading for our core:

```
Settings/danifunker.MacLC/Interact/_core/interact_persist.json
  id 110 val 90   (= 0x5A Return)   id 111 val 41  (= 0x29 Space)
  id 112 val 18   (= 0x12 Shift)    id 113 val 49  (= 0x31 N)
  id 114 val 118  (= 0x76 Esc)      id 115 val 21  (= 0x15 Q)
  id 116 val 17   (= 0x11 Command)
```

Those are the correct scancodes, i.e. the hex-string defaults are parsed as
VALUES and delivered correctly. **Do not "fix" these to indices** — writing 0
would send scancode 0 to all seven buttons and kill every one of them.

Unexplained: a fresh test slot persisted `id 110 val 0` while all six other
buttons held correct values. Something set Button A alone to 0. The clean
experiment is to delete `Interact/_core/interact_persist.json`, launch without
touching the menu, and read back what APF writes from defaults alone.

## Menu laws learned 2026-08-20 (the input-settings feature)

1. **Never change a row's TYPE (or value semantics) under an existing id.**
   The OS persists values per-id and restores them into the new shape:
   row 131 went list -> slider under the same id and rendered
   UN-TOGGLEABLE on hardware (stale list-era 0 into a min=1 slider).
   Re-id on any shape change; ids are free.
2. **Long names truncate in the Pocket UI.** Keep row names short
   ("PC Modifier Keys", not "Remap Alt + CMD keys for PC keymaps");
   put explanation in option names, which render on the full-screen
   picker each list row opens.
3. **No submenus exist, period** — confirmed against Analogue's current
   spec (flat list; the only "group" field gangs radio buttons). The
   per-row full-screen option picker is the platform's only
   submenu-like affordance.
4. **Minification is the envelope lever.** The v2 input menu overshot
   pretty-printed (7,935 > 7,793); compact serialization landed the
   same content at 3,707 bytes. Minified-file load: ★ VERIFIED on hardware
   2026-08-20 (user: "menu looks okay" on the 3,707-byte file; short
   names render, rows toggle). Minified is now the house serialization.

## Backlog: the real submenu answer

The user wants hierarchical settings; Analogue's menu cannot nest (law 3).
The path that CAN: a native Mac control panel (cdev) in the guest that
configures the core through a register window / spare PRAM bytes —
authentic Mac UI, arbitrarily organizable, persists once the parked
PRAM/.nvr persistence mission lands (same plumbing). Pair the two
missions when that work is scheduled.

## The entry cap, measured (2026-08-20)

The spec's combined limit is REAL and binds before the byte envelope:
**interact vars + data slots <= ~19 rendered** with this core's 5 data
slots — at 14 vars a face-button row silently vanished from the menu on
hardware ("additional entries will be dropped"). 13 vars + 5 slots
renders fully (proven twice). Budget: with 5 data slots, treat 13
interact rows as the ceiling; consolidate with multi-option lists (each
list holds up to 16 options and opens its own full-screen picker — the
platform's submenu substitute, and the reason the "Input Mode" 2x2 row
exists).
