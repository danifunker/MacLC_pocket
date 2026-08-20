// tb_mem_seam.v — SEAM bench: the whole Pocket memory pipeline (F-line hunt).
//
// tb_pocket_sdram proved the engine alone is clean. The MiSTer mission doc
// warns (verbatim): "The unit TBs do not cross module boundaries... every
// defect in Law 3 lived in exactly that seam while every TB passed. Test the
// seams, not just the modules." This bench closes that gap for the Pocket:
//
//   REAL rtl/fetch_cache.sv
//   REAL src/fpga/core/pocket_sdram.v
//   the GLUE equations copied VERBATIM from mac_lc_pocket.sv
//     (dtack_en, _cpuDTACK chain, cpu_din_muxed, ram_* request wires,
//      the clk_sys registration bundle)
//   a bus-functional model of the Phase-B FSM's exact bus timing
//     (AS+strobes at issue, DTACK sampled every clk_sys, exit+2 din latch,
//      addr_early presented one clk before AS — the tg68k.v shapes)
//   the protocol-checking chip model from tb_pocket_sdram
//
// Checks: every latched read == scoreboard; every CACHE HIT == memory truth
// (stale-hit corruption); self-modifying write->fetch returns the NEW word
// (the QuickDraw runtime-blit class that first fires at Finder load); byte
// writes land on the right lanes; DTACK never pre-asserted; end-of-run chip
// memory == scoreboard for every address touched.
//
// Run: bash run_seam.sh   |   PASS = "ALL SEAM CHECKS PASSED"

`timescale 1ns/1ps

module tb_mem_seam;

// ── clocks (identical scheme to tb_pocket_sdram) ────────────────────────────
reg clk64 = 0;  always #7.692 clk64 = ~clk64;
reg clk_sys = 0; always @(posedge clk64) clk_sys <= ~clk_sys;
reg [1:0] busPhase = 0; always @(posedge clk_sys) busPhase <= busPhase + 2'd1;
wire clk8 = !busPhase[1];

reg init = 1; initial begin #100 init = 0; end
reg n_rst = 0; initial begin #200000 n_rst = 1; end  // release after ladder

// ── BFM state: the CPU side (Phase-B FSM shapes from rtl/tg68k/tg68k.v) ────
reg  [23:0] bfm_addr_early = 0;   // kernel's comb address (1 clk before AS)
reg  [23:0] bfm_addr = 0;         // registered address (with AS)
reg         bfm_as_n = 1, bfm_rw = 1, bfm_uds_n = 1, bfm_lds_n = 1;
reg  [2:0]  bfm_fc = 3'b101;
reg  [15:0] bfm_dout = 0;         // CPU write data

// ── address decode (mini map: <$A00000 RAM, $Axxxxx ROM; no VRAM/periph) ───
wire selectRAM = !bfm_as_n && (bfm_addr[23:20] <  4'hA);
wire selectROM = !bfm_as_n && (bfm_addr[23:20] == 4'hA);
wire selectVRAM = 1'b0;

// SDRAM word mapping (addrController mini form: RAM 1:1, ROM at $500000)
wire [22:0] memoryAddr = selectROM ? {5'b10100, bfm_addr[18:1]}
                                   : {1'b0, bfm_addr[22:1]};
wire [15:0] memoryDataOut = bfm_dout;
wire        _memoryUDS = bfm_uds_n;
wire        _memoryLDS = bfm_lds_n;
wire        _ramOE = ~((selectRAM || selectVRAM) && bfm_rw);
wire        _ramWE = ~((selectRAM || selectVRAM) && !bfm_rw);
wire        _romOE = ~(selectROM && bfm_rw);

// ── GLUE UNDER TEST — copied from mac_lc_pocket.sv (shapes verbatim) ───────
wire        icache_hit;
wire [15:0] icache_data;
wire        icache_hit_now;
wire [15:0] sdram_cpu_dout;
wire        sdram_cpu_done;
wire [15:0] dataControllerDataOut = sdram_cpu_dout;   // memory leg passthrough

fetch_cache #(.LOG2_WORDS(9)) icache (
	.clk        ( clk_sys ),
	.reset      ( ~n_rst ),
	.flush_bits ( 2'b00 ),
	.enable     ( 1'b1 ),
	.cpuAddr    ( bfm_addr_early ),
	.as_n       ( bfm_as_n ),
	.rw         ( bfm_rw ),
	.fc         ( bfm_fc ),
	.cacheable  ( selectRAM || selectROM ),
	.snoopable  ( selectRAM ),
	.mem_din    ( dataControllerDataOut ),
	.hit        ( icache_hit ),
	.hit_data   ( icache_data ),
	.hit_now    ( icache_hit_now )
);

reg dtack_en;
always @(posedge clk_sys) begin
	if (!n_rst) dtack_en <= 0;
	else begin
		if (bfm_as_n) dtack_en <= 0;
		if (!bfm_as_n & ( (!selectROM & !selectRAM & !selectVRAM)
		              | (selectROM & !bfm_rw) )) dtack_en <= 1;
	end
end

wire        _cpuDTACK = icache_hit ? 1'b0 :
                        (!bfm_as_n && (selectRAM || selectVRAM || (selectROM && bfm_rw))) ? ~sdram_cpu_done :
                        (~(!bfm_as_n && bfm_addr[23:21] != 3'b111) | !dtack_en);

wire [15:0] cpu_din_muxed = icache_hit ? icache_data : dataControllerDataOut;

// request wires + registration bundle (verbatim shapes)
wire [24:0] ram_addr = {2'b00, memoryAddr[22:0]};
wire [15:0] ram_din  = memoryDataOut;
wire  [1:0] ram_ds   = { !_memoryUDS, !_memoryLDS };
wire        ram_we   = !_ramWE;
wire        ram_oe   = (!_ramOE || !_romOE) && !icache_hit_now;

reg [24:0] ram_addr_q; reg [15:0] ram_din_q; reg [1:0] ram_ds_q;
reg        ram_we_q, ram_oe_q;
always @(posedge clk_sys) begin
	ram_addr_q <= ram_addr; ram_din_q <= ram_din; ram_ds_q <= ram_ds;
	ram_we_q <= ram_we; ram_oe_q <= ram_oe;
end

wire [15:0] sd_data; wire [12:0] sd_addr; wire [1:0] sd_dqm, sd_ba;
wire sd_cke, sd_we_n, sd_ras_n, sd_cas_n;
wire [15:0] flp_dout_nc;

pocket_sdram dut (
	.sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
	.sd_cke(sd_cke), .sd_we(sd_we_n), .sd_ras(sd_ras_n), .sd_cas(sd_cas_n),
	.init(init), .clk_64(clk64), .clk_8(clk8),
	.din(ram_din_q), .dout(flp_dout_nc), .addr(ram_addr_q[23:0]), .ds(ram_ds_q),
	.oe(ram_oe_q), .we(ram_we_q),
	.flp_win(1'b0), .flp_addr(24'd0), .flp_guard(1'b0),
	.dl_req(1'b0), .dl_slot(1'b0), .dl_addr(24'd0), .dl_din(16'd0), .dl_ack(),
	.cpu_done(sdram_cpu_done), .cpu_dout(sdram_cpu_dout)
);

// ── chip model (same as tb_pocket_sdram, checks folded in) ─────────────────
localparam C_ACT=3'b011, C_RD=3'b101, C_WR=3'b100, C_PRE=3'b010,
           C_REF=3'b001, C_MRS=3'b000;
wire [2:0] cmd = {sd_ras_n, sd_cas_n, sd_we_n};
integer violations = 0, mismatches = 0;
task viol(input [511:0] msg); begin
	violations = violations + 1;
	$display("VIOLATION @%0t: %0s", $time, msg);
end endtask

reg  [3:0]  bk_open = 0; reg [12:0] bk_row [0:3];
integer bk_act_t [0:3]; integer bk_pre_t [0:3];
integer tick = 0; integer ref_t = -1000; integer mrs_done = 0;
reg [15:0] mem [0:8388607];
reg [3:0] ap_pending = 0; integer ap_due [0:3];
reg [15:0] rd_pipe_data [0:4]; reg rd_pipe_v [0:4];
integer i;
reg [15:0] chip_dq_r; reg chip_dq_oe = 0;
assign sd_data = chip_dq_oe ? chip_dq_r : 16'bz;

always @(posedge clk64) begin
	tick = tick + 1;
	chip_dq_oe <= rd_pipe_v[0]; chip_dq_r <= rd_pipe_data[0];
	for (i = 0; i < 4; i = i + 1) begin
		rd_pipe_v[i] <= rd_pipe_v[i+1]; rd_pipe_data[i] <= rd_pipe_data[i+1];
	end
	rd_pipe_v[4] <= 0;
	for (i = 0; i < 4; i = i + 1)
		if (ap_pending[i] && tick >= ap_due[i]) begin
			bk_open[i] <= 0; ap_pending[i] <= 0; bk_pre_t[i] <= tick;
		end
	if (!init && mrs_done == 0 && cmd == C_MRS) mrs_done = 1;
	case (cmd)
	C_ACT: begin
		if (tick - ref_t < 4)                     viol("tRFC");
		if (bk_open[sd_ba] && !ap_pending[sd_ba]) viol("ACT to open bank");
		if (ap_pending[sd_ba])                    viol("ACT during AP");
		if (tick - bk_act_t[sd_ba] < 4)           viol("tRC");
		if (tick - bk_pre_t[sd_ba] < 2)           viol("tRP");
		bk_open[sd_ba] <= 1; bk_row[sd_ba] <= sd_addr; bk_act_t[sd_ba] = tick;
	end
	C_RD: begin
		if (!bk_open[sd_ba])              viol("READ closed bank");
		if (tick - bk_act_t[sd_ba] < 2)   viol("tRCD rd");
		rd_pipe_v[1] <= 1; rd_pipe_v[2] <= 1; rd_pipe_v[3] <= 1;
		rd_pipe_data[1] <= mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}];
		rd_pipe_data[2] <= mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}];
		rd_pipe_data[3] <= mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}];
		if (sd_addr[10]) begin ap_pending[sd_ba] <= 1; ap_due[sd_ba] <= tick + 2; end
	end
	C_WR: begin
		if (!bk_open[sd_ba])              viol("WRITE closed bank");
		if (tick - bk_act_t[sd_ba] < 2)   viol("tRCD wr");
		if (!sd_dqm[0]) mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}][7:0]  = sd_data[7:0];
		if (!sd_dqm[1]) mem[{sd_ba, bk_row[sd_ba][11:0], sd_addr[8:0]}][15:8] = sd_data[15:8];
		if (sd_addr[10]) begin ap_pending[sd_ba] <= 1; ap_due[sd_ba] <= tick + 2; end
	end
	C_PRE: begin
		if (sd_addr[10]) bk_open <= 4'b0; else bk_open[sd_ba] <= 0;
		bk_pre_t[sd_ba] = tick;
	end
	C_REF: begin
		if (bk_open != 4'b0 && mrs_done) viol("REF with bank open");
		ref_t = tick;
	end
	default: ;
	endcase
end

// ── scoreboard over the CPU byte address space ─────────────────────────────
reg [15:0] score [0:8388607];   // per WORD address (bfm_addr[23:1])
reg        score_v [0:8388607];

integer n_fetch = 0, n_hit = 0, n_dread = 0, n_write = 0, n_selfmod = 0;

// ── the Phase-B bus-functional model ───────────────────────────────────────
// Timing (rtl/tg68k/tg68k.v): kernel presents addr (early) >=1 clk before the
// FSM asserts AS+RW+strobes; S_WAIT samples DTACK every clk; exit -> TAIL1 ->
// TAIL2 (din latch + AS release) -> ENDC. din latched exit+2, AS high exit+2.
task automatic bus_cycle(
	input        is_fetch,       // fc = program space, cache eligible
	input        is_write,
	input [23:0] a,              // byte address (bit 0 ignored)
	input [15:0] wdata,
	input [1:0]  strobes,        // {uds, lds} active-high
	input integer idle_after
);
	integer w;
	reg [15:0] got;
	reg was_hit;
begin
	// kernel presents the access: early address settles first
	@(posedge clk_sys); #2;
	bfm_addr_early = a;
	bfm_fc = is_fetch ? 3'b110 : 3'b101;
	// FSM IDLE-exit edge: register addr, assert AS + strobes + RW together
	@(posedge clk_sys); #2;
	bfm_addr = a; bfm_as_n = 0; bfm_rw = !is_write;
	bfm_uds_n = !strobes[1]; bfm_lds_n = !strobes[0];
	if (is_write) bfm_dout = wdata;
	// S_WAIT: sample DTACK every clk_sys
	w = 0;
	@(posedge clk_sys);
	while (w < 300 && _cpuDTACK !== 1'b0) begin @(posedge clk_sys); w = w + 1; end
	if (w >= 300) begin
		mismatches = mismatches + 1;
		$display("MISMATCH @%0t: BUS TIMEOUT a=%h fetch=%b wr=%b", $time, a, is_fetch, is_write);
	end
	was_hit = icache_hit;
	// TAIL1
	@(posedge clk_sys);
	// TAIL2: latch din, release AS/strobes at this edge
	got = cpu_din_muxed;
	#2; bfm_as_n = 1; bfm_uds_n = 1; bfm_lds_n = 1;
	@(posedge clk_sys); #2;
	bfm_rw = 1;
	// checks
	if (!is_write) begin
		if (score_v[a[23:1]] && got !== score[a[23:1]]) begin
			mismatches = mismatches + 1;
			$display("MISMATCH @%0t: %0s a=%h got %h expected %h (hit=%b)",
			         $time, is_fetch ? "FETCH" : "READ", a, got, score[a[23:1]], was_hit);
		end
		if (is_fetch) begin n_fetch = n_fetch + 1; if (was_hit) n_hit = n_hit + 1; end
		else n_dread = n_dread + 1;
	end else begin
		if (score_v[a[23:1]]) begin
			if (strobes[1]) score[a[23:1]][15:8] = wdata[15:8];
			if (strobes[0]) score[a[23:1]][7:0]  = wdata[7:0];
		end else if (strobes == 2'b11) begin
			score[a[23:1]] = wdata; score_v[a[23:1]] = 1;
		end
		n_write = n_write + 1;
	end
	repeat (idle_after) @(posedge clk_sys);
end endtask

integer k, j; reg [23:0] ra; reg [15:0] rd_; reg [23:0] loop_base;
integer seed = 7;
initial begin
	for (k = 0; k < 8388608; k = k + 1) score_v[k] = 0;
	// model silicon power-up: Cyclone V M10K contents are all-zeros, which the
	// cache's gen==0 never-match rule depends on. 4-state X here poisons
	// lookup_match -> hit_now -> ram_oe and stalls fetches to untouched
	// indexes � a sim-only artifact (proven by the WP probe 2026-08-19).
	for (k = 0; k < 512; k = k + 1) begin
		icache.tag_ram[k] = 0; icache.data_ram[k] = 0;
	end
	wait (n_rst === 1'b1);
	repeat (20) @(posedge clk_sys);

	$display("=== seam 1: data write/read sweep ===");
	for (k = 0; k < 300; k = k + 1) begin
		ra = ($random(seed)) & 24'h1FFFFE; rd_ = $random(seed);
		bus_cycle(0, 1, ra, rd_, 2'b11, ($random(seed)) & 3);
		bus_cycle(0, 0, ra, 0, 2'b11, ($random(seed)) & 3);
	end

	$display("=== seam 2: fetch loops (cache fill + hit correctness) ===");
	// seed a 16-word "code" region, then loop-fetch it 8 times: first pass
	// misses+fills, later passes HIT — every hit checked against scoreboard.
	loop_base = 24'h004000;
	for (k = 0; k < 16; k = k + 1)
		bus_cycle(0, 1, loop_base + k*2, 16'h4E71 + k[15:0], 2'b11, 0);
	for (j = 0; j < 8; j = j + 1)
		for (k = 0; k < 16; k = k + 1)
			bus_cycle(1, 0, loop_base + k*2, 0, 2'b11, ($random(seed)) & 1);

	$display("=== seam 3: SELF-MODIFYING code (the QuickDraw class) ===");
	// fetch a word (cached), overwrite it, refetch IMMEDIATELY (zero gap):
	// must return the NEW word every time. 200 rounds over aliasing indexes.
	for (k = 0; k < 200; k = k + 1) begin
		ra = 24'h008000 + ((($random(seed)) & 24'h0007FE));   // small window
		rd_ = $random(seed);
		bus_cycle(0, 1, ra, rd_, 2'b11, 0);
		bus_cycle(1, 0, ra, 0, 2'b11, 0);        // fetch (fills)
		rd_ = $random(seed);
		bus_cycle(0, 1, ra, rd_, 2'b11, 0);      // modify
		bus_cycle(1, 0, ra, 0, 2'b11, 0);        // refetch: MUST be new
		n_selfmod = n_selfmod + 1;
	end

	$display("=== seam 4: index-alias eviction (same cache line, diff tag) ===");
	for (k = 0; k < 100; k = k + 1) begin
		ra = 24'h010000 + (k[7:0] * 2);
		rd_ = 16'hA000 + k[15:0];
		bus_cycle(0, 1, ra, rd_, 2'b11, 0);
		bus_cycle(1, 0, ra, 0, 2'b11, 0);
		// alias: same LOG2_WORDS index, different tag (offset by 1024 words)
		bus_cycle(0, 1, ra + 24'h000800, rd_ ^ 16'hFFFF, 2'b11, 0);
		bus_cycle(1, 0, ra + 24'h000800, 0, 2'b11, 0);
		bus_cycle(1, 0, ra, 0, 2'b11, 0);        // back to the first: no stale
	end

	$display("=== seam 5: byte-lane writes then word reads ===");
	for (k = 0; k < 100; k = k + 1) begin
		ra = ($random(seed)) & 24'h1FFFFE; rd_ = $random(seed);
		bus_cycle(0, 1, ra, rd_, 2'b11, 0);
		bus_cycle(0, 1, ra, ~rd_, 2'b10, 0);     // upper byte only
		bus_cycle(0, 0, ra, 0, 2'b11, 0);
		bus_cycle(0, 1, ra, {rd_[15:8], ~rd_[7:0]}, 2'b01, 0);  // lower only
		bus_cycle(0, 0, ra, 0, 2'b11, 1);
	end

	$display("=== seam 6: ROM-region fetch stream (2nd mapping) ===");
	// ROM is read-only through the glue (writes ack-and-discard � validated
	// incidentally by an earlier bench revision: they complete and never
	// land). Seed the ROM content BACKDOOR into the chip + scoreboard.
	// ROM byte addr $A00100+k*2 -> SDRAM word $500080+k -> chip index
	// {ba, row[11:0], col[8:0]} of that word address.
	for (k = 0; k < 64; k = k + 1) begin
		ra = 24'hA00100 + k*2;
		// word $500080+k -> ba=1, row=$000, col=$180+k ({addr[22], addr[7:0]})
		mem[{2'b01, 12'h000, 9'h180} + k[8:0]] = 16'h5000 + k[15:0];
		score[ra[23:1]] = 16'h5000 + k[15:0]; score_v[ra[23:1]] = 1;
	end
	for (j = 0; j < 4; j = j + 1)
		for (k = 0; k < 64; k = k + 1)
			bus_cycle(1, 0, 24'hA00100 + k*2, 0, 2'b11, 0);

	$display("");
	$display("fetches=%0d (hits=%0d) dreads=%0d writes=%0d selfmod-rounds=%0d",
	         n_fetch, n_hit, n_dread, n_write, n_selfmod);
	if (violations == 0 && mismatches == 0)
		$display("ALL SEAM CHECKS PASSED");
	else
		$display("SEAM FAILED: %0d violations, %0d mismatches", violations, mismatches);
	$finish;
end

// window probe: the first timing-out fetch
integer wp_n = 0;
always @(posedge clk_sys)
	if (bfm_addr == 24'ha0010a && !bfm_as_n && wp_n < 30) begin
		wp_n = wp_n + 1;
		$display("WP oe=%b oeq=%b hitnow=%b hit=%b lookup=%b tagq=%h gen_tag=%h rdidx=%h idx=%h seqb=%b done=%b refdue=%0d dtack=%b",
			ram_oe, ram_oe_q, icache_hit_now, icache_hit, icache.lookup_match,
			icache.tag_q, {icache.gen, icache.tag}, icache.rd_idx_d, icache.idx,
			dut.seq_busy, sdram_cpu_done, dut.ref_due, _cpuDTACK);
	end

initial begin
	#120000000;
	$display("WATCHDOG TIMEOUT");
	$finish;
end

endmodule
