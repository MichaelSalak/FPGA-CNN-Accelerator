`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:30:22 PM
// Design Name: 
// Module Name: top_fully_connected
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

// test wrapper for fully connected / dense layer operation
module top_fully_connected(input clk, rst, start,
    // base addresses
    input [17:0] input_base,
    input [17:0] weight_base,
    input [17:0] bias_base,

    // requantization parameters
    input signed [31:0] multiplier,
    input signed [7:0] shift,

    // testbench initialization interface
    input init_w_en,
    input [17:0] init_w_addr,
    input signed [7:0] init_w_data,

    output signed [7:0] result,
    output done
);
    // activation buffer A
    wire act_a_r_en, act_a_w_en;
    wire [17:0] act_a_r_addr, act_a_w_addr;
    wire signed [7:0] act_a_r_data, act_a_w_data;
    
    // expose write ports for buffer a for testing
    assign act_a_w_en = init_w_en;
    assign act_a_w_addr = init_w_addr;
    assign act_a_w_data = init_w_data;

    // weight memory
    wire weight_r_en;
    wire [16:0] weight_addr;
    wire signed [7:0] weight_data;
    
    // bias memory
    wire bias_r_en;
    wire [11:0] bias_addr;
    wire signed [31:0] bias_data;

    fully_connected fc_inst(.clk(clk),
                            .rst(rst),
                            .start(start),
                            .input_base(input_base),
                            .weight_base(weight_base),
                            .bias_base(bias_base),
                            .input_data(act_a_r_data),
                            .input_addr(act_a_r_addr),
                            .input_r_en(act_a_r_en),
                            .weight_data(weight_data),
                            .weight_addr(weight_addr),
                            .weight_r_en(weight_r_en),
                            .bias_data(bias_data),
                            .bias_addr(bias_addr),
                            .bias_r_en(bias_r_en),
                            .multiplier(multiplier),
                            .shift(shift),
                            .result(result),
                            .done(done));

    // activation buffer A (cannot init uram from file)
    activation_mem_packed #(.ADDR_WIDTH(18), 
                            .COUNT(32768)) 
               activation_a(.clk(clk),
                            .r_en(act_a_r_en),
                            .w_en(act_a_w_en),
                            .r_addr(act_a_r_addr),
                            .w_addr(act_a_w_addr),
                            .w_data(act_a_w_data),
                            .r_data(act_a_r_data));

    weight_mem #(.COUNT(1280),
                 .INIT_FILE("fc_weights.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data));

    bias_mem #(.COUNT(1),
               .INIT_FILE("fc_bias.mem"))
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data));

endmodule
