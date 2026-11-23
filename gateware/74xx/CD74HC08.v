`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Quad two-input AND gate.
// TI SCHS118D section 6.6: 5 V, 25 C, CL=15 pF typical tpd=10 ns.
// Digital logic only: no supply, slew, or variable-load simulation.
module CD74HC08 #(
    parameter real T_DATA_NS = 10.0
)(input [3:0] A, B, output [3:0] Y);
    assign Y = A & B;
    specify
        (A => Y) = (T_DATA_NS, T_DATA_NS);
        (B => Y) = (T_DATA_NS, T_DATA_NS);
    endspecify
endmodule
