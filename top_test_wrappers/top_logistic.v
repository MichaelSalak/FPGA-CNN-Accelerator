`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:30:22 PM
// Design Name: 
// Module Name: top_logistic
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

// test wrapper for sigmoid logistic function LUT
module top_logistic(input clk, 
                    input signed [7:0] input_data,
                    output signed [7:0] result
);

    logistic l(.clk(clk),
               .input_data(input_data),
               .result(result));

endmodule
