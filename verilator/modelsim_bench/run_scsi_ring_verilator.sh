#!/usr/bin/env bash
# run_scsi_ring_verilator.sh — tb_scsi_ring on Verilator 5 (macOS/Linux box).
# Twin of run_scsi_ring.sh (whose bundled ModelSim path is Windows-only),
# same pattern as run_scsi_face_verilator.sh. Extracts scsi_dpram fresh from
# rtl/scsi.v so the bench always tests shipping RTL.
#
# Run (from verilator/modelsim_bench/):
#   bash run_scsi_ring_verilator.sh
# PASS = final line "ALL RING CHECKS PASSED".
set -eu
cd "$(dirname "$0")"

sed -n '/^module scsi_dpram/,/^endmodule/p' ../../rtl/scsi.v > scsi_dpram_gen.v

verilator --binary -j 0 --timing -Wno-fatal --timescale 1ns/1ps \
  --Mdir obj_ring --top-module tb_scsi_ring \
  scsi_dpram_gen.v tb_scsi_ring.v

./obj_ring/Vtb_scsi_ring | tee scsi_ring_verilator.log
grep -E "ALL RING CHECKS PASSED|FAILED" scsi_ring_verilator.log
