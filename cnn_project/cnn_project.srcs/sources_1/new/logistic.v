`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 03:50:16 PM
// Design Name: 
// Module Name: logistic
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// applies the sigmoid function to the 8 bit logit produced from fully connected 
// implemented as a ROM LUT using precomputed values due to small input range
// and computational complexity
module logistic(input clk,
                input signed [7:0] input_data,
                output reg signed [7:0] result
);
    // 256 x 8-bit ROM
    reg signed [7:0] logistic_lut [0:255];

    initial begin
        $readmemh("logistic_lut.mem", logistic_lut);
    end

    // convert signed input into LUT address
    wire [7:0] lut_addr = input_data ^ 8'h80;

    // synchronous ROM read
    always @(posedge clk) begin
        result <= logistic_lut[lut_addr];
    end
endmodule
