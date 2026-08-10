// ============================================================================
// sdp_ram.sv — simple-dual-port RAM primitives (one write port, one registered
// read port).
//
// PROVENANCE: these two modules were lifted verbatim out of rtl/cd_audio.sv
// during the Pocket port. cd_audio.sv was deleted with the rest of the CD-ROM
// support, but rtl/asc.sv instantiates cd_sdp for the ASC's FIFO A storage, so
// the primitives had to survive their original home. Names are unchanged so
// the existing instantiations still match.
//
// Original comment from cd_audio.sv:
//   Minimal simple-dual-port RAM (one write, one registered read) for the
//   single-reader buffers above — scsi_dpram would burn two unused mirror
//   arrays per instance (the map.rpt M10K check applies here; see the
//   2026-07-07 BRAM-inference lesson: exactly one write statement per array).
// ============================================================================

module cd_sdp #(parameter DW = 16, AW = 12)
(
	input           clock,
	input  [AW-1:0] waddr,
	input  [DW-1:0] wdata,
	input           wr,
	input  [AW-1:0] raddr,
	output reg [DW-1:0] q
);
// vram_bram's hardware-proven inference recipe (see rtl/vram_bram.sv):
// forced "M10K" (overrides the small-RAM heuristic that silently turned the
// 2 Kbit response planes into ~2000 registers each — fit attempts #1-#3 of
// the original file) + no_rw_check, with write and read in SEPARATE always
// blocks.
(* ramstyle = "M10K,no_rw_check" *) reg [DW-1:0] ram [0:(1<<AW)-1];
always @(posedge clock) if (wr) ram[waddr] <= wdata;
always @(posedge clock) q <= ram[raddr];
endmodule

// MLAB variant for small (2 Kbit) arrays. Same contract as cd_sdp; the
// forced-M10K recipe above exists because AUTO turned these into ~2000
// registers each — MLAB is the third option that recipe predates: ALM-based
// distributed RAM, zero M10K blocks. Motivation (2026-08-03): the DE10 device
// was at 513/553 M10K blocks (93%) while only 71% of memory BITS were used —
// M10K placement pressure is the per-seed fit-marginality driver.
//
// Currently unused after the Pocket CD cut (its only callers were the CD-audio
// response planes). Kept because M10K pressure is far WORSE on the Pocket's
// 308-block device than it ever was on the DE10, so this is the tool to reach
// for if a small array needs to move out of block RAM.
module cd_sdp_mlab #(parameter DW = 16, AW = 12)
(
	input           clock,
	input  [AW-1:0] waddr,
	input  [DW-1:0] wdata,
	input           wr,
	input  [AW-1:0] raddr,
	output reg [DW-1:0] q
);
(* ramstyle = "MLAB,no_rw_check" *) reg [DW-1:0] ram [0:(1<<AW)-1];
always @(posedge clock) if (wr) ram[waddr] <= wdata;
always @(posedge clock) q <= ram[raddr];
endmodule
