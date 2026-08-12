//
// pocket_sdram.v
//
// SDRAM controller for the Analogue Pocket, adapted from rtl/sdram.v
// (Till Harbaum's MiST controller, as carried by the MacLC MiSTer core).
//
// Copyright (c) 2015 Till Harbaum <till@harbaum.org>
// Pocket adaptation 2026.
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// ===========================================================================
// WHAT CHANGED FROM rtl/sdram.v, AND WHAT DELIBERATELY DID NOT
//
// DID NOT CHANGE — the cycle state machine, the reset/init ladder, the RAS/CAS
// timing, CAS_LATENCY, the auto-precharge bit, or the addr[] -> row/col/bank
// mapping. That machine is the thing the whole Mac core's memory timing was
// validated against (one access per 8.125 MHz chipset cycle, 8 clk_mem states
// per cycle, resynchronised on clk_8). Reproducing it byte-for-byte means the
// floppy fetch cadence, the CPU bus latency and the video path all behave
// exactly as they did on the DE10-Nano.
//
// CHANGED:
//  1. The chip. MiSTer's module was written for an MT48LC16M16 (16M x16, 4 MB
//     x 4 banks, 13 addr pins, 9 column bits). The Pocket carries a 512 Mbit
//     x16 part (32M x16 = 64 MB) with 13 row bits and 10 column bits.
//     We deliberately drive it as a SUBSET: 12 row bits, 9 column bits, 2 bank
//     bits = 8M words = 16 MB addressable. The Mac's whole word space is under
//     8 MB (see the memory map below), so the extra capacity buys nothing and
//     using it would mean re-deriving the address mux. Unused high row/column
//     pins are held at 0.
//  2. The clock output. The MiSTer version generated sd_clk from an
//     altddio_out inside the module. Here dram_clk is driven at the top level
//     from a phase-shifted PLL output (clk_mem_90), which is the openFPGA
//     house style and lets the shift be retuned on hardware without editing
//     the controller. The altddio_out instance is therefore gone.
//  3. CKE. The Pocket's dram_cke is a real pin and must be driven high; the
//     MiSTer SDRAM module had it strapped on the board.
//  4. The data bus. dram_dq is an inout at core_top and is passed straight
//     through, same as MiSTer's sd_data.
//
// MEMORY MAP (word addresses — inherited from addrController_top.v, unchanged):
//     $000000..$0FFFFF   motherboard RAM (2 MB)
//     $100000..$4FFFFF   SIMM RAM (up to 8 MB)
//     $500000..$50FFFF   ROM image (512 KB)
//     $580000..           VRAM shadow (CPU-side; video reads on-chip BRAM)
//     $600000..           internal floppy image
//     ($700000 was the external floppy image — freed by the Pocket 1-drive cut)
// ===========================================================================

module pocket_sdram
(
	// interface to the Pocket's SDRAM chip
	//
	// The data bus is driven by a CONTINUOUS assign from a registered value +
	// output enable, rather than the procedural `sd_data <= 16'bZ` the MiSTer
	// original used inside its clocked block. Same hardware, but Verilator
	// rejects the procedural form ("Unsupported tristate construct: ASSIGNDLY"),
	// which is why the MiSTer Makefile could never lint or simulate its SDRAM
	// controller and substituted sim_ram instead. This form lets the real
	// controller be linted with the rest of the design.
	inout      [15:0]   sd_data,    // 16 bit bidirectional data bus  (dram_dq)
	output reg [12:0]   sd_addr,    // 13 bit multiplexed address bus (dram_a)
	output     [1:0]    sd_dqm,     // two byte masks                 (dram_dqm)
	output reg [1:0]    sd_ba,      // bank select                    (dram_ba)
	output              sd_cke,     // clock enable                   (dram_cke)
	output              sd_we,      // write enable                   (dram_we_n)
	output              sd_ras,     // row address select             (dram_ras_n)
	output              sd_cas,     // column address select          (dram_cas_n)

	// cpu/chipset interface
	input               init,       // init signal after FPGA config to initialize RAM
	input               clk_64,     // sdram is accessed at 65MHz (clk_mem)
	input               clk_8,      // 8.125MHz chipset clock the state machine tracks

	input [15:0]        din,        // data input from chipset/cpu
	output reg [15:0]   dout,       // data output to chipset/cpu
	input [23:0]        addr,       // 24 bit word address
	input [1:0]         ds,         // upper/lower data strobe
	input               oe,         // cpu/chipset requests read
	input               we,         // cpu/chipset requests write
	// ★ 2026-08-11: the JEDEC init ladder below (1023 chipset cycles of NOPs,
	// then PRECHARGE / 8x AUTO REFRESH / LOAD MODE, ~126 us) runs entirely
	// inside this module and NOTHING outside knew when it finished. During it
	// the state machine ignores oe/we completely, so every write is silently
	// discarded. The ROM download starts as soon as the Analogue OS is ready,
	// which on a cold boot is inside that window -- so the first words of
	// boot0.rom went nowhere while every counter upstream reported success.
	// Reloading the ROM later, with the ladder long since done, stored it
	// properly and the machine booted. Hence "it takes two or three ROM loads".
	output              sdram_ready // init ladder complete; writes will stick
);

localparam RASCAS_DELAY   = 3'd2;   // tRCD=20ns -> 3 cycles@65MHz
localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd2;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

// The Pocket's SDRAM has no separate chip-select strobe exposed as an
// independent core signal in the APF pinout — CS is board-tied. The command
// encodings below therefore keep their 4-bit shape (so the ladder is
// unchanged and diffable against rtl/sdram.v) and only RAS/CAS/WE leave the
// module; sd_cmd[3] (the CS bit) is dropped on the floor.
//
// CKE is held high once out of reset. Holding it high through the init ladder
// is correct: the JEDEC sequence wants a stable clock and CKE high during the
// 100 us NOP wait.
assign sd_cke = 1'b1;


// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

// The state machine runs at 65MHz synchronous to the 8.125 MHz chipset clock.
// It wraps from T7 to T0 on the rising edge of clk_8.

localparam STATE_FIRST     = 3'd0;   // first state in cycle
localparam STATE_CMD_START = 3'd0;   // state in which a new command can be started
localparam STATE_CMD_CONT  = STATE_CMD_START  + RASCAS_DELAY; // command can be continued
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 4'd2;  // +2 for 65MHz margin (was +1)
localparam STATE_LAST      = 3'd7;  // last state in cycle

reg [2:0] t;
always @(posedge clk_64) begin
	// 65MHz counter synchronous to 8.125 MHz clock
	// force counter to pass state 0 exactly after the rising edge of clk_8
	if(((t == STATE_LAST)  && ( clk_8 == 0)) ||
		((t == STATE_FIRST) && ( clk_8 == 1)) ||
		((t != STATE_LAST) && (t != STATE_FIRST)))
			t <= t + 3'd1;
end

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// JEDEC SDR-SDRAM init: ~118us of NOPs after the clock starts (the chip
// wants 100us of stable clock before the first command — the FPGA was just
// reconfigured, so the SDRAM clock was dead/floating until now), then
// PRECHARGE ALL -> 8x AUTO REFRESH -> LOAD MODE. The previous sequence
// (31 chipset cycles ~4us, ZERO refreshes; its "wait 1ms" comment was wrong)
// relied on the chip state the PREVIOUS core left behind; whether the mode
// register write took was per-load luck — suspected cause of the cold-load
// flakiness that clears after loading a different core first.
// The ladder is content-preserving (NOPs/refreshes/MRS only), so it is also
// safe to re-run via `init` on a warm user reset while the ROM is in SDRAM.
reg [9:0] reset;
always @(posedge clk_64) begin
	if(init)	reset <= 10'h3ff;
	else if((t == STATE_LAST) && (reset != 0))
		reset <= reset - 10'd1;
end

initial reset = 10'h3FF;

assign sdram_ready = (reset == 10'd0);

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [3:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];
assign sd_dqm = sd_addr[12:11];

reg oe_latch, we_latch;

// Registered data-bus driver + output enable (see the sd_data port comment).
reg [15:0] sd_dout_r;
reg        sd_oe_r;
assign sd_data = sd_oe_r ? sd_dout_r : 16'bZZZZZZZZZZZZZZZZ;

always @(posedge clk_64) begin
	sd_cmd <= CMD_INHIBIT;  // default: idle
	sd_oe_r <= 1'b0;        // default: release the bus

	if(reset != 0) begin
		// init ladder, one command slot per chipset cycle (~123ns apart):
		// 1023..65 = NOP wait, 64 = PRECHARGE ALL, 56/52/../28 = 8x AUTO
		// REFRESH, 2 = LOAD MODE. tRP/tRFC/tMRD are all satisfied by orders
		// of magnitude at this spacing.
		if(t == STATE_CMD_START) begin

			if(reset == 64) begin
				sd_cmd <= CMD_PRECHARGE;
				sd_addr[10] <= 1'b1;      // precharge all banks
			end

			if(reset >= 28 && reset <= 56 && reset[1:0] == 2'b00)
				sd_cmd <= CMD_AUTO_REFRESH;

			if(reset == 2) begin
				sd_cmd <= CMD_LOAD_MODE;
				sd_addr <= MODE;
			end

		end
	end else begin
		// normal operation

		// RAS phase
		// -------------------  cpu/chipset read/write ----------------------
		if(t == STATE_CMD_START) begin
			{oe_latch, we_latch} <= {oe, we};
			if (we || oe) begin
				sd_cmd <= CMD_ACTIVE;
				// Row = addr[19:8] (12 bits). The Pocket part has a 13th row
				// pin; it is held at 0, which confines us to the lower half of
				// each bank. Intentional — see the header.
				sd_addr <= { 1'b0, addr[19:8] };
				sd_ba <= addr[21:20];
			// ------------------------ no access --------------------------
			end else begin
				sd_cmd <= CMD_AUTO_REFRESH;
			end
		end

		// CAS phase
		if(t == STATE_CMD_CONT && (we_latch || oe_latch)) begin
			sd_cmd <= we_latch?CMD_WRITE:CMD_READ;
			if (we_latch) begin
				sd_dout_r <= din;
				sd_oe_r   <= 1'b1;
			end
			// always return both bytes in a read. The cpu may not
			// need it, but the caches need to be able to store everything
			//
			// Column field layout (unchanged from rtl/sdram.v):
			//   [12:11] = DQM (write byte mask / 00 on read)
			//   [10]    = 1  -> auto precharge
			//   [9]     = 0  -> the Pocket part's 10th column bit, held low
			//   [8]     = addr[22]
			//   [7:0]   = addr[7:0]
			sd_addr <= { we_latch ? ~ds : 2'b00, 2'b10, addr[22], addr[7:0] };  // auto precharge
		end

		// Data ready
		if (t == STATE_READ && oe_latch) dout <= sd_data;

	end
end

endmodule
