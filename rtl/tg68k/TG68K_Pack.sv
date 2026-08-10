//------------------------------------------------------------------------------
//------------------------------------------------------------------------------
//
// Copyright (c) 2009-2020 Tobias Gubener
// Patches by MikeJ, Till Harbaum, Rok Krajnk, ...
// Subdesign fAMpIGA by TobiFlex
// VHDL to Verilog conversion
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//------------------------------------------------------------------------------
//------------------------------------------------------------------------------

// Micro states enumeration
localparam [6:0]
    idle         = 7'd0,
    nop          = 7'd1,
    ld_nn        = 7'd2,
    st_nn        = 7'd3,
    ld_dAn1      = 7'd4,
    ld_AnXn1     = 7'd5,
    ld_AnXn2     = 7'd6,
    st_dAn1      = 7'd7,
    ld_AnXnbd1   = 7'd8,
    ld_AnXnbd2   = 7'd9,
    ld_AnXnbd3   = 7'd10,
    ld_229_1     = 7'd11,
    ld_229_2     = 7'd12,
    ld_229_3     = 7'd13,
    ld_229_4     = 7'd14,
    st_229_1     = 7'd15,
    st_229_2     = 7'd16,
    st_229_3     = 7'd17,
    st_229_4     = 7'd18,
    st_AnXn1     = 7'd19,
    st_AnXn2     = 7'd20,
    bra1         = 7'd21,
    bsr1         = 7'd22,
    bsr2         = 7'd23,
    nopnop       = 7'd24,
    dbcc1        = 7'd25,
    movem1       = 7'd26,
    movem2       = 7'd27,
    movem3       = 7'd28,
    andi         = 7'd29,
    pack1        = 7'd30,
    pack2        = 7'd31,
    pack3        = 7'd32,
    op_AxAy      = 7'd33,
    cmpm         = 7'd34,
    link1        = 7'd35,
    link2        = 7'd36,
    unlink1      = 7'd37,
    unlink2      = 7'd38,
    int1         = 7'd39,
    int2         = 7'd40,
    int3         = 7'd41,
    int4         = 7'd42,
    rte1         = 7'd43,
    rte2         = 7'd44,
    rte3         = 7'd45,
    rte4         = 7'd46,
    rte5         = 7'd47,
    rtd1         = 7'd48,
    rtd2         = 7'd49,
    trap00       = 7'd50,
    trap0        = 7'd51,
    trap1        = 7'd52,
    trap2        = 7'd53,
    trap3        = 7'd54,
    cas1         = 7'd55,
    cas2         = 7'd56,
    cas21        = 7'd57,
    cas22        = 7'd58,
    cas23        = 7'd59,
    cas24        = 7'd60,
    cas25        = 7'd61,
    cas26        = 7'd62,
    cas27        = 7'd63,
    cas28        = 7'd64,
    chk20        = 7'd65,
    chk21        = 7'd66,
    chk22        = 7'd67,
    chk23        = 7'd68,
    chk24        = 7'd69,
    trap4        = 7'd70,
    trap5        = 7'd71,
    trap6        = 7'd72,
    movec1       = 7'd73,
    movep1       = 7'd74,
    movep2       = 7'd75,
    movep3       = 7'd76,
    movep4       = 7'd77,
    movep5       = 7'd78,
    rota1        = 7'd79,
    bf1          = 7'd80,
    mul1         = 7'd81,
    mul2         = 7'd82,
    mul_end1     = 7'd83,
    mul_end2     = 7'd84,
    div1         = 7'd85,
    div2         = 7'd86,
    div3         = 7'd87,
    div4         = 7'd88,
    div_end1     = 7'd89,
    div_end2     = 7'd90,
    moves1       = 7'd91,
    moves2       = 7'd92,
    ld_An1       = 7'd93;

// Opcode constants for exec bit vector
localparam opcMOVE           = 0;
localparam opcMOVEQ          = 1;
localparam opcMOVESR         = 2;
localparam opcADD            = 3;
localparam opcADDQ           = 4;
localparam opcOR             = 5;
localparam opcAND            = 6;
localparam opcEOR            = 7;
localparam opcCMP            = 8;
localparam opcROT            = 9;
localparam opcCPMAW          = 10;
localparam opcEXT            = 11;
localparam opcABCD           = 12;
localparam opcSBCD           = 13;
localparam opcBITS           = 14;
localparam opcSWAP           = 15;
localparam opcScc            = 16;
localparam andiSR            = 17;
localparam eoriSR            = 18;
localparam oriSR             = 19;
localparam opcMULU           = 20;
localparam opcDIVU           = 21;
localparam dispouter         = 22;
localparam rot_nop           = 23;
localparam ld_rot_cnt        = 24;
localparam writePC_add       = 25;
localparam ea_data_OP1       = 26;
localparam ea_data_OP2       = 27;
localparam use_XZFlag        = 28;
localparam get_bfoffset      = 29;
localparam save_memaddr      = 30;
localparam opcCHK            = 31;
localparam movec_rd          = 32;
localparam movec_wr          = 33;
localparam Regwrena          = 34;
localparam update_FC         = 35;
localparam linksp            = 36;
localparam movepl            = 37;
localparam update_ld         = 38;
localparam OP1addr           = 39;
localparam write_reg         = 40;
localparam changeMode        = 41;
localparam ea_build          = 42;
localparam trap_chk          = 43;
localparam store_ea_data     = 44;
localparam addrlong          = 45;
localparam postadd           = 46;
localparam presub            = 47;
localparam subidx            = 48;
localparam no_Flags          = 49;
localparam use_SP            = 50;
localparam to_CCR            = 51;
localparam to_SR             = 52;
localparam OP2out_one        = 53;
localparam OP1out_zero       = 54;
localparam mem_addsub        = 55;
localparam addsub            = 56;
localparam directPC          = 57;
localparam direct_delta      = 58;
localparam directSR          = 59;
localparam directCCR         = 60;
localparam exg               = 61;
localparam get_ea_now        = 62;
localparam ea_to_pc          = 63;
localparam hold_dwr          = 64;
localparam to_USP            = 65;
localparam from_USP          = 66;
localparam write_lowlong     = 67;
localparam write_reminder    = 68;
localparam movem_action      = 69;
localparam briefext          = 70;
localparam get_2ndOPC        = 71;
localparam mem_byte          = 72;
localparam longaktion        = 73;
localparam opcRESET          = 74;
localparam opcBF             = 75;
localparam opcBFwb           = 76;
localparam opcPACK           = 77;
localparam opcUNPACK         = 78;
localparam hold_ea_data      = 79;
localparam store_ea_packdata = 80;
localparam exec_BS           = 81;
localparam hold_OP2          = 82;
localparam restore_ADDR      = 83;
localparam alu_exec          = 84;
localparam alu_move          = 85;
localparam alu_setFlags      = 86;
localparam opcCHK2           = 87;
localparam opcEXTB           = 88;
localparam moves_fc          = 89;  // MOVES: use SFC/DFC for function code

localparam lastOpcBit        = 89;
