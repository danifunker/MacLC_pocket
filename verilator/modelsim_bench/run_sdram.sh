#!/usr/bin/env bash
# run_sdram.sh — compile and run tb_pocket_sdram against the REAL controller.
# Usage: bash run_sdram.sh   (from verilator/modelsim_bench)
set -eu
cd "$(dirname "$0")"

MS="C:/intelFPGA_lite/18.1/modelsim_ase/win32aloem"

"$MS/vlib.exe" work_sdram >/dev/null 2>&1 || true
"$MS/vlog.exe" -work work_sdram ../../src/fpga/core/pocket_sdram.v tb_pocket_sdram.v
"$MS/vsim.exe" -c -work work_sdram tb_pocket_sdram -do "run -all; quit -f" | tee sdram_bench.log
grep -E "ALL CHECKS PASSED|FAILED|VIOLATION|MISMATCH|WATCHDOG" sdram_bench.log | tail -20
