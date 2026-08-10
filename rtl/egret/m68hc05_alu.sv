
// m68hc05_alu.sv - Arithmetic components for 68HC05
// Converted from VHDL by Ulrich Riedel

module fadd (
    input  logic a,
    input  logic b,
    input  logic cin,
    output logic s,
    output logic cout
);
    assign s = a ^ b ^ cin;
    assign cout = (a & b) | (a & cin) | (b & cin);
endmodule

module add8 (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic       cin,
    output logic [7:0] sum,
    output logic       cout
);
    logic [6:0] c;  // internal carries
    
    fadd a0  (.a(a[0]), .b(b[0]), .cin(cin),   .s(sum[0]), .cout(c[0]));
    fadd a1  (.a(a[1]), .b(b[1]), .cin(c[0]),  .s(sum[1]), .cout(c[1]));
    fadd a2  (.a(a[2]), .b(b[2]), .cin(c[1]),  .s(sum[2]), .cout(c[2]));
    fadd a3  (.a(a[3]), .b(b[3]), .cin(c[2]),  .s(sum[3]), .cout(c[3]));
    fadd a4  (.a(a[4]), .b(b[4]), .cin(c[3]),  .s(sum[4]), .cout(c[4]));
    fadd a5  (.a(a[5]), .b(b[5]), .cin(c[4]),  .s(sum[5]), .cout(c[5]));
    fadd a6  (.a(a[6]), .b(b[6]), .cin(c[5]),  .s(sum[6]), .cout(c[6]));
    fadd a31 (.a(a[7]), .b(b[7]), .cin(c[6]),  .s(sum[7]), .cout(cout));
endmodule

module add8c (
    input  logic       b,
    input  logic [7:0] a,
    input  logic [7:0] sum_in,
    input  logic [7:0] cin,
    output logic [7:0] sum_out,
    output logic [7:0] cout
);
    logic [7:0] aa;
    
    assign aa = b ? a : 8'h00;
    
    genvar i;
    generate
        for (i = 0; i < 8; i++) begin : stage
            fadd sta (.a(aa[i]), .b(sum_in[i]), .cin(cin[i]), .s(sum_out[i]), .cout(cout[i]));
        end
    endgenerate
endmodule

module mul8 (
    input  logic [7:0]  a,      // multiplicand
    input  logic [7:0]  b,      // multiplier
    output logic [15:0] prod    // product
);
    logic [7:0] s[0:7];    // partial sums
    logic [7:0] c[0:7];    // partial carries
    logic [7:0] ss[0:7];   // shifted sums
    logic nc1;
    
    // Stage 0
    add8c st0 (.b(b[0]), .a(a), .sum_in(8'h00), .cin(8'h00), .sum_out(s[0]), .cout(c[0]));
    assign ss[0] = {1'b0, s[0][7:1]};
    assign prod[0] = s[0][0];
    
    // Stages 1-7
    genvar i;
    generate
        for (i = 1; i < 8; i++) begin : stage
            add8c st (.b(b[i]), .a(a), .sum_in(ss[i-1]), .cin(c[i-1]), .sum_out(s[i]), .cout(c[i]));
            assign ss[i] = {1'b0, s[i][7:1]};
            assign prod[i] = s[i][0];
        end
    endgenerate
    
    // Final addition
    add8 final_add (.a(ss[7]), .b(c[7]), .cin(1'b0), .sum(prod[15:8]), .cout(nc1));
endmodule