`timescale 1ns/1ps

// Run with just test-memory. Fixture files live only in ignored zig-out/.
// WARNING messages from deliberately invalid writes are expected.
module test_memory;
    integer checks = 0, file_handle, n, before_count;
    reg [18:0] fa = 0, probe_a = 0;
    reg fce = 1, foe = 1, fwe = 1, fdrive = 0;
    reg [7:0] fdata = 0;
    wire [7:0] fdq;
    assign fdq = fdrive ? fdata : 8'bz;
    SST39SF040 #(.INIT_FILE("zig-out/gateware/memory/flash.hex")) flash(fa, fdq, fce, foe, fwe);
    reg [16:0] sa = 0;
    reg sce = 1, sce2 = 0, soe = 1, swe = 1, sdrive = 0;
    reg [7:0] sdata = 0;
    wire [7:0] sdq;
    assign sdq = sdrive ? sdata : 8'bz;
    AS6C1008 #(.INIT_FILE("zig-out/gateware/memory/ram.hex")) ram(sa, sdq, sce, sce2, soe, swe);

    wire [7:0] flash_raw_q, flash_binary_q, flash_erased_q;
    wire [7:0] ram_raw_q, ram_binary_q, ram_empty_q;
    SST39SF040 #(.INIT_FILE("zig-out/gateware/memory/bytes.raw"), .INIT_FORMAT("raw"),
                .T_POWERUP_NS(0)) flash_raw(probe_a, flash_raw_q, 1'b0, 1'b0, 1'b1);
    SST39SF040 #(.INIT_FILE("zig-out/gateware/memory/bytes.bits"), .INIT_FORMAT("binary"),
                .T_POWERUP_NS(0)) flash_binary(probe_a, flash_binary_q, 1'b0, 1'b0, 1'b1);
    SST39SF040 #(.T_POWERUP_NS(0)) flash_erased(probe_a, flash_erased_q, 1'b0, 1'b0, 1'b1);
    AS6C1008 #(.INIT_FILE("zig-out/gateware/memory/bytes.raw"), .INIT_FORMAT("raw"))
        ram_raw(probe_a[16:0], ram_raw_q, 1'b0, 1'b1, 1'b0, 1'b1);
    AS6C1008 #(.INIT_FILE("zig-out/gateware/memory/bytes.bits"), .INIT_FORMAT("binary"))
        ram_binary(probe_a[16:0], ram_binary_q, 1'b0, 1'b1, 1'b0, 1'b1);
    AS6C1008 ram_empty(probe_a[16:0], ram_empty_q, 1'b0, 1'b1, 1'b0, 1'b1);
    realtime started;

    task check(input condition, input [8*120-1:0] message);
        begin
            checks = checks + 1;
            if (condition !== 1'b1)
                $fatal(1, "at %0.3f ns: %0s", $realtime, message);
        end
    endtask

    // Models load at the first delta, after these time-zero fixtures exist.
    initial begin
        file_handle = $fopen("zig-out/gateware/memory/flash.hex", "w");
        $fdisplay(file_handle, "@00000 12 34 56 78\n@7ffff e1");
        $fclose(file_handle);
        file_handle = $fopen("zig-out/gateware/memory/ram.hex", "w");
        $fdisplay(file_handle, "@00000 12 34 56 78\n@1ffff e1");
        $fclose(file_handle);
        file_handle = $fopen("zig-out/gateware/memory/bytes.bits", "w");
        $fdisplay(file_handle, "@00000 00111100 10110011 10000000 11111111\n@1ffff 11100010");
        $fclose(file_handle);
        file_handle = $fopen("zig-out/gateware/memory/bytes.raw", "wb");
        $fwrite(file_handle, "%c%c%c%c", 8'h00, 8'h0a, 8'h80, 8'hff);
        $fclose(file_handle);
    end

    task idle_ram;
        begin
            soe = 1; swe = 1; sce = 1; sce2 = 0; sdrive = 0;
            #30;
        end
    endtask

    task write_byte(input [16:0] address, input [7:0] value, input integer ending_pin);
        begin
            idle_ram;
            sa = address; sdata = value; sdrive = 1;
            sce = 0; sce2 = 1;
            #30; swe = 0;
            #55;
            case (ending_pin)
                0: swe = 1;
                1: sce = 1;
                2: sce2 = 0;
            endcase
            sdrive = 0; // legal zero hold time, same timestamp as write end
            #25;
        end
    endtask

    task read_byte(input [16:0] address, input [7:0] value);
        begin
            idle_ram;
            sa = address; sce = 0; sce2 = 1; soe = 0;
            #55.001;
            check(sdq === value, "SRAM readback");
        end
    endtask

    initial begin
        #80;
        check(flash_raw_q === 0 && ram_raw_q === 0, "raw preload preserves NUL byte");
        check(flash_binary_q === 8'h3c && ram_binary_q === 8'h3c, "binary-text preloads");
        check(flash_erased_q === 8'hff && ram_empty_q === 8'bx, "uninitialized flash erased; SRAM unknown");
        probe_a = 1; #70.001;
        check(flash_raw_q === 8'h0a && ram_raw_q === 8'h0a, "raw preload preserves newline byte");
        check(flash_binary_q === 8'hb3 && ram_binary_q === 8'hb3, "binary-text byte order");
        probe_a = 2; #70.001;
        check(flash_raw_q === 8'h80 && ram_raw_q === 8'h80, "raw preload preserves high bit");
        probe_a = 3; #70.001;
        check(flash_raw_q === 8'hff && ram_raw_q === 8'hff, "raw FF is not EOF");
        probe_a = 4; #70.001;
        check(flash_raw_q === 8'hff && ram_raw_q === 8'bx, "partial images retain default fill");
        probe_a = 19'h1ffff; #70.001;
        check(flash_binary_q === 8'he2 && ram_binary_q === 8'he2, "sparse binary-text address directives");

        check(fdq === 8'bz && sdq === 8'bz, "disabled chips release buses");
        fce = 0; foe = 0;
        #0.001; check(fdq === 8'bx, "flash unavailable before power-up interval");
        #(99999.999 - $realtime); check(fdq === 8'bx, "flash power-up boundary before 100 us");
        #0.002; check(fdq === 8'h12, "flash power-up boundary after 100 us");
        fa = 1;
        #0.001; check(fdq === 8'bx, "flash zero address hold then invalid access window");
        #69.998; check(fdq === 8'bx, "flash address before 70 ns");
        #0.002; check(fdq === 8'h34, "flash address after 70 ns");
        fa = 19'h7ffff; #70.001;
        check(fdq === 8'he1, "flash full 19-bit address and hex preload");
        foe = 1;
        #24.999; check(fdq === 8'he1, "flash OE disable before 25 ns");
        #0.002; check(fdq === 8'bz, "flash OE disable after 25 ns");
        foe = 0;
        #34.999; check(fdq === 8'bx, "flash OE access before 35 ns");
        #0.002; check(fdq === 8'he1, "flash OE access after 35 ns");
        fce = 1; #5; foe = 1;
        #19.999; check(fdq === 8'he1, "first flash disable not postponed by later disable");
        #0.002; check(fdq === 8'bz, "earliest flash disable wins");

        // A later OE assertion must not outrun an unfinished address access.
        #30; fa = 0; #80; fce = 0;
        #20; fa = 1;
        #30; foe = 0;
        #35.001; check(fdq === 8'bx, "flash meets concurrent address and enable deadlines");
        #4.998; check(fdq === 8'bx, "flash limiting address deadline before boundary");
        #0.002; check(fdq === 8'h34, "flash limiting address deadline after boundary");
        fa = 0; #30; fa = 2;
        #40.001; check(fdq === 8'bx, "stale flash address access is cancelled");
        #30; check(fdq === 8'h56, "latest flash address eventually settles");

        // Read-only flash ignores write attempts and releases its data bus.
        foe = 1; fwe = 0; #30;
        fa = 0; fdata = 8'h00; fdrive = 1;
        #50; fwe = 1; fdrive = 0; foe = 0;
        #70.001; check(fdq === 8'h12, "flash write attempt cannot change preloaded bytes");
        fa = 19'bx; #70.001;
        check(fdq === 8'bx, "unknown flash address reads unknown");
        fce = 1; #25.001;
        check(fdq === 8'bz, "known flash disable masks unknown address");
        fce = 1'bx; #1;
        check(fdq === 8'bx, "uncertain flash selection is unknown");
        fce = 1; #30;

        // SRAM CE/CE2/OE qualification, access, low-Z, hold and release.
        sa = 0; sce = 0; sce2 = 1; soe = 0;
        #9.999; check(sdq === 8'bz, "SRAM CE low-Z before 10 ns");
        #0.002; check(sdq === 8'bx, "SRAM low-Z before valid data");
        #44.998; check(sdq === 8'bx, "SRAM CE access before 55 ns");
        #0.002; check(sdq === 8'h12, "SRAM CE access after 55 ns, hex preload");
        sa = 1;
        #9.999; check(sdq === 8'h12, "SRAM address hold before 10 ns");
        #0.002; check(sdq === 8'bx, "SRAM address hold after 10 ns");
        #44.998; check(sdq === 8'bx, "SRAM address access before 55 ns");
        #0.002; check(sdq === 8'h34, "SRAM address access after 55 ns");
        soe = 1;
        #19.999; check(sdq === 8'h34, "SRAM OE disable before 20 ns");
        #0.002; check(sdq === 8'bz, "SRAM OE disable after 20 ns");
        soe = 0;
        #4.999; check(sdq === 8'bz, "SRAM OE low-Z before 5 ns");
        #0.002; check(sdq === 8'bx, "SRAM OE low-Z after 5 ns");
        #24.998; check(sdq === 8'bx, "SRAM OE access before 30 ns");
        #0.002; check(sdq === 8'h34, "SRAM OE access after 30 ns");
        sce2 = 0;
        #19.999; check(sdq === 8'h34, "SRAM CE2 disable before 20 ns");
        #0.002; check(sdq === 8'bz, "SRAM CE2 disable after 20 ns");
        sce2 = 1;
        #54.999; check(sdq === 8'bx, "SRAM CE2 access before 55 ns");
        #0.002; check(sdq === 8'h34, "SRAM CE2 access after 55 ns");
        idle_ram;
        sce = 0; sce2 = 1; soe = 0;
        #10; soe = 1;
        #20.001; check(sdq === 8'bz, "SRAM disabled during pending access");
        #30; check(sdq === 8'bz, "cancelled SRAM access cannot drive later");
        read_byte(17'h1ffff, 8'he1);

        // Each of WE_n, CE_n and CE2 can terminate a write; zero data hold.
        for (n = 0; n < 3; n = n + 1) begin
            write_byte(n, 8'ha0 + n, n);
            read_byte(n, 8'ha0 + n);
        end
        // Walking address/data patterns, including the highest SRAM byte.
        for (n = 0; n < 17; n = n + 1) write_byte(17'b1 << n, 8'h80 + n, n % 3);
        for (n = 0; n < 17; n = n + 1) read_byte(17'b1 << n, 8'h80 + n);
        for (n = 0; n < 8; n = n + 1) begin
            write_byte(17'h1ffff, 8'b1 << n, 0);
            read_byte(17'h1ffff, 8'b1 << n);
        end
        check(ram.timing_violations == 0, "valid SRAM traffic has no timing violations");

        // OE may stay low during a WE-controlled write. Allow drivers to
        // release, then meet data setup; read resumes 5 ns after write end.
        read_byte(0, 8'ha0);
        sdata = 8'h5a; sdrive = 1; swe = 0;
        #19.999; check(ram.drive === 8'ha0, "SRAM WE output release before 20 ns");
        #0.002; check(ram.drive === 8'bz && sdq === 8'h5a, "SRAM WE output release after 20 ns");
        #34.999; swe = 1; sdrive = 0;
        #4.999; check(sdq === 8'bz, "SRAM write-to-output before 5 ns");
        #0.002; check(sdq === 8'h5a, "SRAM write-to-output after 5 ns");

        // Exact input timing boundaries and violations 1 ps below them.
        idle_ram; sa = 20; sce = 0; sce2 = 1; sdata = 8'h66; sdrive = 1;
        #60; swe = 0; #45; swe = 1; sdrive = 0; #25;
        read_byte(20, 8'h66);
        before_count = ram.timing_violations;
        idle_ram; sa = 21; sce = 0; sce2 = 1; sdata = 8'h77; sdrive = 1;
        #60; swe = 0; #44.999; swe = 1; sdrive = 0; #25;
        read_byte(21, 8'bx);
        check(ram.timing_violations == before_count + 1, "short SRAM write pulse reported");

        idle_ram; sa = 22; sce = 0; sce2 = 1; sdata = 0; sdrive = 1;
        #60; swe = 0; #30; sdata = 8'h88; #25; swe = 1; sdrive = 0; #25;
        read_byte(22, 8'h88);
        before_count = ram.timing_violations;
        idle_ram; sa = 23; sce = 0; sce2 = 1; sdata = 0; sdrive = 1;
        #60; swe = 0; #30; sdata = 8'h99; #24.999; swe = 1; sdrive = 0; #25;
        read_byte(23, 8'bx);
        check(ram.timing_violations == before_count + 1, "insufficient SRAM data setup reported");

        idle_ram; sce = 0; sce2 = 1; #60;
        sa = 24; sdata = 8'haa; sdrive = 1;
        #5; swe = 0; #45; swe = 1; sdrive = 0; #25;
        read_byte(24, 8'haa);
        before_count = ram.timing_violations;
        idle_ram; sce = 0; sce2 = 1; #60;
        sa = 25; sdata = 8'hbb; sdrive = 1;
        #4.999; swe = 0; #45; swe = 1; sdrive = 0; #25;
        read_byte(25, 8'bx);
        check(ram.timing_violations == before_count + 1, "insufficient SRAM address setup reported");

        idle_ram; sa = 26; sdata = 8'hcc; sdrive = 1; swe = 0;
        #60; sce = 0; sce2 = 1; #50; sce2 = 0; sdrive = 0; #25;
        read_byte(26, 8'hcc);
        before_count = ram.timing_violations;
        idle_ram; sa = 27; sdata = 8'hdd; sdrive = 1; swe = 0;
        #60; sce = 0; sce2 = 1; #49.999; sce = 1; sdrive = 0; #25;
        read_byte(27, 8'bx);
        check(ram.timing_violations == before_count + 1, "insufficient SRAM chip enable duration reported");

        // Invalid address changes corrupt both touched locations only.
        idle_ram; sa = 28; sce = 0; sce2 = 1; sdata = 8'hee; sdrive = 1;
        #60; swe = 0; #20; sa = 29; #60; swe = 1; sdrive = 0; #25;
        read_byte(28, 8'bx); read_byte(29, 8'bx); read_byte(26, 8'hcc);

        // A write ending edge may change address with tWR=0; save old address.
        idle_ram; sa = 30; sce = 0; sce2 = 1; sdata = 8'hf0; sdrive = 1;
        #60; swe = 0; #55; swe = 1; sa = 31; sdrive = 0; #25;
        read_byte(30, 8'hf0); read_byte(31, 8'bx);

        // Repeated writes still need the full cycle interval.
        idle_ram; sa = 32; sce = 0; sce2 = 1; sdata = 8'hf1; sdrive = 1;
        #60; swe = 0; #45; swe = 1;
        #10; swe = 0; #45; swe = 1; sdrive = 0; #25;
        read_byte(32, 8'hf1);
        before_count = ram.timing_violations;
        idle_ram; sa = 33; sce = 0; sce2 = 1; sdata = 8'hf2; sdrive = 1;
        #60; swe = 0; #45; swe = 1;
        #9.999; swe = 0; #45; swe = 1; sdrive = 0; #25;
        read_byte(33, 8'bx);
        check(ram.timing_violations == before_count + 1, "write cycle 1 ps below boundary reported");

        write_byte(17'h100, 8'h55, 0); write_byte(17'h101, 8'haa, 0);
        idle_ram; sa = 17'h100; sce = 0; sce2 = 1; sdata = 8'hff; sdrive = 1;
        #60; swe = 0; #20; sa[0] = 1'bx; #60; swe = 1; sdrive = 0; #25;
        read_byte(17'h100, 8'bx); read_byte(17'h101, 8'bx);
        read_byte(30, 8'hf0);
        idle_ram; sa = 34; sce = 0; sce2 = 1; sdata = 8'hf3; sdrive = 1;
        #60; swe = 0; #60; sce = 1'bx; #25; swe = 1; sce = 1; sdrive = 0;
        #25; read_byte(34, 8'bx);

        // Known disable masks uncertain address/control, and prevents writes.
        idle_ram; sa = 17'bx; swe = 0; sce = 1; sce2 = 1; #60;
        check(sdq === 8'bz, "SRAM CE disable masks unknown address while WE low");
        swe = 1; sce = 0; sce2 = 1'bx; soe = 0; #60;
        check(sdq === 8'bx, "uncertain SRAM selection reads unknown");
        sce2 = 0; #20.001;
        check(sdq === 8'bz, "known CE2 disable masks unknown inputs");
        read_byte(26, 8'hcc);

        $display("PASS: %0d memory checks (flash/SRAM, preloads, timing and write violations)", checks);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "memory regression timed out");
    end
endmodule
