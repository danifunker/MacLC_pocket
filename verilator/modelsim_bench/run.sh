#!/usr/bin/env bash
# Extract the AMNT block verbatim from core_top.sv, build, simulate.
set -eu
cd "$(dirname "$0")"
MS=/c/intelFPGA_lite/18.1/modelsim_ase/win32aloem
REPO=../..

awk '/localparam \[2:0\] A_IDLE/,/: amnt_size;/' \
    "$REPO/src/fpga/core/core_top.sv" > amnt_block.vh
lines=$(wc -l < amnt_block.vh)
echo "extracted amnt_block.vh: $lines lines"
[ "$lines" -gt 100 ] || { echo "extraction failed"; exit 1; }

# core_bridge_cmd.v declares the b_datatable_* regs after first use; Quartus
# accepts that, ModelSim does not. Bench-local copy with the declarations
# hoisted to the top of the module (framework file itself untouched).
sed -e 's/^module core_bridge_cmd (/module core_bridge_cmd (/' \
    "$REPO/src/fpga/core/core_bridge_cmd.v" > core_bridge_cmd_ms.v
python - <<'PY'
import re
src = open('core_bridge_cmd_ms.v').read()
decl = """
    wire    [31:0]  b_datatable_q;
    reg     [9:0]   b_datatable_addr;
    reg             b_datatable_wren;
"""
# remove the late declarations
src = src.replace("""    wire    [31:0]  b_datatable_q;
    reg     [9:0]   b_datatable_addr;
    reg             b_datatable_wren;
""", "")
# insert right after the port list ends
src = src.replace(");\n\n// handle endianness", ");\n" + decl + "\n// handle endianness", 1)
# 4-state sim: hstate/tstate have no initializer; on the FPGA they power up 0,
# in ModelSim they X-deadlock the FSMs. Mirror hardware power-up.
src = src.replace("    reg     [3:0]   hstate;", "    reg     [3:0]   hstate = 4'd0;")
src = src.replace("    reg     [3:0]   tstate;", "    reg     [3:0]   tstate = 4'd0;")
open('core_bridge_cmd_ms.v','w').write(src)
print("hoisted b_datatable_* declarations; initialized hstate/tstate")
PY

# altsyncram resolves the datatable init file relative to the sim cwd
mkdir -p apf
cp "$REPO/src/fpga/apf/build_id.mif" apf/build_id.mif

rm -rf work
"$MS/vlib.exe" work >/dev/null
"$MS/vlog.exe" -quiet -sv amnt_wrap.sv
"$MS/vlog.exe" -quiet \
    core_bridge_cmd_ms.v \
    "$REPO/src/fpga/apf/common.v" \
    "$REPO/src/fpga/apf/mf_datatable.v" \
    "$REPO/src/fpga/core/apf_blockdev.v" \
    tb_amnt.v
"$MS/vsim.exe" -c -quiet -L altera_mf_ver tb_amnt -do "run -all; quit -f" | tee sim.log
grep -q "TB PASS" sim.log
