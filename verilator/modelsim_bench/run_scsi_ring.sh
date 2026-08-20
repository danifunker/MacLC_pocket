#!/usr/bin/env bash
# run_scsi_ring.sh — REAL scsi_dpram (fresh-extracted) under Pocket cadences.
set -eu
cd "$(dirname "$0")"
MS="C:/intelFPGA_lite/18.1/modelsim_ase/win32aloem"
# fresh extraction: no drifting copy of the shipping module
sed -n '/^module scsi_dpram/,/^endmodule/p' ../../rtl/scsi.v > scsi_dpram_gen.v
"$MS/vlib.exe" work_ring >/dev/null 2>&1 || true
"$MS/vlog.exe" -work work_ring scsi_dpram_gen.v tb_scsi_ring.v
"$MS/vsim.exe" -c -work work_ring tb_scsi_ring -do "run -all; quit -f" | tee scsi_ring.log
grep -E "ALL RING|FAILED|MISMATCH|WATCHDOG|pace|phase" scsi_ring.log | tail -25
