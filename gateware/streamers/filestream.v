`timescale 1ns/1ps


module FileStream #(
    parameter INIT_FILE = "",
    parameter integer STROBE_PERIOD = 1_000_000_000 / (115200 / 10),
    parameter integer STROBE_LENGTH =         1_000,
    parameter integer MAX_LOOPS = 100
)(
    output reg [7:0] c_data,
    output reg       c_strobe,
    input            c_halt_n
);
    integer loops;
    integer code_fd;
    integer bytes_read;
    reg [7:0] code_byte [0:0];

    reg halted = 0;

    always @(negedge(c_halt_n)) begin 
        halted <= 1;
    end

    initial begin 

        c_data <= 0;
        c_strobe <= 0;

        code_fd = $fopen(INIT_FILE, "rb");
        if (code_fd == 0) begin
            $fatal(1, "Cannot open examples/hello.bin");
            $finish;
        end

        #1000; // startup delay

        for (loops = 0; loops < MAX_LOOPS && !halted; loops ++) begin
            while (!halted) begin
                bytes_read = $fread( code_byte, code_fd);
                if(bytes_read == 0) begin
                    $rewind(code_fd);
                    break;
                end

                $display("read %d bytes: %02x, %d", bytes_read, code_byte[0], $time);

                c_data <= code_byte[0];
                c_strobe <= 1;

                #STROBE_LENGTH;
                c_strobe <= 0;

                #(STROBE_PERIOD - STROBE_LENGTH);
            end
        end

        #1000;

        $finish;

    end

endmodule
