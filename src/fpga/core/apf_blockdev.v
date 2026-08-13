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

	// ---- PRAM (NVRAM) persistence ----------------------------------------
	// The Egret's 256-byte PRAM is the Mac's NVRAM: boot device, video depth,
	// sound volume, the RTC seed. It is initialised from rtl/egret/egret.pram
	// at FPGA configuration, so the machine always boots with a VALID PRAM --
	// but without this path every power-up starts from that same image and the
	// guest's settings never survive. MiSTer persists it to an hps_io save
	// slot; the Pocket equivalent is a nonvolatile data slot moved with the
	// same target_dataslot machinery the SCSI path already uses.
	//
	// ORDERING IS LOAD-BEARING. egret_wrapper copies pram[] into the HC05's
	// working RAM exactly once, gated on `pram_ready` (its line ~767), and
	// holds the 68020 in reset until that copy completes
	// (reset_680x0 = reset_680x0_latched | ~pram_loaded). So every
	// pram_load_wr MUST land before pram_ready rises. pram_loaded below is
	// that permission signal, and it is raised on success OR on failure --
	// a missing/unreadable save slot must never wedge the boot.
	input  wire [15:0] slot_pram_id,
	input  wire        pram_save_req,   // clk_sys: rising edge = flush to card
	output reg  [7:0]  pram_load_addr,
	output reg  [7:0]  pram_load_data,
	output reg         pram_load_wr,
	output reg  [7:0]  pram_save_addr,
	input  wire [7:0]  pram_save_data,
	output reg         pram_loaded,     // load attempt finished (ok or failed)

	// ---- bring-up readout (clk_74a) --------------------------------------
	// Highest point the block path has ever reached, as a monotonic stage.
	// Surfaced through the interact read-back so it can be read off the Core
	// Settings menu -- the Pocket offers no other introspection, and this
	// distinguishes "the OS never acked" from "we moved data but the target
	// rejected it" without opening the case for JTAG.
	//   0 nothing   1 mounted   2 read issued   3 ack seen
	//   4 done seen 5 sector delivered to the core
	output wire [2:0]  dbg_stage,
	// Core-side FSM state, for the JTAG probe deck. A PRAM load that never
	// resolves parks this somewhere identifiable instead of leaving us to
	// guess (C_REQ=3 waiting to issue, C_WAIT=4 waiting on the OS, C_PV_*=16-18
	// validating, C_PR_*=13-15 copying into the Egret).
	output wire [4:0]  dbg_cstate,
	// ★ 2026-08-12 (buildX): the whole SCSI-serving story in one JTAG word —
	// dbg_stage is bridge-readable only, which is useless when the question
	// IS the bridge. [31] saw_tmo (OS failed to answer), [30] read raised,
	// [29] acked, [28] done, [27] sector delivered to the machine,
	// [26] mount seen, [25:23] mount count, [22:0] img_size[31:9] (512-byte
	// block count of the LAST mount; 0 here = the OS sent no/zero size).
	output wire [31:0] dbg_bdst,
	// ★ buildY: the direct eye on served data. BDW0 = first two 16-bit words
	// of the LAST read sector as handed to scsi.v (block 0 of a partitioned
	// Apple disk must read 4552 0200 = "ER",512). BDLB = {deliveries[7:0],
	// last requested LBA[23:0]}.
	output wire [31:0] dbg_bdw0,
	output wire [31:0] dbg_bdlb
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
	// ★ 2026-08-12 (buildY): the update latch must NOT be gated on reset_n.
	// Analogue OS announces named deferload slots (data.json "filename") at
	// core launch — potentially within the pll_core_locked_s settling window.
	// The old `if (!reset_n) ... else if (edge)` arm DISCARDED any
	// announcement landing in that window, which is why auto-mount never
	// worked while manual OSD mounts (minutes after lock) always did. Same
	// defect family as the eaten power-up PRAM request (buildW). The sizes
	// initialize to 0 by declaration; nothing needs a reset arm here.
	reg dsu_d = 1'b0;
always @(posedge clk_74a) begin
	dsu_d <= dataslot_update;

	if (dataslot_update && !dsu_d) begin
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
	localparam [4:0] C_IDLE   = 5'd0,
	                 C_FILL_A = 5'd1,   // writes: present sd_buff_addr
	                 C_FILL_B = 5'd2,   // writes: sample sd_buff_din
	                 C_REQ    = 5'd3,
	                 C_WAIT   = 5'd4,
	                 C_DRN_A  = 5'd5,   // reads: present buffer address
	                 C_DRN_W  = 5'd6,   // reads: RAM read latency
	                 C_DRN_B  = 5'd7,   // reads: drive sd_buff_*
	                 C_FIN    = 5'd8,
	                 C_FLP_A  = 5'd9,   // floppy: present buffer address
	                 C_FLP_W  = 5'd10,  // floppy: RAM read latency
	                 C_FLP_B  = 5'd11,  // floppy: emit one dio word
	                 C_FLP_K  = 5'd12,  // floppy: wait for dio_ack
	                 C_PR_A   = 5'd13,  // PRAM load: present rdbuf address
	                 C_PR_W   = 5'd14,  // PRAM load: RAM read latency
	                 C_PR_B   = 5'd15,  // PRAM load: emit 4 bytes to the Egret
	                 C_PV_A   = 5'd16,  // PRAM validate: present rdbuf address
	                 C_PV_W   = 5'd17,  // PRAM validate: RAM read latency
	                 C_PV_B   = 5'd18;  // PRAM validate: accumulate blankness

	// PRAM save states live in a second small FSM (below) so the 4-bit cstate
	// encoding above stays as-is and the SCSI/floppy paths are untouched.
	reg [4:0]  cstate = C_IDLE;
	assign dbg_cstate = cstate;
	reg [8:0]  cidx;
	reg [15:0] fill_hi;
	wire [15:0] dinw = req_slot ? sd_buff_din1 : sd_buff_din0;
	// ★★ 2026-08-12 (buildAA): sd_buff words are LITTLE-endian — byte0 in the
	// LOW half. That is the real-HPS convention scsi.v is built for
	// (scsi.v:181-183; its VERILATOR branch is byte0-high, which is what
	// misled every code read here). This module's first cut packed the
	// sd_buff face big-endian like its bridge/dio faces, so every byte pair
	// reached the Mac swapped: captured on hardware as the CPU receiving
	// 52 45 ("RE") for block 0's 45 52 ("ER") — DDM parse survived word reads
	// only by luck of what the ROM checks, and the Driver43 image failed its
	// checksum every round. dinw_le/the drain swap below convert both
	// directions at this face ONLY — the bridge/dio/PRAM faces stay
	// big-endian (file order) as before.
	wire [15:0] dinw_le = { dinw[7:0], dinw[15:8] };

	// ---- PRAM sequencing ---------------------------------------------------
	// 256 bytes = 64 x 32-bit buffer words. Bridge byte order is big-endian
	// (byte 0 arrives in [31:24]), so word w carries PRAM bytes 4w..4w+3 from
	// the top down -- same convention as the sector path.
	localparam integer PRAM_BYTES = 256;
	localparam integer PRAM_WORDS = PRAM_BYTES/4;   // 64
	reg        req_is_pram  = 1'b0;
	// ★ 2026-08-12 (buildW): PRAM power-up read DISARMED. Slot 220 no longer
	// exists in data.json (removed with the PRAM slot after it corrupted the
	// ROM), but this request still fired at config time — so early that the
	// clk_74a host FSM was still in reset (pll_core_locked_s not yet high):
	// the req toggle was consumed while tstate was held in T_IDLE, no
	// transfer and no timeout ever ran (the 226 ms bailouts only tick in
	// T_ACK/T_DONE), and the sequencer sat in C_WAIT forever. Every SCSI
	// sector read then starved behind it: media mounted, "?" cleared, zero
	// sectors ever served, machine parked at the ROM's grey screen + cursor.
	// pram_loaded initializes to 1 so the boot proceeds on the built-in
	// egret.pram defaults immediately (same no-writes-then-ready contract the
	// ~1 s backstop exercised while the load never resolved).
	// If PRAM persistence ever returns: re-arm this AND make the request
	// re-issuable/level-based so a pre-lock issue cannot be eaten.
	reg        pram_rd_todo = 1'b0;   // was 1'b1: load once, at power-up
	reg        pram_sv_todo = 1'b0;
	reg [1:0]  pram_bsel;             // which byte of the current 32-bit word
	reg [31:0] pram_word;
	reg        pram_sv_busy = 1'b0;
	initial begin
		pram_loaded    = 1'b1;   // resolved: built-in defaults, no slot to read
		pram_load_wr   = 1'b0;
		pram_load_addr = 8'd0;
		pram_load_data = 8'd0;
		pram_save_addr = 8'd0;
	end
	reg [8:0]  pram_sv_idx;
	reg [31:0] pram_sv_word;
	reg        psq_d = 1'b0;
	// A nonvolatile slot with parameters bit 5 set is CREATED BY THE OS filled
	// with 0xFF, so the very first boot reads a successful transfer of 256
	// blank bytes. Copying that into the Egret would replace a valid PRAM with
	// garbage. Validate first: an all-0xFF (or all-0x00) image means "no save
	// yet" and the built-in egret.pram defaults are kept.
	reg        pram_blank;

	// Floppy bulk load state
	reg        req_is_flp   = 1'b0;
	reg        flp_pending  = 1'b0;   // a mount is waiting to be copied in
	reg        flp_busy     = 1'b0;
	reg [22:0] flp_sector   = 23'd0;  // 512-byte sector index into the image
	reg [31:0] flp_total    = 32'd0;  // image size in bytes
	reg [24:0] flp_byte     = 25'd0;  // running byte offset for dio_addr

always @(posedge clk_sys) begin
	sd_buff_wr   <= 1'b0;
	buf_we_sys   <= 1'b0;
	dio_wr       <= 1'b0;
	pram_load_wr <= 1'b0;   // 1-cycle strobe, re-asserted in C_PR_B

	done_s <= {done_s[1:0], done_tgl};

	// ---- PRAM save walker -------------------------------------------------
	// Runs independently of cstate: it only reads the Egret's pram[] (async
	// read via pram_save_addr) and stages 32-bit words into wrbuf. When the
	// last word is staged it raises pram_sv_todo, and C_IDLE issues the write.
	// Kept separate so a flush can stage while the SCSI path is mid-sector.
	psq_d <= pram_save_req;
	if (pram_save_req && !psq_d && !pram_sv_busy && pram_loaded) begin
		pram_sv_busy <= 1'b1;
		pram_sv_idx  <= 9'd0;
		pram_save_addr <= 8'd0;
	end else if (pram_sv_busy) begin
		// pram_save_data is the byte for the address presented LAST cycle.
		pram_sv_word <= {pram_sv_word[23:0], pram_save_data};
		if (pram_sv_idx[1:0] == 2'd3) begin
			buf_addr_sys  <= pram_sv_idx[8:2];
			buf_wdata_sys <= {pram_sv_word[23:0], pram_save_data};
			buf_we_sys    <= 1'b1;
		end
		if (pram_sv_idx == PRAM_BYTES-1) begin
			pram_sv_busy <= 1'b0;
			pram_sv_todo <= 1'b1;      // ask C_IDLE to issue the write
		end else begin
			pram_sv_idx    <= pram_sv_idx + 9'd1;
			pram_save_addr <= pram_sv_idx[7:0] + 8'd1;
		end
	end

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
		// PRAM load runs FIRST and before anything else can start, because the
		// 68020 is held in reset until it finishes and every other client here
		// is downstream of a running CPU. It happens exactly once.
		if (pram_rd_todo) begin
			pram_rd_todo <= 1'b0;
			req_is_pram  <= 1'b1;
			req_is_flp   <= 1'b0;
			req_is_wr    <= 1'b0;
			cstate       <= C_REQ;
		end else if (pram_sv_todo && !pram_sv_busy) begin
			// Save: the bytes are already staged in wrbuf by the save walker.
			pram_sv_todo <= 1'b0;
			req_is_pram  <= 1'b1;
			req_is_flp   <= 1'b0;
			req_is_wr    <= 1'b1;
			cstate       <= C_REQ;
		// SCSI requests take priority; a floppy bulk load is not time-critical
		// and simply resumes between them.
		end else if (!(sd_rd[0] | sd_rd[1] | sd_wr[0] | sd_wr[1]) && flp_busy && flp_allow) begin
			req_is_pram <= 1'b0;
			req_is_flp <= 1'b1;
			req_is_wr  <= 1'b0;
			req_lba    <= {9'd0, flp_sector};
			cstate     <= C_REQ;
		end else if (sd_rd[0] | sd_rd[1] | sd_wr[0] | sd_wr[1]) begin
			req_is_pram <= 1'b0;
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
			buf_wdata_sys <= {fill_hi, dinw_le};
			buf_we_sys    <= 1'b1;
		end else begin
			fill_hi <= dinw_le;
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
			// A PRAM READ feeds the Egret; a PRAM WRITE is simply finished.
			// Either way, a failed transfer must still release the boot, so
			// pram_loaded is raised on the write/failure path too.
			if      (req_is_pram && !req_is_wr) begin
				pram_blank <= 1'b1;
				if (xfer_err) begin
					// No save file yet (first ever boot), or the OS could not
					// read it. KEEP the built-in egret.pram defaults and let
					// the machine boot.
					pram_loaded <= 1'b1;
					cstate      <= C_FIN;
				end else begin
					pram_bsel <= 2'd0;
					cstate    <= C_PV_A;   // validate before committing
				end
			end
			else if (req_is_pram)  begin pram_loaded <= 1'b1; cstate <= C_FIN; end
			else if (req_is_flp)   cstate <= C_FLP_A;
			else if (req_is_wr)    cstate <= C_FIN;
			else                   cstate <= C_DRN_A;
		end
	end

	// ---- PRAM validate: is the save file still blank? --------------------
	C_PV_A: begin
		buf_addr_sys <= cidx[6:0];
		cstate       <= C_PV_W;
	end

	C_PV_W: cstate <= C_PV_B;

	C_PV_B: begin
		if (rdbuf_rd_sys != 32'hFFFFFFFF && rdbuf_rd_sys != 32'h00000000)
			pram_blank <= 1'b0;
		if (cidx == PRAM_WORDS-1) begin
			cidx <= 9'd0;
			if (pram_blank && (rdbuf_rd_sys == 32'hFFFFFFFF || rdbuf_rd_sys == 32'h00000000)) begin
				// Never written: keep the built-in defaults.
				pram_loaded <= 1'b1;
				cstate      <= C_FIN;
			end else begin
				pram_bsel <= 2'd0;
				cstate    <= C_PR_A;
			end
		end else begin
			cidx   <= cidx + 9'd1;
			cstate <= C_PV_A;
		end
	end

	// ---- PRAM load: rdbuf -> the Egret's pram[] via pram_load_* ----------
	C_PR_A: begin
		buf_addr_sys <= cidx[6:0];
		cstate       <= C_PR_W;
	end

	C_PR_W: cstate <= C_PR_B;      // rdbuf_rd_sys is registered

	C_PR_B: begin
		// Big-endian unpack: byte 0 of the file is in [31:24].
		pram_load_addr <= {cidx[5:0], pram_bsel};
		case (pram_bsel)
			2'd0: pram_load_data <= rdbuf_rd_sys[31:24];
			2'd1: pram_load_data <= rdbuf_rd_sys[23:16];
			2'd2: pram_load_data <= rdbuf_rd_sys[15:8];
			2'd3: pram_load_data <= rdbuf_rd_sys[7:0];
		endcase
		pram_load_wr <= 1'b1;
		if (pram_bsel == 2'd3) begin
			pram_bsel <= 2'd0;
			if (cidx == PRAM_WORDS-1) begin
				pram_loaded <= 1'b1;   // release the 68020
				cstate      <= C_FIN;
			end else begin
				cidx   <= cidx + 9'd1;
				cstate <= C_PR_A;
			end
		end else begin
			pram_bsel <= pram_bsel + 2'd1;
			cstate    <= C_PR_B;
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
		// The 32-bit bridge word is big-endian (MS half = lower word offset),
		// but the sd_buff face wants LITTLE-endian 16-bit words (byte0 low) --
		// swap byte lanes within the chosen half. See the dinw_le note.
		sd_buff_dout <= cidx[0] ? {rdbuf_rd_sys[7:0],  rdbuf_rd_sys[15:8]}
		                        : {rdbuf_rd_sys[23:16], rdbuf_rd_sys[31:24]};
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
	// Per-transfer failure flag. Settled before done_tgl toggles, so the core
	// side may sample it in C_WAIT alongside the done handshake. Needed because
	// a FAILED PRAM read leaves rdbuf holding garbage, and copying that into the
	// Egret would destroy the known-good built-in PRAM image -- far worse than
	// simply not having a save file.
	reg        xfer_err = 1'b0;

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
				// PRAM is a whole-file transfer: slot PRAM, offset 0, 256 bytes.
				// req_is_pram/req_is_flp/req_slot/req_lba are all clk_sys regs
				// that are settled well before the req toggle crosses, which is
				// the same convention the SCSI path already relies on.
				target_dataslot_id         <= req_is_pram ? slot_pram_id
				                            : req_is_flp  ? slot_flp_id
				                                          : (req_slot ? slot1_id : slot0_id);
				// req_lba is a 512-byte sector index; the OS wants a BYTE
				// offset into the file.
				target_dataslot_slotoffset <= req_is_pram ? 32'd0 : (req_lba << 9);
				target_dataslot_bridgeaddr <= BUF_BASE;
				target_dataslot_length     <= req_is_pram ? PRAM_BYTES[31:0]
				                                          : SECTOR_BYTES[31:0];
				tmo                        <= 24'd0;
				xfer_err                   <= 1'b0;
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
				xfer_err              <= 1'b1;
				done_tgl              <= ~done_tgl;
				tstate                <= T_IDLE;
			end
		end

		T_DONE: if (&tmo) begin
			saw_tmo  <= 1'b1;
			xfer_err <= 1'b1;
			done_tgl <= ~done_tgl;
			tstate   <= T_IDLE;
		end else if (!done_rise) begin
			tmo <= tmo + 24'd1;
		end else if (done_rise) begin
			if (target_dataslot_err != 3'd0) xfer_err <= 1'b1;
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

	// JTAG probe word (see the port comment). Sticky bits are 0->1 only, so
	// sampling them from the ISSP's clk_sys side needs no handshake; img_size
	// is quasi-static after the mount pulse.
	// ★ buildY: mount_cnt now counts RAW clk_74a announcement edges for the
	// HDD slots — before any gating — so "OS never sent one" (cnt=0) is
	// distinguishable from "sent but the core dropped it" (cnt>0, mount=0).
	reg [2:0] dbg_mount_cnt = 3'd0;
	always @(posedge clk_74a)
		if (dataslot_update && !dsu_d &&
		    (dataslot_update_id == slot0_id || dataslot_update_id == slot1_id))
			dbg_mount_cnt <= dbg_mount_cnt + 3'd1;
	assign dbg_bdst = { saw_tmo, saw_read_74, saw_ack_74, saw_done_74,
	                    saw_deliver_sys, saw_mount_sys, dbg_mount_cnt,
	                    img_size[31:9] };

	// Served-data capture (clk_sys, C_DRN_B is SCSI-read-only by construction).
	// Word mux mirror of the sd_buff_dout line: cidx 0 -> MS half, 1 -> LS half.
	reg [15:0] dbg_w0 = 16'd0, dbg_w1 = 16'd0;
	reg [7:0]  dbg_dlv_cnt = 8'd0;
	reg [23:0] dbg_last_lba = 24'd0;
	always @(posedge clk_sys) begin
		if (cstate == C_DRN_B) begin
			if (cidx == 9'd0) dbg_w0 <= rdbuf_rd_sys[31:16];
			if (cidx == 9'd1) dbg_w1 <= rdbuf_rd_sys[15:0];
			if (cidx == SECTOR_WORDS-1) dbg_dlv_cnt <= dbg_dlv_cnt + 8'd1;
		end
		if (cstate == C_REQ && !req_is_pram && !req_is_flp && !req_is_wr)
			dbg_last_lba <= req_lba[23:0];
	end
	assign dbg_bdw0 = { dbg_w0, dbg_w1 };
	assign dbg_bdlb = { dbg_dlv_cnt, dbg_last_lba };

endmodule

`default_nettype wire
