`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:59:52 PM
// Design Name: 
// Module Name: top_conv_pointwise_tb
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

module top_conv_pointwise_tb();
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg init_w_en = 0;
    reg [17:0] init_w_addr = 0;
    reg signed [7:0] init_w_data = 0;
    reg output_r_en = 0;
    reg [17:0] output_r_addr = 0;
    wire [7:0] output_r_data;
    wire done;
                 
    top_conv_pointwise dut(.clk(clk),
                           .rst(rst),
                           .start(start),
                           .init_w_en(init_w_en),
                           .init_w_addr(init_w_addr),
                           .init_w_data(init_w_data),
                           .output_r_en(output_r_en),
                           .output_r_addr(output_r_addr),
                           .output_r_data(output_r_data),
                           .done(done));
    
    always #5 clk = ~clk;
    
    reg signed [7:0] input_values [0:31];

    initial begin
        $readmemh("input_3x3x2.mem", input_values);
    end
    
    integer i;

    initial begin
        #20 rst = 0;
        
        // populate input uram buffer before testing
        for(i = 0; i < 18; i = i + 1) begin
            @(negedge clk);
            init_w_en   = 1;
            init_w_addr = i;
            init_w_data = input_values[i];
        end
            
        @(negedge clk);
        init_w_en = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);
        
        // ensure final write has completed
        @(posedge clk);
        #1;

        // print output memory
        $display("\n========== OUTPUT ==========");

        for (i = 0; i < 36; i = i + 1) begin
            $write("%02h ", dut.activation_b.mem[i / 8][(i % 8) * 8 +: 8]);
        end

        $display("\n======================================");

        $finish;
    end
endmodule
