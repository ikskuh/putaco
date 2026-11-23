`timescale 1ns/1ps

// Run with just test-74xx. Expected WARNING lines exercise timing failures;
// assertions verify both the violation counters and resulting unknown state.
module test_74xx;
    integer checks = 0;
    integer n, k, before_count;
    reg [3:0] a2 = 0, b2 = 0;
    wire [3:0] y2;
    CD74HC08 and2(a2, b2, y2);
    reg [1:0] a4 = 0, b4 = 0, c4 = 0, d4 = 0;
    wire [1:0] y4;
    CD74HC21 and4(a4, b4, c4, d4, y4);

    reg [2:0] address = 0;
    reg g0 = 0, g1 = 0, g2 = 1;
    wire [7:0] dec_n, dec;
    CD74HC138 decoder_n(address, g0, g1, g2, dec_n);
    CD74HC238 decoder(address, g0, g1, g2, dec);

    reg [7:0] buffer_a = 0;
    reg oe1 = 1, oe2 = 1;
    wire [7:0] hc_y, hct_y, inv_y;
    CD74HC541 hc_buffer(buffer_a, oe1, oe2, hc_y);
    CD74HCT541 hct_buffer(buffer_a, oe1, oe2, hct_y);
    SN74HC540 inverter(buffer_a, oe1, oe2, inv_y);
    reg bus_drive = 0;
    wire [7:0] shared_bus = hc_y;
    assign shared_bus = bus_drive ? ~buffer_a : 8'bz;

    reg [3:0] mux_a = 0, mux_b = 0;
    reg select_b = 0, strobe_n = 0;
    wire [3:0] mux_y;
    SN74HC157 mux(mux_a, mux_b, select_b, strobe_n, mux_y);
    reg [7:0] cmp_a = 0, cmp_b = 0;
    reg cmp_e = 0;
    wire cmp_y;
    CD74HC688 comparator(cmp_a, cmp_b, cmp_e, cmp_y);

    reg [3:0] data = 0;
    reg cp = 0, mr = 0, e1 = 0, e2 = 0, ro1 = 0, ro2 = 0;
    wire [3:0] q, hold_q;
    CD74HC173 register(data, cp, mr, e1, e2, ro1, ro2, q);
    // Exercise the overridable enable-hold check as well as its default 0.
    CD74HC173 #(.T_HOLD_ENABLE_NS(3.0)) hold_register(
        data, cp, mr, e1, e2, ro1, ro2, hold_q);
    reg period_cp = 0;
    wire [3:0] period_q;
    // Isolate the period check from the more restrictive pulse-width limits.
    CD74HC173 #(.T_CLOCK_WIDTH_NS(0), .T_PERIOD_NS(20)) period_register(
        4'ha, period_cp, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, period_q);

    reg [1:0] ma = 2'b11, mb = 0, reset_n = 0;
    wire [1:0] mq, mqn, sq, sqn;
    CD74HC221 #(.RX1_OHMS(1000), .CX1_PF(1000),
                 .RX2_OHMS(1000), .CX2_PF(2000)) mono(ma, mb, reset_n, mq, mqn);
    // Doubling R must match doubling C on channel 2 of mono.
    CD74HC221 #(.T_RECOVERY_NS(10), .RX1_OHMS(2000), .CX1_PF(1000),
                 .RX2_OHMS(2000), .CX2_PF(1000)) scaled(ma, mb, reset_n, sq, sqn);
    realtime started, start2;

    reg [1:0] ref_a = 2'b11, ref_b = 0, ref_r = 0;
    wire [1:0] ref_q, ref_qn;
    reg reference_done = 0;
    realtime reference_start;
    CD74HC221 reference_mono(ref_a, ref_b, ref_r, ref_q, ref_qn);

    task check(input condition, input [8*120-1:0] message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1)
                $fatal(1, "at %0.3f ns: %0s", $realtime, message);
        end
    endtask

    initial begin
        #50; ref_r = 3;
        #20; ref_a[0] = 0;
        #20; ref_b[0] = 1;
        @(posedge ref_q[0]); reference_start = $realtime;
        @(negedge ref_q[0]);
        check($realtime - reference_start == 680000.0, "default 10 kohm/100 nF pulse is 680 us");
        reference_done = 1;
    end

    task reset_register;
        begin
            cp = 0; mr = 1; e1 = 0; e2 = 0; ro1 = 0; ro2 = 0;
            #30; mr = 0;
            #20;
            check(q === 0, "register recovers on valid reset");
        end
    endtask

    task capture(input [3:0] value);
        begin
            data = value;
            #20; cp = 1;
            #20; cp = 0;
            #20;
        end
    endtask

    task reset_mono;
        begin
            reset_n = 0; ma = 3; mb = 0;
            #30; reset_n = 3;
            #20;
            check(mq === 0 && mqn === 3, "monostable recovers on valid reset");
        end
    endtask

    initial begin
        #50;
        check(q === 4'bxxxx, "HC173 storage starts unknown");
        check(mq === 0 && mqn === 3, "HC221 power-on reset");

        // Exhaustive gate truth tables, all buffer bytes, all mux inputs,
        // all decoder enable/address combinations, and all 65,536 comparisons.
        oe1 = 0; oe2 = 0;
        for (n = 0; n < 256; n = n + 1) begin
            a2 = n[3:0]; b2 = n[7:4];
            a4 = n[1:0]; b4 = n[3:2]; c4 = n[5:4]; d4 = n[7:6];
            buffer_a = n[7:0];
            #20;
            check(y2 === (a2 & b2), "HC08 truth table");
            check(y4 === (a4 & b4 & c4 & d4), "HC21 truth table");
            check(hc_y === buffer_a && hct_y === buffer_a, "HC/HCT541 truth tables");
            check(inv_y === ~buffer_a, "HC540 truth table");
        end
        for (n = 0; n < 1024; n = n + 1) begin
            mux_a = n[3:0]; mux_b = n[7:4]; select_b = n[8]; strobe_n = n[9];
            #20;
            check(mux_y === (strobe_n ? 4'b0 : (select_b ? mux_b : mux_a)), "HC157 truth table");
        end
        for (n = 0; n < 64; n = n + 1) begin
            address = n[2:0]; g0 = n[3]; g1 = n[4]; g2 = n[5];
            #14;
            check(dec === ((!g0 && !g1 && g2) ? (8'b1 << address) : 8'b0), "HC238 truth table");
            check(dec_n === ~dec, "HC138 truth table and polarity");
        end
        for (n = 0; n < 65536; n = n + 1) begin
            cmp_a = n[15:8]; cmp_b = n[7:0];
            #15;
            check(cmp_y === (cmp_a != cmp_b), "HC688 exhaustive comparison");
        end

        // Controlling values must mask X/Z; otherwise preserve uncertainty.
        a2 = 4'bxz11; b2 = 4'b001x;
        a4 = 2'bxx; b4 = 3; c4 = 0; d4 = 3;
        address = 3'bx00; g0 = 0; g1 = 0; g2 = 1;
        mux_a = 5; mux_b = 5; select_b = 1'bx; strobe_n = 0;
        cmp_a = 8'bx0000001; cmp_b = 0;
        #20;
        check(y2 === 4'b001x && y4 === 0, "AND controlling values and X/Z");
        check(dec_n === 8'b111x111x && dec === 8'b000x000x, "partial unknown decoder address");
        check(mux_y === 5, "unknown mux select merges identical data");
        check(cmp_y === 1, "known inequality masks unknown compare bits");
        mux_b = 10; cmp_b = 1;
        #20;
        check(mux_y === 4'bxxxx && cmp_y === 1'bx, "unknown selection and possible equality");
        strobe_n = 1; cmp_e = 1; g2 = 0;
        #20;
        check(mux_y === 0 && cmp_y === 1 && dec === 0 && dec_n === 8'hff, "disable masks unknown data");
        buffer_a = 8'bz;
        #20;
        check(hc_y === 8'bx && hct_y === 8'bx && inv_y === 8'bx, "floating buffer inputs become X");
        buffer_a = 8'ha5; bus_drive = 1;
        #20;
        check(shared_bus === 8'bx, "bus contention resolves to X");
        oe1 = 1;
        #20;
        check(hc_y === 8'bz && shared_bus === 8'h5a, "released bus leaves other driver visible");
        bus_drive = 0;

        // Both inputs of every HC08 gate, and all four HC21 input paths.
        a2 = 0; b2 = 15;
        #30; a2 = 15;
        #9.999; check(y2 === 0, "HC08 A path before 10 ns");
        #0.002; check(y2 === 15, "HC08 A path after 10 ns");
        #20; b2 = 0;
        #9.999; check(y2 === 15, "HC08 B path before 10 ns");
        #0.002; check(y2 === 0, "HC08 B path after 10 ns");
        for (k = 0; k < 4; k = k + 1) begin
            a4 = 3; b4 = 3; c4 = 3; d4 = 3;
            #20;
            case (k) 0: a4 = 0; 1: b4 = 0; 2: c4 = 0; 3: d4 = 0; endcase
            #8.999; check(y4 === 3, "HC21 path before 9 ns");
            #0.002; check(y4 === 0, "HC21 path after 9 ns");
        end

        // Address and each enable pin of BOTH decoder polarities.
        address = 0; g0 = 0; g1 = 0; g2 = 1;
        #30; address = 1;
        #12.999; check(dec === 1 && dec_n === 8'hfe, "decoder address path before 13 ns");
        #0.002; check(dec === 2 && dec_n === 8'hfd, "decoder address path after 13 ns");
        for (k = 0; k < 3; k = k + 1) begin
            g0 = 0; g1 = 0; g2 = 1;
            #20;
            case (k) 0: g0 = 1; 1: g1 = 1; 2: g2 = 0; endcase
            #12.999; check(dec === 2 && dec_n === 8'hfd, "decoder enable path before 13 ns");
            #0.002; check(dec === 0 && dec_n === 8'hff, "decoder enable path after 13 ns");
        end

        // Separate buffer data, enable and disable paths, including both OEs.
        buffer_a = 0; oe1 = 1; oe2 = 0;
        #30;
        for (k = 0; k < 2; k = k + 1) begin
            if (k == 0) oe1 = 0; else oe2 = 0;
            #13.999; check(hc_y === 8'bz && hct_y === 8'bz && inv_y === 8'bz, "buffer enable before delay");
            #0.002; check(hc_y === 0 && hct_y === 0 && inv_y === 8'bz, "HC/HCT buffer enable at 14 ns");
            #0.331; check(inv_y === 8'bz, "HC540 enable before 14.333 ns");
            #0.002; check(inv_y === 8'hff, "HC540 enable after 14.333 ns");
            #20;
            if (k == 0) oe1 = 1; else oe2 = 1;
            #13.999; check(hc_y === 0 && hct_y === 0 && inv_y === 8'hff, "buffer disable before delay");
            #0.002; check(hc_y === 8'bz && hct_y === 8'bz && inv_y === 8'hff, "HC/HCT buffer disable at 14 ns");
            #3.665; check(inv_y === 8'hff, "HC540 disable before 17.667 ns");
            #0.002; check(inv_y === 8'bz, "HC540 disable after 17.667 ns");
            if (k == 0) begin oe2 = 1; oe1 = 0; end
            #30;
        end
        oe1 = 0; oe2 = 0;
        #30; buffer_a = 8'hff;
        #8.999; check(hc_y === 0 && hct_y === 0 && inv_y === 8'hff, "buffer data before delays");
        #0.002; check(hc_y === 8'hff && hct_y === 0, "HC541 9 ns data path");
        #0.331; check(inv_y === 8'hff, "HC540 data before 9.333 ns");
        #0.002; check(inv_y === 0, "HC540 data after 9.333 ns");
        #1.665; check(hct_y === 0, "HCT541 data before 11 ns");
        #0.002; check(hct_y === 8'hff, "HCT541 data after 11 ns");

        mux_a = 0; mux_b = 0; select_b = 0; strobe_n = 0;
        #30; mux_a = 15;
        #12.332; check(mux_y === 0, "mux A before 12.333 ns");
        #0.002; check(mux_y === 15, "mux A after 12.333 ns");
        #20; select_b = 1;
        #16.666; check(mux_y === 15, "mux select before 16.667 ns");
        #0.002; check(mux_y === 0, "mux select after 16.667 ns");
        #20; mux_b = 15;
        #12.332; check(mux_y === 0, "mux B before 12.333 ns");
        #0.002; check(mux_y === 15, "mux B after 12.333 ns");
        #20; strobe_n = 1;
        #14.999; check(mux_y === 15, "mux strobe before 15 ns");
        #0.002; check(mux_y === 0, "mux strobe after 15 ns");

        cmp_a = 0; cmp_b = 0; cmp_e = 0;
        #30; cmp_a = 1;
        #13.999; check(cmp_y === 0, "comparator A before 14 ns");
        #0.002; check(cmp_y === 1, "comparator A after 14 ns");
        #20; cmp_b = 1;
        #13.999; check(cmp_y === 1, "comparator B before 14 ns");
        #0.002; check(cmp_y === 0, "comparator B after 14 ns");
        #20; cmp_e = 1;
        #8.999; check(cmp_y === 0, "comparator enable before 9 ns");
        #0.002; check(cmp_y === 1, "comparator enable after 9 ns");

        // Register timing and state. Start with a known reset and no errors.
        reset_register;
        data = 10;
        #12; cp = 1;
        #16.999; check(q === 0, "register clock path before 17 ns");
        #0.002; check(q === 10, "register clock path after 17 ns");
        cp = 0;
        #20; mr = 1;
        #11.999; check(q === 10, "register reset path before 12 ns");
        #0.002; check(q === 0, "register reset path after 12 ns");
        #8; mr = 0;
        #20;
        check(register.timing_violations == 0, "legal register traffic has no violations");
        capture(5);
        e1 = 1;
        #20; capture(10);
        check(q === 5, "first data enable inhibits capture");
        e1 = 0; e2 = 1;
        #20; capture(10);
        check(q === 5, "second data enable inhibits capture");
        e2 = 0;
        #20;
        for (k = 0; k < 2; k = k + 1) begin
            if (k == 0) ro1 = 1; else ro2 = 1;
            #11.999; check(q === 5, "register disable before 12 ns");
            #0.002; check(q === 4'bz, "register disable after 12 ns");
            capture(10);
            if (k == 0) ro1 = 0; else ro2 = 0;
            #11.999; check(q === 4'bz, "register enable before 12 ns");
            #0.002; check(q === 10, "register captures while outputs disabled");
            capture(5);
        end
        e1 = 1'bx;
        #20; capture(5);
        check(q === 5, "uncertain data enable merges identical hold/capture");
        capture(10);
        check(q === 4'bxxxx, "uncertain data enable merges differing bits to X");
        e1 = 0;
        #20; capture(7);
        check(q === 7, "clean capture recovers unknown register state");
        before_count = register.timing_violations;
        e1 = 1; #20; e2 = 1; #1; cp = 1;
        #20; cp = 0; #20;
        check(q === 7 && register.timing_violations == before_count,
              "stable E1 inhibit masks late E2 changes");
        e1 = 0; #20; e1 = 1; #1; cp = 1;
        #20; cp = 0; #20;
        check(q === 7 && register.timing_violations == before_count,
              "stable E2 inhibit masks late E1 changes");
        e1 = 0; e2 = 0; #20;

        // Setup: exactly the limit passes; 1 ps below fails.
        before_count = register.timing_violations;
        data = 1; #12; cp = 1;
        #20; cp = 0; #20;
        check(q === 1 && register.timing_violations == before_count, "data setup boundary passes");
        data = 2; #11.999; cp = 1;
        #20; cp = 0; #20;
        check(q === 4'bx && register.timing_violations == before_count + 1, "data setup below boundary poisons state");
        capture(3);
        before_count = register.timing_violations;
        cp = 1; #3; data = 4;
        #17; cp = 0; #20;
        check(q === 3 && register.timing_violations == before_count, "data hold boundary passes");
        #20; cp = 1; #2.999; data = 5;
        #20; cp = 0; #20;
        check(q === 4'bx && register.timing_violations == before_count + 1, "data hold below boundary poisons state");

        reset_register;
        e1 = 1; #20; e1 = 0; #12; cp = 1;
        #20; cp = 0; #20;
        before_count = register.timing_violations;
        e2 = 1; #20; e2 = 0; #11.999; cp = 1;
        #20; cp = 0; #20;
        check(q === 4'bx && register.timing_violations == before_count + 1, "enable setup below boundary");
        reset_register;
        cp = 1; #3; e1 = 1;
        #20; cp = 0; #20;
        check(hold_q === data, "overridden enable hold boundary passes");
        e1 = 0; #20; cp = 1; #2.999; e1 = 1;
        #20; cp = 0; #20;
        check(hold_q === 4'bx, "overridden enable hold below boundary poisons state");

        reset_register;
        before_count = register.timing_violations;
        cp = 1; #16; cp = 0; #16; cp = 1; #16; cp = 0; #20;
        check(register.timing_violations == before_count, "clock width boundary passes on both levels");
        cp = 1; #15.999; cp = 0; #20;
        check(q === 4'bx && register.timing_violations == before_count + 1, "short high clock pulse poisons state");
        reset_register;
        cp = 1; #16; cp = 0; #15.999; cp = 1; #20; cp = 0; #20;
        check(q === 4'bx, "short low clock pulse poisons state");
        reset_register;
        cp = 1; #8; cp = 0; #8; cp = 1; #20; cp = 0; #20;
        check(q === 4'bx, "clock period violation poisons state");

        mr = 1; #16; mr = 0; #12; cp = 1;
        #20; cp = 0; #20;
        check(q === data, "reset width and reset-release boundaries pass");
        mr = 1; #15.999; mr = 0; #30;
        check(q === 4'bx, "short reset pulse poisons state");
        mr = 1; #20; mr = 0; #11.999; cp = 1;
        #20; cp = 0; #20;
        check(q === 4'bx, "reset-release separation below boundary");
        reset_register;
        data = 9; #20; cp = 1; #5; mr = 1;
        #30;
        check(q === 0, "reset overrides in-flight register capture");
        cp = 0; #20; mr = 0; #20;
        data = 4'bz; #20; cp = 1; #20; cp = 0; #20;
        check(q === 4'bx, "floating register data is unknown");
        reset_register;
        cp = 1'bx; #30;
        check(q === 4'bx, "ambiguous clock poisons register");
        reset_register;

        period_cp = 1; #10; period_cp = 0; #10; period_cp = 1;
        #17.001;
        check(period_q === 10 && period_register.timing_violations == 0, "clock period boundary passes");
        period_cp = 0; #2.998; period_cp = 1;
        #17.001;
        check(period_q === 4'bx && period_register.timing_violations == 1, "clock period 1 ps below boundary fails");

        // A and B trigger qualification, independent channels, and RC width.
        reset_mono;
        mb[0] = 1; #30;
        check(mq === 0, "B rising is inhibited when A is high");
        mb[0] = 0; ma[0] = 0; #30;
        check(mq === 0, "A falling is inhibited when B is low");
        mb[0] = 1; started = $realtime;
        #13.999; check(mq[0] === 0 && mqn[0] === 1, "HC221 trigger before Q_n delay");
        #0.002; check(mqn[0] === 0 && mq[0] === 0, "HC221 Q_n falls at 14 ns");
        #3.998; check(mq[0] === 0, "HC221 Q before 18 ns");
        #0.002; check(mq[0] === 1 && mq[1] === 0, "HC221 Q rises at 18 ns; channels independent");
        #20; mb[0] = 0; #20; mb[0] = 1;
        #20; ma[0] = 1; #20; ma[0] = 0;
        #20; ma[0] = 1'bx; mb[0] = 1'bx;
        #20; check(mq[0] === 1, "unknown trigger activity cannot alter an active pulse");
        ma[0] = 0; mb[0] = 1;
        // Both rising-B and falling-A triggers during a pulse are ignored.
        #(started + 693.999 - $realtime);
        check(mqn[0] === 0, "Q_n pulse before 680 ns expiry");
        #0.002; check(mqn[0] === 1, "Q_n pulse width excludes propagation delay");
        #3.998; check(mq[0] === 1, "Q pulse before 680 ns expiry");
        #0.002; check(mq[0] === 0 && sq[0] === 1, "ignored triggers do not extend pulse; doubled R still active");
        #(started + 1378.001 - $realtime);
        check(sq[0] === 0, "doubling R doubles pulse width");
        mb[1] = 1; #20; ma[1] = 0; start2 = $realtime;
        #18.001; check(mq[1] === 1 && mq[0] === 0, "A falling triggers independent second channel");
        #(start2 + 1377.999 - $realtime);
        check(mq[1] === 1 && sq[1] === 1, "doubling C matches doubling R before expiry");
        #0.002; check(mq[1] === 0 && sq[1] === 0, "doubling C matches doubling R after expiry");
        check(mono.channel[0].timing_violations == 0 && mono.channel[1].timing_violations == 0,
              "legal monostable traffic has no violations");

        // Reset-release arming sequence, then cancellation before leading edge.
        reset_mono;
        ma[0] = 0; mb[0] = 1; #30;
        reset_n[0] = 0; #30; reset_n[0] = 1; #30;
        check(mq[0] === 0, "reset release without arming does not trigger");
        reset_n[0] = 0; ma[0] = 1; mb[0] = 0;
        #20; ma[0] = 0; mb[0] = 1;
        #20; reset_n[0] = 1;
        #18.001; check(mq[0] === 1, "armed reset release triggers");
        reset_mono;
        ma[0] = 0; #20; mb[0] = 1;
        #5; reset_n[0] = 0;
        #13.001; check(mq[0] === 0, "reset cancels pending trigger edge");
        #20; check(mq[0] === 0 && mqn[0] === 1, "reset cancels both pending output edges");

        // Reset paths and stale expiry cancellation across a new pulse.
        reset_mono;
        ma[0] = 0; #20; mb[0] = 1;
        #30; reset_n[0] = 0;
        #13.999; check(mq[0] === 1 && mqn[0] === 0, "reset Q before 14 ns");
        #0.002; check(mq[0] === 0 && mqn[0] === 0, "reset Q after 14 ns");
        #3.998; check(mqn[0] === 0, "reset Q_n before 18 ns");
        #0.002; check(mqn[0] === 1, "reset Q_n after 18 ns");
        ma[0] = 1; mb[0] = 0; #20; reset_n[0] = 1;
        #20; ma[0] = 0; #20; mb[0] = 1; started = $realtime;
        #600; check(mq[0] === 1, "old expiry cannot terminate later pulse");
        #(started + 698.001 - $realtime); check(mq[0] === 0, "new pulse expires on its own timer");

        // Trigger exactly at an old expiry must not depend on delta ordering.
        reset_mono;
        ma[0] = 0; #20; mb[0] = 1; started = $realtime;
        #30; mb[0] = 0;
        #(started + 698.0 - $realtime); mb[0] = 1;
        #0.001; check(mq[0] === 0, "expiry-edge retrigger begins with idle output");
        #18; check(mq[0] === 1, "expiry-edge retrigger produces a new pulse");
        #680; check(mq[0] === 0, "expiry-edge retrigger has full RC width");

        // A legal 14 ns reset may be released before its 18 ns Q_n delay.
        // The new trigger must preserve reset edges preceding its own edges.
        reset_mono;
        ma[0] = 0; #20; mb[0] = 1; #30;
        reset_n[0] = 0;
        #5; ma[0] = 1; mb[0] = 0;
        #5; ma[0] = 0; mb[0] = 1;
        #4; reset_n[0] = 1;
        #0.001; check(mq[0] === 0, "minimum reset preserves pending Q reset on immediate rearm");
        #3.998; check(mqn[0] === 0, "pending Q_n reset before 18 ns");
        #0.002; check(mqn[0] === 1, "pending Q_n reset survives immediate rearm");
        #9.998; check(mqn[0] === 1, "rearmed Q_n before new trigger delay");
        #0.002; check(mqn[0] === 0, "rearmed Q_n after new trigger delay");
        #3.998; check(mq[0] === 0, "rearmed Q before new trigger delay");
        #0.002; check(mq[0] === 1, "rearmed Q after new trigger delay");

        reset_mono;
        ma[0] = 0; #20; mb[0] = 1; started = $realtime;
        #697; reset_n[0] = 0;
        #0.999; check(mq[0] === 1, "late reset before natural pulse expiry");
        #0.002; check(mq[0] === 0, "late reset cannot extend pulse beyond natural expiry");

        // Minimum trigger/reset pulse widths: limit passes, limit-1 ps fails.
        reset_mono;
        ma[0] = 0; #20;
        before_count = mono.channel[0].timing_violations;
        mb[0] = 1; #14; mb[0] = 0; #30;
        check(mq[0] === 1 && mono.channel[0].timing_violations == before_count, "B width boundary passes");
        reset_mono;
        ma[0] = 0; #20; mb[0] = 1; #13.999; mb[0] = 0; #30;
        check(mq[0] === 1'bx && mqn[0] === 1'bx, "short B pulse cancels timer and poisons outputs");
        reset_mono;
        mb[0] = 1; #20; ma[0] = 0; #14; ma[0] = 1; #30;
        check(mq[0] === 1, "A width boundary passes");
        reset_mono;
        mb[0] = 1; #20; ma[0] = 0; #13.999; ma[0] = 1; #30;
        check(mq[0] === 1'bx, "short A pulse poisons output");
        reset_mono;
        // The short pin can be the qualifier rather than the triggering pin.
        mb[0] = 1; #1; ma[0] = 0; #1; mb[0] = 0; #30;
        check(mq[0] === 1'bx, "short B qualifier also violates pulse prerequisite");
        reset_mono;
        ma[0] = 0; #1; mb[0] = 1; #1; ma[0] = 1; #30;
        check(mq[0] === 1'bx, "short A qualifier also violates pulse prerequisite");
        reset_n[0] = 0; ma[0] = 1; mb[0] = 0;
        #14; reset_n[0] = 1; #30;
        check(mq[0] === 0 && mqn[0] === 1, "reset width boundary passes");
        reset_n[0] = 0; #13.999; reset_n[0] = 1; #30;
        check(mq[0] === 1'bx && mqn[0] === 1'bx, "short reset pulse poisons outputs");
        reset_mono;
        reset_n[0] = 1'bx; #30;
        check(mq[0] === 1'bx && mqn[0] === 1'bx, "unknown reset poisons outputs");
        reset_mono;
        ma[0] = 1'bx; mb[0] = 1; #20; ma[0] = 0; #30;
        check(mq[0] === 1'bx, "ambiguous trigger edge preserves uncertainty");
        reset_mono;
        ma[0] = 0; #20; mb[0] = 1'bx; #30;
        check(mq[0] === 1'bx, "possible B rising edge preserves uncertainty");
        reset_mono;
        mb[0] = 1'bx; #20; ma[0] = 0; #30;
        check(mq[0] === 1'bx, "unknown qualifier on definite trigger edge preserves uncertainty");
        reset_mono;

        // Recovery is zero by default; exercise its nonzero override on scaled.
        reset_n = 0; ma = 0; mb = 0; #20; reset_n = 3;
        #10; mb[0] = 1; #30;
        check(sq[0] === 1, "overridden recovery boundary passes");
        reset_mono;
        reset_n = 0; ma = 0; mb = 0; #20; reset_n = 3;
        #9.999; mb[0] = 1; #30;
        check(sq[0] === 1'bx && mq[0] === 1, "recovery below boundary affects only configured model");
        reset_mono;

        check(reference_done, "default-RC reference pulse completed");
        $display("PASS: %0d checks across all 11 timed 74xx models", checks);
        $finish;
    end

    initial begin
        #3000000;
        $fatal(1, "74xx regression timed out");
    end
endmodule
