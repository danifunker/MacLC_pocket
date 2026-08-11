`timescale 1ns/10ps
module  mf_pllbase_0002(

	// interface 'refclk'
	input wire refclk,

	// interface 'reset'
	input wire rst,

	// interface 'outclk0'
	output wire outclk_0,

	// interface 'outclk1'
	output wire outclk_1,

	// interface 'outclk2'
	output wire outclk_2,

	// interface 'outclk3'
	output wire outclk_3,

	// interface 'outclk4'
	output wire outclk_4,

	// interface 'locked'
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("74.25 MHz"),
		.operation_mode("normal"),
		.number_of_clocks(4),
		// ---------------------------------------------------------------
		// MacLC Pocket clock plan (retargeted from the APF template's
		// 12.288/133.12 MHz defaults). Reference is clk_74a = 74.25 MHz.
		//
		//  outclk_0  65.000 MHz  clk_mem  — SDRAM state machine. Must be
		//                        EXACTLY 8x the 8.125 MHz bus clock: pocket_sdram
		//                        runs 8 states per chipset cycle and resyncs on
		//                        clk_8, so any other ratio breaks the wrap.
		//  outclk_1  65.000 MHz  clk_mem_90 — clk_mem shifted 3846 ps (90 deg at
		//                        65 MHz), driven onto the SDRAM's dram_clk pin so
		//                        the chip samples mid-eye. The MiSTer core got the
		//                        same effect from an altddio_out on clk_mem; on
		//                        the Pocket a phase-shifted PLL output is the
		//                        house style and lets the shift be retuned on
		//                        hardware without touching the controller.
		//                        UNVALIDATED: 90 deg is the conventional starting
		//                        point, not a measured value.
		//  outclk_2  32.500 MHz  clk_sys  — everything else. clk_mem/2. The whole
		//                        design is timed against 32.5 MHz: the Egret HC05,
		//                        the VIA timers, v8_clocks' 3.672 MHz Bresenham
		//                        divider (PCLK_LIM = 32500 is literally this
		//                        number), and the CPU's 8.125/16.25 MHz enables.
		//                        Do not change it without auditing all of those.
		//  outclk_3  15.662651 MHz  clk_pix — 512x384 12in RGB dot clock.
		//
		//  ALL FOUR OUTPUTS SHARE ONE VCO, so the pixel clock is not free: with
		//  65 and 32.5 MHz fixed, VCO = 65 x N and clk_pix = 65 x N / C for
		//  integer counters. Asking for a "nice" 15.666667 MHz is NOT
		//  synthesisable and the Fitter rejects it outright:
		//     Error: PLL Output Counter parameter 'output_clock_frequency' is
		//     set to an illegal value of '15.666667 MHz'
		//  Searching N gives N=20 (VCO 1300 MHz) with C=83 -> 15.662651 MHz,
		//  which is 0.008% from the 15.664 MHz ideal (640 x 407 x 60.15 Hz).
		//  Resulting frame rate 60.147 Hz. Runners-up were much worse: N=13
		//  gives 15.648 (-0.10%), N=14 gives 15.690 (+0.16%).
		//
		//  If a future change needs a pixel clock this constraint cannot reach,
		//  give it its OWN PLL — the 5CEBA4 has four and this design uses one,
		//  which is what MiSTer did with pll_video.
		// ---------------------------------------------------------------
		.output_clock_frequency0("65.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.output_clock_frequency1("65.000000 MHz"),
		// dram_clk. 3846 ps = 90deg at 65 MHz (T = 15384.6 ps).
		//
		// I briefly set this to 7692 ps (180deg) to match what MiSTer's
		// altddio_out(datain_h=0,datain_l=1) produced. That was reasoning by
		// analogy and it made things WORSE. Once the SDRAM pins were actually
		// constrained (see core_constraints.sdc) STA could finally measure it,
		// and the read path is the binding one. With phase phi:
		//
		//   read  budget = T - phi - tAC(5.9)   -> routing + setup
		//     phi=90deg : 15.38 - 3.85 - 5.9 = 5.63 ns
		//     phi=180deg: 15.38 - 7.69 - 5.9 = 1.79 ns
		//   cmd   budget = phi - output_delay(2.0)
		//     phi=90deg : 1.85 ns
		//     phi=180deg: 5.69 ns
		//
		// Every failing path was dram_dq[*] -> pocket_sdram|dout[*] (reads) at
		// -5.1 ns; no command path failed. 90deg buys the read side 3.85 ns and
		// costs the command side, which had margin to spare. The remaining read
		// deficit is attacked with FAST_INPUT_REGISTER in ap_core.qsf.
		//
		// This is now a MEASURED choice, not a guessed one -- re-check the
		// dram_dq -> dout slack in ap_core.sta.rpt after any change here.
		.phase_shift1("3846 ps"),
		.duty_cycle1(50),
		.output_clock_frequency2("32.500000 MHz"),
		.phase_shift2("0 ps"),
		.duty_cycle2(50),
		.output_clock_frequency3("15.662651 MHz"),
		.phase_shift3("0 ps"),
		.duty_cycle3(50),
		.output_clock_frequency4("0 MHz"),
		.phase_shift4("0 ps"),
		.duty_cycle4(50),
		.output_clock_frequency5("0 MHz"),
		.phase_shift5("0 ps"),
		.duty_cycle5(50),
		.output_clock_frequency6("0 MHz"),
		.phase_shift6("0 ps"),
		.duty_cycle6(50),
		.output_clock_frequency7("0 MHz"),
		.phase_shift7("0 ps"),
		.duty_cycle7(50),
		.output_clock_frequency8("0 MHz"),
		.phase_shift8("0 ps"),
		.duty_cycle8(50),
		.output_clock_frequency9("0 MHz"),
		.phase_shift9("0 ps"),
		.duty_cycle9(50),
		.output_clock_frequency10("0 MHz"),
		.phase_shift10("0 ps"),
		.duty_cycle10(50),
		.output_clock_frequency11("0 MHz"),
		.phase_shift11("0 ps"),
		.duty_cycle11(50),
		.output_clock_frequency12("0 MHz"),
		.phase_shift12("0 ps"),
		.duty_cycle12(50),
		.output_clock_frequency13("0 MHz"),
		.phase_shift13("0 ps"),
		.duty_cycle13(50),
		.output_clock_frequency14("0 MHz"),
		.phase_shift14("0 ps"),
		.duty_cycle14(50),
		.output_clock_frequency15("0 MHz"),
		.phase_shift15("0 ps"),
		.duty_cycle15(50),
		.output_clock_frequency16("0 MHz"),
		.phase_shift16("0 ps"),
		.duty_cycle16(50),
		.output_clock_frequency17("0 MHz"),
		.phase_shift17("0 ps"),
		.duty_cycle17(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst	(rst),
		.outclk	({outclk_4, outclk_3, outclk_2, outclk_1, outclk_0}),
		.locked	(locked),
		.fboutclk	( ),
		.fbclk	(1'b0),
		.refclk	(refclk)
	);
endmodule

