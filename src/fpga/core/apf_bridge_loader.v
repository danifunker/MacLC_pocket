// ============================================================================
// apf_bridge_loader.v — Analogue Pocket data slots -> the Mac core's download
// stream.
//
// WHAT THIS REPLACES
//
// On MiSTer, hps_io hands the core a download stream:
//     dio_download   high while a file is streaming
//     dio_index      which slot/file (0 = ROM, 1 = floppy 1, 2 = floppy 2)
//     ioctl_addr     byte offset within the file
//     ioctl_data     16-bit payload
//     ioctl_wait     backpressure from the core
// MacLC.sv turns that into SDRAM writes at a per-slot base address.
//
// On the Pocket there is no HPS. The Analogue OS pushes a slot's contents at
// the core over the BRIDGE: 32-bit writes, synchronous to clk_74a, with
// bridge_addr in whatever window the core told the OS to use (via the
// dataslot's bridge address in data.json). This module decodes that window and
// re-creates the MiSTer-shaped stream so the Mac side is unchanged.
//
// SHAPE OF THE APF SIDE
//   - Writes are 32-bit and BIG-ENDIAN over the wire when
//     bridge_endian_little = 0, which is what core_top sets. Each bridge word
//     therefore carries two 16-bit Mac words, most significant first.
//   - The OS writes sequential addresses but makes no guarantee about gaps or
//     ordering across slots, so the byte offset is taken from bridge_addr
//     rather than from an internal counter.
//   - bridge_wr is a single-cycle strobe in the clk_74a domain.
//
// CLOCK CROSSING
//   The bridge runs on clk_74a; the Mac core and its SDRAM arbiter run on
//   clk_sys (32.5 MHz). Each 32-bit bridge write becomes two 16-bit core
//   writes, so the peak core-side rate is 2 words per bridge write. A small
//   FIFO absorbs the crossing and the SDRAM arbitration stall (the download
//   only gets the bus on dioBusControl slots). `busy` backpressures the OS the
//   same way ioctl_wait did on MiSTer.
//
// WHY A FIFO AND NOT A HANDSHAKE PER WORD
//   The download shares the SDRAM with the running CPU and gets one slot per
//   bus cycle. Without buffering, every bridge write would stall until its
//   slot came round, and the Analogue OS's loader would crawl. 512 entries is
//   ~1 KB of buffer — one M10K — and covers the worst-case arbitration gap.
// ============================================================================

`default_nettype none

module apf_bridge_loader #(
	// Bridge address window this loader claims. Must match the addresses
	// declared for the slots in data.json.
	parameter [31:0] ADDR_BASE = 32'h1000_0000,
	parameter [31:0] ADDR_MASK = 32'hF000_0000
)(
	// ---- APF bridge side (clk_74a) ----
	input  wire        clk_74a,
	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,

	// Slot selection. The Analogue OS tells the core which slot is being
	// written via dataslot_requestwrite before the data arrives; core_top
	// latches the id and presents it here.
	input  wire [15:0] slot_id,
	input  wire        slot_active,   // a write session is in progress

	// ---- Core side (clk_sys) ----
	input  wire        clk_sys,
	input  wire        reset,

	output reg         dio_download,  // high while a file is streaming
	output reg  [7:0]  dio_index,     // 0 = ROM, 1 = floppy
	output wire [24:0] dio_addr,      // BYTE offset within the file
	output wire [15:0] dio_data,      // 16-bit payload, core byte order
	output wire        dio_wr,        // 1-cycle write strobe
	input  wire        dio_ack,       // core consumed the word

	output wire        busy           // backpressure to the OS
);

	// ------------------------------------------------------------------
	// Bridge-side capture
	// ------------------------------------------------------------------
	wire in_window = ((bridge_addr & ADDR_MASK) == (ADDR_BASE & ADDR_MASK));
	wire accept    = bridge_wr && in_window && slot_active;

	// Each 32-bit bridge write = two 16-bit core words. Byte offset of the
	// FIRST of the pair is bridge_addr masked to the window.
	wire [24:0] wr_byte_addr = bridge_addr[24:0] & ~ADDR_MASK[24:0];

	// FIFO entry: {byte_addr[24:0], data[15:0]} = 41 bits, two per bridge write.
	localparam integer FIFO_AW = 9;                 // 512 entries
	localparam integer FIFO_DW = 25 + 16;

	(* ramstyle = "M10K,no_rw_check" *)
	reg [FIFO_DW-1:0] fifo [0:(1<<FIFO_AW)-1];

	reg [FIFO_AW:0] wptr_74;    // extra bit for full/empty disambiguation
	reg [FIFO_AW:0] rptr_sys;

	// Two-phase write: a bridge write pushes the high half then the low half.
	reg             pend;       // low half still to push
	reg [24:0]      pend_addr;
	reg [15:0]      pend_data;

	always @(posedge clk_74a) begin
		if (!slot_active) begin
			// A fresh session always starts from an empty pending slot; the
			// pointers themselves are reset from the core side.
			pend <= 1'b0;
		end else if (pend) begin
			fifo[wptr_74[FIFO_AW-1:0]] <= {pend_addr, pend_data};
			wptr_74 <= wptr_74 + 1'b1;
			pend    <= 1'b0;
		end else if (accept) begin
			// High half first (big-endian bridge => most significant 16 bits
			// are the LOWER file offset).
			fifo[wptr_74[FIFO_AW-1:0]] <= {wr_byte_addr, bridge_wr_data[31:16]};
			wptr_74   <= wptr_74 + 1'b1;
			pend      <= 1'b1;
			pend_addr <= wr_byte_addr + 25'd2;
			pend_data <= bridge_wr_data[15:0];
		end
	end

	// ------------------------------------------------------------------
	// Pointer CDC (Gray code both ways)
	// ------------------------------------------------------------------
	function [FIFO_AW:0] bin2gray;
		input [FIFO_AW:0] b;
		begin bin2gray = b ^ (b >> 1); end
	endfunction

	function [FIFO_AW:0] gray2bin;
		input [FIFO_AW:0] g;
		integer i;
		begin
			gray2bin[FIFO_AW] = g[FIFO_AW];
			for (i = FIFO_AW-1; i >= 0; i = i - 1)
				gray2bin[i] = gray2bin[i+1] ^ g[i];
		end
	endfunction

	reg [FIFO_AW:0] wptr_gray_74;
	always @(posedge clk_74a) wptr_gray_74 <= bin2gray(wptr_74);

	reg [FIFO_AW:0] wptr_gray_s1, wptr_gray_s2;
	always @(posedge clk_sys) begin
		wptr_gray_s1 <= wptr_gray_74;
		wptr_gray_s2 <= wptr_gray_s1;
	end
	wire [FIFO_AW:0] wptr_sys = gray2bin(wptr_gray_s2);

	reg [FIFO_AW:0] rptr_gray_sys;
	always @(posedge clk_sys) rptr_gray_sys <= bin2gray(rptr_sys);

	reg [FIFO_AW:0] rptr_gray_b1, rptr_gray_b2;
	always @(posedge clk_74a) begin
		rptr_gray_b1 <= rptr_gray_sys;
		rptr_gray_b2 <= rptr_gray_b1;
	end
	wire [FIFO_AW:0] rptr_74 = gray2bin(rptr_gray_b2);

	// Full when the pointers differ only in the wrap bit. Leave 2 entries of
	// headroom so the pending low half always has somewhere to go.
	wire [FIFO_AW:0] level_74 = wptr_74 - rptr_74;
	assign busy = (level_74 >= ((1<<FIFO_AW) - 4)) || pend;

	// ------------------------------------------------------------------
	// Core-side pop
	// ------------------------------------------------------------------
	wire empty = (rptr_sys == wptr_sys);

	reg [FIFO_DW-1:0] rd_data;
	always @(posedge clk_sys) rd_data <= fifo[rptr_sys[FIFO_AW-1:0]];

	// One-deep output register so dio_data/dio_addr are stable while the
	// SDRAM arbiter waits for a download slot.
	reg valid;
	always @(posedge clk_sys) begin
		if (reset) begin
			rptr_sys <= 0;
			valid    <= 1'b0;
		end else begin
			if (!valid && !empty) begin
				// rd_data is registered, so it is the entry at rptr_sys as of
				// this cycle; advance and mark valid for the NEXT cycle.
				rptr_sys <= rptr_sys + 1'b1;
				valid    <= 1'b1;
			end else if (valid && dio_ack) begin
				valid <= 1'b0;
			end
		end
	end

	assign dio_addr = rd_data[FIFO_DW-1:16];
	assign dio_data = rd_data[15:0];
	assign dio_wr   = valid;

	// ------------------------------------------------------------------
	// Download framing
	// ------------------------------------------------------------------
	// dio_download must stay high until the last queued word has actually
	// reached SDRAM, not merely until the OS stops writing — the Mac's reset
	// hold and the floppy media-change logic both key off its falling edge.
	reg slot_active_s1, slot_active_s2;
	always @(posedge clk_sys) begin
		slot_active_s1 <= slot_active;
		slot_active_s2 <= slot_active_s1;
	end

	reg [15:0] slot_id_s1, slot_id_s2;
	always @(posedge clk_sys) begin
		slot_id_s1 <= slot_id;
		slot_id_s2 <= slot_id_s1;
	end

	always @(posedge clk_sys) begin
		if (reset) begin
			dio_download <= 1'b0;
			dio_index    <= 8'd0;
		end else begin
			if (slot_active_s2) begin
				dio_download <= 1'b1;
				dio_index    <= slot_id_s2[7:0];
			end else if (empty && !valid) begin
				dio_download <= 1'b0;
			end
		end
	end

endmodule

`default_nettype wire
