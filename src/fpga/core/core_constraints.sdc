#
# user core constraints
#
# put your clock groups in here as well as any net assignments
#

# ---------------------------------------------------------------------------
# SDRAM I/O TIMING  (added 2026-08-10)
# ---------------------------------------------------------------------------
# WHY THIS EXISTS: the dram_* pins had NO timing constraints at all. The APF
# core-template ships this file as a stub and the port never added them, so:
#
#   * the Fitter had no timing goal for the SDRAM pins and placed them freely;
#   * STA never analysed them -- "0 negative slack" was SILENT about SDRAM,
#     not clean;
#   * every recompile reshuffled placement into a different pin delay, so the
#     interface was marginal in a way that CHANGED BUILD TO BUILD. Observed on
#     hardware as corrupted video that came back after a rebuild which touched
#     nothing in the memory path.
#
# Adapted from the reference Pocket core (Pocket-Amiga
# src/fpga/core/core_constraints.sdc), which runs the same SDRAM part on the
# same board. The delay numbers are board+chip properties (trace delay, chip
# tSU/tHD), not frequency dependent, so they carry over unchanged.
#
# general[0] = 65 MHz clk_mem     -- the controller clock (pocket_sdram)
# general[1] = 65 MHz @180deg     -- driven onto the dram_clk PIN (chip clock)
# general[2] = 32.5 MHz clk_sys
# general[3] = 15.66 MHz clk_pix
#
# CRITICAL: general[0] and general[1] must be in the SAME clock group. They
# were previously listed as mutually asynchronous, which cuts the launch->chip
# relationship the constraints below depend on and silently makes them a no-op.
# They are two phase offsets of one VCO; treating them as unrelated was wrong.
# clk_mem_90/180 drives nothing but the output pin, so grouping them creates no
# new internal register-to-register paths.

set dram_chip_clk "ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk"
set dram_cont_clk "ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk"

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk }

# Read path: data launched by the SDRAM relative to the clock it sees.
# -add_delay on the SECOND of each min/max pair is required: without it Quartus
# REPLACES the previous delay on the same port instead of adding to it
# ("Assignment set_input_delay ... has replaced one or more delays on port ...").
# The reference core omits it and silently loses one half of each pair.
set_input_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] -max 5.9 [get_ports dram_dq[*]]
set_input_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] -min 0.9 -add_delay [get_ports dram_dq[*]]

# Write/command path. The reference core constrains only the command group;
# dram_dq* and dram_dqm* are added here because this core does SDRAM writes
# (CPU RAM and the framebuffer mirror), and leaving them out would repeat the
# same mistake on the write direction.
set_output_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] -max  2.0 \
    [get_ports {dram_cke dram_a* dram_ba* dram_dqm* dram_dq* dram_cas_n dram_ras_n dram_we_n}]
set_output_delay -clock $dram_chip_clk -reference_pin [get_ports {dram_clk}] -min -1.0 -add_delay \
    [get_ports {dram_cke dram_a* dram_ba* dram_dqm* dram_dq* dram_cas_n dram_ras_n dram_we_n}]

set_multicycle_path -from $dram_chip_clk -to $dram_cont_clk -setup -end 2
# The -hold companion is NOT optional. -setup -end 2 moves the setup latch edge
# out by one period; the hold check then references the edge one cycle before
# THAT, i.e. a full period later than it should be, so hold is tightened by 1T.
# Measured here: adding the setup multicycle alone took the dram_dq -> dout
# paths from -5.1 ns setup to -6.6 ns HOLD -- same paths, failure just moved.
# -hold -end 1 puts the hold check back on the correct edge. The reference core
# (Pocket-Amiga) omits this line.
set_multicycle_path -from $dram_chip_clk -to $dram_cont_clk -hold  -end 1
