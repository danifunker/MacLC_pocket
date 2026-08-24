// tb_blockdev.v — offline bench for src/fpga/core/apf_blockdev.v
//
// WHY: apf_blockdev sits between the Mac's hps_io-shaped block interface and
// the APF target-dataslot commands. It cannot be observed on hardware (no HPS,
// no JTAG), so every defect in it costs a 6-minute build and a human round
// trip. This bench models the APF host side and checks the sequencing in
// milliseconds instead.
//
// It models the host the way the REAL one behaves, including the details that
// bit us:
//   - dataslot_update is a multi-cycle LEVEL, not a pulse;
//   - target_dataslot_read is a LEVEL the core holds until the ack;
//   - target_dataslot_done is consumed on its RISING edge;
//   - the OS answers after a long latency (hundreds of us per transfer) —
//     which is the whole reason the pipelined refill exists;
//   - the sd_buff face is LITTLE-endian 16-bit (byte0 low; buildAA 2026-08-12,
//     HW-validated: block 0 must reach the Mac as "ER",512). The original
//     content oracle here predated that fix and expected file order.
//
// ★ 2026-08-24 (blockdev-pipeline): extended for the pipelined refill —
//   - an always-running host server with parameterized latency, since
//     speculative fetches are posted asynchronously to the demand flow;
//   - per-LBA, per-generation content patterns (cross-sector or stale-buffer
//     serving is the failure class, and it must not be maskable);
//   - sequential-stream test: after the stream is established, each sector
//     must cost exactly one host transfer, be served measurably faster than
//     a demand round trip, and the next fetch must overlap the live ack
//     envelope (the overlap witness);
//   - the mailbox/CDC law: no sd_buff word may be handed to the core from an
//     rdbuf half the host is still writing (data publishes before done);
//   - a seek (non-sequential read) must NOT speculate — random reads never
//     pay a wasted-transfer tax;
//   - a write invalidates the speculative sector (stale-read hazard), and
//     the write round trip itself is content-checked, including the -1
//     readback-lag compensation (file word w is read from bridge (w+1)*4);
//   - a media change (dataslot_update) invalidates the speculative sector,
//     both when it is already delivered and while it is still in flight.
//
// build/run (see scripts note): invoke the simulator with
//       --binary --timing -Mdir obj_tb_blockdev -o Vtb_blockdev
//       tb_blockdev.v ../src/fpga/core/apf_blockdev.v
//       --top-module tb_blockdev -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
//       -Wno-UNUSEDSIGNAL -Wno-PINMISSING -Wno-DECLFILENAME
// then run ./obj_tb_blockdev/Vtb_blockdev
// PASS = final line "ALL BLOCKDEV CHECKS PASSED".
//
`timescale 1ns/1ps

module tb_blockdev;

	localparam [15:0] ID_HDD0 = 16'd310;
	localparam [15:0] ID_HDD1 = 16'd311;
	localparam [15:0] ID_FLP  = 16'd210;
	localparam [31:0] BUF_BASE = 32'h4000_0000;

	// host service latency, clk_74a cycles from request to ack and again from
	// ack to payload+done. 2 x 4000 = ~108 us per transfer — the hundreds-of-
	// us regime the serialized refill paid per sector.
	localparam integer HOST_LAT = 4000;

	reg clk_74a = 0, clk_sys = 0, reset_n = 0;
	always #6.734  clk_74a = ~clk_74a;   // 74.25 MHz
	always #15.385 clk_sys = ~clk_sys;   // 32.5 MHz

	// bridge
	reg  [31:0] bridge_addr = 0;
	reg         bridge_wr = 0;
	reg  [31:0] bridge_wr_data = 0;
	wire [31:0] bridge_rd_data;

	// dataslot events
	reg         dataslot_update = 0;
	reg  [15:0] dataslot_update_id = 0;
	reg  [31:0] dataslot_update_size = 0;

	// target commands
	wire        tgt_read, tgt_write;
	reg         tgt_ack = 0, tgt_done = 0;
	wire [15:0] tgt_id;
	wire [31:0] tgt_slotoffset, tgt_bridgeaddr, tgt_length;

	// core side (slot 2 = CD-ROM, idle in this bench)
	reg  [31:0] sd_lba0 = 0, sd_lba1 = 0, sd_lba2 = 0;
	reg  [2:0]  sd_rd = 0, sd_wr = 0;
	wire [2:0]  sd_ack;
	wire [7:0]  sd_buff_addr;
	wire [15:0] sd_buff_dout;
	wire        sd_buff_wr;
	reg  [15:0] sd_buff_din0 = 0, sd_buff_din1 = 0;
	wire [2:0]  img_mounted;
	wire [31:0] img_size;

	// floppy download port
	wire        dio_download, dio_wr;
	wire [7:0]  dio_index;
	wire [24:0] dio_addr;
	wire [15:0] dio_data;
	reg         dio_ack = 0;

apf_blockdev #(.BUF_BASE(BUF_BASE)) dut (
	.clk_74a(clk_74a), .reset_n(reset_n),
	.bridge_addr(bridge_addr), .bridge_wr(bridge_wr),
	.bridge_wr_data(bridge_wr_data), .bridge_rd_data(bridge_rd_data),
	.dataslot_update(dataslot_update), .dataslot_update_id(dataslot_update_id),
	.dataslot_update_size(dataslot_update_size),
	.target_dataslot_read(tgt_read), .target_dataslot_write(tgt_write),
	.target_dataslot_ack(tgt_ack), .target_dataslot_done(tgt_done),
	.target_dataslot_err(3'd0),
	.target_dataslot_id(tgt_id), .target_dataslot_slotoffset(tgt_slotoffset),
	.target_dataslot_bridgeaddr(tgt_bridgeaddr), .target_dataslot_length(tgt_length),
	.slot0_id(ID_HDD0), .slot1_id(ID_HDD1), .slot_cd_id(16'd320), .slot_flp_id(ID_FLP),
	.dio_download(dio_download), .dio_index(dio_index), .dio_addr(dio_addr),
	.dio_data(dio_data), .dio_wr(dio_wr), .dio_ack(dio_ack),
	.flp_allow(1'b1),
	.clk_sys(clk_sys),
	.sd_lba0(sd_lba0), .sd_lba1(sd_lba1), .sd_lba2(sd_lba2), .sd_rd(sd_rd), .sd_wr(sd_wr),
	.sd_ack(sd_ack), .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr), .sd_buff_din0(sd_buff_din0), .sd_buff_din1(sd_buff_din1),
	.img_mounted(img_mounted), .img_size(img_size)
);

	integer errors = 0;
	integer mount_pulses = 0;

	// ---- observe img_mounted ------------------------------------------
	always @(posedge clk_sys) if (img_mounted[0]) mount_pulses = mount_pulses + 1;

	// ---- per-LBA file content model -----------------------------------
	// File byte i of sector lba, generation g. Writes bump the slot-0
	// generation, so a stale speculative buffer can never fake a pass.
	function [7:0] fb(input [31:0] lba, input integer i, input integer g);
		fb = i[7:0] + lba[7:0]*8'h3 + g[7:0]*8'h55;
	endfunction
	// Expected sd_buff word k: LITTLE-endian pair of file bytes 2k/2k+1
	// (buildAA — what scsi.v is built for, HW-validated).
	function [15:0] exp_sd(input [31:0] lba, input integer k, input integer g);
		exp_sd = { fb(lba, 2*k+1, g), fb(lba, 2*k, g) };
	endfunction

	integer gen0 = 0;              // slot-0 content generation (bumped on write)

	// ---- capture what the core is handed on a read ---------------------
	reg [15:0] got [0:255];
	integer    got_n = 0;
	always @(posedge clk_sys) if (sd_buff_wr) begin
		got[sd_buff_addr] = sd_buff_dout;
		got_n = got_n + 1;
	end

	// ---- host server: services EVERY transfer, forever ------------------
	integer serve_cnt = 0;              // completed transfers, either kind
	reg        srv_writing = 1'b0;      // payload write burst in progress
	reg [31:0] srv_addr    = 32'd0;     // ... into this bridge window base
	reg [31:0] srv_lba;
	reg [15:0] wr_got [0:255];          // last write-back, as 16-bit file words
	reg [31:0] wr_lba = 32'hFFFFFFFF;
	integer w;
	reg [31:0] rb;
	always begin : host_server
		@(posedge clk_74a);
		if (reset_n && (tgt_read || tgt_write)) begin
			// hold-check: the request must stay asserted until our ack
			for (w = 0; w < HOST_LAT; w = w + 1) begin
				@(posedge clk_74a);
				if (!(tgt_read || tgt_write)) begin
					$display("FAIL: target_dataslot request dropped before ack (cycle %0d)", w);
					errors = errors + 1;
					disable host_server;
				end
			end
			// legality checks on the command
			if (tgt_length != 32'd512) begin
				$display("FAIL: tgt_length=%0d expected 512", tgt_length);
				errors = errors + 1;
			end
			if (tgt_slotoffset[8:0] != 9'd0) begin
				$display("FAIL: tgt_slotoffset=%0d not sector-aligned", tgt_slotoffset);
				errors = errors + 1;
			end
			if (tgt_bridgeaddr != BUF_BASE && tgt_bridgeaddr != (BUF_BASE + 32'd512)) begin
				$display("FAIL: tgt_bridgeaddr=%h not a legal rdbuf half", tgt_bridgeaddr);
				errors = errors + 1;
			end
			srv_lba = tgt_slotoffset >> 9;
			if (tgt_read) begin
				tgt_ack <= 1'b1; @(posedge clk_74a); tgt_ack <= 1'b0;
				for (w = 0; w < HOST_LAT; w = w + 1) @(posedge clk_74a);
				// payload: 128 x 32-bit, big-endian file order
				srv_writing <= 1'b1;
				srv_addr    <= tgt_bridgeaddr;
				for (w = 0; w < 128; w = w + 1) begin
					@(posedge clk_74a);
					bridge_addr    <= tgt_bridgeaddr + (w*4);
					bridge_wr      <= 1'b1;
					bridge_wr_data <= { fb(srv_lba, 4*w,   (tgt_id==ID_HDD0)?gen0:0),
					                    fb(srv_lba, 4*w+1, (tgt_id==ID_HDD0)?gen0:0),
					                    fb(srv_lba, 4*w+2, (tgt_id==ID_HDD0)?gen0:0),
					                    fb(srv_lba, 4*w+3, (tgt_id==ID_HDD0)?gen0:0) };
				end
				@(posedge clk_74a);
				bridge_wr <= 1'b0;
				repeat (4) @(posedge clk_74a);
				srv_writing <= 1'b0;
				tgt_done <= 1'b1; @(posedge clk_74a); tgt_done <= 1'b0;
			end else begin
				tgt_ack <= 1'b1; @(posedge clk_74a); tgt_ack <= 1'b0;
				for (w = 0; w < HOST_LAT; w = w + 1) @(posedge clk_74a);
				// read the payload back over the bridge. The OS pairs each
				// response with the PREVIOUS transaction (the -1 readback-lag
				// compensation in the DUT): file word w arrives from the read
				// of address (w+1)*4.
				for (w = 0; w < 128; w = w + 1) begin
					@(posedge clk_74a);
					bridge_addr <= tgt_bridgeaddr + ((w+1)*4);
					@(posedge clk_74a); @(posedge clk_74a);
					rb = bridge_rd_data;
					wr_got[2*w]   = rb[31:16];
					wr_got[2*w+1] = rb[15:0];
				end
				wr_lba = srv_lba;
				repeat (4) @(posedge clk_74a);
				tgt_done <= 1'b1; @(posedge clk_74a); tgt_done <= 1'b0;
			end
			serve_cnt = serve_cnt + 1;
			repeat (2) @(posedge clk_74a);
		end
	end

	// ---- overlap witness: a host transfer live DURING an ack envelope ----
	// This is the pipeline's whole point; the serialized design can never
	// set this during a read stream (its transfer completes before ack ends
	// only WITH the drain inside the envelope — a NEW request during the
	// envelope was structurally impossible).
	reg overlap_seen = 1'b0;
	always @(posedge clk_74a)
		if ((tgt_read || tgt_ack) && sd_ack[0]) overlap_seen <= 1'b1;

	// ---- mailbox/CDC law: never hand the core a word from a half the host
	// ---- is still writing (data must publish before the completion flag) --
	always @(posedge clk_sys) begin
		if (sd_buff_wr && srv_writing && (srv_addr[9] == dut.drain_half)) begin
			$display("FAIL: sd_buff word served from rdbuf half %0d while the host is still writing it", dut.drain_half);
			errors = errors + 1;
		end
	end

	// ---- spurious-ack watch: sd_ack only ever for a pending envelope -----
	// scsi.v drops io_rd while ack is high, so remember the live envelope.
	reg [2:0] ack_hold = 3'b000;
	always @(posedge clk_sys)
		ack_hold <= (ack_hold | (sd_ack & (sd_rd | sd_wr))) & sd_ack;
	always @(posedge clk_sys) begin
		if ((sd_ack & ~(sd_rd | sd_wr | ack_hold)) != 3'b000) begin
			$display("FAIL: sd_ack=%b with no matching request (sd_rd=%b sd_wr=%b)", sd_ack, sd_rd, sd_wr);
			errors = errors + 1;
		end
	end

	// ---- core-side sector read, with the real scsi.v handshake ----------
	// (io_rd holds until ack rises, drops during the envelope, re-raises
	// only after ack falls.)
	integer to;
	task read_sector0(input [31:0] lba, input integer maxwait_us,
	                  output integer took_us);
		integer t0; begin : body
		got_n = 0;
		@(posedge clk_sys);
		sd_lba0 <= lba;
		sd_rd   <= 3'b001;
		t0 = $time;
		to = 0;
		while (!sd_ack[0] && to < maxwait_us*33) begin @(posedge clk_sys); to = to + 1; end
		if (!sd_ack[0]) begin
			$display("FAIL: lba %0d: no sd_ack within %0d us", lba, maxwait_us);
			errors = errors + 1; sd_rd <= 3'b000; took_us = maxwait_us; disable body;
		end
		sd_rd <= 3'b000;
		to = 0;
		while (sd_ack[0] && to < maxwait_us*33) begin @(posedge clk_sys); to = to + 1; end
		if (sd_ack[0]) begin
			$display("FAIL: lba %0d: sd_ack stuck high", lba);
			errors = errors + 1; took_us = maxwait_us; disable body;
		end
		took_us = ($time - t0)/1000;
		if (got_n != 256) begin
			$display("FAIL: lba %0d: core received %0d of 256 words", lba, got_n);
			errors = errors + 1;
		end
	end endtask

	task check_sector0(input [31:0] lba, input integer g);
		integer k, e; begin
		e = 0;
		for (k = 0; k < 256; k = k + 1)
			if (got[k] !== exp_sd(lba, k, g)) begin
				if (e < 4) $display("FAIL: lba %0d word %0d = %h, expected %h",
				                    lba, k, got[k], exp_sd(lba, k, g));
				e = e + 1;
			end
		if (e != 0) begin
			$display("FAIL: lba %0d content: %0d bad words (gen %0d)", lba, e, g);
			errors = errors + e;
		end
	end endtask

	// wait until the DUT has no transfer in flight (speculative included)
	task wait_xfer_idle;
		begin
		to = 0;
		while ((dut.x_busy || tgt_read || tgt_write) && to < 400000) begin
			@(posedge clk_74a); to = to + 1;
		end
		if (dut.x_busy) begin
			$display("FAIL: transfer engine stuck busy");
			errors = errors + 1;
		end
	end endtask

	// ---- core-side sector write ------------------------------------------
	// scsi.v presents sd_buff_din registered one clock after sd_buff_addr
	// (the DUT's C_FILL_W wait state exists for exactly this) — model that.
	reg [31:0] wr_cur_lba = 0;
	always @(posedge clk_sys)
		sd_buff_din0 <= exp_sd(wr_cur_lba, sd_buff_addr, gen0 + 1);
	task write_sector0(input [31:0] lba, input integer maxwait_us);
		integer k, e; begin : body
		wr_cur_lba = lba;
		@(posedge clk_sys);
		sd_lba0 <= lba;
		sd_wr   <= 3'b001;
		to = 0;
		while (!sd_ack[0] && to < maxwait_us*33) begin @(posedge clk_sys); to = to + 1; end
		if (!sd_ack[0]) begin
			$display("FAIL: wr lba %0d: no sd_ack", lba);
			errors = errors + 1; sd_wr <= 3'b000; disable body;
		end
		sd_wr <= 3'b000;
		to = 0;
		while (sd_ack[0] && to < maxwait_us*33) begin @(posedge clk_sys); to = to + 1; end
		if (sd_ack[0]) begin
			$display("FAIL: wr lba %0d: sd_ack stuck high", lba);
			errors = errors + 1; disable body;
		end
		if (wr_lba !== lba) begin
			$display("FAIL: wr lba %0d: host stored lba %0d", lba, wr_lba);
			errors = errors + 1;
		end
		// content the host read back = what the core staged (little-endian
		// sd_buff face converted back to file byte order by the DUT)
		e = 0;
		for (k = 0; k < 128; k = k + 1) begin
			if (wr_got[2*k]   !== { fb(lba, 4*k,   gen0+1), fb(lba, 4*k+1, gen0+1) }) e = e + 1;
			if (wr_got[2*k+1] !== { fb(lba, 4*k+2, gen0+1), fb(lba, 4*k+3, gen0+1) }) e = e + 1;
		end
		if (e != 0) begin
			$display("FAIL: wr lba %0d: %0d bad file words reached the host", lba, e);
			errors = errors + e;
		end
		gen0 = gen0 + 1;   // the file changed
	end endtask

	task mount_slot(input [15:0] id, input [31:0] size);
		begin
		@(posedge clk_74a);
		dataslot_update_id   <= id;
		dataslot_update_size <= size;
		dataslot_update      <= 1'b1;
		repeat (6) @(posedge clk_74a);            // held, like core_bridge_cmd
		dataslot_update      <= 1'b0;
		repeat (20) @(posedge clk_sys);
	end endtask
	task mount0(input [31:0] size); begin mount_slot(ID_HDD0, size); end endtask

	// ---- floppy download port model + capture ----------------------------
	// dio_wr is a LEVEL held until dio_ack (the machine's SDRAM slot retire).
	always @(posedge clk_sys) dio_ack <= dio_wr && !dio_ack;
	integer flp_n = 0;
	integer flp_addr_errs = 0;
	integer flp_data_errs = 0;
	always @(posedge clk_sys) if (dio_wr && dio_ack) begin
		if (dio_addr !== flp_n*2) flp_addr_errs = flp_addr_errs + 1;
		if (dio_data !== { fb(flp_n[31:8], (flp_n%256)*2, 0),
		                   fb(flp_n[31:8], (flp_n%256)*2+1, 0) })
			flp_data_errs = flp_data_errs + 1;
		flp_n = flp_n + 1;
	end

	// guest think time between sectors: the Mac's PDMA drain of the ring plus
	// driver overhead — the window the speculative fetch overlaps with
	task think; begin repeat (2000) @(posedge clk_sys); end endtask

	// ---- main --------------------------------------------------------
	integer k;
	integer t_us, base_cnt;
	integer slow_us, hit_us;
	initial begin
		$display("=== tb_blockdev (pipelined refill) ===");
		repeat (10) @(posedge clk_74a);
		reset_n <= 1'b1;
		repeat (10) @(posedge clk_74a);

		// --- 1. mount: dataslot_update as a multi-cycle LEVEL -----------
		mount0(32'd1048576);                      // 1 MB => 2048 blocks

		if (mount_pulses != 1) begin
			$display("FAIL: img_mounted[0] pulsed %0d times, expected exactly 1", mount_pulses);
			errors = errors + 1;
		end else
			$display("PASS: mount produced exactly one img_mounted pulse");

		if (img_size != 32'd1048576) begin
			$display("FAIL: img_size = %0d, expected 1048576", img_size);
			errors = errors + 1;
		end else
			$display("PASS: img_size latched (%0d bytes)", img_size);

		// --- 2. single demand read: full round trip, correct content ----
		read_sector0(32'd5, 2000, slow_us);
		check_sector0(32'd5, 0);
		if (serve_cnt != 1) begin
			$display("FAIL: %0d host transfers for one cold read", serve_cnt);
			errors = errors + 1;
		end else
			$display("PASS: cold demand read served, correct content (%0d us, 1 transfer)", slow_us);

		// --- 3. sequential stream: the pipeline -------------------------
		// lba 6 is sequential after 5 -> demand fetch + speculation starts;
		// lbas 7..9 must each cost exactly one host transfer and be served
		// in well under a demand round trip.
		think; read_sector0(32'd6, 2000, t_us); check_sector0(32'd6, 0);
		for (k = 7; k <= 9; k = k + 1) begin
			think;
			read_sector0(k[31:0], 2000, hit_us);
			check_sector0(k[31:0], 0);
			if (hit_us > slow_us/2) begin
				$display("FAIL: lba %0d took %0d us — not served from the speculative half (demand path = %0d us)", k, hit_us, slow_us);
				errors = errors + 1;
			end
		end
		wait_xfer_idle;                            // let the trailing fetch (lba 10) retire
		if (serve_cnt != 6) begin
			$display("FAIL: 5-sector sequential stream used %0d host transfers, expected 6 (5 + 1 trailing speculative)", serve_cnt);
			errors = errors + 1;
		end else
			$display("PASS: sequential stream: 1 transfer/sector, hits in %0d us vs %0d us demand", hit_us, slow_us);
		if (!overlap_seen) begin
			$display("FAIL: no host transfer ever overlapped an ack envelope — the pipeline never pipelined");
			errors = errors + 1;
		end else
			$display("PASS: refill overlapped a live serve envelope");

		// --- 4. seek: a non-sequential read must not speculate -----------
		base_cnt = serve_cnt;
		read_sector0(32'd100, 2000, t_us);
		check_sector0(32'd100, 0);
		repeat (6000) @(posedge clk_74a);          // window for a wrong speculative post
		if (serve_cnt != base_cnt + 1 || dut.x_busy || tgt_read) begin
			$display("FAIL: seek read caused extra host activity (transfers=%0d busy=%b)", serve_cnt - base_cnt, dut.x_busy);
			errors = errors + 1;
		end else
			$display("PASS: seek read = exactly one host transfer, no speculation");

		// --- 5. resume sequential + write invalidation --------------------
		read_sector0(32'd101, 2000, t_us);         // sequential again -> speculates 102
		check_sector0(32'd101, 0);
		wait_xfer_idle;                            // speculative 102 delivered
		write_sector0(32'd102, 3000);              // ... then the sector changes on card
		read_sector0(32'd102, 3000, t_us);
		check_sector0(32'd102, gen0);              // MUST be post-write content
		$display("PASS: write invalidated the speculative sector (fresh fetch, new content)");

		// --- 6. media change invalidation (speculative already delivered) --
		read_sector0(32'd103, 3000, t_us);         // sequential -> speculates 104
		check_sector0(32'd103, gen0);
		wait_xfer_idle;                            // speculative 104 delivered
		mount0(32'd1048576);                       // swap: same size, new medium
		base_cnt = serve_cnt;
		read_sector0(32'd104, 3000, t_us);
		check_sector0(32'd104, gen0);
		if (serve_cnt != base_cnt + 1) begin
			$display("FAIL: post-mount read did not refetch (%0d transfers)", serve_cnt - base_cnt);
			errors = errors + 1;
		end else if (t_us < slow_us/2) begin
			$display("FAIL: post-mount read served from the stale speculative half (%0d us)", t_us);
			errors = errors + 1;
		end else
			$display("PASS: media change dropped the delivered speculative sector (full refetch)");

		// --- 7. media change with the speculative fetch IN FLIGHT ----------
		read_sector0(32'd105, 3000, t_us);
		read_sector0(32'd106, 3000, t_us);         // sequential -> speculates 107
		mount0(32'd1048576);                       // lands while 107 is in flight
		wait_xfer_idle;
		base_cnt = serve_cnt;
		read_sector0(32'd107, 3000, t_us);
		check_sector0(32'd107, gen0);
		if (serve_cnt != base_cnt + 1 || t_us < slow_us/2) begin
			$display("FAIL: in-flight speculative sector survived the media change (transfers=%0d, %0d us)", serve_cnt - base_cnt, t_us);
			errors = errors + 1;
		end else
			$display("PASS: media change killed the in-flight speculative sector");

		// --- 8. floppy bulk copy through the same sequencer ----------------
		// (its transfers pass the reworked C_REQ/C_WAIT and always land in
		// rdbuf half 0; a SCSI read interleaves mid-copy at higher priority)
		flp_n = 0;
		mount_slot(ID_FLP, 32'd2048);              // 4 sectors
		to = 0;
		while (flp_n < 300 && to < 4000000) begin @(posedge clk_sys); to = to + 1; end
		if (!dio_download) begin
			$display("FAIL: floppy mount never raised dio_download");
			errors = errors + 1;
		end
		read_sector0(32'd200, 3000, t_us);         // SCSI preempts between sectors
		check_sector0(32'd200, gen0);
		if (!dio_download) begin
			$display("FAIL: dio_download dropped across an interleaved SCSI read");
			errors = errors + 1;
		end
		to = 0;
		while (dio_download && to < 8000000) begin @(posedge clk_sys); to = to + 1; end
		if (dio_download) begin
			$display("FAIL: floppy copy never finished");
			errors = errors + 1;
		end else if (flp_n != 1024 || flp_addr_errs != 0 || flp_data_errs != 0) begin
			$display("FAIL: floppy copy: %0d/1024 words, %0d addr errs, %0d data errs",
			         flp_n, flp_addr_errs, flp_data_errs);
			errors = errors + 1;
		end else if (dio_addr !== 25'd2048) begin
			$display("FAIL: end-of-download address = %0d, expected one-past = 2048", dio_addr);
			errors = errors + 1;
		end else
			$display("PASS: floppy bulk copy correct (1024 words, one-past end addr), SCSI interleaved cleanly");

		if (sd_ack != 3'b000) begin
			$display("FAIL: sd_ack still asserted at end");
			errors = errors + 1;
		end

		$display("=== %0d error(s) ===", errors);
		if (errors == 0) $display("ALL BLOCKDEV CHECKS PASSED");
		$finish;
	end

	// global watchdog
	initial begin
		#20_000_000;
		$display("FAIL: global timeout — FSM is stuck");
		$finish;
	end

endmodule
