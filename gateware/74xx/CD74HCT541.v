`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Non-inverting octal buffer.
// TI SCHS189E section 5.5, HCT types: 5 V, 25 C, CL=15 pF typicals.
// Data=11 ns; enable and disable=14 ns. Both enables are active low.
// Logic levels are digital; HCT analog input thresholds are not modeled.
module CD74HCT541 #(
    parameter real T_DATA_NS = 11.0,
    parameter real T_ENABLE_NS = 14.0,
    parameter real T_DISABLE_NS = 14.0
)(input [7:0] A, input OE1_n, OE2_n, output [7:0] Y);
    wire enabled = ~OE1_n & ~OE2_n;
    bufif1 buffer_gate[7:0](Y, A, enabled);
    specify
        (A => Y) = (T_DATA_NS, T_DATA_NS);
        (OE1_n *> Y) = (T_ENABLE_NS, T_ENABLE_NS, T_DISABLE_NS,
                        T_ENABLE_NS, T_DISABLE_NS, T_ENABLE_NS);
        (OE2_n *> Y) = (T_ENABLE_NS, T_ENABLE_NS, T_DISABLE_NS,
                        T_ENABLE_NS, T_DISABLE_NS, T_ENABLE_NS);
    endspecify
endmodule
