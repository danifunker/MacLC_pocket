# MacLCtest 1.1.0-sp — SNAPSHOT (known-good, pre-release)

The full CPU-perf stack (Phase B collapsed bus FSM + Phase C demand
engine + always-on 1 KB I-cache) with SDRAM command starts quantized to
one phase per clk_8 period (`t == 3'd1`) — the configuration that ended
the F-line hunt (docs/F-Line_Build_Errors.md, Case 3).

- source commit: 7023c47 (tree identical through 36a45da)
- fit: seed 4, Quartus 18.1.1; STA met all corners (+2.041 setup /
  +0.064 hold worst-case; request bundle +7.07/+1.16; cpu_dout +8.7)
- ap_core.rbf md5: 4487633bb4c2034f7db15bd61526fbab
- HW verdict 2026-08-19: boots clean through Finder, floppy + SCSI
  healthy, Speedometer CPU results at MiSTer-core level (user-run).
- .sof archived (NOT in git): scratch/builds/2026-08-19-slotphase-1.1.0sp-seed4-4487633b.sof
- bitstream.rbf_r itself is not committed (house rule: hash-only, see
  MANIFEST.sha256 — sha256 f1d7928f…); the bytes live on the card's test
  slot, in scratch/staging/testslot/, and are rebuildable from tag
  v1.1.0-sp (fit seed 4).

This snapshot exists so post-1.1.0-sp experiments can always retreat to
a proven build. Do not overwrite; supersede with a new directory.
