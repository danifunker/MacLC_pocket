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
		// dram_clk. 5769 ps = 135deg at 65 MHz (T = 15384.6 ps).
		//
		// History: 7692 ps (180deg) was tried by analogy with MiSTer's
		// altddio_out(datain_h=0,datain_l=1) and was worse; 3846 ps (90deg)
		// replaced it and held until 2026-08-10.
		//
		// ★ 90deg was over-corrected. The budget arithmetic that chose it
		// ("read budget = T - phi - tAC = 5.63 ns, cmd budget = phi - 2.0 =
		// 1.85 ns") counted only the SDC delay numbers and ignored the FPGA's
		// own clock-to-out plus routing, so it read 1.85 ns as MARGIN when it
		// is the entire BUDGET. What the design actually consumes leaves a
		// tenth of it. Measured on the 18.1.0/625 fit, slow 1100mV 85C, with
		// get_timing_paths (not the .sta.summary, which reports per-CLOCK-
		// DOMAIN worsts and hides the interface paths inside general[0]):
		//
		//   phi = 90deg (3846 ps)
		//     READ   dram_dq[*] -> pocket_sdram|dout[*]  setup +9.21  hold +12.57
		//     WRITE  sd_oe_r    -> dram_dq[10]           setup +0.107 hold  +8.40
		//     ...and all TWELVE worst setup paths in the whole design were
		//     SDRAM writes/commands (sd_oe_r/sd_dout_r/sd_addr/sd_cmd).
		//
		// So the reads the 90deg choice was protecting had 9.2 ns to spare
		// while the write side ran on 107 ps. Both directions trade against
		// phase 1:1, so move ~1.9 ns from the fat side to the starving one:
		//
		//   phi = 135deg (5769 ps), predicted
		//     READ   setup ~+7.29   hold ~+14.5
		//     WRITE  setup ~+2.03   hold  ~+6.48
		//
		// A marginal WRITE path is the natural suspect for the cold-boot
		// symptom (ROM streamed into SDRAM, then chimes of death / black /
		// grey at random, independent of 2MB-vs-10MB and of whether a floppy
		// is mounted) -- a few corrupted words in a freshly written ROM fail
		// its POST checksum, and re-loading boot.rom rewrites them.
		//
		// MEASURED, not guessed. After ANY change here re-run:
		//   get_timing_paths -setup -from [get_ports {dram_dq[*]}]   (reads)
		//   get_timing_paths -setup -to   [get_ports {dram_*}]       (writes)
		// and keep BOTH directions positive with real margin. Do not trust
		// ap_core.sta.summary alone for this interface.
		// ★ 2026-08-11: 5769 ps (135deg) -> 7692 ps (180deg).
		//
		// EVIDENCE, not analogy this time. Three independent lines agree:
		//
		//  1. dave18/MemTest_Pocket -- a core whose ENTIRE PURPOSE is validating
		//     SDRAM on Pocket hardware, and which states it "still uses the SDRAM
		//     interface designed for the MiSTer" (same controller lineage as
		//     pocket_sdram.v) -- keeps MiSTer's altddio_out clock generator:
		//         altddio_out(.datain_h(1'b0), .datain_l(1'b1), .outclock(clk))
		//     datain_h=0 / datain_l=1 emits the INVERSE of the controller clock,
		//     i.e. exactly 180deg, generated in the IO cell so it is tightly
		//     matched to the data outputs (clocked by the same clk). Its SDC
		//     carries NO sdram timing constraints at all and it still works.
		//     This controller was designed around a 180deg clock; the Pocket port
		//     deleted the altddio_out (see pocket_sdram.v header, change #2) and
		//     substituted a PLL tap, but did not move the phase to match.
		//  2. Pocket-Amiga drives its SDRAM clock at 6573/5634 ps of a 7512 ps
		//     period = 315deg / 270deg -- also far later than 135deg.
		//  3. Our own measurements: at 135deg the margins are lopsided 5:1,
		//     write setup +2.03 ns against read setup +9.93 ns, and CPU-driven
		//     WRITES are the one path nothing has verified. 180deg spends ~1.9 ns
		//     of surplus read margin on the weak side: predicted write ~+3.95,
		//     read ~+8.0, both healthy.
		//
		// PORT_STATUS.md records 180deg being tried and "made things worse" --
		// but that verdict came from arithmetic that counted only the SDC delays
		// and IGNORED FPGA clock-to-out, the same error that made 90deg look
		// right. Re-measure dram_dq->dout and sd_oe_r->dram_dq after this.
		// ★★ 2026-08-12: 7692 ps (180deg) -> BACK to 5769 ps (135deg). HARDWARE
		// VERDICT, overriding the STA argument above. Every build that ever
		// reached the "?" floppy screen (via the reload-ROM workaround) ran at
		// 135deg. The first reload-workaround test after the 180deg change
		// ("major regression... only unhappy mac sounds") failed, and the
		// 18:48 revert build -- which kept ONLY 180deg + BIST + serialCTS of
		// the evening's changes -- still failed the same way: death chimes
		// (POST RAM-test failure) with occasional happy chimes. That is the
		// signature of marginal SDRAM, at the exact phase the docs already
		// recorded as "tried and worse".
		//
		// Why STA said 180deg was healthy (+3.95 write / +8.99 read) while
		// hardware disagreed: the set_input_delay/set_output_delay numbers in
		// core_constraints.sdc were copied from Pocket-Amiga ("board+chip
		// properties, carry over unchanged"). If those delays are off for THIS
		// board+chip, the model optimises toward the wrong phase while
		// reporting comfortable margins. Treat the SDC model as relative
		// guidance only; the reload-to-"?" test is the ground truth for this
		// interface. Do not move this phase again without a hardware A/B.
		.phase_shift1("5769 ps"),
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

