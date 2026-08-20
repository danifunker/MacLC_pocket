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
# general[1] = 65 MHz @180deg     -- NO LONGER USED (dram_clk is DDIO-generated)
# general[2] = 32.5 MHz clk_sys
# general[3] = 15.66 MHz clk_pix
#
# ★ CRITICAL, AND IT BIT AGAIN 2026-08-11. When dram_clk moved to the DDIO
# generator, general[1] stopped driving anything and Quartus stripped it, while
# the new dram_clk_out was in NO group -- so -asynchronous made it unrelated to
# general[0] and CUT EVERY SDRAM I/O PATH. STA then reported a worst-case slack
# of 5.806 ns and zero violations because it was analysing NOTHING:
#     get_timing_paths -to [get_ports dram_*]  ->  0 paths
# Verify with scripts/check_sdram_paths.tcl after ANY change here. A good number
# with no paths behind it is the exact failure this whole file exists to stop.
#
# The controller clock and the chip clock must be in the SAME clock group. They
# were previously listed as mutually asynchronous, which cuts the launch->chip
# relationship the constraints below depend on and silently makes them a no-op.
# They are two phase offsets of one VCO; treating them as unrelated was wrong.
# clk_mem_90/180 drives nothing but the output pin, so grouping them creates no
# new internal register-to-register paths.

# ★ 2026-08-11 DDIO EXPERIMENT -- TRIED AND BACKED OUT. Read before retrying.
# pocket_sdram was switched to MiSTer's altddio_out clock generator (the form
# dave18/MemTest_Pocket uses on this hardware) and dram_clk modelled here as
#   create_generated_clock -name dram_clk_out -source <general[0]> -invert [get_ports dram_clk]
# It BUILT CLEAN and reported a worst-case slack of 5.806 ns -- an apparent big
# win over the PLL tap's 2.03 ns. It was fiction: STA was analysing ZERO SDRAM
# paths (scripts/check_sdram_paths.tcl -> write=0 read=0). Quartus would not
# associate the dq/command pins with a generated clock defined that way through
# the DDIO cell, and putting dram_clk_out in general[0]'s clock group did not
# fix it either.
#
# Both upstreams run their SDRAM with NO I/O constraints at all -- MiSTer's
# sys/sys_top.sdc and MemTest_Pocket's core_constraints.sdc each contain none --
# because the DDIO emits the clock from the IO cell alongside the data, so the
# skew is matched by construction rather than by analysis. That is a legitimate
# design, but it is UNVERIFIABLE by STA, and this port's largest historical
# defect was exactly an unconstrained SDRAM (see the header above). Keeping a
# configuration whose margins we can MEASURE beats matching upstream's form
# and losing the ability to check it.
#
# If retried: source the generated clock from the altddio_out instance's
# outclock PIN rather than the PLL divclk, and re-run check_sdram_paths.tcl --
# a healthy slack number with no paths behind it means nothing.

set dram_chip_clk "ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk"
set dram_cont_clk "ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk"

# ★ 2026-08-16: clk_mem (general[0]), the dram phase clock (general[1]) and
# clk_sys (general[2]) are SAME-PLL, integer-ratio, edge-aligned clocks, and
# pocket_sdram hands CPU data between mem and sys with no synchronizers BY
# DESIGN (the "65 MHz must stay exactly 8x" law). The old grouping declared
# them ASYNCHRONOUS, which told STA to ignore every path between the CPU and
# the SDRAM controller — the entire interface was untimed, and its behavior
# was decided by placement luck. That is the fit-lottery mechanism behind
# months of per-build corruption (F-lines / icon garbage / video corruption /
# hangs — all read-path damage). They now share one group so STA times the
# interface; clk_pix (general[3]) stays async (its crossings are metastable-
# hardened and false-pathed in maclc_constraints.sdc).
set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group { ic|mp1|mf_pllbase_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk \
          ic|mp1|mf_pllbase_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk } \
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

# ============================================================================
# ★ PORTED FROM ../MacLC_MiSTer MacLC.sdc (5a75f9b) on 2026-08-11.
# None of the three blocks below existed in this fork. They are not cosmetic:
# upstream marks the first "REQUIRED for reliable timing closure" and says that
# without it the design was "closing timing by luck", and the second is the
# constraint half of the periph_din_reg fix in mac_lc_pocket.sv (which was also
# missing). A port that carries the RTL fix but not its SDC gets the "STA
# passes but HW fails" trap upstream warns about.
# ============================================================================

# ---- TG68 kernel-internal multicycle ---------------------------------------
# Scope is kernel-INTERNAL only (-from kernel -to kernel). It deliberately does
# NOT touch the tg68k WRAPPER state machine (s_state/eCntr update every clk_sys
# = genuine single-cycle) nor any CPU<->SDRAM/peripheral path (those sample at
# full clk_sys rate and must stay single-cycle). Upstream HW-validated this by
# booting to the Finder desktop -- the CPU executes millions of instructions
# through these paths, so a wrong multicycle would corrupt or crash it.
set_multicycle_path -setup -end 2 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*TG68KdotC_Kernel*}]
set_multicycle_path -hold  -end 1 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*TG68KdotC_Kernel*}]

# ---- Peripheral (VPA) read-data register -----------------------------------
# periph_din_reg captures the peripheral read mux one clk_sys stage before the
# CPU samples it on VPA/6800 cycles. Its deepest input cone is the SCSI CSR's
# scsi_bsy bit (scsi.v phase -> |target_bsy -> CSR -> long route -> 7-way mux)
# -- upstream's "dice-roll boot": bit6/scsi_bsy read wrong while bit1/scsi_sel
# read right, depending on placement.
#
# Peripheral reads are E-paced: the Phase-B kernel wrapper stalls at S_WAIT
# for the E-paced (phi2 && xVma) exit and latches read data two ticks later
# at S_TAIL2, ALWAYS >= 5 clk_sys after address/select settle
# (rtl/tg68k/tg68k.v). Crediting a conservative 2x (61.5 ns @ 32.5 MHz) is
# well inside that window and makes STA report the real margin instead of
# over-constraining an E-paced read to a single 30.8 ns period. Its fan-OUT
# toward the CPU stays a normal single-cycle path and is deliberately NOT
# relaxed.
set_multicycle_path -setup -end 2 -to [get_keepers {*periph_din_reg*}]
set_multicycle_path -hold  -end 1 -to [get_keepers {*periph_din_reg*}]

# ----------------------------------------------------------------------------
# ★ Phase C: clk_sys -> SDRAM demand sequencer — NO multicycle. Deliberate.
# ----------------------------------------------------------------------------
# (Reasoning ported from MiSTer MacLC.sdc, cpu-icache, 2026-08-19.) A MiSTer
# attempt credited these paths 2 destination periods on the theory that the
# t[0] start gate made the request data "a full clk_sys old" at capture. STA
# on the post-fit netlist DISPROVED it:
#   slack -6.710 ns, WINDOW 15.381 ns, tg68k|addr[16] -> sdram|sd_addr[12]
# i.e. the capture window is ONE clk_64 period, and the V8 address-translation
# cone needs ~22 ns. The constraint was hiding a 6.7 ns violation; the SDRAM
# was being handed a half-settled row/column address, which corrupted memory
# and bombed the guest (F-line class).
#
# The fix is structural instead: mac_lc_pocket.sv registers the whole SDRAM
# request bundle (ram_*_q) in clk_sys before it reaches the sequencer, so the
# deep cone terminates at a clk_sys flop with a full 30.76 ns period, and the
# sequencer captures from an adjacent register over a short route. Both legs
# are then honest single-cycle paths that STA checks for real (the 2026-08-16
# same-group clocking above is what makes that check real on this fork).
# DO NOT add a multicycle here — if these paths fail, fix the pipelining.

# ---- CDC synchronizer heads ------------------------------------------------
# The clk_sys (general[2]) and clk_pix (general[3]) groups above already declare
# these domains mutually asynchronous, so this is belt-and-braces documentation
# of the 2FF heads added in mac_lc_pocket.sv: vidrst_meta (clk_sys -> clk_pix
# video reset) and vbl_meta/hbl_meta (clk_pix -> clk_sys blanking levels).
set_false_path -to [get_keepers {*vidrst_meta* *vbl_meta* *hbl_meta*}]
