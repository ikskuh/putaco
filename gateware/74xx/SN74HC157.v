`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Quad 2-to-1 multiplexer.
// S=0 selects A, S=1 selects B; G_n=1 forces all outputs LOW.
// TI SCLS113F section 4.5: ESTIMATED 5 V, 25 C, CL=50 pF delays.
// Linear interpolation 1/3 from 4.5 V to 6 V typicals:
// data 13->11 ns, select 18->14 ns, strobe 16->13 ns.
module SN74HC157 #(
    parameter real T_DATA_NS = 13.0 + (11.0 - 13.0) / 3.0,
    parameter real T_SELECT_NS = 18.0 + (14.0 - 18.0) / 3.0,
    parameter real T_STROBE_NS = 16.0 + (13.0 - 16.0) / 3.0
)(input [3:0] A, B, input S, G_n, output [3:0] Y);
    assign Y = {4{~G_n}} & (S ? B : A);
    specify
        (A => Y) = (T_DATA_NS, T_DATA_NS);
        (B => Y) = (T_DATA_NS, T_DATA_NS);
        (S *> Y) = (T_SELECT_NS, T_SELECT_NS);
        (G_n *> Y) = (T_STROBE_NS, T_STROBE_NS);
    endspecify
endmodule
