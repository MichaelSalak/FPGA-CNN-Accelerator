`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/11/2026 10:33:16 PM
// Design Name: 
// Module Name: accelerator_tb
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


module conv1x1_small_tb();
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    wire signed [31:0] result;
    wire done;

    conv1x1_small dut(.clk(clk),
                      .rst(rst),
                      .start(start),
                      .result(result),
                      .done(done));

    always #5 clk = ~clk;

    initial begin
        #20 rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);

        #20 $finish;
    end
endmodule
