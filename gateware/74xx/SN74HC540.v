`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Inverting octal buffer.
// TI SCLS007F section 5.5: ESTIMATED 5 V, 25 C, CL=50 pF delays.
// Linear interpolation 1/3 from the 4.5 V to 6 V typicals:
// data 10->8 ns, enable 15->13 ns, disable 18->17 ns.
// These estimates use a different load from the CD74HC/HCT541 typicals.
module SN74HC540 #(
    parameter real T_DATA_NS = 10.0 + (8.0 - 10.0) / 3.0,
    parameter real T_ENABLE_NS = 15.0 + (13.0 - 15.0) / 3.0,
    parameter real T_DISABLE_NS = 18.0 + (17.0 - 18.0) / 3.0
)(input [7:0] A, input OE1_n, OE2_n, output [7:0] Y_n);
    wire enabled = ~OE1_n & ~OE2_n;
    notif1 buffer_gate[7:0](Y_n, A, enabled);
    specify
        (A => Y_n) = (T_DATA_NS, T_DATA_NS);
        (OE1_n *> Y_n) = (T_ENABLE_NS, T_ENABLE_NS, T_DISABLE_NS,
                        T_ENABLE_NS, T_DISABLE_NS, T_ENABLE_NS);
        (OE2_n *> Y_n) = (T_ENABLE_NS, T_ENABLE_NS, T_DISABLE_NS,
                        T_ENABLE_NS, T_DISABLE_NS, T_ENABLE_NS);
    endspecify
endmodule
