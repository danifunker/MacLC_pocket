#!/usr/bin/env bash
# run_scsi_face_verilator.sh — tb_scsi_face on Verilator 5 (macOS/Linux box).
#
# WHY THIS RUNNER EXISTS: the Windows box's bundled ModelSim ASE (10.5b,
# 32-bit) SIGSEGVs at time-0 executing ncr5380 in any topology — a vendor
# runtime bug, diagnosed 2026-08-20 (five configurations, same crash).
# Verilator handles this module fine (the MiSTer scsi_bench proved it).
#
# WHAT IT TESTS: the REAL ncr5380 pseudo-DMA host face — DACK width-latch
# machine, ack trains, dma_settle/holdoff DREQ gating, the 2026-07-19
# host-face pipeline hardening — under Phase-B pacing (inter-cycle gap down
# to 2 clks), against a behavioral target serving the documented delivery
# contract. Part of the 7.5.5 corruption hunt: this is the one
# Pocket-divergent seam not yet exercised offline (tb_scsi_ring cleared the
# scsi_dpram seam; see docs/F-Line_Build_Errors.md).
#
# Run (from verilator/modelsim_bench/):
#   bash run_scsi_face_verilator.sh
# Needs: verilator >= 5.x (with --timing support), python3.
#
# PASS = final line "ALL FACE CHECKS PASSED".
# Any MISMATCH/TIMEOUT line is a real finding — paste the whole output back.
set -eu
cd "$(dirname "$0")"

python3 gen_ncr_bench.py    # fresh flatten of rtl/ncr5380.sv (guarded, 5 lines)

verilator --binary -j 0 --timing -Wno-fatal --timescale 1ns/1ps \
  --Mdir obj_face --top-module tb_scsi_face \
  ncr5380_bench_gen.v tb_scsi_face.v

./obj_face/Vtb_scsi_face | tee scsi_face_verilator.log
grep -E "ALL FACE CHECKS PASSED|FAILED" scsi_face_verilator.log
