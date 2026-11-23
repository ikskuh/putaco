`timescale 1ns/1ps

// Simulation only; compile with -g2012 -gspecify. Quad D register.
// TI SCHS158F sections 5.5/5.6: 5 V, 25 C, CL=15 pF typical delays
// are clock=17 ns, MR=12 ns, OE=12 ns. MR is ACTIVE HIGH.
// Timing requirements are specified limits, NOT typical delays: nearest
// 4.5 V, 25 C limits are setup=12, data hold=3, enable hold=0,
// clock/MR width=16, MR release-to-clock=12 ns. Typical fmax=60 MHz.
// Procedural checks work independently of simulator specify-check support.
// A violation poisons the whole register until reset or a clean capture;
// OE still releases poisoned storage. Storage has no power-on reset.
module CD74HC173 #(
    parameter real T_CLOCK_NS = 17.0,
    parameter real T_RESET_NS = 12.0,
    parameter real T_ENABLE_NS = 12.0,
    parameter real T_DISABLE_NS = 12.0,
    parameter real T_SETUP_DATA_NS = 12.0,
    parameter real T_SETUP_ENABLE_NS = 12.0,
    parameter real T_HOLD_DATA_NS = 3.0,
    parameter real T_HOLD_ENABLE_NS = 0.0,
    parameter real T_CLOCK_WIDTH_NS = 16.0,
    parameter real T_RESET_WIDTH_NS = 16.0,
    parameter real T_RESET_RELEASE_NS = 12.0,
    parameter real T_PERIOD_NS = 1000.0 / 60.0
)(
    input [3:0] D,
    input CP, MR, E1_n, E2_n, OE1_n, OE2_n,
    output [3:0] Q
);
    reg [3:0] state = 4'bxxxx;
    wire enabled = ~E1_n & ~E2_n;
    wire visible = ~OE1_n & ~OE2_n;
    bufif1 output_gate[3:0](Q, state, visible);

    integer timing_violations = 0;
    realtime last_data = -1.0e9;
    realtime last_e1 = -1.0e9, last_e2 = -1.0e9;
    realtime last_capture = -1.0e9, last_rise = -1.0e9;
    realtime last_clock_change = -1.0e9;
    realtime reset_asserted = -1.0e9, reset_released = -1.0e9;
    reg previous_clock = 1'bx, previous_reset = 1'bx;
    reg capture_window = 0;

    initial begin
        // Inputs initialized by their caller need not generate an event at
        // time zero. Establish their levels without inventing a clock edge.
        #0;
        previous_clock = CP;
        previous_reset = MR;
        last_clock_change = $realtime;
        last_data = $realtime;
        last_e1 = $realtime;
        last_e2 = $realtime;
        if (MR === 1'b1) begin
            state <= 4'b0000;
            reset_asserted = $realtime;
        end
    end

    task violation(input [8*80-1:0] reason);
        begin
            timing_violations = timing_violations + 1;
            $display("WARNING %m at %0.3f ns: %0s", $realtime, reason);
            state <= 4'bxxxx;
        end
    endtask

    always @(D) begin
        last_data = $realtime;
        if (MR === 1'b0 && capture_window &&
            $realtime - last_capture < T_HOLD_DATA_NS)
            violation("data hold");
    end

    always @(E1_n) begin
        last_e1 = $realtime;
        if (MR === 1'b0 && capture_window &&
            $realtime - last_capture < T_HOLD_ENABLE_NS)
            violation("enable hold");
    end

    always @(E2_n) begin
        last_e2 = $realtime;
        if (MR === 1'b0 && capture_window &&
            $realtime - last_capture < T_HOLD_ENABLE_NS)
            violation("enable hold");
    end

    always @(MR) begin
        if (MR === 1'b1) begin
            state <= 4'b0000;
            capture_window = 0;
            reset_asserted = $realtime;
        end else if (MR === 1'b0) begin
            if (previous_reset === 1'b1) begin
                reset_released = $realtime;
                if ($realtime - reset_asserted < T_RESET_WIDTH_NS)
                    violation("reset pulse width");
            end
        end else begin
            state <= 4'bxxxx;
            capture_window = 0;
        end
        previous_reset = MR;
    end

    always @(CP) begin
        // Observe same-timestamp data/enable/reset changes before checking
        // setup, independent of active-region execution order.
        #0;
        if (CP === 1'b1 && previous_clock === 1'b0) begin
            capture_window = 0;
            if (MR === 1'b1)
                state <= 4'b0000;
            else if (MR !== 1'b0)
                state <= 4'bxxxx;
            else begin
                // The conditional merges hold/capture bitwise if E is X.
                // XOR converts floating data inputs into unknown bits.
                state <= enabled ? (D ^ 4'b0000) : state;
                capture_window = (enabled !== 1'b0);
                last_capture = $realtime;
                if (capture_window && $realtime - last_data < T_SETUP_DATA_NS)
                    violation("data setup");
                // A stable HIGH on either enable masks the other pin.
                // If both changed recently, neither safely inhibits capture.
                if (($realtime - last_e1 < T_SETUP_ENABLE_NS &&
                     (E2_n !== 1'b1 || $realtime - last_e2 < T_SETUP_ENABLE_NS)) ||
                    ($realtime - last_e2 < T_SETUP_ENABLE_NS &&
                     (E1_n !== 1'b1 || $realtime - last_e1 < T_SETUP_ENABLE_NS)))
                    violation("enable setup");
                if ($realtime - reset_released < T_RESET_RELEASE_NS)
                    violation("reset release to clock");
                if ($realtime - last_rise < T_PERIOD_NS)
                    violation("clock period");
            end
            last_rise = $realtime;
        end else if (MR !== 1'b1 &&
                     (CP !== 1'b0 || previous_clock !== 1'b1)) begin
            // X/Z clock transitions can represent an unobserved rising edge.
            state <= 4'bxxxx;
            capture_window = 0;
        end
        if (MR === 1'b0 &&
            ((CP === 1'b1 && previous_clock === 1'b0) ||
             (CP === 1'b0 && previous_clock === 1'b1)) &&
            $realtime - last_clock_change < T_CLOCK_WIDTH_NS)
            violation("clock pulse width");
        previous_clock = CP;
        last_clock_change = $realtime;
    end

    specify
        (CP *> Q) = (T_CLOCK_NS, T_CLOCK_NS);
        (MR *> Q) = (T_RESET_NS, T_RESET_NS);
        (OE1_n *> Q) = (T_ENABLE_NS, T_ENABLE_NS, T_DISABLE_NS,
                        T_ENABLE_NS, T_DISABLE_NS, T_ENABLE_NS);
        (OE2_n *> Q) = (T_ENABLE_NS, T_ENABLE_NS, T_DISABLE_NS,
                        T_ENABLE_NS, T_DISABLE_NS, T_ENABLE_NS);
    endspecify
endmodule
