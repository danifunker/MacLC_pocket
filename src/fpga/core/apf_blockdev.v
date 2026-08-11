//
// apf_blockdev.v — APF data slots -> MiSTer's hps_io block-device interface
//
// WHAT THIS REPLACES
//
// On MiSTer the HPS serves 512-byte sectors to the core:
//     sd_lba[n]     sector the core wants
//     sd_rd[n]      "fetch it"          sd_wr[n]  "store it"
//     sd_ack[n]     transfer in progress
//     sd_buff_addr / sd_buff_dout / sd_buff_wr   host -> core payload
//     sd_buff_din[n]                             core -> host payload
//     img_mounted[n] / img_size                  media present + geometry
//
// The Pocket has no HPS. Instead the core ASKS the OS to move bytes:
// set target_dataslot_{id,slotoffset,bridgeaddr,length}, pulse
// target_dataslot_read (or _write), wait for _ack then _done. The payload
// lands at a BRIDGE address, so this module owns a 512-byte buffer mapped
// into the bridge window at BUF_BASE that the OS writes into directly.
//
// This follows the pattern the reference Pocket core uses (Pocket-Amiga):
// disk slots are declared `deferload`, so NOTHING is transferred at mount
// time. The OS raises dataslot_update with the slot id and size -- that event
// IS the media-change notification -- and sectors are fetched on demand.
// Contrast the ROM/floppy path in apf_bridge_loader.v, which streams a whole
// image into SDRAM and therefore fights the running CPU for memory slots.
//
// CLOCK DOMAINS. Requests originate on clk_sys (the Mac). The target command
// interface and the bridge live on clk_74a. Crossing is done with toggle
// handshakes in both directions; the sector buffer is a true dual-port RAM
// with independent clocks, so no payload byte crosses a timed path.
//
// NOT DONE YET: only the read direction is exercised by a booting Mac. The
// write path is implemented but untested on hardware -- treat save-back as
// unproven.
//
`default_nettype none

module apf_blockdev #(
	// Bridge window for the 512-byte sector buffer. Must NOT collide with
	// apf_bridge_loader's window (bridge_addr[31:30] == 2'b00 after its
	// 0xC000_0000 mask) or the interact registers at 0xF0000000.
	parameter [31:0] BUF_BASE = 32'h4000_0000
)(
	// ---- bridge / target-command side (clk_74a) --------------------------
	input  wire        clk_74a,
	input  wire        reset_n,

	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,
	output wire [31:0] bridge_rd_data,

	input  wire        dataslot_update,
	input  wire [15:0] dataslot_update_id,
	input  wire [31:0] dataslot_update_size,

	output reg         target_dataslot_read,
	output reg         target_dataslot_write,
	input  wire        target_dataslot_ack,
	input  wire        target_dataslot_done,
	input  wire [2:0]  target_dataslot_err,
	output reg  [15:0] target_dataslot_id,
	output reg  [31:0] target_dataslot_slotoffset,
	output reg  [31:0] target_dataslot_bridgeaddr,
	output reg  [31:0] target_dataslot_length,

	// Data-slot ids from data.json: the two SCSI disks, and the floppy.
	input  wire [15:0] slot0_id,
	input  wire [15:0] slot1_id,
	input  wire [15:0] slot_flp_id,

	// ---- floppy bulk load -> the machine's download port (clk_sys) -------
	// The floppy CANNOT be served on demand like the SCSI disks: rtl/floppy.v
	// fetches a word at a time (dskReadAddr/dskReadAck) paced by the GCR/MFM
	// encoder generating the bitstream, so it needs single-slot latency. An
	// OS round trip is milliseconds. The image therefore still has to live in
	// SDRAM.
	//
	// What changes versus streaming it over the bridge (apf_bridge_loader) is
	// WHO SETS THE PACE. Here the core asks for one 512-byte sector at a time
	// and only asks for the next when the previous one has been written away,
	// so the bridge is never backpressured and the CPU keeps running --
	// hot-insert is preserved. Same shape the machine already expects, so
	// mac_lc_pocket is untouched.
	output reg         dio_download,
	output reg  [7:0]  dio_index,
	output reg  [24:0] dio_addr,
	output reg  [15:0] dio_data,
	output reg         dio_wr,
	input  wire        dio_ack,
	// Hold off the floppy bulk copy until the ROM download has finished.
	// Both producers share the machine's single download port; running them
	// concurrently corrupted the ROM at cold boot.
	input  wire        flp_allow,

	// ---- core side (clk_sys), MiSTer hps_io shape ------------------------
	input  wire        clk_sys,
	input  wire [31:0] sd_lba0,
	input  wire [31:0] sd_lba1,
	input  wire [1:0]  sd_rd,
	input  wire [1:0]  sd_wr,
	output reg  [1:0]  sd_ack,
	output reg  [7:0]  sd_buff_addr,
	output reg  [15:0] sd_buff_dout,
	output reg         sd_buff_wr,
	input  wire [15:0] sd_buff_din0,
	input  wire [15:0] sd_buff_din1,
	output reg  [1:0]  img_mounted,
	// hps_io semantics: img_size is valid ON the img_mounted pulse for the
	// slot that just changed. The core latches it per slot itself.
	output reg  [31:0] img_size,

	// ---- bring-up readout (clk_74a) --------------------------------------
	// Highest point the block path has ever reached, as a monotonic stage.
	// Surfaced through the interact read-back so it can be read off the Core
	// Settings menu -- the Pocket offers no other introspection, and this
	// distinguishes "the OS never acked" from "we moved data but the target
	// rejected it" without opening the case for JTAG.
	//   0 nothing   1 mounted   2 read issued   3 ack seen
	//   4 done seen 5 sector delivered to the core
	output wire [2:0]  dbg_stage
);

	localparam integer SECTOR_BYTES = 512;
	localparam integer SECTOR_WORDS = 256;   // 16-bit words

	// ======================================================================
	// Sector buffers — TWO simple-dual-port RAMs, 128 x 32
	// ======================================================================
	// Deliberately NOT one shared true-dual-port array. Quartus rejects a reg
	// array driven from two always blocks ("Error (10028): Can't resolve
	// multiple constant drivers"), and no M10K can take two writes in one
	// cycle -- both of which the first cut of this file did, and the lint
	// pass happily accepted. See the Verilator-vs-Quartus note in
	// CLAUDE.md; this is exactly that trap.
	//
	// So: one buffer per direction, each with a single write port.
	//   rdbuf  bridge (clk_74a) writes  -> core (clk_sys) reads   [file->Mac]
	//   wrbuf  core   (clk_sys) writes  -> bridge (clk_74a) reads [Mac->file]
	//
	// 32 bits wide because the bridge moves 32 bits per access; the core side
	// picks the half it wants. bridge_endian_little is 0, so the MS half is
	// the LOWER 16-bit word offset -- same convention as apf_bridge_loader,
	// and the 68020 is big-endian, so file order survives.
	localparam integer BUF_DEPTH = SECTOR_WORDS/2;   // 128 x 32 = 512 bytes

	(* ramstyle = "M10K,no_rw_check" *) reg [31:0] rdbuf [0:BUF_DEPTH-1];
	(* ramstyle = "M10K,no_rw_check" *) reg [31:0] wrbuf [0:BUF_DEPTH-1];

	wire       buf_hit  = (bridge_addr[31:24] == BUF_BASE[31:24]);
	wire [6:0] buf_widx = bridge_addr[8:2];

	reg [31:0] wrbuf_rd_74;
always @(posedge clk_74a) begin
	if (bridge_wr && buf_hit) rdbuf[buf_widx] <= bridge_wr_data;
	wrbuf_rd_74 <= wrbuf[buf_widx];
end
assign bridge_rd_data = wrbuf_rd_74;

	reg [31:0] rdbuf_rd_sys;
	reg [6:0]  buf_addr_sys;
	reg [31:0] buf_wdata_sys;
	reg        buf_we_sys;
always @(posedge clk_sys) begin
	if (buf_we_sys) wrbuf[buf_addr_sys] <= buf_wdata_sys;
	rdbuf_rd_sys <= rdbuf[buf_addr_sys];
end

	// ======================================================================
	// Media present / size  (clk_74a -> clk_sys)
	// ======================================================================
	reg  [31:0] size0_74 = 32'd0, size1_74 = 32'd0, sizeF_74 = 32'd0;
	reg         mount_tgl0 = 1'b0, mount_tgl1 = 1'b0, mount_tglF = 1'b0;

	// dataslot_update is a multi-cycle LEVEL, not a pulse: core_bridge_cmd
	// raises it in the 0x008A handler and only clears it when its FSM returns
	// to ST_IDLE several cycles later. (The RTC handler immediately below it
	// spells out the convention: "user logic should detect rising edge, it is
	// not continuously updated.")
	//
	// Testing the level directly toggled mount_tgl* once per clk_74a cycle for
	// the whole time it was high. At 74.25 MHz into a 32.5 MHz synchroniser
	// those toggles alias, and an even count produces NO net edge -- so
	// img_mounted never pulsed and neither the SCSI disks nor the floppy were
	// ever seen. Edge-detect it.
	reg dsu_d = 1'b0;
always @(posedge clk_74a) begin
	dsu_d <= dataslot_update;

	if (!reset_n) begin
		size0_74 <= 32'd0;
		size1_74 <= 32'd0;
		sizeF_74 <= 32'd0;
	end else if (dataslot_update && !dsu_d) begin
		if (dataslot_update_id == slot_flp_id) begin
			sizeF_74   <= dataslot_update_size;
			mount_tglF <= ~mount_tglF;
		end
		// This is the insertion event. Nothing is transferred -- we are told
		// the slot's new size and fetch sectors on demand from here on.
		if (dataslot_update_id == slot0_id) begin
			size0_74   <= dataslot_update_size;
			mount_tgl0 <= ~mount_tgl0;
		end
		if (dataslot_update_id == slot1_id) begin
			size1_74   <= dataslot_update_size;
			mount_tgl1 <= ~mount_tgl1;
		end
	end
end

	reg [2:0] m0_s, m1_s, mF_s;
	reg [31:0] flp_size_sys;
	wire mnt0 = m0_s[2] ^ m0_s[1];
	wire mnt1 = m1_s[2] ^ m1_s[1];
	wire mntF = mF_s[2] ^ mF_s[1];
always @(posedge clk_sys) begin
	mF_s <= {mF_s[1:0], mount_tglF};
	flp_size_sys <= sizeF_74;
	m0_s <= {m0_s[1:0], mount_tgl0};
	m1_s <= {m1_s[1:0], mount_tgl1};
	img_mounted <= {mnt1, mnt0};
	// The size register settles many clocks before its toggle is observed
	// here, so presenting it alongside the pulse is safe.
	if      (mnt0) img_size <= size0_74;
	else if (mnt1) img_size <= size1_74;
end

	// ======================================================================
	// Request handshake  (clk_sys -> clk_74a -> clk_sys)
	// ======================================================================
	reg        req_tgl   = 1'b0;    // clk_sys: a request is posted
	reg        req_is_wr = 1'b0;
	reg        req_slot  = 1'b0;
	reg [31:0] req_lba   = 32'd0;
	reg        done_seen = 1'b0;

	reg [2:0]  done_s;
	reg        done_tgl  = 1'b0;    // clk_74a: the transfer finished

	// ---- core-side sequencer ----
	// Each buffer word takes a couple of cycles (address out, RAM latency,
	// data). 256 words is then well under 50 us at 32.5 MHz -- irrelevant
	// next to the OS's own transfer time, so the states stay explicit rather
	// than pipelined.
	localparam [3:0] C_IDLE   = 4'd0,
	                 C_FILL_A = 4'd1,   // writes: present sd_buff_addr
	                 C_FILL_B = 4'd2,   // writes: sample sd_buff_din
	                 C_REQ    = 4'd3,
	                 C_WAIT   = 4'd4,
	                 C_DRN_A  = 4'd5,   // reads: present buffer address
	                 C_DRN_W  = 4'd6,   // reads: RAM read latency
	                 C_DRN_B  = 4'd7,   // reads: drive sd_buff_*
	                 C_FIN    = 4'd8,
	                 C_FLP_A  = 4'd9,   // floppy: present buffer address
	                 C_FLP_W  = 4'd10,  // floppy: RAM read latency
	                 C_FLP_B  = 4'd11,  // floppy: emit one dio word
	                 C_FLP_K  = 4'd12;  // floppy: wait for dio_ack

	reg [3:0]  cstate = C_IDLE;
	reg [8:0]  cidx;
	reg [15:0] fill_hi;
	wire [15:0] dinw = req_slot ? sd_buff_din1 : sd_buff_din0;

	// Floppy bulk load state
	reg        req_is_flp   = 1'b0;
	reg        flp_pending  = 1'b0;   // a mount is waiting to be copied in
	reg        flp_busy     = 1'b0;
	reg [22:0] flp_sector   = 23'd0;  // 512-byte sector index into the image
	reg [31:0] flp_total    = 32'd0;  // image size in bytes
	reg [24:0] flp_byte     = 25'd0;  // running byte offset for dio_addr

always @(posedge clk_sys) begin
	sd_buff_wr <= 1'b0;
	buf_we_sys <= 1'b0;
	dio_wr     <= 1'b0;

	done_s <= {done_s[1:0], done_tgl};

	// A floppy mount kicks off a bulk copy into SDRAM. dio_download is held
	// for the whole transfer so the machine sees the same envelope it would
	// from a streamed download -- its media-change logic keys off that edge.
	if (mntF) begin
		flp_total    <= flp_size_sys;
		flp_sector   <= 23'd0;
		flp_byte     <= 25'd0;
		flp_busy     <= (flp_size_sys != 32'd0);
		dio_download <= (flp_size_sys != 32'd0);
		dio_index    <= 8'd1;
	end

	case (cstate)
	C_IDLE: begin
		sd_ack <= 2'b00;
		cidx   <= 9'd0;
		// SCSI requests take priority; a floppy bulk load is not time-critical
		// and simply resumes between them.
		if (!(sd_rd[0] | sd_rd[1] | sd_wr[0] | sd_wr[1]) && flp_busy && flp_allow) begin
			req_is_flp <= 1'b1;
			req_is_wr  <= 1'b0;
			req_lba    <= {9'd0, flp_sector};
			cstate     <= C_REQ;
		end else if (sd_rd[0] | sd_rd[1] | sd_wr[0] | sd_wr[1]) begin
			req_is_flp <= 1'b0;
			req_is_wr <= (sd_wr[0] | sd_wr[1]);
			req_slot  <= (sd_rd[1] | sd_wr[1]);
			req_lba   <= (sd_rd[1] | sd_wr[1]) ? sd_lba1 : sd_lba0;
			sd_ack    <= { (sd_rd[1] | sd_wr[1]), (sd_rd[0] | sd_wr[0]) };
			// A write must have the core's data in the buffer BEFORE the OS
			// is asked to store it.
			cstate    <= (sd_wr[0] | sd_wr[1]) ? C_FILL_A : C_REQ;
			sd_buff_addr <= 8'd0;
		end
	end

	// ---- write direction: core data -> wrbuf, a 16-bit half at a time ----
	C_FILL_A: begin
		sd_buff_addr <= cidx[7:0];
		cstate       <= C_FILL_B;
	end

	C_FILL_B: begin
		if (cidx[0]) begin
			// odd index completes a 32-bit pair
			buf_addr_sys  <= cidx[7:1];
			buf_wdata_sys <= {fill_hi, dinw};
			buf_we_sys    <= 1'b1;
		end else begin
			fill_hi <= dinw;
		end
		if (cidx == SECTOR_WORDS-1) cstate <= C_REQ;
		else begin
			cidx   <= cidx + 9'd1;
			cstate <= C_FILL_A;
		end
	end

	C_REQ: begin
		req_tgl <= ~req_tgl;
		cstate  <= C_WAIT;
	end

	C_WAIT: begin
		if (done_s[2] ^ done_s[1]) begin
			cidx <= 9'd0;
			if      (req_is_flp) cstate <= C_FLP_A;
			else if (req_is_wr)  cstate <= C_FIN;
			else                 cstate <= C_DRN_A;
		end
	end

	// ---- floppy: rdbuf -> the machine's download port ----
	C_FLP_A: begin
		buf_addr_sys <= cidx[7:1];
		cstate       <= C_FLP_W;
	end

	C_FLP_W: cstate <= C_FLP_B;      // rdbuf_rd_sys is registered

	C_FLP_B: begin
		// Byte address, +2 per 16-bit word — the convention
		// apf_bridge_loader uses and mac_lc_pocket's DC42 skip expects.
		dio_addr <= flp_byte;
		dio_data <= cidx[0] ? rdbuf_rd_sys[15:0] : rdbuf_rd_sys[31:16];
		dio_wr   <= 1'b1;
		cstate   <= C_FLP_K;
	end

	C_FLP_K: begin
		// Hold dio_wr until the machine's SDRAM slot retires the word. This
		// is the whole point of the design: the next sector is not requested
		// until the previous one is fully absorbed, so nothing can outrun the
		// bus and the CPU is never starved.
		dio_wr <= 1'b1;
		if (dio_ack) begin
			dio_wr   <= 1'b0;
			flp_byte <= flp_byte + 25'd2;
			if (cidx == SECTOR_WORDS-1) begin
				// Sector done — advance, or finish the image.
				if (((flp_sector + 23'd1) << 9) >= flp_total) begin
					flp_busy     <= 1'b0;
					dio_download <= 1'b0;
					cstate       <= C_IDLE;
				end else begin
					flp_sector <= flp_sector + 23'd1;
					cstate     <= C_IDLE;
				end
			end else begin
				cidx   <= cidx + 9'd1;
				cstate <= C_FLP_A;
			end
		end
	end

	// ---- read direction: rdbuf -> core, a 16-bit half at a time ----
	C_DRN_A: begin
		buf_addr_sys <= cidx[7:1];
		cstate       <= C_DRN_W;
	end

	C_DRN_W: cstate <= C_DRN_B;      // rdbuf_rd_sys is registered

	C_DRN_B: begin
		sd_buff_addr <= cidx[7:0];
		// Big-endian: the MS half of the 32-bit bridge word is the LOWER
		// 16-bit word offset.
		sd_buff_dout <= cidx[0] ? rdbuf_rd_sys[15:0] : rdbuf_rd_sys[31:16];
		sd_buff_wr   <= 1'b1;
		if (cidx == SECTOR_WORDS-1) cstate <= C_FIN;
		else begin
			cidx   <= cidx + 9'd1;
			cstate <= C_DRN_A;
		end
	end

	C_FIN: begin
		sd_ack <= 2'b00;
		// Hold off until the core drops its request, or we would immediately
		// re-trigger on the same sd_rd/sd_wr level.
		if (!(sd_rd[0] | sd_rd[1] | sd_wr[0] | sd_wr[1])) cstate <= C_IDLE;
	end

	default: cstate <= C_IDLE;
	endcase
end

	// ---- bridge-side target-command FSM ----
	localparam [2:0] T_IDLE = 3'd0,
	                 T_CMD  = 3'd1,
	                 T_ACK  = 3'd2,
	                 T_DONE = 3'd3;

	reg [2:0]  tstate = T_IDLE;
	reg [2:0]  req_s;
	reg        done_d  = 1'b0;
	reg [23:0] tmo     = 24'd0;   // ~226 ms at 74.25 MHz
	reg        saw_tmo = 1'b0;    // sticky: the OS failed to respond at least once

	// PROTOCOL (openfpga-PCXT src/fpga/core/softcpu_fdd_bridge.sv:233-249):
	//   * target_dataslot_read/_write is a LEVEL. Raise it and HOLD it; the
	//     host's ack is what clears it. The first cut of this file pulsed it
	//     for a single clk_74a cycle, so the host never saw the request: every
	//     SCSI read stalled with sd_ack stuck high, which on hardware looked
	//     like "the disk is never found and everything runs slowly".
	//     tb_blockdev.v reproduces that exact failure.
	//   * target_dataslot_done is consumed on its RISING EDGE, not as a level,
	//     or a done still high from the previous transfer retires the next one
	//     instantly.
	wire done_rise = target_dataslot_done & ~done_d;

always @(posedge clk_74a) begin
	req_s  <= {req_s[1:0], req_tgl};
	done_d <= target_dataslot_done;

	if (!reset_n) begin
		tstate                <= T_IDLE;
		target_dataslot_read  <= 1'b0;
		target_dataslot_write <= 1'b0;
		tmo                   <= 24'd0;
		saw_tmo               <= 1'b0;
	end else begin
		case (tstate)
		T_IDLE: begin
			if (req_s[2] ^ req_s[1]) begin
				target_dataslot_id         <= req_is_flp ? slot_flp_id
				                                         : (req_slot ? slot1_id : slot0_id);
				// req_lba is a 512-byte sector index; the OS wants a BYTE
				// offset into the file.
				target_dataslot_slotoffset <= req_lba << 9;
				target_dataslot_bridgeaddr <= BUF_BASE;
				target_dataslot_length     <= SECTOR_BYTES;
				tmo                        <= 24'd0;
				tstate                     <= T_CMD;
			end
		end

		T_CMD: begin
			// Raise and LEAVE raised — cleared by the ack in T_ACK.
			if (req_is_wr) target_dataslot_write <= 1'b1;
			else           target_dataslot_read  <= 1'b1;
			tstate <= T_ACK;
		end

		// TIMEOUTS. An FSM that waits forever on an external ack is a hang
		// waiting to happen, and this one hung: with the floppy now a
		// deferload slot, a mount starts a bulk copy at boot, and if the OS
		// does not service the target command the SHARED sequencer wedges --
		// starving SCSI as well and leaving dio_download asserted for ever.
		// ~226 ms at 74.25 MHz is far longer than any real 512-byte transfer.
		// On expiry we give up and still toggle done_tgl, so the core side is
		// released rather than stuck; dbg_stage records that it happened.
		T_ACK: begin
			tmo <= tmo + 24'd1;
			if (target_dataslot_ack) begin
				target_dataslot_read  <= 1'b0;
				target_dataslot_write <= 1'b0;
				tmo                   <= 24'd0;
				tstate                <= T_DONE;
			end else if (&tmo) begin
				target_dataslot_read  <= 1'b0;
				target_dataslot_write <= 1'b0;
				saw_tmo               <= 1'b1;
				done_tgl              <= ~done_tgl;
				tstate                <= T_IDLE;
			end
		end

		T_DONE: if (&tmo) begin
			saw_tmo  <= 1'b1;
			done_tgl <= ~done_tgl;
			tstate   <= T_IDLE;
		end else if (!done_rise) begin
			tmo <= tmo + 24'd1;
		end else if (done_rise) begin
			// target_dataslot_err is deliberately not surfaced: the SCSI
			// target has no channel for "the host could not read that
			// sector", and reporting nothing looks like a media error to the
			// guest anyway. Revisit if real errors show up.
			done_tgl <= ~done_tgl;
			tstate   <= T_IDLE;
		end

		default: tstate <= T_IDLE;
		endcase
	end
end

	// ======================================================================
	// Bring-up readout
	// ======================================================================
	// Sticky "furthest point reached" flags, each set in its own domain and
	// combined on clk_74a (where the bridge read happens). They only ever go
	// from 0 to 1, so the clk_sys -> clk_74a crossings need no handshake.
	reg saw_read_74 = 1'b0, saw_ack_74 = 1'b0, saw_done_74 = 1'b0;
always @(posedge clk_74a) begin
	if (!reset_n) begin
		saw_read_74 <= 1'b0;
		saw_ack_74  <= 1'b0;
		saw_done_74 <= 1'b0;
	end else begin
		if (target_dataslot_read || target_dataslot_write) saw_read_74 <= 1'b1;
		if (target_dataslot_ack)                           saw_ack_74  <= 1'b1;
		if (done_rise)                                     saw_done_74 <= 1'b1;
	end
end

	reg saw_mount_sys = 1'b0, saw_deliver_sys = 1'b0;
always @(posedge clk_sys) begin
	if (img_mounted != 2'b00)                    saw_mount_sys   <= 1'b1;
	if (cstate == C_FIN && !req_is_wr && !req_is_flp) saw_deliver_sys <= 1'b1;
end

	reg [1:0] mnt_s, dlv_s;
always @(posedge clk_74a) begin
	mnt_s <= {mnt_s[0], saw_mount_sys};
	dlv_s <= {dlv_s[0], saw_deliver_sys};
end

assign dbg_stage = dlv_s[1]    ? 3'd5 :
                   saw_tmo     ? 3'd6 :
                   saw_done_74 ? 3'd4 :
                   saw_ack_74  ? 3'd3 :
                   saw_read_74 ? 3'd2 :
                   mnt_s[1]    ? 3'd1 : 3'd0;

endmodule

`default_nettype wire
