`timescale 1ns/1ps

// Simulation only; compile with -gspecify. Active-low equality comparator.
// TI SCHS196E section 5.5, footnote 3: 5 V, 25 C, CL=15 pF typicals.
// A/B to output=14 ns; enable to output=9 ns. E_n=1 forces Y_n HIGH.
module CD74HC688 #(
    parameter real T_COMPARE_NS = 14.0,
    parameter real T_ENABLE_NS = 9.0
)(input [7:0] A, B, input E_n, output Y_n);
    assign Y_n = ~(~E_n & (A == B));
    specify
        (A *> Y_n) = (T_COMPARE_NS, T_COMPARE_NS);
        (B *> Y_n) = (T_COMPARE_NS, T_COMPARE_NS);
        (E_n => Y_n) = (T_ENABLE_NS, T_ENABLE_NS);
    endspecify
endmodule
