`timescale 1ns/1ps

// Simulation-only, read-only SST39SF040-70-4C-NHE: 512K x 8.
// Microchip DS20005022F, tables 6-2/7-1, 4.5-5.5 V (-70 grade):
// access maxima AA/CE=70, OE=35 ns; disable maxima CHZ/OHZ=25 ns;
// low-Z and address-hold minima=0 ns. These are limits, NOT typicals.
// Power-up-to-read=100 us. Assume a valid supply from simulation time zero.
// Program/erase/ID commands are deliberately omitted. WE_n=0 releases DQ
// without changing storage; its release/access delays borrow OHZ/AA because
// read-only WE timing is not specified. No analog load/supply modeling.
//
// INIT_FILE="" leaves the flash erased (FF). INIT_FORMAT selects:
// "hex": $readmemh byte tokens, "binary": $readmemb byte tokens,
// "raw": literal bytes ($fread), e.g. zig-out/aux/alu.bin. Paths are relative
// to the simulator's working directory. Partial images leave the rest FF.
// Example: SST39SF040 #(.INIT_FILE("zig-out/aux/alu.bin"),
//                      .INIT_FORMAT("raw")) alu(...);
module SST39SF040 #(
    parameter INIT_FILE = "",
    parameter INIT_FORMAT = "hex",
    parameter real T_AA_NS = 70.0,
    parameter real T_CE_NS = 70.0,
    parameter real T_OE_NS = 35.0,
    parameter real T_CHZ_NS = 25.0,
    parameter real T_OHZ_NS = 25.0,
    parameter real T_CLZ_NS = 0.0,
    parameter real T_OLZ_NS = 0.0,
    parameter real T_OH_NS = 0.0,
    parameter real T_POWERUP_NS = 100000.0
)(input [18:0] A, inout [7:0] DQ, input CE_n, OE_n, WE_n);
    reg [7:0] storage [0:524287];
    integer index, file_handle, bytes_read;
    reg initialized = 0;
    initial begin
        #0;
        for (index = 0; index < 524288; index = index + 1)
            storage[index] = 8'hff;
        if (INIT_FORMAT != "hex" && INIT_FORMAT != "binary" && INIT_FORMAT != "raw")
            $fatal(1, "%m: INIT_FORMAT must be hex, binary or raw");
        if (INIT_FILE != "") begin
            file_handle = $fopen(INIT_FILE, "rb");
            if (!file_handle) $fatal(1, "%m: cannot open %0s", INIT_FILE);
            if (INIT_FORMAT == "raw") begin
                bytes_read = $fread(storage, file_handle);
                if ($fgetc(file_handle) != -1) $fatal(1, "%m: image exceeds 524288 bytes");
            end
            $fclose(file_handle);
            if (INIT_FORMAT == "hex") $readmemh(INIT_FILE, storage);
            if (INIT_FORMAT == "binary") $readmemb(INIT_FILE, storage);
        end
        initialized = 1;
    end

    wire [7:0] memory_data = storage[A];
    wire reading = ~CE_n & ~OE_n & WE_n;
    reg [7:0] drive = 8'bz, pending_data;
    assign DQ = drive;
    reg [18:0] previous_a = 19'bx;
    reg previous_ce = 1'bx, previous_oe = 1'bx, previous_we = 1'bx;
    realtime address_changed = 0, ce_changed = 0, oe_changed = 0, we_changed = 0;
    realtime valid_due, active_due, release_due;
    integer generation = 0, valid_token = -1, active_token = -1, release_token = -1;

    function real later(input real a, b);
        later = (a > b) ? a : b;
    endfunction

    always @(valid_token) if (valid_token == generation) drive = pending_data;
    always @(active_token) if (active_token == generation)
        drive = ($realtime >= valid_due) ? pending_data : 8'bx;
    always @(release_token) if (release_token == generation) drive = 8'bz;

    always @(A or CE_n or OE_n or WE_n or memory_data or initialized) begin
        #0;
        if (initialized) begin
            if (A !== previous_a) address_changed = $realtime;
            if (CE_n !== previous_ce) ce_changed = $realtime;
            if (OE_n !== previous_oe) oe_changed = $realtime;
            if (WE_n !== previous_we) we_changed = $realtime;
            generation = generation + 1;
            if (reading === 1'b1) begin
                // Access paths run concurrently: meet ALL applicable deadlines.
                valid_due = later(address_changed + T_AA_NS, ce_changed + T_CE_NS);
                valid_due = later(valid_due, oe_changed + T_OE_NS);
                valid_due = later(valid_due, we_changed + T_AA_NS);
                valid_due = later(valid_due, T_POWERUP_NS);
                active_due = later(address_changed + T_OH_NS, ce_changed + T_CLZ_NS);
                active_due = later(active_due, oe_changed + T_OLZ_NS);
                pending_data = memory_data;
                if (valid_due <= $realtime) drive = pending_data;
                else begin
                    valid_token <= #(valid_due - $realtime) generation;
                    if (active_due <= $realtime) drive = 8'bx;
                    else active_token <= #(active_due - $realtime) generation;
                end
            end else if (reading === 1'b0) begin
                // The first effective disable wins, even if another pin follows.
                release_due = 1.0e30;
                if (CE_n === 1'b1) release_due = ce_changed + T_CHZ_NS;
                if (OE_n === 1'b1 && oe_changed + T_OHZ_NS < release_due)
                    release_due = oe_changed + T_OHZ_NS;
                if (WE_n === 1'b0 && we_changed + T_OHZ_NS < release_due)
                    release_due = we_changed + T_OHZ_NS;
                if (release_due <= $realtime) drive = 8'bz;
                else release_token <= #(release_due - $realtime) generation;
            end else
                drive = 8'bx;
            previous_a = A;
            previous_ce = CE_n;
            previous_oe = OE_n;
            previous_we = WE_n;
        end
    end
endmodule
