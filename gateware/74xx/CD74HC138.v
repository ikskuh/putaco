`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Active-low 3-to-8 decoder.
// TI SCHS147J section 5.5, footnote 3: address tpd=13 ns at 5 V,
// 25 C, CL=15 pF. Enable tpd is an ESTIMATE using that same typical;
// the table gives only maxima for enable paths. Bit 0 is address 000.
module CD74HC138 #(
    parameter real T_ADDRESS_NS = 13.0,
    parameter real T_ENABLE_NS = 13.0
)(input [2:0] A, input G0_n, G1_n, G2, output [7:0] Y);
    wire enabled = ~G0_n & ~G1_n & G2;
    genvar i;
    generate for (i = 0; i < 8; i = i + 1) begin: decode
        assign Y[i] = ~(enabled & (A == i));
    end endgenerate
    specify
        (A *> Y) = (T_ADDRESS_NS, T_ADDRESS_NS);
        (G0_n *> Y) = (T_ENABLE_NS, T_ENABLE_NS);
        (G1_n *> Y) = (T_ENABLE_NS, T_ENABLE_NS);
        (G2 *> Y) = (T_ENABLE_NS, T_ENABLE_NS);
    endspecify
endmodule
