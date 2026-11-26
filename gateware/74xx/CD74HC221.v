`timescale 1ns/1ps

// Simulation-only dual NON-RETRIGGERABLE monostable; bit 0 is channel 1.
// TI SCHS166F, pp. 2, 5-9. A_n falling triggers when B=1, R_n=1;
// B rising triggers when A_n=0, R_n=1. R_n is asynchronous active LOW.
// Reset-release triggering requires the p.2 arming sequence while reset
// is low: first A_n=1 or B=0, then A_n=0 and B=1, then release reset.
// Power-on reset is modeled. Trigger activity cannot alter an active pulse.
//
// 5 V, 25 C, CL=15 pF typical trigger delays: Q rise=18, Q_n fall=14 ns.
// Reset delays are ESTIMATES: the corresponding 14/18 ns output edges;
// reset-specific typicals are not published. Minimum A-low/B-high/reset-low
// widths=14 ns are the specified 4.5 V, 25 C limits, not typical delays.
// Recovery R->A/B is specified as zero at 4.5 V.
//
// Nominal RC approximation: width(ns)=K*R(ohm)*C(pF)*0.001. K=0.68 is
// read approximately from the 5 V, 25 C curve (Fig.6); 0.7 is the quoted
// 4.5 V formula. Defaults give 680 us. Width is measured at each OUTPUT,
// separately from trigger propagation. No analog supply/slew/load model.
// ponytail: this nominal RC model omits small-C parasitics/nonlinearity;
// use a fitted analog model for accuracy below 1 nF. R/C/K remain tunable.
module CD74HC221 #(
    parameter real RX1_OHMS = 10000.0,
    parameter real CX1_PF = 100000.0,
    parameter real RX2_OHMS = 10000.0,
    parameter real CX2_PF = 100000.0,
    parameter real K1 = 0.68,
    parameter real K2 = 0.68,
    parameter real T_TRIGGER_Q_NS = 18.0,
    parameter real T_TRIGGER_Q_N_NS = 14.0,
    parameter real T_RESET_Q_NS = 14.0,
    parameter real T_RESET_Q_N_NS = 18.0,
    parameter real T_A_WIDTH_NS = 14.0,
    parameter real T_B_WIDTH_NS = 14.0,
    parameter real T_RESET_WIDTH_NS = 14.0,
    parameter real T_RECOVERY_NS = 0.0
)(
    input  _1A_n,
    input  _1B,
    input  _1R_n,
    output _1Q,
    output _1Q_n,
    input  _2A_n,
    input  _2B,
    input  _2R_n,
    output _2Q,
    output _2Q_n
);

    wire [1:0] A_n;
    wire [1:0] B;
    wire [1:0] R_n;

    assign A_n[0] = _1A_n;
    assign A_n[1] = _2A_n;
    assign B[0]   = _1B;
    assign B[1]   = _2B;
    assign R_n[0] = _1R_n;
    assign R_n[1] = _2R_n;

    reg [1:0] Q = 2'b00;
    reg [1:0] Q_n = 2'b11;

    assign _1Q = Q[0];
    assign _1Q_n = Q_n[0];
    assign _2Q = Q[1];
    assign _2Q_n = Q_n[1];

    genvar i;
    generate for (i = 0; i < 2; i = i + 1) begin: channel
        localparam real RX = (i == 0) ? RX1_OHMS : RX2_OHMS;
        localparam real CX = (i == 0) ? CX1_PF : CX2_PF;
        localparam real K = (i == 0) ? K1 : K2;
        localparam real PULSE_NS = K * RX * CX * 0.001;
        localparam real END_DELAY_NS = PULSE_NS +
            ((T_TRIGGER_Q_NS > T_TRIGGER_Q_N_NS) ?
              T_TRIGGER_Q_NS : T_TRIGGER_Q_N_NS);

        integer timing_violations = 0;
        integer generation = 0;
        integer reset_generation = 0;
        // Delayed tokens are never allowed to mutate a later generation.
        // This avoids blocking an input process during an RC timer, and
        // also cancels pending trigger edges on reset/timing violations.
        integer rise_token = -1, fall_n_token = -1;
        integer end_token = -1, end_n_token = -1;
        integer reset_token = -1, reset_n_token = -1;
        integer done_token = -1;
        reg busy = 0;
        realtime busy_until = -1.0e9;
        realtime reset_q_due = -1.0e9, reset_q_n_due = -1.0e9;
        realtime trigger_q_due = 1.0e30, trigger_q_n_due = 1.0e30;
        realtime reset_started = -1.0e9, reset_released = -1.0e9;
        realtime a_started = -1.0e9, b_started = -1.0e9;
        reg check_a_pulse = 0, check_b_pulse = 0;
        reg previous_a = 1'bx, previous_b = 1'bx, previous_r = 1'bx;
        reg reset_saw_inhibit = 0, reset_armed = 0;

        initial begin
            if (RX <= 0 || CX <= 0 || K <= 0 || PULSE_NS < 0.001)
                $fatal(1, "%m: R, C and K must be positive; pulse must be >=1 ps");
            if (T_TRIGGER_Q_NS < 0 || T_TRIGGER_Q_N_NS < 0 ||
                T_RESET_Q_NS < 0 || T_RESET_Q_N_NS < 0 ||
                T_A_WIDTH_NS < 0 || T_B_WIDTH_NS < 0 ||
                T_RESET_WIDTH_NS < 0 || T_RECOVERY_NS < 0)
                $fatal(1, "%m: timing parameters must be nonnegative");
            if (RX < 500 || CX < 1000)
                $display("WARNING %m: nominal RC model outside R>=500 ohm, C>=1 nF");
            #0;
            previous_a = A_n[i];
            previous_b = B[i];
            previous_r = R_n[i];
            if (R_n[i] === 1'b0) begin
                reset_started = $realtime;
                reset_saw_inhibit = (A_n[i] === 1'b1 || B[i] === 1'b0);
            end else if (R_n[i] !== 1'b1) begin
                Q[i] = 1'bx;
                Q_n[i] = 1'bx;
            end
        end

        task invalidate;
            begin
                generation = generation + 1;
                reset_generation = reset_generation + 1;
                busy = 0;
                trigger_q_due = 1.0e30;
                trigger_q_n_due = 1.0e30;
                check_a_pulse = 0;
                check_b_pulse = 0;
            end
        endtask

        task violation(input [8*80-1:0] reason);
            begin
                timing_violations = timing_violations + 1;
                $display("WARNING %m at %0.3f ns: %0s", $realtime, reason);
                invalidate;
                Q[i] = 1'bx;
                Q_n[i] = 1'bx;
            end
        endtask

        task trigger_pulse;
            begin
                generation = generation + 1;
                busy = 1;
                busy_until = $realtime + END_DELAY_NS;
                trigger_q_due = $realtime + T_TRIGGER_Q_NS;
                trigger_q_n_due = $realtime + T_TRIGGER_Q_N_NS;
                rise_token <= #(T_TRIGGER_Q_NS) generation;
                fall_n_token <= #(T_TRIGGER_Q_N_NS) generation;
                end_token <= #(T_TRIGGER_Q_NS + PULSE_NS) generation;
                end_n_token <= #(T_TRIGGER_Q_N_NS + PULSE_NS) generation;
                done_token <= #(END_DELAY_NS) generation;
            end
        endtask

        always @(rise_token) if (rise_token == generation) Q[i] = 1'b1;
        always @(fall_n_token) if (fall_n_token == generation) Q_n[i] = 1'b0;
        always @(end_token) if (end_token == generation) Q[i] = 1'b0;
        always @(end_n_token) if (end_n_token == generation) Q_n[i] = 1'b1;
        // A minimum-width reset can be released before its output delays
        // finish. Preserve reset edges that precede a new trigger's edges;
        // suppress edges overtaken by that trigger. New resets and timing
        // violations invalidate these tokens independently of RC timers.
        always @(reset_token)
            if (reset_token == reset_generation && reset_q_due <= trigger_q_due)
                Q[i] = 1'b0;
        always @(reset_n_token)
            if (reset_n_token == reset_generation && reset_q_n_due <= trigger_q_n_due)
                Q_n[i] = 1'b1;
        always @(done_token) if (done_token == generation) busy = 0;

        always @(A_n[i] or B[i] or R_n[i]) begin
            // Coalesce simultaneous pin changes so reset wins deterministically.
            #0;
            if (A_n[i] === 1'b0 && previous_a !== 1'b0) a_started = $realtime;
            if (B[i] === 1'b1 && previous_b !== 1'b1) b_started = $realtime;

            if (R_n[i] === 1'b0) begin
                if (previous_r !== 1'b0) begin
                    reset_q_due = $realtime + T_RESET_Q_NS;
                    reset_q_n_due = $realtime + T_RESET_Q_N_NS;
                    // Reset may shorten a pulse, but cannot postpone a
                    // natural expiry that precedes reset propagation.
                    if (busy && trigger_q_due + PULSE_NS >= $realtime &&
                        trigger_q_due + PULSE_NS < reset_q_due)
                        reset_q_due = trigger_q_due + PULSE_NS;
                    if (busy && trigger_q_n_due + PULSE_NS >= $realtime &&
                        trigger_q_n_due + PULSE_NS < reset_q_n_due)
                        reset_q_n_due = trigger_q_n_due + PULSE_NS;
                    invalidate;
                    reset_started = $realtime;
                    reset_saw_inhibit = 0;
                    reset_armed = 0;
                    reset_token <= #(reset_q_due - $realtime) reset_generation;
                    reset_n_token <= #(reset_q_n_due - $realtime) reset_generation;
                end
                if (A_n[i] === 1'b1 || B[i] === 1'b0) begin
                    reset_saw_inhibit = 1;
                    reset_armed = 0;
                end else if (A_n[i] === 1'b0 && B[i] === 1'b1)
                    reset_armed = reset_saw_inhibit;
                else
                    reset_armed = 0;
            end else if (R_n[i] !== 1'b1) begin
                invalidate;
                Q[i] = 1'bx;
                Q_n[i] = 1'bx;
                reset_armed = 0;
            end else if (previous_r === 1'b0 &&
                         $realtime - reset_started < T_RESET_WIDTH_NS) begin
                reset_released = $realtime;
                violation("reset pulse width");
                reset_armed = 0;
            end else begin
                if (previous_r === 1'b0) reset_released = $realtime;
                // Resolve an expiry-edge trigger identically regardless of
                // whether the delayed-token process has run in this delta.
                if (busy && $realtime >= busy_until) begin
                    Q[i] = 0;
                    Q_n[i] = 1;
                    busy = 0;
                end
                if (check_a_pulse && A_n[i] === 1'b1 && previous_a === 1'b0) begin
                    check_a_pulse = 0;
                    if ($realtime - a_started < T_A_WIDTH_NS)
                        violation("A low pulse width");
                end
                if (check_b_pulse && B[i] === 1'b0 && previous_b === 1'b1) begin
                    check_b_pulse = 0;
                    if ($realtime - b_started < T_B_WIDTH_NS)
                        violation("B high pulse width");
                end
                if (!busy && A_n[i] === 1'b0 && B[i] === 1'b1) begin
                    if ((previous_a === 1'b1 && previous_r === 1'b1) ||
                        (previous_b === 1'b0 && previous_r === 1'b1) ||
                        (previous_r === 1'b0 && reset_armed)) begin
                        if (previous_r === 1'b1 &&
                            $realtime - reset_released < T_RECOVERY_NS)
                            violation("reset recovery");
                        else begin
                            trigger_pulse;
                            // Both input pulse prerequisites apply, including
                            // the pin qualifying a trigger on the other pin.
                            check_a_pulse = 1;
                            check_b_pulse = 1;
                        end
                    end
                end
                if (!busy && previous_r === 1'b1 &&
                    A_n[i] !== 1'b1 && B[i] !== 1'b0 &&
                    ((previous_a !== 1'b0 && A_n[i] !== 1'b1 && previous_a !== A_n[i]) ||
                     (previous_b !== 1'b1 && B[i] !== 1'b0 && previous_b !== B[i]))) begin
                    // A possible edge with an uncertain qualifier/level may
                    // have triggered; never silently assume it was inhibited.
                    invalidate;
                    Q[i] = 1'bx;
                    Q_n[i] = 1'bx;
                end
                if (previous_r === 1'b0) reset_armed = 0;
            end
            previous_a = A_n[i];
            previous_b = B[i];
            previous_r = R_n[i];
        end
    end endgenerate
endmodule
