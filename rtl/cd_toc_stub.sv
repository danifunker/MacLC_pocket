//
// cd_toc_stub.sv — single-track ISO TOC provider for the CDROM scsi.v target
//
// WHAT THIS REPLACES. On MiSTer the cdrom_target's three TOC response planes
// (the vendor 0xC1 table, the standard 0x43 format-0 table, and the format-2
// FULL TOC + format-1 session-info page the AppleCD driver actually mounts
// with) were owned by rtl/cd_audio.sv — 3,076 ALUTs of playback engine that
// also fetched a Main-supplied TOC blob ("MCDA") describing bin/cue track
// layouts. The Pocket fork cut cd_audio with the CD target (2026-08-09).
//
// This stub restores ONLY the TOC planes, for the one disc shape the Pocket
// serves: a plain ISO = ONE data track at LBA 0. cd_audio already contained
// this exact degenerate case as its no-blob fallback ("real blob or
// synthesized", its M_HDR_RD word5 arm: n_tracks=1, ctrl=0x14, start 0,
// leadout = img_blocks/4). Every byte this module serves is transcribed from
// that synthesized path at MiSTer 5a75f9b — cd_audio.sv is the byte oracle,
// and its port comments (0xC1 layout at its line ~74, format-0 at ~84,
// format-2 + session page at ~91) are the layout spec:
//
//   0xC1 plane (all BCD):   [0..3] {01, bcd(last)=01, 00, 00}
//                           [4..7] lead-out {M,S,F BCD, 00}   — NO +150 (raw)
//                           [8+4k] track rows {ctrl=14, 00,00,00} k=0..98
//                             (synthesized track repeats: start MSF 00:00:00)
//   0x43 fmt-0 (binary):    {00,12, 01,01} + track row {00,14,01,00,00,
//                           00,02,00} (+150 => 00:02:00) + lead-out row
//                           {00,14,AA,00,00, M,S,F} (+150). Served len = 20.
//   fmt-2 FULL TOC (MMC4    {00,2E,01,01} + A0/A1/A2 rows + track row, 11 B
//   BCD rule, +150):        each; PMIN/PSEC/PFRAME BCD, POINT binary.
//                           Session-info page (fmt-1) parked at [496..507].
//                           Served len = 48.
//
// The playback/position/audio-classification outputs the guest also consults
// (ast_code, cur_ctrl/trk, abs/rel MSF, disc_audio) are NOT here — scsi.v's
// unconditional tie-offs already hold their correct data-disc idle values.
//
// Serving is COMBINATIONAL (cd_audio's planes were registered RAM reads;
// scsi.v samples the quartets only at DREQ-gated instants many cycles after
// the address settles, so zero-latency is strictly safer). The only
// sequential work is the leadout LBA -> MSF conversion: the same iterative
// -4500/-75 subtract divider cd_audio used, run twice per mount (raw for the
// 0xC1 plane, +150 for the MMC planes), ~300 cycles total — invisible next
// to the guest's insertion-poll cadence. No RAM, no M10K.
//
`default_nettype none

module cd_toc_stub
(
	input  wire        clk,
	input  wire        sys_rst,      // power-on reset; TOC survives bus resets
	input  wire        mounted,      // scsi.v media latch
	input  wire        img_mounted,  // mount pulse: size may have changed
	input  wire [31:0] img_blocks,   // image size in 512-byte blocks

	// 0xC1 vendor READ TOC plane: bytes at toc_base..toc_base+3
	input  wire  [8:0] toc_base,
	output wire  [7:0] toc_q0, toc_q1, toc_q2, toc_q3,
	output reg         toc_ready,

	// standard 0x43 format-0 plane
	input  wire  [8:0] toc43_base,
	output wire  [7:0] toc43_q0, toc43_q1, toc43_q2, toc43_q3,
	output wire  [9:0] toc43_len,

	// 0x43 format-2 FULL TOC plane (+ format-1 session page at [496..507])
	input  wire  [8:0] toc2_base,
	output wire  [7:0] toc2_q0, toc2_q1, toc2_q2, toc2_q3,
	output wire  [9:0] toc2_len
);

// Response lengths for the 1-track tables (dlen + the 2 length bytes):
// fmt-0 dlen = 2 + 2*8 = 18 (0x12) -> 20; fmt-2 dlen = 4 rows*11 + 2 = 46
// (0x2E) -> 48. Constants because the track count is 1 by construction.
assign toc43_len = 10'd20;
assign toc2_len  = 10'd48;

// 2048-byte CD blocks, exactly cd_audio's no-blob arm.
wire [31:0] leadout = {2'd0, img_blocks[31:2]};

function [7:0] bcd(input [6:0] v);
	bcd = {1'b0, v / 7'd10, v % 7'd10};
endfunction

// ---------------------------------------------------------------------------
// Lead-out MSF: iterative divider, two passes per (re)build.
//   pass 1: leadout       -> lo_m/lo_s/lo_f  (0xC1 plane, BCD at the serve)
//   pass 2: leadout + 150 -> l1_m/l1_s/l1_f  (fmt-0 binary; fmt-2 BCD)
// Need-driven like cd_audio's M_IDLE arm: any (mounted && !toc_ready) state
// rebuilds, so a mid-acquisition restart can never park a stale zero TOC.
// ---------------------------------------------------------------------------
localparam [1:0] S_IDLE = 2'd0, S_D1 = 2'd1, S_D2 = 2'd2;
reg [1:0]  st;
reg [31:0] dv;
reg [6:0]  dm, ds;
reg [6:0]  lo_m, lo_s, lo_f;
reg [6:0]  l1_m, l1_s, l1_f;

always @(posedge clk) begin
	if (sys_rst) begin
		st <= S_IDLE; toc_ready <= 1'b0;
		dv <= 32'd0; dm <= 7'd0; ds <= 7'd0;
		lo_m <= 7'd0; lo_s <= 7'd0; lo_f <= 7'd0;
		l1_m <= 7'd0; l1_s <= 7'd0; l1_f <= 7'd0;
	end else if (!mounted || img_mounted) begin
		// Unmount drops the tables; a fresh mount pulse re-arms the build.
		toc_ready <= 1'b0;
		st        <= S_IDLE;
	end else begin
		case (st)
		S_IDLE: if (!toc_ready) begin
			dv <= leadout; dm <= 7'd0; ds <= 7'd0;
			st <= S_D1;
		end
		S_D1:
			if ((dv >= 32'd4500) && (dm != 7'd99)) begin
				dv <= dv - 32'd4500; dm <= dm + 7'd1;
			end else if (dv >= 32'd75) begin
				dv <= dv - 32'd75; ds <= ds + 7'd1;
			end else begin
				lo_m <= dm; lo_s <= ds; lo_f <= dv[6:0];
				dv <= leadout + 32'd150; dm <= 7'd0; ds <= 7'd0;
				st <= S_D2;
			end
		S_D2:
			if ((dv >= 32'd4500) && (dm != 7'd99)) begin
				dv <= dv - 32'd4500; dm <= dm + 7'd1;
			end else if (dv >= 32'd75) begin
				dv <= dv - 32'd75; ds <= ds + 7'd1;
			end else begin
				l1_m <= dm; l1_s <= ds; l1_f <= dv[6:0];
				toc_ready <= 1'b1;
				st <= S_IDLE;
			end
		default: st <= S_IDLE;
		endcase
	end
end

// ---------------------------------------------------------------------------
// Plane byte functions (synthesized 1-track content; zero elsewhere)
// ---------------------------------------------------------------------------
// 0xC1: header {01,01,00,00}, lead-out BCD at [4..6], track rows at 8+4k
// (k=0..98) each {14,00,00,00} — the synthesized track start is MSF 0.
function [7:0] c1_byte(input [8:0] a);
	if      (a == 9'd0 || a == 9'd1)  c1_byte = 8'h01;
	else if (a == 9'd4)               c1_byte = bcd(lo_m);
	else if (a == 9'd5)               c1_byte = bcd(lo_s);
	else if (a == 9'd6)               c1_byte = bcd(lo_f);
	else if (a >= 9'd8 && a <= 9'd403 && a[1:0] == 2'b00)
	                                  c1_byte = 8'h14;
	else                              c1_byte = 8'h00;
endfunction

// 0x43 format 0: {00,12,01,01} hdr; track row [4..11]; 0xAA row [12..19].
function [7:0] t43_byte(input [8:0] a);
	case (a)
		9'd1:    t43_byte = 8'h12;         // dlen lo
		9'd2:    t43_byte = 8'h01;         // first track
		9'd3:    t43_byte = 8'h01;         // last track
		9'd5:    t43_byte = 8'h14;         // adr/ctrl (data)
		9'd6:    t43_byte = 8'h01;         // track 1
		9'd10:   t43_byte = 8'h02;         // start 00:02:00 (+150, binary)
		9'd13:   t43_byte = 8'h14;
		9'd14:   t43_byte = 8'hAA;         // lead-out
		9'd17:   t43_byte = {1'b0, l1_m};  // lead-out MSF, binary
		9'd18:   t43_byte = {1'b0, l1_s};
		9'd19:   t43_byte = {1'b0, l1_f};
		default: t43_byte = 8'h00;
	endcase
endfunction

// format 2: {00,2E,01,01} hdr; A0 [4..14], A1 [15..25], A2 [26..36],
// track 1 [37..47]; session page [496..507]. POINT binary, PMSF BCD.
function [7:0] t2_byte(input [8:0] a);
	case (a)
		9'd1:    t2_byte = 8'h2E;          // dlen lo
		9'd2:    t2_byte = 8'h01;          // first session
		9'd3:    t2_byte = 8'h01;          // last session
		// A0: first track number + disc type
		9'd4:    t2_byte = 8'h01;
		9'd5:    t2_byte = 8'h14;
		9'd7:    t2_byte = 8'hA0;
		9'd12:   t2_byte = 8'h01;          // PMIN = bcd(first) = 01
		// A1: last track number
		9'd15:   t2_byte = 8'h01;
		9'd16:   t2_byte = 8'h14;
		9'd18:   t2_byte = 8'hA1;
		9'd23:   t2_byte = 8'h01;          // PMIN = bcd(last) = 01
		// A2: lead-out MSF (BCD, +150)
		9'd26:   t2_byte = 8'h01;
		9'd27:   t2_byte = 8'h14;
		9'd29:   t2_byte = 8'hA2;
		9'd34:   t2_byte = bcd(l1_m);
		9'd35:   t2_byte = bcd(l1_s);
		9'd36:   t2_byte = bcd(l1_f);
		// track 1 row: start 00:02:00 (BCD, +150)
		9'd37:   t2_byte = 8'h01;
		9'd38:   t2_byte = 8'h14;
		9'd40:   t2_byte = 8'h01;          // POINT = track 1, binary
		9'd46:   t2_byte = 8'h02;          // PSEC = bcd(2)
		// format-1 session-info page
		9'd497:  t2_byte = 8'h0A;          // u16be len = 10
		9'd498:  t2_byte = 8'h01;          // first session
		9'd499:  t2_byte = 8'h01;          // last session
		9'd501:  t2_byte = 8'h14;          // adr/ctrl
		9'd502:  t2_byte = 8'h01;          // first track in last session
		9'd506:  t2_byte = 8'h02;          // track 1 start 00:02:00 (binary)
		default: t2_byte = 8'h00;
	endcase
endfunction

// Quartet serve: bytes at base..base+3, 9-bit wrap — the same mod-512
// addressing the RAM planes had.
assign toc_q0   = c1_byte (toc_base);
assign toc_q1   = c1_byte (toc_base   + 9'd1);
assign toc_q2   = c1_byte (toc_base   + 9'd2);
assign toc_q3   = c1_byte (toc_base   + 9'd3);
assign toc43_q0 = t43_byte(toc43_base);
assign toc43_q1 = t43_byte(toc43_base + 9'd1);
assign toc43_q2 = t43_byte(toc43_base + 9'd2);
assign toc43_q3 = t43_byte(toc43_base + 9'd3);
assign toc2_q0  = t2_byte (toc2_base);
assign toc2_q1  = t2_byte (toc2_base  + 9'd1);
assign toc2_q2  = t2_byte (toc2_base  + 9'd2);
assign toc2_q3  = t2_byte (toc2_base  + 9'd3);

endmodule

`default_nettype wire
