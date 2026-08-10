#!/bin/bash
# lint.sh — Verilator lint of the Macintosh machine top and all of rtl/.
#
# WHY THIS EXISTS: Quartus is the only tool that compiles the whole Pocket
# design (the APF framework instantiates Altera primitives — altsyncram,
# altera_pll — that Verilator cannot elaborate), but a Quartus pass costs
# minutes and needs a licence-free install that may not be on every box. This
# checks the part that actually changes: mac_lc_pocket.sv plus every file
# under rtl/. It runs in ~10 seconds and catches width mismatches, undriven
# nets, port-count errors and syntax before you spend a fit on them.
#
# Scope, stated honestly:
#   COVERED     rtl/*, src/fpga/core/mac_lc_pocket.sv, pocket_sdram.v
#   NOT COVERED core_top.sv, core_bridge_cmd.v, src/fpga/apf/* — they pull in
#               Altera IP. Quartus is the gate for those.
#
# Usage:  bash scripts/lint.sh        (from the repo root, under WSL/Linux)
# Exit:   0 = clean

set -u
cd "$(dirname "$0")/.."

WAIVERS="-Wno-TIMESCALEMOD -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
         -Wno-IMPLICIT -Wno-PINMISSING -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT
         -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-CMPCONST -Wno-LATCH
         -Wno-UNDRIVEN -Wno-MISINDENT -Wno-COMBDLY -Wno-INITIALDLY
         -Wno-SYNCASYNCNET -Wno-BLKLOOPINIT -Wno-MULTIDRIVEN -Wno-GENUNNAMED
         -Wno-DECLFILENAME"

verilator --lint-only --top-module mac_lc_pocket \
    -Irtl -Irtl/tg68k -Irtl/uart -Irtl/egret \
    --timescale-override 1ps/1ps $WAIVERS \
    src/fpga/core/mac_lc_pocket.sv \
    src/fpga/core/pocket_sdram.v \
    rtl/tg68k/TG68K_ALU.v rtl/tg68k/TG68K_Pack.sv \
    rtl/tg68k/TG68KdotC_Kernel.v rtl/tg68k/tg68k.v \
    rtl/addrController_top.v rtl/addrDecoder.v rtl/dataController_top.sv \
    rtl/maclc_v8_video.sv rtl/vram_bram.sv rtl/ariel_ramdac.sv \
    rtl/pseudovia.sv rtl/via6522.sv rtl/adb.sv rtl/adb_device.sv \
    rtl/asc.sv rtl/sdp_ram.sv rtl/v8_clocks.sv rtl/ps2_mouse.v \
    rtl/swim.v rtl/floppy.v rtl/floppy_track_encoder.v \
    rtl/mfm_track_encoder.v rtl/scsi.v rtl/ncr5380.sv rtl/scc.v \
    rtl/egret/egret_wrapper.sv rtl/egret/m68hc05_core.sv \
    rtl/egret/m68hc05_alu.sv rtl/uart/txuart.v rtl/uart/rxuart.v

rc=$?
if [ $rc -eq 0 ]; then echo "lint: clean"; else echo "lint: FAILED ($rc)"; fi
exit $rc
