// tb_blockdev.v — offline bench for src/fpga/core/apf_blockdev.v
//
// WHY: apf_blockdev sits between the Mac's hps_io-shaped block interface and
// the APF target-dataslot commands. It cannot be observed on hardware (no HPS,
// no JTAG), so every defect in it costs a 6-minute build and a human round
// trip. This bench models the APF host side and checks the sequencing in
// milliseconds instead.
//
// It models the host the way the REAL one behaves, including the detail that
// bit us: dataslot_update is a multi-cycle LEVEL, not a pulse.
//
// build/run (see scripts note): invoke the simulator with
//       --binary --timing -Mdir obj_tb_blockdev -o Vtb_blockdev
//       tb_blockdev.v ../src/fpga/core/apf_blockdev.v
//       --top-module tb_blockdev -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
//       -Wno-UNUSEDSIGNAL -Wno-PINMISSING -Wno-DECLFILENAME
// then run ./obj_tb_blockdev/Vtb_blockdev
//
`timescale 1ns/1ps

module tb_blockdev;

	localparam [15:0] ID_HDD0 = 16'd310;
	localparam [15:0] ID_HDD1 = 16'd311;
	localparam [15:0] ID_FLP  = 16'd210;
	localparam [31:0] BUF_BASE = 32'h4000_0000;

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

	// ---- capture what the core is handed on a read ---------------------
	reg [15:0] got [0:255];
	integer    got_n = 0;
	always @(posedge clk_sys) if (sd_buff_wr) begin
		got[sd_buff_addr] = sd_buff_dout;
		got_n = got_n + 1;
	end

	// expected sector content: word k = 16'hA000 + k
	function [15:0] expw(input integer k); expw = 16'hA000 + k[15:0]; endfunction

	// ---- model the APF host servicing one target_dataslot_read ---------
	// Models the REAL host protocol, per openfpga-PCXT
	// src/fpga/core/softcpu_fdd_bridge.sv:233-249:
	//   * target_dataslot_read is a LEVEL the core holds until the host acks;
	//     the ack is what clears it.
	//   * target_dataslot_done is consumed on its RISING EDGE.
	// The host does not respond instantly, so the request must survive a wait.
	task serve_read;
		integer w;
		integer lat;
		begin : body
			// Host takes a while to get to it. The request MUST stay asserted.
			for (lat = 0; lat < 20; lat = lat + 1) begin
				@(posedge clk_74a);
				if (!tgt_read) begin
					$display("FAIL: target_dataslot_read dropped before ack (cycle %0d) -- the host would never see it", lat);
					errors = errors + 1;
					disable body;
				end
			end
			tgt_ack <= 1'b1;
			@(posedge clk_74a);
			tgt_ack <= 1'b0;
			// The OS writes the payload into our bridge window: 128 x 32-bit,
			// big-endian (MS half is the LOWER 16-bit word offset).
			for (w = 0; w < 128; w = w + 1) begin
				@(posedge clk_74a);
				bridge_addr    <= BUF_BASE + (w*4);
				bridge_wr      <= 1'b1;
				bridge_wr_data <= {expw(w*2), expw(w*2+1)};
			end
			@(posedge clk_74a);
			bridge_wr <= 1'b0;
			repeat (4) @(posedge clk_74a);
			tgt_done <= 1'b1;
			@(posedge clk_74a);
			tgt_done <= 1'b0;
		end
	endtask

	// ---- main --------------------------------------------------------
	integer k;
	integer timeout;
	initial begin
		$display("=== tb_blockdev ===");
		repeat (10) @(posedge clk_74a);
		reset_n <= 1'b1;
		repeat (10) @(posedge clk_74a);

		// --- 1. mount: dataslot_update as a multi-cycle LEVEL -----------
		@(posedge clk_74a);
		dataslot_update_id   <= ID_HDD0;
		dataslot_update_size <= 32'd1048576;      // 1 MB => 2048 blocks
		dataslot_update      <= 1'b1;
		repeat (6) @(posedge clk_74a);            // held, like core_bridge_cmd
		dataslot_update      <= 1'b0;
		repeat (20) @(posedge clk_sys);

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

		// --- 2. a sector read -------------------------------------------
		got_n = 0;
		@(posedge clk_sys);
		sd_lba0 <= 32'd5;
		sd_rd   <= 3'b001;

		// wait for the target command
		timeout = 0;
		while (!tgt_read && timeout < 2000) begin @(posedge clk_74a); timeout = timeout + 1; end
		if (!tgt_read) begin
			$display("FAIL: no target_dataslot_read within timeout");
			errors = errors + 1;
		end else begin
			if (tgt_id != ID_HDD0)              begin $display("FAIL: tgt_id=%0d expected %0d", tgt_id, ID_HDD0); errors=errors+1; end
			if (tgt_slotoffset != 32'd2560)     begin $display("FAIL: slotoffset=%0d expected 2560", tgt_slotoffset); errors=errors+1; end
			if (tgt_length != 32'd512)          begin $display("FAIL: length=%0d expected 512", tgt_length); errors=errors+1; end
			if (tgt_bridgeaddr != BUF_BASE)     begin $display("FAIL: bridgeaddr=%h expected %h", tgt_bridgeaddr, BUF_BASE); errors=errors+1; end
			if (errors == 0) $display("PASS: target read cmd id=%0d off=%0d len=%0d addr=%h",
			                          tgt_id, tgt_slotoffset, tgt_length, tgt_bridgeaddr);
			serve_read;
		end

		// wait for the core-side drain
		timeout = 0;
		while (got_n < 256 && timeout < 20000) begin @(posedge clk_sys); timeout = timeout + 1; end

		if (got_n != 256) begin
			$display("FAIL: core received %0d of 256 words", got_n);
			errors = errors + 1;
		end else begin
			$display("PASS: core received all 256 words");
			for (k = 0; k < 256; k = k + 1)
				if (got[k] !== expw(k)) begin
					if (errors < 8) $display("FAIL: word %0d = %h, expected %h", k, got[k], expw(k));
					errors = errors + 1;
				end
			if (errors == 0) $display("PASS: sector content correct, byte order correct");
		end

		sd_rd <= 3'b000;
		repeat (50) @(posedge clk_sys);
		if (sd_ack != 3'b000) begin
			$display("FAIL: sd_ack still asserted after request dropped");
			errors = errors + 1;
		end else
			$display("PASS: sd_ack released");

		$display("=== %0d error(s) ===", errors);
		$finish;
	end

	// global watchdog
	initial begin
		#5_000_000;
		$display("FAIL: global timeout — FSM is stuck");
		$finish;
	end

endmodule
