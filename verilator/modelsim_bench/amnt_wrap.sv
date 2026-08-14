// amnt_wrap.sv — bench wrapper around the AMNT block, awk-extracted VERBATIM
// from src/fpga/core/core_top.sv (amnt_block.vh), so the bench exercises the
// shipping text rather than a copy. Provides the context the block expects:
// the SLOT_* localparams, jmnt_src/jmnt_active, the dataslot_* inputs and the
// datatable port wires.
module amnt_wrap (
    input  wire        clk_74a,
    input  wire        dataslot_update,
    input  wire [15:0] dataslot_update_id,
    input  wire [31:0] dataslot_update_size,
    input  wire        dataslot_allcomplete,
    output wire [9:0]  datatable_addr,
    output wire        datatable_wren,
    output wire [31:0] datatable_data,
    input  wire [31:0] datatable_q,
    input  wire        jmnt_active_ext,
    output wire        o_bd_dsu,
    output wire [15:0] o_bd_dsu_id,
    output wire [31:0] o_bd_dsu_size,
    output wire [31:0] o_dbg_amnt
);
    localparam [15:0] SLOT_HDD0   = 16'd310;
    localparam [15:0] SLOT_HDD1   = 16'd311;
    localparam [15:0] SLOT_CD     = 16'd320;
    localparam [15:0] SLOT_FLOPPY = 16'd210;

    wire        jmnt_active = jmnt_active_ext;
    wire [48:0] jmnt_src    = 49'd0;

    `include "amnt_block.vh"

    assign o_bd_dsu      = bd_dsu;
    assign o_bd_dsu_id   = bd_dsu_id;
    assign o_bd_dsu_size = bd_dsu_size;
    assign o_dbg_amnt    = dbg_amnt;
endmodule
