`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Dual four-input AND gate.
// TI SCHS131D section 6.6: 5 V, 25 C, CL=15 pF typical tpd=9 ns.
module CD74HC21 #(
    parameter real T_DATA_NS = 9.0
)(input [1:0] A, B, C, D, output [1:0] Y);
    assign Y = A & B & C & D;
    specify
        (A => Y) = (T_DATA_NS, T_DATA_NS);
        (B => Y) = (T_DATA_NS, T_DATA_NS);
        (C => Y) = (T_DATA_NS, T_DATA_NS);
        (D => Y) = (T_DATA_NS, T_DATA_NS);
    endspecify
endmodule
