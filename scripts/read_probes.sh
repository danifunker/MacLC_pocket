#!/usr/bin/env bash
# Read the MacLC JTAG In-System probes from the running FPGA (decoded dump).
# Portable: resolves the repo root from this script's location and adds
# Quartus to PATH. Don't run while a Quartus compile is using the cable.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"

quartus_stp_tcl -t scripts/cpu_state.tcl 2>&1 \
  | grep -ivE "copyright|license|agreement|partner|foregoing|associated|terms of|subscription|megacore|expressly subject|authorized distrib|including, without|applicable license|please refer|sole purpose|your use of"
