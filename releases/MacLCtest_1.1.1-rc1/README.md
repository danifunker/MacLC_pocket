# MacLCtest 1.1.1-rc1 — RELEASE CANDIDATE (parked 2026-08-20)

v1.1.0-rc1 (CPU-perf stack + slot-phase SDRAM starts + 32 KB HD1 ring)
PLUS the restored Dock USB HID stack: the ladder/mouse-default RTL
(pocket_hid.v + core_top glue + pocket_input startup-mode sampling),
merged to main via integrate/hid-restore after the carry-forward gap
was discovered (main had shipped v1.0.3's HID as a prebuilt binary
while the RTL lived only on the ladder branch).

- shipped as test-slot build "1.1.1-hid2"
- fit: seed 7, now the canonical qsf SEED (seed 4 of this netlist drew
  an unstable placement — another Law 7 datum at 275/308 M10K;
  docs/F-Line_Build_Errors.md)
- ap_core.rbf md5: 6f570cc6 (archived with .sof + the seed-11 spare
  3496cf2b: scratch/builds/2026-08-20-hidint-*)
- STA: met all corners (+2.043 setup / +0.119 hold); M10K 275/308;
  anchors preserved (1067 map attribute rows)

HW verdict (user, 2026-08-20): "working completely" — stability, docked
keyboard + mouse, normal boot. Modifier mapping is still POSITIONAL
(Alt=Command, Win=Option); the semantic swap is the next planned change.

Known gaps carried forward: no PRAM/.nvr persistence (every cold load
is a dead-battery Mac — 32-bit addressing and colors reset); Case 5
(7.5.5 corruption) mitigated by the ring, mechanism still open;
tb_scsi_face still owed on the Verilator box.

Fallbacks: v1.1.0-rc1, then v1.1.0-sp, then v1.0.3.
