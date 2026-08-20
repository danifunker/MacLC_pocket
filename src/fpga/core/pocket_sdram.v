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
// ★ 2026-08-19: this file now carries the MiSTer core's Phase-C DEMAND-START
// engine (ported from rtl/sdram.v @ branch cpu-icache, where it is
// hardware-validated — see ../MacLC_MiSTer/docs/CPU_Perf_Log.md). The 8-clk_64
// ACTIVE/CAS/capture command schedule, the reset/init ladder, CAS_LATENCY, the
// auto-precharge bit and the addr[] -> row/col/bank mapping are all unchanged
// from the slot machine; what changed is the START discipline — an access now
// begins at any idle clk_64 edge instead of only at a bus-slot boundary, which
// removes the mod-4 slot quantization that pinned every CPU memory access to
// >= 8 clk_sys. Floppy windows still run slot-aligned by construction (the
// window IS the old slot), so floppy.v and its fetch-freshness protocol see
// identical timing. Refresh is explicit now that idle slots no longer
// auto-refresh.
//
// POCKET ADAPTATIONS (unchanged from the pre-Phase-C version of this file):
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
//  5. dout_stb REMOVED (2026-08-19, with the Phase-C port). It was the ROMV
//     oracle's completion strobe (2026-08-12); the ROMV engine is retired
//     with the JTAG bring-up path, and under demand-start its free-running
//     oe protocol is meaningless anyway (CPU-class reads complete via
//     cpu_done/cpu_dout now). Recover both from git history if ever needed.
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
	// controller be linted with the rest of the design. (It also makes the
	// MiSTer tb_icache_seam TB_NO_TRISTATE pin split unnecessary here.)
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
	output reg [15:0]   dout,       // data output to chipset/cpu (floppy-window reads)
	input [23:0]        addr,       // 24 bit word address
	input [1:0]         ds,         // upper/lower data strobe
	input               oe,         // cpu/chipset requests read
	input               we,         // cpu/chipset requests write

	// ── demand-start CPU service (Phase C, ported from MiSTer cpu-icache) ──
	// oe/we + addr/din/ds form a LEVEL request (held while _cpuAS is low).
	// The sequencer starts an access at the next clk_64 edge instead of
	// waiting for a bus-slot boundary; that removes the mod-4 slot
	// quantization that pinned every CPU memory access to >=8 clk_sys
	// (../MacLC_MiSTer/docs/CPU_Perf_Log.md).
	input               flp_win,    // floppy fetch window (old slot timing): serve
	                                // `flp_addr` into `dout`, priority
	input  [23:0]       flp_addr,   // UNREGISTERED floppy address. ★ The floppy path must
	                                // NOT take the clk_sys request pipeline: floppy.v latches
	                                // its byte at busPhase 3 of the window slot, and delaying
	                                // the access by the pipeline's one tick pushes the data
	                                // capture to busPhase 0 of the NEXT slot — one tick after
	                                // the latch, so the guest receives the PREVIOUS byte and
	                                // the disk stream is corrupt (observed on hardware as
	                                // illegal-instruction / coprocessor bombs after a mount).
	                                // Bypassing is safe here: this cone is a shallow add+mux
	                                // and the encoder holds the address stable for the whole
	                                // window, unlike the deep V8 CPU translation the pipeline
	                                // exists to protect.
	input               flp_guard,  // a pending floppy window opens soon: don't START a
	                                // CPU access that would still occupy the chip then

	// ── download (image write) port ────────────────────────────────────────
	// ★★★ ROOT CAUSE of the MiSTer "mounting a floppy bombs the guest"
	// regression (2026-08-18, branch cpu-icache). The download used to ride
	// the CPU's own oe/we/addr/din nets, muxed in for the dioBusControl slot
	// (`download_cycle` — this fork had the identical mux). That was sound
	// under the OLD slot machine, where _ramOE/_ramWE were gated on
	// cpuBusControl — the exact complement of dioBusControl — so a CPU
	// request and a download write could not coexist. Phase C deleted that
	// gating to make the CPU request a LEVEL held for the whole AS-low
	// window, and the level now spans the download's slot. Two failures
	// followed, both fatal:
	//   1. While the mux pointed at the download, the CPU's request was
	//      INVISIBLE here, and the download's posted-write ack landed in
	//      `cpu_done` — which is the CPU's DTACK. When the slot ended and the
	//      CPU's still-asserted `oe` came back, `!(oe||we)` was never true, so
	//      cpu_done never cleared: the CPU completed a read it had never
	//      issued and latched the PREVIOUS access's cpu_dout. Executing that
	//      stale word is the "illegal instruction" / "coprocessor not
	//      installed" bomb seen on every floppy mount.
	//   2. In slots where the download had no write pending, oe/we were forced
	//      to 0, CLEARING a legitimate in-flight CPU cpu_done mid-access.
	// The ROM download at boot was immune only because the top holds the CPU
	// in reset while (dio_download && dio_index==0) — which is why booting
	// always worked and only mounting broke.
	// This port restores the mutual exclusion STRUCTURALLY: the download has
	// its own request, its own frozen address/data, and never writes cpu_done.
	input               dl_req,     // LEVEL: a download word is pending (= ioctl_wait)
	input               dl_slot,    // its bus slot (dioBusControl) — gating the START
	                                // here keeps the download to one word per bus
	                                // round, exactly the pre-Phase-C rate, so the
	                                // CPU/download bandwidth split is unchanged
	input  [23:0]       dl_addr,    // SDRAM word address for that word
	input  [15:0]       dl_din,     // the word
	output reg          dl_ack,     // LEVEL, not a pulse: clk_64 is 2x clk_sys, so a
	                                // one-tick pulse is not reliably sampleable over
	                                // there. Held from issue until dl_req drops, i.e.
	                                // until the clk_sys side has seen it and cleared
	                                // ioctl_wait. Keying the release on the SLOT
	                                // instead would drop the ack at the slot edge and
	                                // hang the download when the two just missed.

	output reg          cpu_done,   // request served: read data will be stable in cpu_dout
	                                // before a consumer sampling done can latch it 2 ticks
	                                // later (early-done: set at ACTIVE+3 clk_64, capture at
	                                // ACTIVE+6); for writes set at ACTIVE (posted). Holds
	                                // until the request level drops (AS release), so the
	                                // CPU glue can use it as an async DTACK directly.
	output reg [15:0]   cpu_dout    // held CPU read data (private register: floppy-window
	                                // reads land in `dout` and can no longer clobber it)
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

// The ladder counter runs at 65MHz synchronous to the 8.125 MHz chipset clock.
// It wraps from T7 to T0 on the rising edge of clk_8. Under demand-start it no
// longer schedules accesses (the sequencer below does); it still paces the
// init ladder, defines the floppy/download SLOT phase, and provides the t[0]
// parity gate for CPU starts.

localparam STATE_FIRST     = 3'd0;   // first state in cycle
localparam STATE_CMD_START = 3'd0;   // state in which a new command can be started
localparam STATE_CMD_CONT  = STATE_CMD_START  + RASCAS_DELAY; // command can be continued
localparam STATE_READ      = STATE_CMD_CONT + CAS_LATENCY + 4'd2;  // +2 for 65MHz margin (was +1)
localparam STATE_LAST      = 3'd7;  // last state in cycle

reg [2:0] t;
// Explicit power-up value: identical to Cyclone V silicon (uninitialized
// registers power up 0), but REQUIRED for 4-state simulation — an X here
// poisons the increment guard and the init ladder never counts down
// (found by verilator/modelsim_bench/tb_pocket_sdram.v, 2026-08-19).
initial t = 3'd0;
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

// Read view of the data pins.
wire [15:0] sd_data_rd = sd_data;

// ── Demand sequencer state (Phase C, ported from MiSTer cpu-icache) ──────
// One access = the same 8-clk_64 command schedule the old slot machine used
// (ACTIVE at start, READ/WRITE+auto-precharge at STATE_CMD_CONT, capture at
// STATE_READ with its empirically-margined +2) — only the START is now any
// idle clk_64 edge instead of a bus-slot boundary. Floppy windows (flp_win)
// take priority and still run slot-aligned by construction (the window IS
// the old slot), so floppy.v and its fetch-freshness protocol see identical
// timing. Refresh is explicit now that idle slots no longer auto-refresh:
// tREF needs one AUTO_REFRESH per 7.8 us (~508 clk_64); opportunistic when
// idle past REF_OPP, request-blocking past REF_FORCE. (The old design
// refreshed every idle slot — orders of magnitude more than required.)
reg [2:0]  seq;          // position within a running access (1..7; ACTIVE at start)
reg        seq_busy;
reg        src_cpu;      // running access belongs to the CPU (vs floppy or download):
                         // gates cpu_done / cpu_dout, which only the CPU may touch
// Request values frozen at ACTIVE, so an access that starts late — e.g.
// delayed behind a refresh, or a download word that had to wait out a CPU
// access — cannot see its inputs change underneath it mid-access.
reg [15:0] din_q;
reg [1:0]  ds_q;
reg [8:0]  col_q;        // {addr[22], addr[7:0]} for the CAS phase
reg        flp_served;   // this floppy window already got its access
reg        dl_served;    // this download window already got its access
reg        ref_busy;
reg [2:0]  ref_cnt;
reg [9:0]  ref_due;      // clk_64 ticks since last refresh (saturating)
// ── served_addr / cpu_rearm NOT PORTED (removed on MiSTer 2026-08-18) ──────
// They existed to re-arm a write whose `we` stayed high across two DIFFERENT
// addresses (imagined download bursts). That case cannot occur: during a
// download `we` never rides the CPU nets any more (dl_* port), and CPU writes
// always release AS between accesses — either way cpu_done clears and the
// next write starts on its own. The compare cost a 24-bit clk_sys -> clk_64
// crossing that repeatedly produced marginal HOLD violations on MiSTer.
localparam REF_OPP   = 10'd300;  // idle refresh threshold
localparam REF_FORCE = 10'd480;  // block new CPU starts, refresh first

wire req_flp   = flp_win && !flp_served;
// Download: served in its own bus slot, at most one word per window, ranked
// between the floppy window and the CPU. If a CPU access happens to straddle
// the whole window the word simply waits for the next one — dl_ack, not the
// slot edge, is what releases the loader, so no word can be silently dropped.
wire req_dl    = dl_req && dl_slot && !dl_served;
// t[0] parity gate: only start CPU accesses on clk_64 edges that coincide
// with a clk_sys edge (the free-running ladder counter t wraps at the clk_8
// boundary, so an edge evaluating an ODD t begins an even-t period = an
// integer clk_sys tick). This pins the STATE_READ capture edge to a clk_sys
// boundary, so cpu_dout -> clk_sys consumer paths are timed at a full
// 30.8 ns period by STA — no cross-clock multicycle, no half-period races.
// Costs at most one clk_64 of start latency.
wire req_cpu   = (oe || we) && !flp_win && !flp_guard && t[0]
                 && !cpu_done && (ref_due < REF_FORCE);

always @(posedge clk_64) begin
	sd_cmd <= CMD_INHIBIT;  // default: idle
	sd_oe_r <= 1'b0;        // default: release the bus

	if(reset != 0) begin
		seq_busy   <= 0;
		ref_busy   <= 0;
		ref_due    <= 0;
		cpu_done   <= 0;
		flp_served <= 0;
		dl_served  <= 0;
		dl_ack     <= 0;
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
		// normal operation (demand-start)

		// request-level bookkeeping
		if (!(oe || we)) cpu_done <= 0;    // AS released / request withdrawn
		if (!flp_win)    flp_served <= 0;
		if (!dl_req)   begin dl_served <= 0; dl_ack <= 0; end
		if (ref_due != 10'h3FF) ref_due <= ref_due + 10'd1;

		if (seq_busy) begin
			seq <= seq + 3'd1;
			// CAS phase (auto-precharge), from the values frozen at ACTIVE
			if (seq == STATE_CMD_CONT) begin
				sd_cmd <= we_latch ? CMD_WRITE : CMD_READ;
				if (we_latch) begin
					sd_dout_r <= din_q;
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
				sd_addr <= { we_latch ? ~ds_q : 2'b00, 2'b10, col_q };  // auto precharge
			end
			// early-done for CPU reads: 3 clk_64 (1.5 clk_sys) before capture.
			// The CPU bus FSM samples done, then latches din TWO clk_sys ticks
			// later (S_WAIT exit -> S_TAIL2), so cpu_dout is stable a full
			// clk_sys tick before the consumer's latch edge. Do not move done
			// earlier than STATE_CMD_CONT+1 without redoing that arithmetic.
			//
			// ★★ `&& oe` (MiSTer 2026-08-19): done may only be BORN while its
			// request level is still up. A fetch-cache HIT answers the CPU
			// early, so the FSM releases AS ~4 ticks in and ABANDONS this
			// transaction; if its ACTIVE was delayed (floppy window / download
			// / refresh occupancy) the unqualified set fired AFTER the level
			// dropped — and, being written after the `!(oe||we)` clear above,
			// it WON the same-edge conflict. The orphan done then landed
			// inside the NEXT cycle's S_WAIT sampling window: a false DTACK,
			// the CPU latching the PREVIOUS access's cpu_dout — the
			// I-cache-enable hang (same stale-done family as the oe-bridge
			// magenta bug and the download-ack floppy-mount bomb). Cache-off
			// never abandons (the FSM waits in S_WAIT for its own done), so
			// this qualifier is inert there. `oe` alone, not (oe||we): a
			// newly-risen WRITE level must not legitimise a stale READ's done.
			// Proven both ways on MiSTer by verilator/tb_icache_seam.v.
`ifdef SDRAM_NO_DONE_LEVEL_FIX
			// NEGATIVE CONTROL (TB only, never synthesised): the pre-fix set,
			// kept so a future bench can demonstrate it catches the defect
			// rather than passing vacuously.
			if (seq == STATE_CMD_CONT + 3'd1 && src_cpu && oe_latch) cpu_done <= 1;
`else
			if (seq == STATE_CMD_CONT + 3'd1 && src_cpu && oe_latch && oe) cpu_done <= 1;
`endif
			// Data ready
			if (seq == STATE_READ) begin
				if (src_cpu) begin
					if (oe_latch) cpu_dout <= sd_data_rd;
				end else begin
					dout <= sd_data_rd;   // floppy-window data (legacy consumer path)
				end
			end
			if (seq == 3'd7) seq_busy <= 0;
		end else if (ref_busy) begin
			ref_cnt <= ref_cnt + 3'd1;
			if (ref_cnt == 3'd4) ref_busy <= 0;   // 5 clk_64 = 77 ns > tRFC
		end else if (req_flp || req_dl || req_cpu) begin
			sd_cmd  <= CMD_ACTIVE;
			// Row = addr[19:8] (12 bits). The Pocket part has a 13th row
			// pin; it is held at 0, which confines us to the lower half of
			// each bank. Intentional — see the header.
			sd_addr <= req_flp ? { 1'b0, flp_addr[19:8] } :
			           req_dl  ? { 1'b0, dl_addr[19:8]  } : { 1'b0, addr[19:8] };
			sd_ba   <= req_flp ? flp_addr[21:20]          :
			           req_dl  ? dl_addr[21:20]           : addr[21:20];
			din_q   <= req_dl ? dl_din : din;
			ds_q    <= req_dl ? 2'b11  : ds;
			col_q   <= req_flp ? { flp_addr[22], flp_addr[7:0] } :
			           req_dl  ? { dl_addr[22],  dl_addr[7:0]  }
			                   : { addr[22],     addr[7:0] };
			seq      <= 3'd1;
			seq_busy <= 1;
			src_cpu  <= !req_flp && !req_dl;
			we_latch <= req_flp ? 1'b0 : req_dl ? 1'b1 : we;
			oe_latch <= req_flp ? 1'b1 : req_dl ? 1'b0 : oe;
			if (req_flp) begin
				flp_served <= 1;
			end else if (req_dl) begin
				dl_served <= 1;
				dl_ack    <= 1;          // ★ never touches cpu_done
			end else begin
				if (we) cpu_done <= 1;   // posted write: ack at ACTIVE; din/ds
				                         // stay valid (AS held) through CAS
			end
		end else if (ref_due >= REF_OPP && !flp_guard && !flp_win && !(dl_req && dl_slot)) begin
			// !flp_guard/!flp_win: a refresh started just before a floppy
			// window would push the window's capture past its end — floppy.v
			// latches on its own (post-window) enables and would read stale
			// data. The guard zone gives refresh a hard keep-out; plenty of
			// other idle edges exist (tREF needs one refresh per ~508 clk_64).
			sd_cmd   <= CMD_AUTO_REFRESH;
			ref_busy <= 1;
			ref_cnt  <= 0;
			ref_due  <= 0;
		end
	end
end

endmodule
