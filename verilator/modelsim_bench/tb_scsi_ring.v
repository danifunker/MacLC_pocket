// tb_scsi_ring.v — REAL scsi_dpram (extracted from rtl/scsi.v at run time)
// under the two cadences the CPU-perf port changed (2026-08-20, 7.5.5 hunt).
//
// Port A plays apf_blockdev's read-drain: 256-word sector bursts at EXACTLY
// 3 clks/word (C_DRN_A/W/B), parameterized sector latency — the Pocket's
// real fill rhythm (the HPS this module was tuned against had a different
// one; mystery B proved the prefetch is cadence-sensitive).
// Port B plays the target's mac-side read face: address_b = mac_addr,
// address_c/d = mac_addr+1/+2 (exactly how scsi.v wires the look-ahead),
// with mac_addr advancing on a sweep of rhythms — the old ~10-clk pace down
// to the Phase-B floor — at every relative phase against the fill.
//
// Checked EVERY advance (streaming-time, not just quiescence — tb_scsi_pf
// checked after quiet windows): q_b/q_c/q_d against a golden array. Any
// stale byte = the mystery-B class reopened under a new alignment.
//
// PASS = "ALL RING CHECKS PASSED".
// Run: bash run_scsi_ring.sh   (extracts scsi_dpram fresh; no drifting copy)

`timescale 1ns/1ps

module tb_scsi_ring;

localparam AW = 13;   // BUF_AW at RING_LOG=5 (the shipping config)

reg clk = 0;
always #15.384 clk = ~clk;

// port A (blockdev fill)
reg  [AW-1:0] address_a = 0;
reg  [7:0]    data_a = 0;
reg           wren_a = 0;
wire [7:0]    q_a;
// port B (mac face)
reg  [AW-1:0] mac_addr = 0;
reg  [7:0]    data_b = 0;
reg           wren_b = 0;
wire [7:0]    q_b, q_c, q_d;

scsi_dpram #(.DATAWIDTH(8), .ADDRWIDTH(AW)) dut (
	.clock(clk),
	.address_a(address_a), .data_a(data_a), .wren_a(wren_a), .q_a(q_a),
	.address_b(mac_addr),  .data_b(data_b), .wren_b(wren_b), .q_b(q_b),
	.address_c(mac_addr + 13'd1), .q_c(q_c),
	.address_d(mac_addr + 13'd2), .q_d(q_d)
);

reg [7:0] golden [0:(1<<AW)-1];
integer mismatches = 0;
integer checks = 0;

function [7:0] ramp(input [31:0] off);
	ramp = off[7:0] ^ off[15:8] ^ off[23:16];
endfunction

// ---- port A: blockdev sector fill, 3 clks/word-write (1 byte lane here:
// scsi.v feeds buffer0/1 one byte per 16-bit sd_buff write — the per-buffer
// port-A cadence is one write every 3 clks, 256 per sector) ----
task fill_sector(input integer slot, input [31:0] sec_no);
	integer i; begin
	for (i = 0; i < 256; i = i + 1) begin
		@(posedge clk); #2;
		address_a = slot*256 + i;
		data_a    = ramp(sec_no*256 + i);
		wren_a    = 1;
		golden[slot*256 + i] = ramp(sec_no*256 + i);
		@(posedge clk); #2; wren_a = 0;
		@(posedge clk);        // 3-clk period
	end
	#2; wren_a = 0;
end endtask

// ---- port B: one mac-side advance + settle + streaming check ----
// After an advance the contract says q_b/q_c/q_d consistent <= 7 clks
// (dma_settle=8 covers it). `pace` = clks between advances; 10 = old-world,
// 8 = settle floor, and 6/5 model Phase-B trains arriving faster than the
// settle was recalibrated for (if 8 truly gates, 6/5 must STILL pass because
// DREQ holds the host off — this bench checks the DPRAM's own contract at
// exactly the settle boundary).
task advance_and_check(input integer pace);
	begin
	@(posedge clk); #2;
	mac_addr = mac_addr + 1;
	repeat (pace) @(posedge clk);
	#1;
	checks = checks + 3;
	if (q_b !== golden[mac_addr]) begin
		mismatches = mismatches + 1;
		$display("MISMATCH q_b  addr=%0d got=%02x exp=%02x pace=%0d @%0t", mac_addr, q_b, golden[mac_addr], pace, $time);
	end
	if (q_c !== golden[mac_addr + 13'd1]) begin
		mismatches = mismatches + 1;
		$display("MISMATCH q_c  addr=%0d got=%02x exp=%02x pace=%0d @%0t", mac_addr+1, q_c, golden[mac_addr+13'd1], pace, $time);
	end
	if (q_d !== golden[mac_addr + 13'd2]) begin
		mismatches = mismatches + 1;
		$display("MISMATCH q_d  addr=%0d got=%02x exp=%02x pace=%0d @%0t", mac_addr+2, q_d, golden[mac_addr+13'd2], pace, $time);
	end
end endtask

integer s, i, ph, pace;
integer sec = 0;
initial begin
	wren_b = 0;
	// init all 8 KB so every compare is against known data
	for (i = 0; i < (1<<AW); i = i + 1) golden[i] = 8'hEE;
	@(posedge clk); #2;
	for (i = 0; i < (1<<AW); i = i + 1) begin
		@(posedge clk); #2; address_a = i; data_a = 8'hEE; wren_a = 1;
	end
	@(posedge clk); #2; wren_a = 0;

	$display("=== phase 1: prime 2 sectors, stream-read at old pace (control) ===");
	fill_sector(0, sec); sec = sec + 1;
	fill_sector(1, sec); sec = sec + 1;
	mac_addr = 0;
	for (i = 0; i < 500; i = i + 1) advance_and_check(10);

	$display("=== phase 2: concurrent fill-ahead vs stream-read, pace sweep x fill phase ===");
	// The real geometry: the host reads slot k while the fill writes slot k+1..
	// Sweep the mac pace {10,8,7,6,5} x starting phase offset {0,1,2} against
	// the 3-clk fill lattice. fork/join: fill runs while reads advance.
	for (pace = 10; pace >= 5; pace = pace - 1) begin
		for (ph = 0; ph < 3; ph = ph + 1) begin
			mac_addr = 0;
			fill_sector(0, sec); sec = sec + 1;
			fill_sector(1, sec); sec = sec + 1;
			repeat (ph) @(posedge clk);
			fork
				begin : filler
					integer fs;
					for (fs = 2; fs < 8; fs = fs + 1) begin
						fill_sector(fs, sec); sec = sec + 1;
					end
				end
				begin : reader
					integer rd;
					mac_addr = 0;
					for (rd = 0; rd < 256*6; rd = rd + 1) advance_and_check(pace);
				end
			join
		end
		$display("  pace %0d done, mismatches so far: %0d", pace, mismatches);
	end

	$display("=== phase 3: rewrite-under-lookahead (the mystery-B geometry) at Pocket cadence ===");
	// Rewrite addr_c/addr_d while the prefetch may be mid-flight, at every
	// phase of the 3-clk fill lattice vs a just-advanced mac_addr.
	for (ph = 0; ph < 12; ph = ph + 1) begin
		mac_addr = 100;
		repeat (12) @(posedge clk);   // prefetch settles on 101/102
		@(posedge clk); #2;
		mac_addr = 101;               // advance: prefetch must move to 102/103
		repeat (ph) @(posedge clk);
		// port-A rewrite of the NEW look-ahead targets at fill cadence
		@(posedge clk); #2; address_a = 102; data_a = ramp(sec*256 + ph); golden[102] = data_a; wren_a = 1;
		@(posedge clk); #2; wren_a = 0;
		@(posedge clk);
		@(posedge clk); #2; address_a = 103; data_a = ramp(sec*256 + ph + 77); golden[103] = data_a; wren_a = 1;
		@(posedge clk); #2; wren_a = 0;
		repeat (10) @(posedge clk);   // quiescence
		#1;
		checks = checks + 2;
		if (q_c !== golden[102]) begin
			mismatches = mismatches + 1;
			$display("MISMATCH ph3 q_c ph=%0d got=%02x exp=%02x", ph, q_c, golden[102]);
		end
		if (q_d !== golden[103]) begin
			mismatches = mismatches + 1;
			$display("MISMATCH ph3 q_d ph=%0d got=%02x exp=%02x", ph, q_d, golden[103]);
		end
		sec = sec + 1;
	end

	$display("");
	$display("checks=%0d", checks);
	if (mismatches == 0) $display("ALL RING CHECKS PASSED");
	else $display("FAILED: %0d mismatches", mismatches);
	$finish;
end

initial begin #200000000; $display("WATCHDOG TIMEOUT"); $finish; end

endmodule
