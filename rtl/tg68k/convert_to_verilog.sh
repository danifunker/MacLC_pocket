#!/bin/bash
#
# convert_to_verilog.sh — regenerate TG68KdotC_Kernel.v from the VHDL source.
#
# The VHDL files (TG68K_Pack.vhd, TG68K_ALU.vhd, TG68KdotC_Kernel.vhd) are the
# SOURCE OF TRUTH for the CPU core. Quartus compiles the VHDL directly (see
# rtl/tg68k/TG68K.qip); Verilator compiles the generated .v (see
# verilator/Makefile). After ANY edit to the VHDL, run this script and rebuild
# the Verilator sim so both toolchains stay in sync.
#
# IMPORTANT: this core is the MOVES-era kernel (lastOpcBit=89, moves_fc). Do NOT
# replace the VHDL with upstream MacPlus originals — that drops MOVES support the
# Mac LC boot ROM relies on and desyncs sim from FPGA (see bootprogress.md).
#
# Requires ghdl (tested with GHDL 6.0.0 / LLVM). The ghdl synth output is the
# whole kernel hierarchy with the ALU inlined as a submodule, so the generated
# TG68KdotC_Kernel.v is self-contained.
#
# Generics: use the entity DEFAULTS (SR_Read=2, VBR_Stackframe=2, extAddr_Mode=2,
# MUL_Mode=2, DIV_Mode=2, BitField=2, BarrelShifter=1, MUL_Hardware=1). GHDL 6.0.0
# rejects -g overrides for these ("out of bounds"), and the defaults already match
# the committed core (validated: byte-for-byte identical boot trace).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GHDL_FLAGS="-fsynopsys -fexplicit --workdir=$WORK"

echo "=== Analyzing VHDL (Pack -> ALU -> Kernel) ==="
ghdl -a $GHDL_FLAGS TG68K_Pack.vhd
ghdl -a $GHDL_FLAGS TG68K_ALU.vhd
ghdl -a $GHDL_FLAGS TG68KdotC_Kernel.vhd

echo "=== Synthesizing TG68KdotC_Kernel -> TG68KdotC_Kernel.v ==="
ghdl synth $GHDL_FLAGS --latches --out=verilog TG68KdotC_Kernel > TG68KdotC_Kernel.v.tmp
mv TG68KdotC_Kernel.v.tmp TG68KdotC_Kernel.v

echo "=== Done. Lines: $(wc -l < TG68KdotC_Kernel.v) ==="
echo "Now rebuild the sim: (cd ../../verilator && make clean && make)"
