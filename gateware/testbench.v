`timescale 1ns / 1ps

module testbench;

    reg        reset;

    wire [6:0] c_data;
    wire [6:0] c_label;
    wire       c_strobe;
    wire       c_seek_n;
    wire       c_halt_n;

    wire [7:0] mem_addr;
    wire [7:0] mem_data;
    wire       mem_cs_n;
    wire       mem_oe_n;
    wire       mem_we_n;

    PutacoCore dut(
        .CODE_DATA(c_data),
        .CODE_STROBE(c_strobe),
        .CODE_LABEL(c_label),
        .CODE_SEEK_n(c_seek_n),
        .CODE_HALT_n(c_halt_n),
        .MEM_ADDR(mem_addr),
        .MEM_DATA(mem_data),
        .MEM_CS_n(mem_cs_n),
        .MEM_OE_n(mem_oe_n),
        .MEM_WE_n(mem_we_n),
        .AUX_RESET(reset)
    );

    AS6C1008 sram(
        .A({ 9'b0, mem_addr}),
        .DQ(mem_data),
        .CE_n(mem_cs_n),
        .CE2(1'b1),
        .OE_n(mem_oe_n),
        .WE_n(mem_we_n)
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

        reset <= 1;

        # 100; // time for initialization

        reset <= 0;

        # 100; // time for settling/init
        
        wait (c_halt_n === 1'b0);
        
        # 1000; // time for "aftermath"

        $display("Testbench completed");
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Simulation timeout: CPU did not halt");
    end
endmodule
