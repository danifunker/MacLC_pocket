# MacLC design timing constraints for the Analogue Pocket.
#
# Ported from the MiSTer core's MacLC.sdc. This file was MISSING from the
# initial Pocket project, and its absence was not cosmetic: the first fit
# failed timing at -4.482 ns on clk_sys, and every one of the twelve worst
# paths was the TG68 register-file WE -> read-during-write bypass — the exact
# path the first constraint below exists to legitimise.
#
# Clock-name mapping from the MiSTer original:
#   MiSTer  emu|pllv|*|divclk        (pll_video, reconfigurable)
#   Pocket  ic|mp1|...|general[3].*  (mf_pllbase outclk_3, fixed 15.662651 MHz)
# The Pocket has one PLL with four fixed outputs instead of MiSTer's two PLLs
# with a reconfigurable video clock, so the video clock is identified by its
# output-counter index rather than by a separate PLL instance name.

# ----------------------------------------------------------------------------
# TG68 kernel multicycle — REQUIRED for reliable timing closure.
# ----------------------------------------------------------------------------
# The TG68 kernel (TG68KdotC_Kernel) is a clock-enabled CPU: it advances ONLY on
# tg68_clkena (rtl/tg68k/tg68k.v). The Phase-B bus FSM (ported from MiSTer
# cpu-icache 2026-08-19) pulses clkena once per bus cycle at S_ENDC — always
# >= 5 ticks after the previous pulse — and for internal (busstate==01) steps
# gates it with !clkena_d (clkena delayed one tick), so clkena can never pulse
# on two consecutive clk_sys cycles — consecutive kernel updates are always
# >= 2 clk_sys periods apart. (The pre-Phase-B walker got the same guarantee
# from clocking only at phi1.) Every kernel register (including the inferred
# register-file RAM regfile_rtl_0/1 and its read-during-write bypass) takes its
# meaningful input from, and feeds, other clkena-gated kernel logic. So
# kernel-internal reg->reg paths genuinely have TWO clk_sys periods to settle,
# not one. If the FSM's clkena gating is ever changed, re-verify this
# invariant before trusting any fit.
#
# Without this, STA over-constrains the kernel to a single clk_sys period
# (~30.8 ns @ 32.5 MHz) and the ~33 ns decode/datapath/regfile-bypass paths
# "fail". On the DE10-Nano's faster part they failed by -2.699 ns and sometimes
# squeaked by on placement luck; on the Pocket's slower 5CEBA4F23C8 (-8
# commercial vs the DE10's -7 industrial) the same path measured -4.482 ns and
# never closes. Same path, same cause, more margin needed.
#
# Scope is kernel-INTERNAL only (-from kernel -to kernel): it deliberately does NOT
# touch the tg68k WRAPPER state machine (s_state/eCntr update on phi1|phi2 = every
# clk_sys = genuine 1-cycle) nor any CPU<->SDRAM/peripheral path (those sample at
# full clk_sys rate and must stay single-cycle). HW-validated on MiSTer by a clean
# boot to the Finder desktop (the CPU executes millions of instructions through
# these paths to boot; a wrong multicycle would corrupt/crash it).
set_multicycle_path -setup -end 2 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*TG68KdotC_Kernel*}]
set_multicycle_path -hold  -end 1 -from [get_keepers {*TG68KdotC_Kernel*}] -to [get_keepers {*TG68KdotC_Kernel*}]

# ----------------------------------------------------------------------------
# Peripheral (VPA) read-data register — SCSI read-path fit-stabilization.
# ----------------------------------------------------------------------------
# periph_din_reg captures the peripheral read mux (dataControllerDataOut) one
# clk_sys stage before the CPU samples it on VPA/6800 cycles. Its deepest input
# cone is the SCSI CSR's scsi_bsy bit (scsi.v phase -> |target_bsy -> CSR -> far
# route -> 7-way mux) — historically THE fit-sensitive net that made the SCSI HD
# read fail on some MiSTer builds (bit6/scsi_bsy read wrong, bit1/scsi_sel read
# right), i.e. a dice-roll boot.
#
# Peripheral reads are E-paced: the kernel stalls at S_WAIT for the E-paced
# (phi2 && xVma) exit (near E-fall) and latches read data two ticks later at
# S_TAIL2, ALWAYS >= 5 clk_sys after the address/select settle (the VMA/E
# handshake takes at least one E quantum; rtl/tg68k/tg68k.v). Credit a
# CONSERVATIVE 2x — well inside the >=5-cycle window — so STA reports the real
# margin instead of over-constraining this E-paced read to one 30.8 ns period
# (the "STA passes but HW fails" trap). Its fan-OUT (-> tg68_din_r) stays
# single-cycle and is deliberately NOT relaxed.
set_multicycle_path -setup -end 2 -to [get_keepers {*periph_din_reg*}]
set_multicycle_path -hold  -end 1 -to [get_keepers {*periph_din_reg*}]

# ----------------------------------------------------------------------------
# Pixel-clock domain CDC.
# ----------------------------------------------------------------------------
# The V8 scanout, the Ariel palette lookup and vram_bram's read port all run on
# clk_pix (mf_pllbase outclk_3), asynchronous to clk_sys for timing purposes.
#
# The deliberate clk_sys<->clk_pix crossings this blesses are all safe by
# construction: (a) dual-clock M10Ks (vram_bram framebuffer, ariel palette — no
# timed cross-port arc), (b) 2FF *_meta synchronizers (config into the video
# module, video-domain reset, VBL/HBL back into clk_sys), and (c) the
# quasi-static words_per_line bus into addrController's VRAM write packing —
# incoherent only across a depth change, when the guest redraws the whole
# screen anyway.
set_clock_groups -asynchronous -group [get_clocks {*general[3].gpll~PLL_OUTPUT_COUNTER|divclk}]

# Belt-and-braces documentation of the synchronizer heads (redundant with the
# clock group above, harmless).
set_false_path -to [get_keepers {*vmode_meta* *monid_meta* *tbyp_meta* *tsel_meta*}]
set_false_path -to [get_keepers {*vidrst_meta* *vbl_meta* *hbl_meta*}]

# ----------------------------------------------------------------------------
# Bridge (clk_74a) -> clk_sys option-pulse crossings.
# ----------------------------------------------------------------------------
# core_top stretches the interact.json option pulses into toggles and recovers
# the edge with a 3FF chain in clk_sys. The toggle bits themselves are the
# crossing point and are asynchronous by construction.
set_false_path -to [get_keepers {*rst_s* *pram_s* *nmi_s*}]
