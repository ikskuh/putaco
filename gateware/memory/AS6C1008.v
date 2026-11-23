`timescale 1ns/1ps

// Simulation-only AS6C1008-55PCN: 128K x 8 asynchronous SRAM.
// Alliance Memory March 2023 v1.2, pp.4-7. CE_n is active LOW, CE2 HIGH.
// AC limits (NOT typicals): AA/ACE=55, OE=30, CHZ/OHZ/WHZ=20 ns max;
// CLZ=10, OLZ=5, OH=10, OW=5 ns min. AC load=50 pF +1 TTL; low-Z/
// high-Z characterization uses 5 pF. Valid supply is assumed at time zero.
// Writes occur only in the overlap CE_n=0, CE2=1, WE_n=0. The first
// deassertion ends the write, irrespective of OE_n. Required minima:
// WC=55, AW/CW=50, WP=45, DW=25 ns; AS/WR/DH=0 (no extra hold delay).
// Violations poison affected bytes. Unknown write addresses poison matching
// candidate locations, not unrelated storage. No analog/supply simulation.
//
// INIT_FILE="" leaves storage unknown. INIT_FORMAT="hex" uses $readmemh,
// "binary" uses $readmemb, "raw" uses literal bytes via $fread. Relative
// paths resolve from the simulator's working directory; partial images leave
// remaining storage unknown. Example: AS6C1008 #(.INIT_FILE("ram.hex")) ram(...);
module AS6C1008 #(
    parameter INIT_FILE = "",
    parameter INIT_FORMAT = "hex",
    parameter real T_AA_NS = 55.0,
    parameter real T_CE_NS = 55.0,
    parameter real T_OE_NS = 30.0,
    parameter real T_CHZ_NS = 20.0,
    parameter real T_OHZ_NS = 20.0,
    parameter real T_WHZ_NS = 20.0,
    parameter real T_CLZ_NS = 10.0,
    parameter real T_OLZ_NS = 5.0,
    parameter real T_OH_NS = 10.0,
    parameter real T_OW_NS = 5.0,
    parameter real T_WC_NS = 55.0,
    parameter real T_AW_NS = 50.0,
    parameter real T_CW_NS = 50.0,
    parameter real T_WP_NS = 45.0,
    parameter real T_DW_NS = 25.0
)(input [16:0] A, inout [7:0] DQ, input CE_n, CE2, OE_n, WE_n);
    reg [7:0] storage [0:131071];
    integer file_handle, bytes_read;
    reg initialized = 0;
    initial begin
        #0;
        if (INIT_FORMAT != "hex" && INIT_FORMAT != "binary" && INIT_FORMAT != "raw")
            $fatal(1, "%m: INIT_FORMAT must be hex, binary or raw");
        if (INIT_FILE != "") begin
            file_handle = $fopen(INIT_FILE, "rb");
            if (!file_handle) $fatal(1, "%m: cannot open %0s", INIT_FILE);
            if (INIT_FORMAT == "raw") begin
                bytes_read = $fread(storage, file_handle);
                if ($fgetc(file_handle) != -1) $fatal(1, "%m: image exceeds 131072 bytes");
            end
            $fclose(file_handle);
            if (INIT_FORMAT == "hex") $readmemh(INIT_FILE, storage);
            if (INIT_FORMAT == "binary") $readmemb(INIT_FILE, storage);
        end
        initialized = 1;
    end

    wire [7:0] memory_data = storage[A];
    wire selected = ~CE_n & CE2;
    wire reading = selected & ~OE_n & WE_n;
    wire writing = selected & ~WE_n;
    reg [7:0] drive = 8'bz, pending_data;
    assign DQ = drive;
    reg [16:0] previous_a = 17'bx, write_address, previous_write_address;
    reg previous_ce = 1'bx, previous_ce2 = 1'bx;
    reg previous_oe = 1'bx, previous_we = 1'bx, previous_selected = 1'bx;
    realtime address_changed = 0, ce_changed = 0, ce2_changed = 0;
    realtime oe_changed = 0, we_changed = 0, selected_since = 0;
    realtime write_started, previous_write_started = -1.0e9, write_ended = -1.0e9;
    reg write_active = 0, write_bad = 0;
    integer timing_violations = 0;

    // Keep the value BEFORE a same-timestamp bus release: tDH=0 permits
    // changing/releasing data exactly when the write ends. #0 in the pin
    // controller makes this independent of active-region ordering.
    reg [7:0] bus_data = 8'bz, bus_before_change = 8'bz;
    realtime data_changed = -1.0e9, previous_data_since = -1.0e9;
    reg [7:0] sampled_data;
    realtime sampled_since;
    always @(DQ) begin
        bus_before_change = bus_data;
        previous_data_since = data_changed;
        bus_data = DQ;
        data_changed = $realtime;
    end

    task poison(input [16:0] address);
        reg [16:0] known_mask;
        integer bit_number, location;
        begin
            if (^address !== 1'bx) storage[address] <= 8'bx;
            else begin
                for (bit_number = 0; bit_number < 17; bit_number = bit_number + 1)
                    known_mask[bit_number] = (address[bit_number] === 1'b0 || address[bit_number] === 1'b1);
                for (location = 0; location < 131072; location = location + 1)
                    if ((location[16:0] & known_mask) === (address & known_mask))
                        storage[location] <= 8'bx;
            end
        end
    endtask

    task violation(input [8*80-1:0] reason);
        begin
            timing_violations = timing_violations + 1;
            $display("WARNING %m at %0.3f ns: %0s", $realtime, reason);
            write_bad = 1;
        end
    endtask

    function real later(input real a, b);
        later = (a > b) ? a : b;
    endfunction
    realtime valid_due, active_due, release_due;
    integer generation = 0, valid_token = -1, active_token = -1, release_token = -1;
    always @(valid_token) if (valid_token == generation) drive = pending_data;
    always @(active_token) if (active_token == generation)
        drive = ($realtime >= valid_due) ? pending_data : 8'bx;
    always @(release_token) if (release_token == generation) drive = 8'bz;

    always @(A or CE_n or CE2 or OE_n or WE_n or memory_data or initialized) begin
        #0;
        if (initialized) begin
            // End a write using its saved address, before considering an
            // address change on this same edge (tWR=0).
            if (write_active && writing !== 1'b1) begin
                if (data_changed == $realtime) begin
                    sampled_data = bus_before_change;
                    sampled_since = previous_data_since;
                end else begin
                    sampled_data = bus_data;
                    sampled_since = data_changed;
                end
                if (writing !== 1'b0) violation("ambiguous write termination");
                if ($realtime - write_started < T_WP_NS) violation("write pulse width");
                if ($realtime - address_changed < T_AW_NS) violation("address setup to end of write");
                if ($realtime - selected_since < T_CW_NS) violation("chip enable to end of write");
                if ($realtime - sampled_since < T_DW_NS) violation("write data setup");
                if (write_bad || ^write_address === 1'bx) poison(write_address);
                else storage[write_address] <= sampled_data ^ 8'b0;
                write_active = 0;
                write_ended = $realtime;
            end
            if (A !== previous_a) begin
                if (write_active) begin
                    violation("address changed during write");
                    poison(write_address);
                    write_address = A;
                end
                address_changed = $realtime;
            end
            if (CE_n !== previous_ce) ce_changed = $realtime;
            if (CE2 !== previous_ce2) ce2_changed = $realtime;
            if (OE_n !== previous_oe) oe_changed = $realtime;
            if (WE_n !== previous_we) we_changed = $realtime;
            if (selected === 1'b1 && previous_selected !== 1'b1) selected_since = $realtime;
            if (!write_active && writing === 1'b1) begin
                write_active = 1;
                write_bad = 0;
                write_address = A;
                write_started = $realtime;
                if ($realtime - previous_write_started < T_WC_NS) begin
                    violation("write cycle time");
                    poison(previous_write_address);
                end
                previous_write_started = $realtime;
                previous_write_address = A;
            end else if (!write_active && writing !== 1'b0) begin
                // An uncertain control may have caused a write to this byte.
                poison(A);
            end

            generation = generation + 1;
            if (reading === 1'b1) begin
                valid_due = later(address_changed + T_AA_NS, selected_since + T_CE_NS);
                valid_due = later(valid_due, oe_changed + T_OE_NS);
                valid_due = later(valid_due, write_ended + T_OW_NS);
                active_due = later(address_changed + T_OH_NS, selected_since + T_CLZ_NS);
                active_due = later(active_due, oe_changed + T_OLZ_NS);
                active_due = later(active_due, write_ended + T_OW_NS);
                pending_data = memory_data;
                if (valid_due <= $realtime) drive = pending_data;
                else begin
                    valid_token <= #(valid_due - $realtime) generation;
                    if (active_due <= $realtime) drive = 8'bx;
                    else active_token <= #(active_due - $realtime) generation;
                end
            end else if (reading === 1'b0) begin
                release_due = 1.0e30;
                if (CE_n === 1'b1) release_due = ce_changed + T_CHZ_NS;
                if (CE2 === 1'b0 && ce2_changed + T_CHZ_NS < release_due)
                    release_due = ce2_changed + T_CHZ_NS;
                if (OE_n === 1'b1 && oe_changed + T_OHZ_NS < release_due)
                    release_due = oe_changed + T_OHZ_NS;
                if (WE_n === 1'b0 && we_changed + T_WHZ_NS < release_due)
                    release_due = we_changed + T_WHZ_NS;
                if (release_due <= $realtime) drive = 8'bz;
                else release_token <= #(release_due - $realtime) generation;
            end else
                drive = 8'bx;
            previous_a = A;
            previous_ce = CE_n;
            previous_ce2 = CE2;
            previous_oe = OE_n;
            previous_we = WE_n;
            previous_selected = selected;
        end
    end
endmodule
