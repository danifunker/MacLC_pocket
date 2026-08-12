//
// i2s.v — Analogue Pocket I2S audio output
//
// WHY THIS FILE EXISTS
//
// The openFPGA core-template's audgen block is a STUB: it generates MCLK,
// SCLK and LRCK correctly but hardwires audgen_dac to 0 and never shifts any
// sample data. Every core therefore has to supply the shifter itself, and the
// one previously inlined in core_top.sv was written from scratch and never
// produced audible output on hardware.
//
// This is modelled on the shifter in the reference Pocket core
// (Pocket-Amiga src/fpga/core/i2s.v), which is known to work on this hardware.
// Two differences from the inlined version it replaces, either of which could
// account for the silence:
//
//   1. THE SAMPLE IS SYNCHRONISED ACROSS CLOCK DOMAINS. left/right arrive in
//      the Mac's clk_sys domain and are consumed on audgen_sclk (3.072 MHz,
//      derived from clk_74a). The old code sampled them with no synchroniser
//      at all.
//   2. A single 32-bit shift register holds BOTH channels and is loaded once
//      per frame, so the left/right words cannot tear relative to LRCK. The
//      old code reloaded a 16-bit register at the end of every channel slot.
//
// MCLK = 12.288 MHz (fractional accumulator off clk_74a), SCLK = MCLK/4 =
// 3.072 MHz, LRCK = SCLK/64 = 48 kHz. 32 bit-slots per channel, of which the
// first 16 carry data and the rest are idle.
//
// The Mac LC's ASC is MONO -- core_top feeds the same sample to both channels.
//
module i2s (
	input  wire        clk_74a,
	input  wire [15:0] left_audio,
	input  wire [15:0] right_audio,

	output wire        audio_mclk,
	output wire        audio_dac,
	output wire        audio_lrck
);

assign audio_mclk = audgen_mclk;
assign audio_dac  = audgen_dac;
assign audio_lrck = audgen_lrck;

// MCLK = 12.288 MHz via fractional accumulator
	reg [21:0] audgen_accum = 22'd0;
	reg        audgen_mclk  = 1'b0;
	localparam [20:0] CYCLE_48KHZ = 21'd122880 * 2;
always @(posedge clk_74a) begin
	audgen_accum <= audgen_accum + CYCLE_48KHZ;
	if (audgen_accum >= 21'd742500) begin
		audgen_mclk  <= ~audgen_mclk;
		audgen_accum <= audgen_accum - 21'd742500 + CYCLE_48KHZ;
	end
end

// SCLK = MCLK / 4
	reg  [1:0] aud_mclk_divider = 2'd0;
	wire       audgen_sclk = aud_mclk_divider[1] /* synthesis keep */;
always @(posedge audgen_mclk) aud_mclk_divider <= aud_mclk_divider + 1'b1;

// Cross the sample into the SCLK domain. synch_3 comes from the APF framework
// (src/fpga/apf/common.v) and is what the reference core uses here.
	wire [31:0] audgen_sampdata_s;
synch_3 #(.WIDTH(32)) s_aud ({left_audio, right_audio}, audgen_sampdata_s, audgen_sclk);

	reg [31:0] audgen_sampshift = 32'd0;
	reg [4:0]  audgen_lrck_cnt  = 5'd0;
	reg        audgen_lrck      = 1'b0;
	reg        audgen_dac       = 1'b0;

always @(negedge audgen_sclk) begin
	// Output the next bit every SCLK. audgen_dac is REGISTERED, which is what
	// supplies I2S's one-SCLK delay between the LRCK edge and the MSB.
	audgen_dac <= audgen_sampshift[31];

	audgen_lrck_cnt <= audgen_lrck_cnt + 1'b1;
	if (audgen_lrck_cnt == 5'd31) begin
		audgen_lrck <= ~audgen_lrck;
		// Reload once per FRAME, at the end of the right channel.
		if (audgen_lrck) audgen_sampshift <= audgen_sampdata_s;
	end else begin
		// Only 16 data bits per channel; the rest of the slot is idle.
		if (audgen_lrck_cnt < 5'd16)
			audgen_sampshift <= {audgen_sampshift[30:0], 1'b0};
	end
end

endmodule
