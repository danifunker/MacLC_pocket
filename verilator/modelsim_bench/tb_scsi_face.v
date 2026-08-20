// tb_scsi_face.v — the REAL ncr5380 pseudo-DMA host face under Phase-B pacing
// (2026-08-20, 7.5.5 hunt, bench B — complements tb_scsi_ring which cleared
// the scsi_dpram seam).
//
// UNDER TEST (real RTL): ncr5380.sv complete — the DACK width-latch state
// machine (word/longword/second-word/suppress), the ack-train generator, the
// dma_settle=8 / dma_ack_holdoff DREQ gating, and the 2026-07-19 "PDMA
// host-face pipeline registers" fit-hardening — the layer the MiSTer release
// does NOT run, exercised at pacings the old 8-tick walker could never
// produce (inter-cycle gap down to 2 clks, every sample distance).
//
// BEHAVIORAL: the scsi target module only (this file provides a `scsi` stub
// with the full port surface), serving ramp() bytes with the EXACT delivery
// contract rtl/scsi.v documents and dma_settle was derived from:
//   - data_cnt advances 2 clks after each ACK falling edge,
//   - dout/dout_pair/dout_pair_next update 1 clk after that
//     (= presented data stale for 3 clks after an ack train retires),
//   - REQ drops for a parameterized stall every 512 bytes (ring fetch).
// If the ncr face ever lets a host sampling alignment see the stale window,
// or drops/duplicates an ack under fast trains, the byte stream shifts and
// the ramp compare catches it — that is precisely the pre-settle bug class
// ("stream shifted -1/-2, longword pre-latches a duplicate second word").
//
// PASS = "ALL FACE CHECKS PASSED".
// Run: bash run_scsi_face.sh

`timescale 1ns/1ps

// ---------------- behavioral scsi target stub ----------------
module scsi #(parameter ID=0, CDROM=0, CDCHANGER_ENABLE=0, TOOLBOX_ENABLE=0,
              TB_ADDRW=8, RING_LOG=5)
(
	input             clk,
	input             rst,
	input             sys_rst,
	input             sel,
	input             bus_busy,
	input             atn,
	input             cd_enable,
	output reg        bsy,
	output reg        msg,
	output reg        cd,
	output reg        io,
	output reg        req,
	output            req_bus,
	input             ack,
	input             host_csr_rd,
	input             host_data_rd,
	input       [7:0] din,
	output      [7:0] dout,
	output     [15:0] dout_pair,
	output     [15:0] dout_pair_next,
	input             img_mounted,
	input      [31:0] img_blocks,
	output     [31:0] io_lba,
	output            io_rd,
	output reg        io_wr,
	input             io_ack,
	input       [7:0] sd_buff_addr,
	input       [4:0] sd_buff_addr_hi,
	input      [15:0] sd_buff_dout,
	output     [15:0] sd_buff_din,
	input             sd_buff_wr,
	input             tb_mounted,
	output     [31:0] tb_lba,
	output            tb_rd,
	output            tb_wr,
	input             tb_ack,
	output     [15:0] tb_buff_din,
	output            dbg_mounted,
	output      [2:0] dbg_phase,
	output      [7:0] dbg_hs,
	output      [3:0] dbg_hs2,
	output      [7:0] dbg_cmd,
	input             dbg_dma_word,
	input             dbg_dma_long,
	input       [7:0] dbg_dma_lowbyte,
	output     [31:0] dbg_wrsnap,
	output     [31:0] dbg_selsnap,
	output     [31:0] dbg_wrstall,
	output     [31:0] dbg_wrfb,
	output     [31:0] dbg_ring,
	output     [31:0] dbg_cda1
);

function [7:0] ramp(input [31:0] off);
	ramp = off[7:0] ^ off[15:8] ^ off[23:16];
endfunction

// stall behavior knobs (hierarchically set by the TB)
integer stall_len = 0;          // REQ drop at each 512-boundary, clks

localparam P_IDLE=0, P_CMD=1, P_DATAIN=2, P_STATUS=3, P_MSGIN=4;
integer phase = P_IDLE;
integer cmd_i = 0;
reg [7:0] cdb [0:5];
reg [31:0] data_cnt = 0;
reg [31:0] data_len = 0;
integer stall_t = 0;
reg mounted = 0;
// 4-state power-up: every output reg must have a defined value � the CD
// instance and an unmounted disk target never execute an assigning branch,
// and an X bsy poisons bus_busy for everyone (the t-counter lesson, again).
initial begin bsy = 0; msg = 0; cd = 0; io = 0; req = 0; io_wr = 0; end
reg ack_d = 0;
reg [1:0] adv_pipe = 0;         // ack-fall -> +2 clks advance -> +1 clk visible
reg adv_vis = 0;
reg [31:0] vis_cnt = 0;         // the data_cnt the OUTPUTS currently show

assign dout           = ramp(vis_cnt);
assign dout_pair      = {ramp(vis_cnt), ramp(vis_cnt + 1)};
assign dout_pair_next = {ramp(vis_cnt + 2), ramp(vis_cnt + 3)};
assign req_bus = req || (phase == P_DATAIN && stall_t != 0);

assign io_lba = 0; assign io_rd = 0; assign sd_buff_din = 0;
assign tb_lba = 0; assign tb_rd = 0; assign tb_wr = 0; assign tb_buff_din = 0;
assign dbg_mounted = mounted; assign dbg_phase = phase[2:0];
assign dbg_hs = 0; assign dbg_hs2 = 0; assign dbg_cmd = 0;
assign dbg_wrsnap = 0; assign dbg_selsnap = 0;
assign dbg_wrstall = {16'd0, data_cnt[15:0]};
assign dbg_wrfb = 0; assign dbg_ring = 0; assign dbg_cda1 = 0;

wire selected_id = din[ID] && (CDROM == 0);

always @(posedge clk) begin
	ack_d <= ack;
	io_wr <= 0;
	if (img_mounted) mounted <= 1;
	if (rst) begin
		phase <= P_IDLE; bsy <= 0; msg <= 0; cd <= 0; io <= 0; req <= 0;
		cmd_i <= 0; adv_pipe <= 0; adv_vis <= 0; stall_t <= 0;
	end else begin
		// delivery pipeline: ack FALL -> 2 clks -> data_cnt++ -> 1 clk -> visible
		adv_pipe <= {adv_pipe[0], (ack_d && !ack && phase == P_DATAIN)};
		if (adv_pipe[1]) data_cnt <= data_cnt + 1;
		adv_vis <= adv_pipe[1];
		if (adv_vis) vis_cnt <= data_cnt;

		case (phase)
		P_IDLE: begin
			msg <= 0; cd <= 0; io <= 0; req <= 0;
			if (sel && !bus_busy && selected_id && mounted && CDROM == 0) begin
				bsy <= 1;
				phase <= P_CMD;
				cmd_i <= 0;
				cd <= 1; io <= 0; msg <= 0;   // COMMAND phase
				req <= 1;
			end
		end
		P_CMD: begin
			if (req && ack) begin
				cdb[cmd_i] <= din;
				req <= 0;
			end else if (!req && !ack && !sel) begin
				if (cmd_i == 5) begin
					// READ(6) only in this stub
					data_cnt <= 0; vis_cnt <= 0;
					data_len <= {24'd0, cdb[4]} * 512;
					phase <= P_DATAIN;
					cd <= 0; io <= 1; msg <= 0;
					stall_t <= 0;
					req <= 1;
				end else begin
					cmd_i <= cmi(cmd_i);
					req <= 1;
				end
			end
		end
		P_DATAIN: begin
			// sector-boundary fetch stall: drop REQ for stall_len clks
			if (stall_t != 0) begin
				stall_t <= stall_t - 1;
				if (stall_t == 1) req <= 1;
			end else if (req && ack) begin
				req <= 0;           // this byte is being taken (ack train edge)
			end else if (!req && !ack) begin
				if (data_cnt >= data_len) begin
					phase <= P_STATUS;
					cd <= 1; io <= 1; msg <= 0;
					req <= 1;
				end else if (data_cnt != 0 && data_cnt[8:0] == 9'd0 && stall_len != 0 && data_cnt != vis_cnt) begin
					// boundary reached (count advanced past it): hold REQ down
					stall_t <= stall_len;
				end else if (data_cnt[8:0] == 9'd0 && data_cnt != 0 && stall_len != 0) begin
					stall_t <= stall_len;
				end else
					req <= 1;
			end
		end
		P_STATUS: begin
			if (req && ack) req <= 0;
			else if (!req && !ack) begin phase <= P_MSGIN; msg <= 1; cd <= 1; io <= 1; req <= 1; end
		end
		P_MSGIN: begin
			if (req && ack) req <= 0;
			else if (!req && !ack) begin phase <= P_IDLE; bsy <= 0; msg <= 0; cd <= 0; io <= 0; end
		end
		endcase
	end
end

// status/message bytes serve $00 via dout when not DATA_IN
function integer cmi(input integer x); cmi = x + 1; endfunction

endmodule

// ---------------- the bench ----------------
module tb_scsi_face;

localparam RREG_CDR=0, RREG_CSR=4;
localparam WREG_ODR=0, WREG_ICR=1, WREG_MR=2, WREG_TCR=3, WREG_IDMAR=7;
localparam [7:0] CSR_BSY=8'h40, CSR_REQ=8'h20;
localparam [7:0] ICR_ACK=8'h10, ICR_SEL=8'h04, ICR_DATA=8'h01;

reg clk = 0;
always #15.384 clk = ~clk;

reg reset = 1, bus_cs = 0, ior = 0, iow = 0, dack = 0;
reg [2:0] bus_rs = 0;
reg dma_word = 0, dma_longword = 0, dma_second_word = 0;
wire dreq;
reg  [15:0] wdata = 0;
wire [15:0] rdata;
reg  [1:0] img_mounted = 0;
reg  [31:0] img_size = 0;
wire [63:0] io_lba_f;
wire [31:0] sd_buff_din_f;
wire [1:0] io_rd, io_wr;
wire [31:0] dbg_wr;

ncr5380_bench #(.DEVS(2)) dut (
	.clk(clk), .reset(reset),
	.bus_cs(bus_cs), .bus_rs(bus_rs), .ior(ior), .iow(iow), .dack(dack),
	.dma_word(dma_word), .dma_longword(dma_longword),
	.dma_second_word(dma_second_word),
	.dreq(dreq), .o_irq(), .wdata(wdata), .rdata(rdata),
	.img_mounted(img_mounted), .img_size(img_size),
	.io_lba(io_lba_f), .io_rd(io_rd), .io_wr(io_wr), .io_ack(2'b00),
	.sd_buff_addr(8'd0), .sd_buff_addr_hi(5'd0),
	.sd_buff_dout(16'd0), .sd_buff_din(sd_buff_din_f),
	.sd_buff_wr(1'b0),
	.cd_enable(1'b0), .cd_img_mounted(1'b0),
	.cd_io_lba(), .cd_io_rd(), .cd_io_wr(), .cd_io_ack(1'b0),
	.cd_sd_buff_din(),
	.dbg_scsi(), .dbg_scsi2(), .dbg_scsi3(), .dbg_scsi4(), .dbg_scsi5(),
	.dbg_ncr(), .dbg_ncr2(), .dbg_ring0(), .dbg_ring1(),
	.dbg_wr(dbg_wr), .dbg_wrfb(), .dbg_cd(), .dbg_cd_state()
);

function [7:0] ramp(input [31:0] off);
	ramp = off[7:0] ^ off[15:8] ^ off[23:16];
endfunction

integer mismatches = 0, timeouts = 0;
integer got_cnt;
reg [7:0] got [0:65535];

task tickn(input integer n); integer i; begin
	for (i = 0; i < n; i = i + 1) @(posedge clk);
end endtask

task bus_release; begin
	#2; bus_cs = 0; ior = 0; iow = 0; dack = 0;
	dma_word = 0; dma_longword = 0; dma_second_word = 0;
end endtask

task reg_write(input [2:0] rs, input [7:0] v); begin
	@(posedge clk); #2;
	bus_cs = 1; iow = 1; ior = 0; dack = 0; bus_rs = rs; wdata = {8'h00, v};
	tickn(2); bus_release; tickn(2);
end endtask

task reg_read(input [2:0] rs, output [7:0] v); begin
	@(posedge clk); #2;
	bus_cs = 1; ior = 1; iow = 0; dack = 0; bus_rs = rs;
	tickn(2); v = rdata[7:0];
	bus_release; tickn(2);
end endtask

task wait_csr(input [7:0] mask, input [7:0] val, output ok);
	integer i; reg [7:0] v; begin
	ok = 0;
	for (i = 0; i < 20000 && !ok; i = i + 1) begin
		reg_read(RREG_CSR, v);
		if ((v & mask) == val) ok = 1;
	end
end endtask

task pio_put(input [7:0] b, output ok); begin
	wait_csr(CSR_REQ, CSR_REQ, ok);
	if (ok) begin
		reg_write(WREG_ODR, b);
		reg_write(WREG_ICR, ICR_DATA | ICR_ACK);
		wait_csr(CSR_REQ, 8'h00, ok);
		reg_write(WREG_ICR, ICR_DATA);
	end
end endtask

task dma_read16(input word, input lw, input second,
                input integer ds, input integer gap,
                output [15:0] out, output ok);
	integer w; begin
	@(posedge clk); #2;
	bus_cs = 1; dack = 1; ior = 1; iow = 0; bus_rs = 0;
	dma_word = word; dma_longword = lw; dma_second_word = second;
	@(posedge clk);
	w = 0; ok = 1;
	while (!dreq && w < 30000) begin @(posedge clk); w = w + 1; end
	if (w >= 30000) begin ok = 0; timeouts = timeouts + 1; bus_release; end
	else begin
		tickn(ds);
		out = rdata;
		tickn(1);
		bus_release;
		tickn(gap);
	end
end endtask

task collect16(input [15:0] v); begin
	got[got_cnt] = v[15:8]; got[got_cnt+1] = v[7:0];
	got_cnt = got_cnt + 2;
end endtask

task run_read(input integer mode, input integer sectors,
              input integer ds, input integer gap, input integer stall);
	integer len, d, i, errs;
	reg ok; reg [15:0] v1, v2; reg [7:0] cdb_b;
begin
	dut.target[0].target.stall_len = stall;
	bus_release; img_mounted = 0;
	reset = 1; tickn(8); reset = 0; tickn(4);
	img_size = 32'd131072; img_mounted = 2'b01; tickn(1);
	img_mounted = 0; tickn(4);
	reg_write(WREG_ODR, 8'h01);
	reg_write(WREG_ICR, ICR_DATA | ICR_SEL);
	wait_csr(CSR_BSY, CSR_BSY, ok);
	if (!ok) begin $display("SELECT TIMEOUT"); timeouts = timeouts + 1; bus_release; disable run_read; end
	reg_write(WREG_ICR, ICR_DATA);
	for (i = 0; i < 6; i = i + 1) begin
		cdb_b = (i == 0) ? 8'h08 : (i == 4) ? sectors[7:0] : 8'h00;
		pio_put(cdb_b, ok);
		if (!ok) begin $display("CMD TIMEOUT byte=%0d", i); timeouts = timeouts + 1; bus_release; disable run_read; end
	end
	reg_write(WREG_ICR, 8'h00);
	reg_write(WREG_TCR, 8'h01);
	reg_write(WREG_MR,  8'h02);
	reg_write(WREG_IDMAR, 8'h00);
	len = sectors * 512;
	got_cnt = 0;
	case (mode)
	0: for (d = 0; d < len; d = d + 2) begin
		dma_read16(1, 0, 0, ds, gap, v1, ok);
		if (!ok) begin $display("DREQ TIMEOUT W d=%0d", d); disable run_read; end
		collect16(v1);
	end
	1: for (d = 0; d < len; d = d + 4) begin
		dma_read16(1, 1, 0, ds, gap, v1, ok);
		if (!ok) begin $display("DREQ TIMEOUT L d=%0d", d); disable run_read; end
		dma_read16(1, 1, 1, ds, gap, v2, ok);
		if (!ok) begin $display("DREQ TIMEOUT L2 d=%0d", d); disable run_read; end
		collect16(v1); collect16(v2);
	end
	2: begin
		dma_read16(1, 0, 0, ds, gap, v1, ok);
		if (!ok) begin $display("DREQ TIMEOUT LS pre"); disable run_read; end
		collect16(v1);
		d = 2;
		while (len - d >= 6) begin
			dma_read16(1, 1, 0, ds, gap, v1, ok);
			if (!ok) begin $display("DREQ TIMEOUT LS d=%0d", d); disable run_read; end
			dma_read16(1, 1, 1, ds, gap, v2, ok);
			if (!ok) begin $display("DREQ TIMEOUT LS2 d=%0d", d); disable run_read; end
			collect16(v1); collect16(v2);
			d = d + 4;
		end
		while (d < len) begin
			dma_read16(1, 0, 0, ds, gap, v1, ok);
			if (!ok) begin $display("DREQ TIMEOUT LSt d=%0d", d); disable run_read; end
			collect16(v1); d = d + 2;
		end
	end
	3: begin
		dma_read16(0, 0, 0, ds, gap, v1, ok);
		if (!ok) begin $display("DREQ TIMEOUT WS pre"); disable run_read; end
		got[got_cnt] = v1[7:0]; got_cnt = got_cnt + 1;
		d = 1;
		while (len - d >= 2) begin
			dma_read16(1, 0, 0, ds, gap, v1, ok);
			if (!ok) begin $display("DREQ TIMEOUT WS d=%0d", d); disable run_read; end
			collect16(v1); d = d + 2;
		end
	end
	endcase
	errs = 0;
	for (i = 0; i < got_cnt; i = i + 1)
		if (got[i] !== ramp(i)) begin
			errs = errs + 1;
			if (errs <= 4)
				$display("MISMATCH mode=%0d ds=%0d gap=%0d stall=%0d off=%0d got=%02x exp=%02x",
				         mode, ds, gap, stall, i, got[i], ramp(i));
		end
	mismatches = mismatches + errs;
	$display("run mode=%0d sec=%0d ds=%0d gap=%0d stall=%0d: %0d bytes, %0d errs%s",
	         mode, sectors, ds, gap, stall, got_cnt, errs, errs ? "  ***" : "");
end endtask

integer m, g, s;
initial begin
	$display("SIM ALIVE t=0");
	tickn(20);
	$display("=== gap sweep x modes, no stalls ===");
	for (m = 0; m < 4; m = m + 1)
		for (g = 2; g <= 6; g = g + 2)
			run_read(m, 3, 2, g, 0);
	$display("=== sample-distance sweep on LONG at the gap floor ===");
	for (s = 1; s <= 3; s = s + 1)
		run_read(1, 3, s, 2, 0);
	$display("=== sector-boundary REQ stalls (ring-fetch model) x skew modes ===");
	for (m = 0; m < 4; m = m + 1) begin
		run_read(m, 4, 2, 2, 12);
		run_read(m, 4, 2, 2, 60);
	end
	$display("");
	if (mismatches == 0 && timeouts == 0) $display("ALL FACE CHECKS PASSED");
	else $display("FAILED: %0d mismatches, %0d timeouts", mismatches, timeouts);
	$finish;
end

initial begin #60000000; $display("WATCHDOG TIMEOUT"); $finish; end

// heartbeat: where is the handshake sitting?
integer hb;
initial begin
	for (hb = 0; hb < 100; hb = hb + 1) begin
		#500000;
		$display("HB t=%0t phase=%0d dcnt=%0d req=%b ack=%b dreq=%b bsy=%b csr_gate icr=%02x mr=%02x",
			$time, dut.target[0].target.phase, dut.target[0].target.data_cnt,
			dut.target[0].target.req, dut.target[0].target.ack, dreq,
			dut.target[0].target.bsy, dut.icr, dut.mr);
	end
end

endmodule
