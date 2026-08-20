#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
MS="C:/intelFPGA_lite/18.1/modelsim_ase/win32aloem"
python gen_ncr_bench.py && "$MS/vlib.exe" work_face >/dev/null 2>&1 || true
"$MS/vlog.exe" -work work_face -sv ncr5380_bench_gen.v tb_scsi_face.v
"$MS/vsim.exe" -c -work work_face tb_scsi_face -l face_vsim.log -do "run -all; quit -f" > /dev/null 2>&1
grep -E "ALL FACE|FAILED|MISMATCH|TIMEOUT|run mode|===" scsi_face.log | tail -35
