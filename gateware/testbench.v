`timescale 1ns / 1ps

module testbench;

    wire [6:0] c_data;
    wire [6:0] c_label;
    wire       c_strobe;
    wire       c_seek_n;
    wire       c_halt_n;

    wire [7:0] mem_addr;
    wire [7:0] mem_data;
    wire       mem_cs;
    wire       mem_oe;
    wire       mem_we;

    PutacoCore dut(
        .c_data(c_data),
        .c_strobe(c_strobe),
        .c_label(c_label),
        .c_seek_n(c_seek_n),
        .c_halt_n(c_halt_n),
        .mem_addr(mem_addr),
        .mem_data(mem_data),
        .mem_cs(mem_cs),
        .mem_oe(mem_oe),
        .mem_we(mem_we)
    );

    AS6C1008 sram(
        .A({ 9'b0, mem_addr}),
        .DQ(mem_data),
        .CE_n(mem_cs),
        .CE2(1'b1),
        .OE_n(mem_oe),
        .WE_n(mem_we)
    );

    wire [7:0] c_raw_data;
    wire       c_raw_strobe;
    wire       c_raw_halt_n;

    FileStream #(
        .INIT_FILE("examples/hello.bin")
        ,.MAX_LOOPS(10)
    ) fs(
        .c_data(c_raw_data),
        .c_strobe(c_raw_strobe),
        .c_halt_n(c_raw_halt_n)
    );

    PutacoFilterUnit filter(
        // from the code source:
        .c_data_in(c_raw_data),
        .c_strobe_in(c_raw_strobe),
        .c_halt_n_in(c_raw_halt_n),
        
        // to the putaco core:
        .c_data_out(c_data),
        .c_strobe_out(c_strobe),
        .c_label_out(c_label),
        .c_seek_n_out(c_seek_n),
        .c_halt_n_out(c_halt_n)
    );

    initial begin
        $dumpfile("zig-out/gateware/testbench.vcd");
        $dumpvars(0, testbench);
        

        while (c_halt_n) begin 
            #10;
        end

        $display("Testbench completed");
        $finish;
    end
endmodule
