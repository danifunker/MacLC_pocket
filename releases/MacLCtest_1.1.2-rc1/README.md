# MacLCtest 1.1.2-rc1 — RELEASE CANDIDATE (parked 2026-08-20)

v1.1.1-rc1 (CPU-perf + slot-phase + 32KB HD1 ring + Dock HID) PLUS the
input-settings feature:
- Core Settings input cluster (minified interact.json, 3,707 B):
  'D-Pad Mouse Mode' Off/On, 'Pointer Speed' 1..4 list, 'PC Modifier
  Keys' Off/On — all persist.
- Modifier layout selectable: default = Mac/semantic (Apple keyboards
  label-correct — HID Alt->Option, GUI->Command); On = the old
  positional remap. Mid-hold flip cannot strand a modifier (layout
  snapshotted only with all modifiers up).
- Pointer speed: user 1..4 -> shift 4-value, clamped; buildCG clicks-off
  diag bit retired.

- shipped as test-slot build "1.1.2-inp3"
- fit: seed 12, now canonical in the qsf. Netlist lottery record:
  seed 7 = Finder F-lines, seed 11 = ASC alert hang (the anchor_asc0
  fingerprint), seed 12 = clean — 1-of-3 at 275/308 M10K (Law 7).
- ap_core.rbf md5: a2deacd6 (.sof archived; seeds 4/7/11 rbfs archived)
- STA: met all corners (+2.041 setup / +0.116 hold)
- Menu laws learned this cycle: docs/interact_envelope.md (type-change
  re-id law, short names, no submenus, minified serialization).

HW verdict (user, 2026-08-20): "looking really good" — stability, menu
renders and toggles, keyboard mapping correct.

Fallbacks: v1.1.1-rc1 -> v1.1.0-rc1 -> v1.1.0-sp -> v1.0.3.
