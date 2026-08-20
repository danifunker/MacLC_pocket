#!/usr/bin/env bash
# run_seam.sh — compile and run tb_mem_seam (real fetch_cache + real
# pocket_sdram + verbatim glue + Phase-B BFM). PASS = "ALL SEAM CHECKS PASSED".
set -eu
cd "$(dirname "$0")"
MS="C:/intelFPGA_lite/18.1/modelsim_ase/win32aloem"
"$MS/vlib.exe" work_seam >/dev/null 2>&1 || true
"$MS/vlog.exe" -work work_seam ../../src/fpga/core/pocket_sdram.v ../../rtl/fetch_cache.sv tb_mem_seam.v
"$MS/vsim.exe" -c -work work_seam tb_mem_seam -do "run -all; quit -f" | tee seam_bench.log
grep -E "ALL SEAM CHECKS PASSED|SEAM FAILED|VIOLATION|MISMATCH|WATCHDOG|fetches=" seam_bench.log | tail -15
