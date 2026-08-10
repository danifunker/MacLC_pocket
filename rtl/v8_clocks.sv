// V8 ASIC clock generators
//
// On a real Macintosh LC, V8 pin 124 (SCSI_RTXC / SCSI_PCLK) drives the
// 85C80's combined SCSI PCLK and SCC RTxC inputs at 3.672 MHz, derived
// from the 25.175 MHz oscillator on V8 pin 42.  The Z85C30 ESCC half of
// the 85C80 has no separate crystal — RTxCA, PCLK and RTxCB are all
// strapped to this single net.  See plan_040526.md Step 5.
//
// Here we synthesise a 1-cycle-wide enable pulse at ~3.672 MHz from the
// 32.5 MHz clk_sys using a Bresenham (fractional) divider:
//
//   each clk_sys cycle: acc += 3672
//   when acc >= 32500: acc -= 32500, pulse scsi_pclk_en for one cycle
//
// 3672 / 32500 = 0.112985..., target 3.672/32.5 = 0.11298, error <0.01%.

module v8_clocks (
    input  wire clk_sys,
    input  wire reset,
    output reg  scsi_pclk_en
);

    localparam [15:0] PCLK_INC = 16'd3672;
    localparam [15:0] PCLK_LIM = 16'd32500;

    reg [15:0] acc;

    always @(posedge clk_sys) begin
        if (reset) begin
            acc          <= 16'd0;
            scsi_pclk_en <= 1'b0;
        end else begin
            if (acc + PCLK_INC >= PCLK_LIM) begin
                acc          <= acc + PCLK_INC - PCLK_LIM;
                scsi_pclk_en <= 1'b1;
            end else begin
                acc          <= acc + PCLK_INC;
                scsi_pclk_en <= 1'b0;
            end
        end
    end

endmodule
