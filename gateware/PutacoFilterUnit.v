`timescale 1ns/1ps

module PutacoFilterUnit(
    output reg  [6:0] c_data_out,
    output reg        c_strobe_out,
    input wire  [6:0] c_label_out,
    input wire        c_seek_n_out,
    input wire        c_halt_n_out,

    input  wire [7:0] c_data_in,
    input  wire       c_strobe_in,
    output wire       c_halt_n_in
);
    assign c_halt_n_in = c_halt_n_out;

    reg filtering_data = 0;
    reg [6:0] filter_byte;
    
    assign c_data_out[6:0] = c_data_in[6:0];

    assign c_strobe_out = c_strobe_in & !filtering_data & !c_data_in[7];

    always @(negedge c_seek_n_out) begin 
        filtering_data <= 1;
        filter_byte[6:0] <= c_label_out[6:0];
    end

    always @(posedge c_strobe_in) begin 
        if (filtering_data && filter_byte == c_data_in[6:0]) begin 
            filtering_data <= 0;
        end
    end

endmodule
