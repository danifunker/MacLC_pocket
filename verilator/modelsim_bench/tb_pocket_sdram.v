// tb_pocket_sdram.v — protocol + data-integrity bench for the REAL
// src/fpga/core/pocket_sdram.v demand-start engine (2026-08-19 F-line hunt).
//
// WHY THIS EXISTS: seeds 4 and 11 of the CPU-perf port both F-line at Finder
// load on hardware while every offline gate is green. The MiSTer mission's
// hardest lesson (Trap #4) is that its sim stack never executed one cycle of
// the real controller — this fork's pocket_sdram HAS no such excuse: its
// tristate is the continuous-assign form, so the REAL RTL compiles under
// ModelSim. This bench drives it with the exact request shapes the Phase-B/C
// tops produce, at hostile clk_sys/clk_8 phases, against a chip model that
// CHECKS the JEDEC protocol instead of forgiving it.
//
// What it can prove: engine protocol violations (tRCD/tRP/tRC/tRFC, command
// legality per bank state), DQM correctness, address/data freeze correctness,
// posted-write -> read ordering, Law-6 stale-done violations, refresh
// starvation, dl_* port integrity, flp window data integrity.
// What it CANNOT see: board-level analog margins (SSO/crosstalk/phase) — if
// this bench is clean, those become the prime suspect.
//
// Run: cd verilator/modelsim_bench && bash run_sdram.sh
// PASS = "ALL CHECKS PASSED"; any "VIOLATION"/"MISMATCH" line is a real bug.

`timescale 1ns/1ps

module tb_pocket_sdram;

// ── clocks: 65 MHz clk_64; clk_sys = /2 aligned; clk_8 from busPhase ───────
reg clk64 = 0;
always #7.692 clk64 = ~clk64;      // 65 MHz

reg clk_sys = 0;
always @(posedge clk64) clk_sys <= ~clk_sys;  // NBA: clk_sys-domain wakes settle cleanly

// busPhase/clk8 exactly as addrController_top.v derives them (clk_sys domain)
reg [1:0] busPhase = 0;
always @(posedge clk_sys) busPhase <= busPhase + 2'd1;
wire clk8 = !busPhase[1];
// dioBusControl-equivalent slot for dl tests (busCycle==2'b10 analogue):
reg [1:0] busCycle = 0;
always @(posedge clk_sys) if (busPhase == 2'b11) busCycle <= busCycle + 2'd1;
wire dio_slot = (busCycle == 2'b10);

// ── DUT request registers (clk_sys domain, like the ram_*_q bundle) ────────
reg  [23:0] r_addr = 0;
reg  [15:0] r_din  = 0;
reg  [1:0]  r_ds   = 2'b11;
reg         r_oe   = 0, r_we = 0;
reg         r_flp_win = 0;
reg  [23:0] r_flp_addr = 0;
reg         r_flp_guard = 0;
reg         r_dl_req = 0;
reg  [23:0] r_dl_addr = 0;
reg  [15:0] r_dl_din = 0;

wire [15:0] dut_dout;
wire        dut_done;
wire [15:0] dut_cpu_dout;
wire        dut_dl_ack;

wire [15:0] sd_data;
wire [12:0] sd_addr;
wire [1:0]  sd_dqm;
wire [1:0]  sd_ba;
wire        sd_cke, sd_we_n, sd_ras_n, sd_cas_n;

reg init = 1;
initial begin #100 init = 0; end

pocket_sdram dut (
	.sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
	.sd_cke(sd_cke), .sd_we(sd_we_n), .sd_ras(sd_ras_n), .sd_cas(sd_cas_n),
	.init(init), .clk_64(clk64), .clk_8(clk8),
	.din(r_din), .dout(dut_dout), .addr(r_addr), .ds(r_ds),
	.oe(r_oe), .we(r_we),
	.flp_win(r_flp_win), .flp_addr(r_flp_addr), .flp_guard(r_flp_guard),
	.dl_req(r_dl_req), .dl_slot(dio_slot && r_dl_req), .dl_addr(r_dl_addr),
	.dl_din(r_dl_din), .dl_ack(dut_dl_ack),
	.cpu_done(dut_done), .cpu_dout(dut_cpu_dout)
);

// ── behavioral SDRAM chip with protocol checking ───────────────────────────
// Command decode at the chip: CS is board-tied low, so {ras,cas,we} decode.
localparam C_NOP=3'b111, C_ACT=3'b011, C_RD=3'b101, C_WR=3'b100,
           C_PRE=3'b010, C_REF=3'b001, C_MRS=3'b000, C_BST=3'b110;
wire [2:0] cmd = {sd_ras_n, sd_cas_n, sd_we_n};

integer violations = 0;
integer mismatches = 0;
task viol(input [511:0] msg); begin
	violations = violations + 1;
	$display("VIOLATION @%0t: %0s (cmd=%b ba=%b a=%h)", $time, msg, cmd, sd_ba, sd_addr);
end endtask

// per-bank state (banks 0..3)
reg  [3:0]  bk_open = 0;
reg  [12:0] bk_row [0:3];
integer     bk_act_t [0:3];    // time of last ACTIVE (in clk64 ticks)
integer     bk_pre_t [0:3];    // time precharge completes (tick precharge issued)
integer     tick = 0;
integer     ref_t = -1000;     // last refresh tick
integer     mrs_done = 0;
integer     last_act_t = -1000;

// timing in clk64 ticks (15.38 ns each):
localparam T_RCD = 2;   // 20ns ACT->RD/WR      (ceil 20/15.38)
localparam T_RP  = 2;   // 15-20ns PRE->ACT
localparam T_RC  = 4;   // ~60ns ACT->ACT same bank
localparam T_RRD = 1;   // ACT->ACT other bank
localparam T_RFC = 4;   // ~60ns REF->any
localparam T_RAS = 3;   // ~42ns ACT->PRE (auto-precharge earliest)

// memory (16 MB) + auto-precharge bookkeeping
reg [15:0] mem [0:8388607];
reg [3:0]  ap_pending = 0;      // auto-precharge armed per bank
integer    ap_due  [0:3];       // tick when AP closes the row

// read pipeline (CL=2, burst 1): schedule data on the bus
reg [15:0] rd_pipe_data [0:4];
reg        rd_pipe_v    [0:4];
reg [1:0]  dqm_pipe     [0:4];
integer i;

reg [15:0] chip_dq_r; reg chip_dq_oe = 0;
assign sd_data = chip_dq_oe ? chip_dq_r : 16'bz;

always @(posedge clk64) begin
	tick = tick + 1;
	// shift read pipe
	chip_dq_oe <= rd_pipe_v[0];
	chip_dq_r  <= rd_pipe_data[0];
	for (i = 0; i < 4; i = i + 1) begin
		rd_pipe_v[i] <= rd_pipe_v[i+1]; rd_pipe_data[i] <= rd_pipe_data[i+1];
		dqm_pipe[i]  <= dqm_pipe[i+1];
	end
	rd_pipe_v[4] <= 0; dqm_pipe[4] <= sd_dqm;
	// auto-precharge maturation
	for (i = 0; i < 4; i = i + 1)
		if (ap_pending[i] && tick >= ap_due[i]) begin
			bk_open[i] <= 0; ap_pending[i] <= 0; bk_pre_t[i] <= tick;
		end

	if (!init && mrs_done == 0 && cmd == C_MRS) mrs_done = 1;

	case (cmd)
	C_ACT: begin
		if (tick - ref_t < T_RFC)              viol("ACT violates tRFC after refresh");
		if (bk_open[sd_ba] && !ap_pending[sd_ba]) viol("ACT to already-open bank (no precharge)");
		if (ap_pending[sd_ba])                 viol("ACT while auto-precharge still closing");
		if (tick - bk_act_t[sd_ba] < T_RC)     viol("tRC violation (ACT->ACT same bank)");
		if (tick - bk_pre_t[sd_ba] < T_RP)     viol("tRP violation (PRE->ACT)");
		if (tick - last_act_t < T_RRD)         viol("tRRD violation");
		bk_open[sd_ba] <= 1; bk_row[sd_ba] <= sd_addr;
		bk_act_t[sd_ba] = tick; last_act_t = tick;
	end
	C_RD: begin
		if (!bk_open[sd_ba]) viol("READ to closed bank");
		if (tick - bk_act_t[sd_ba] < T_RCD) viol("tRCD violation on READ");
		// drive CL..CL+2: the FPGA's STATE_READ (+2 margin) samples inside the
		// physical tAC/tOH window, which spans past the nominal burst cycle.
		rd_pipe_v[1]    <= 1;
		rd_pipe_v[2]    <= 1;
		rd_pipe_v[3]    <= 1;
		rd_pipe_data[1] <= mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}];
		rd_pipe_data[2] <= mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}];
		rd_pipe_data[3] <= mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}];
		if (sd_addr[10]) begin ap_pending[sd_ba] <= 1; ap_due[sd_ba] <= tick + 2; end
	end
	C_WR: begin
		if (!bk_open[sd_ba]) viol("WRITE to closed bank");
		if (tick - bk_act_t[sd_ba] < T_RCD) viol("tRCD violation on WRITE");
		// same-cycle DQM masking; data sampled at the command edge
		if (!sd_dqm[0]) mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}][7:0]  = sd_data[7:0];
		if (!sd_dqm[1]) mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}][15:8] = sd_data[15:8];
		if (sd_dqm == 2'b11) viol("WRITE with both byte lanes masked (pointless)");
		if (sd_addr[10]) begin ap_pending[sd_ba] <= 1; ap_due[sd_ba] <= tick + 2; end
	end
	C_PRE: begin
		if (sd_addr[10]) bk_open <= 4'b0;
		else             bk_open[sd_ba] <= 0;
		bk_pre_t[sd_ba] = tick;
	end
	C_REF: begin
		if (bk_open != 4'b0 && mrs_done) viol("AUTO_REFRESH with a bank open");
		ref_t = tick;
	end
	default: ;
	endcase
end

// ── harness scoreboard + stimulus ──────────────────────────────────────────
reg [15:0] score [0:8388607];
reg        score_v [0:8388607];

integer seed = 42;
integer n_reads = 0, n_writes = 0, n_aband = 0, n_dl = 0, n_flp = 0;
integer stale_done_checks = 0;

// Law-6 detector: a NEW request must never see done already high.
task automatic chk_no_stale_done; begin
	if (dut_done !== 1'b0) begin
		mismatches = mismatches + 1;
		$display("MISMATCH @%0t: STALE-DONE — cpu_done high at request issue", $time);
	end
	stale_done_checks = stale_done_checks + 1;
end endtask

// one CPU write, Phase-B shaped (request level up, done posts, hold, release)
task automatic cpu_write(input [23:0] a, input [15:0] d, input [1:0] ds_i, input integer gap);
	integer w;
begin
	@(posedge clk_sys); #2; chk_no_stale_done;
	r_addr = a; r_din = d; r_ds = ds_i; r_we = 1;
	w = 0;
	while (w < 200 && !dut_done) begin @(posedge clk_sys); w = w + 1; end
	if (w >= 200) begin mismatches = mismatches + 1; $display("MISMATCH @%0t: WRITE TIMEOUT a=%h", $time, a); end
	// FSM holds AS ~2 more ticks after done
	@(posedge clk_sys); @(posedge clk_sys); #2;
	r_we = 0;
	if (score_v[a]) begin
		if (ds_i[1]) score[a][15:8] = d[15:8];
		if (ds_i[0]) score[a][7:0]  = d[7:0];
	end else begin
		score[a] = d; score_v[a] = 1;
		if (!ds_i[1] || !ds_i[0]) score_v[a] = 0;  // partial first write: don't check
	end
	n_writes = n_writes + 1;
	repeat (gap) @(posedge clk_sys);
end endtask

// one CPU read with data check at the FSM's din_r latch point (done+2)
task automatic cpu_read(input [23:0] a, input integer gap);
	integer w;
begin
	@(posedge clk_sys); #2; chk_no_stale_done;
	r_addr = a; r_ds = 2'b11; r_oe = 1;
	w = 0;
	while (w < 200 && !dut_done) begin @(posedge clk_sys); w = w + 1; end
	if (w >= 200) begin mismatches = mismatches + 1; $display("MISMATCH @%0t: READ TIMEOUT a=%h", $time, a); end
	@(posedge clk_sys); @(posedge clk_sys);   // exit+2 = din_r latch point
	if (score_v[a] && dut_cpu_dout !== score[a]) begin
		mismatches = mismatches + 1;
		$display("MISMATCH @%0t: READ a=%h got %h expected %h", $time, a, dut_cpu_dout, score[a]);
		if (mismatches > 60) begin $display("TOO MANY MISMATCHES � aborting"); $finish; end
	end
	#2; r_oe = 0;
	n_reads = n_reads + 1;
	repeat (gap) @(posedge clk_sys);
end endtask

// abandoned read: raise oe, drop it after `hold` ticks REGARDLESS of done
// (the cache-hit shape), then verify the next real access is unpolluted.
task automatic cpu_abandon(input [23:0] a, input integer hold);
begin
	@(posedge clk_sys); #2;
	r_addr = a; r_ds = 2'b11; r_oe = 1;
	repeat (hold) @(posedge clk_sys);
	#2; r_oe = 0;
	n_aband = n_aband + 1;
end endtask

// download word via dl_* port
task automatic dl_word(input [23:0] a, input [15:0] d);
	integer w;
begin
	@(posedge clk_sys); #2;
	r_dl_addr = a; r_dl_din = d; r_dl_req = 1;
	w = 0;
	while (w < 400 && !dut_dl_ack) begin @(posedge clk_sys); w = w + 1; end
	if (w >= 400) begin mismatches = mismatches + 1; $display("MISMATCH @%0t: DL TIMEOUT", $time); end
	@(posedge clk_sys); #2;
	r_dl_req = 0;
	score[a] = d; score_v[a] = 1;
	@(posedge clk_sys);
	n_dl = n_dl + 1;
end endtask

// floppy window fetch: assert flp_win for one slot-length, check dout
task automatic flp_fetch(input [23:0] a);
begin
	@(posedge clk_sys);
	r_flp_addr <= a; r_flp_guard <= 1;
	@(posedge clk_sys);
	r_flp_win <= 1;
	repeat (4) @(posedge clk_sys);   // one slot
	r_flp_win <= 0; r_flp_guard <= 0;
	@(posedge clk_sys);
	if (score_v[a] && dut_dout !== score[a]) begin
		mismatches = mismatches + 1;
		$display("MISMATCH @%0t: FLP a=%h got %h expected %h", $time, a, dut_dout, score[a]);
	end
	n_flp = n_flp + 1;
end endtask

integer k;
reg [23:0] ra;
reg [15:0] rd;
integer ph;
initial begin
	for (k = 0; k < 8388608; k = k + 1) score_v[k] = 0;
	r_flp_guard = 0;
	// wait out the init ladder (1023 clk_8 periods) + margin
	repeat (9000) @(posedge clk64);
	$display("=== phase 1: write/readback sweep across banks/rows/phases ===");
	for (k = 0; k < 400; k = k + 1) begin
		ra = $random(seed); ra = ra & 24'h7FFFFF;
		rd = $random(seed);
		cpu_write(ra, rd, 2'b11, ($random(seed)) & 3);
		cpu_read(ra, ($random(seed)) & 3);
	end
	$display("=== phase 2: byte-lane writes ===");
	for (k = 0; k < 100; k = k + 1) begin
		ra = ($random(seed)) & 24'h7FFFFF;
		rd = $random(seed);
		cpu_write(ra, rd, 2'b11, 1);
		cpu_write(ra, ~rd, 2'b10, 1);   // high byte only
		score[ra] = {~rd[15:8], rd[7:0]}; score_v[ra] = 1;
		cpu_read(ra, 2);
	end
	$display("=== phase 3: posted-write -> immediate read (ordering) ===");
	for (k = 0; k < 200; k = k + 1) begin
		ra = ($random(seed)) & 24'h7FFFFF;
		rd = $random(seed);
		cpu_write(ra, rd, 2'b11, 0);    // zero gap: read chases the posted write
		cpu_read(ra, 0);
	end
	$display("=== phase 4: abandoned reads (cache-hit shape) + Law 6 ===");
	for (k = 0; k < 300; k = k + 1) begin
		ra = ($random(seed)) & 24'h7FFFFF;
		cpu_abandon(ra, 2 + (($random(seed)) & 3));   // drop oe at tick 2-5
		ra = ($random(seed)) & 24'h7FFFFF;
		if (($random(seed)) & 1) cpu_read(ra, 0); else begin
			rd = $random(seed); cpu_write(ra, rd, 2'b11, 0);
		end
	end
	$display("=== phase 5: refresh-forced interleave (idle gaps) ===");
	for (k = 0; k < 40; k = k + 1) begin
		repeat (350) @(posedge clk64);   // idle past REF_OPP
		ra = ($random(seed)) & 24'h7FFFFF;
		cpu_read(ra, 0);
	end
	$display("=== phase 6: dl port + cpu interleave ===");
	for (k = 0; k < 100; k = k + 1) begin
		dl_word(24'h500000 + k, k[15:0] ^ 16'hA5C3);
		ra = ($random(seed)) & 24'h7FFFFF;
		cpu_read(ra, 0);
	end
	for (k = 0; k < 100; k = k + 1) cpu_read(24'h500000 + k, 0);
	$display("=== phase 7: floppy windows + guard vs cpu stream ===");
	for (k = 0; k < 50; k = k + 1) begin
		rd = $random(seed);
		cpu_write(24'h600000 + k, rd, 2'b11, 1);
	end
	for (k = 0; k < 50; k = k + 1) begin
		flp_fetch(24'h600000 + k);
		ra = ($random(seed)) & 24'h0FFFFF;
		cpu_read(ra, 0);
	end
	$display("");
	$display("reads=%0d writes=%0d abandons=%0d dl=%0d flp=%0d stale-done-checks=%0d",
	         n_reads, n_writes, n_aband, n_dl, n_flp, stale_done_checks);
	if (violations == 0 && mismatches == 0)
		$display("ALL CHECKS PASSED");
	else
		$display("FAILED: %0d protocol violations, %0d data mismatches", violations, mismatches);
	$finish;
end

// temporary probe: what blocks the first request?
integer dbg_n = 0;
always @(posedge clk64)
	if ((r_we || r_oe) && !dut.seq_busy && !dut.cpu_done && dbg_n < 40) begin
		dbg_n = dbg_n + 1;
		$display("PROBE t=%0d seq_busy=%b ref_busy=%b ref_due=%0d done=%b we=%b oe=%b reset=%0d",
			dut.t, dut.seq_busy, dut.ref_busy, dut.ref_due, dut.cpu_done, r_we, r_oe, dut.reset);
	end

// global watchdog
initial begin
	#80000000;
	$display("WATCHDOG TIMEOUT — bench hung");
	$finish;
end

endmodule
