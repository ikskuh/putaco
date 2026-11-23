`timescale 1ns / 1ps

module PutacoCore(
    // code interface
    input [6:0] c_data,
    input       c_strobe,

    output [6:0] c_label,
    output       c_seek_n,
    output       c_halt_n,

    // memory interface
    inout [7:0] mem_addr,
    output [7:0] mem_data,
    output      mem_cs,
    output      mem_oe,
    output      mem_we
);
    // 19-bit address: {opcode[2:0], accumulator[7:0], operand[7:0]}.
    reg [7:0] alu [0:(1 << 19) - 1];
    integer alu_file;
    integer bytes_read;

    assign c_seek_n = 1;
    assign c_halt_n = 1;

    initial begin
        alu_file = $fopen("zig-out/aux/alu.bin", "rb");
        if (alu_file == 0)
            $fatal(1, "Cannot open zig-out/aux/alu.bin");
        bytes_read = $fread(alu, alu_file);
        $fclose(alu_file);
        if (bytes_read != (1 << 19))
            $fatal(1, "Expected 524288 ALU bytes, read %0d", bytes_read);
    end
endmodule
