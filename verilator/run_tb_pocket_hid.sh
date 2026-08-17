#!/usr/bin/env bash
# Build and run the pocket_hid bench under ModelSim (ships with Quartus Lite;
# there is no Verilator on the build machine).
#
# By default it benches the ladder worktree's pocket_hid.v — the version being
# built right now. Pass a path to bench a different one, e.g. an older commit:
#   git -C ../MacLC_BBcolor show 8ef14fa:src/fpga/core/pocket_hid.v > /tmp/cc.v
#   bash run_tb_pocket_hid.sh /tmp/cc.v
set -eu
cd "$(dirname "$0")"
MS=/c/intelFPGA_lite/18.1/modelsim_ase/win32aloem
DUT="${1:-../../MacLC_BBcolor/src/fpga/core/pocket_hid.v}"
# Resolve so a caller can pass any path, absolute or repo-relative.
case "$DUT" in /*) ;; *) [ -f "$DUT" ] || DUT="$(cd .. && pwd)/${DUT#../}" ;; esac

[ -f "$DUT" ] || { echo "no such DUT: $DUT" >&2; exit 1; }
echo "DUT: $DUT"

WORK=obj_tb_pocket_hid
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

"$MS/vlib.exe" work            > /dev/null
DUTABS="$(cd "$(dirname "$DUT")" && pwd)/$(basename "$DUT")"
"$MS/vlog.exe" -quiet "$DUTABS" ../tb_pocket_hid.v 2>&1 | grep -viE "^$|^Top level|^--" || true
"$MS/vsim.exe" -c -quiet work.tb_pocket_hid -do "run -all; quit -f" 2>&1 \
    | grep -vE "^#? *$|^# //|^# Loading|^# vsim|^# Start time|^# End time|^# Errors: 0" \
    | sed 's/^# //'
