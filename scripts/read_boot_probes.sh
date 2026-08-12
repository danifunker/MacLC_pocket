#!/usr/bin/env bash
# Read the MacLC_Pocket cold-boot forensics probes from the running FPGA.
#
#   bash scripts/read_boot_probes.sh
#
# Requires a bitstream built with USE_BOOT_ISSP set in src/fpga/ap_core.qsf,
# programmed onto the Pocket, and a working USB-Blaster.
#
# Do NOT run while a Quartus compile is using the cable.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

# Quartus 18.1 on this Windows box; override with QUARTUS_BIN if it moves.
export PATH="${QUARTUS_BIN:-/c/intelFPGA_lite/18.1/quartus/bin64}:$PATH"

quartus_stp_tcl -t scripts/boot_state.tcl 2>&1 \
  | grep -ivE "copyright|license|agreement|partner|foregoing|associated|terms of|subscription|megacore|expressly subject|authorized distrib|including, without|applicable license|please refer|sole purpose|your use of|^Info: |^ *Info: |Processing (started|ended)|Elapsed time|CPU time|Peak virtual|Quartus Prime Shell|^ *$"
