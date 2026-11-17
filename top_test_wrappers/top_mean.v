`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:30:22 PM
// Design Name: 
// Module Name: top_mean
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

// test wrapper for mean / global pooling operation
module top_mean(input clk, rst, start,
     // memory base addresses
    input [17:0] input_base,
    input [17:0] output_base,

    // requantization parameters
    input signed [31:0] multiplier,
    input signed [7:0] shift,

    // testbench initialization interface
    input init_w_en,
    input [17:0] init_w_addr,
    input signed [7:0] init_w_data,
    input output_r_en,
    input [17:0] output_r_addr,
    output signed [7:0] output_r_data,
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
    
    // activation buffer B
    wire act_b_r_en, act_b_w_en;
    wire [17:0] act_b_r_addr, act_b_w_addr;
    wire signed [7:0] act_b_r_data, act_b_w_data;
    
    // expose read port for buffer b for testing
    assign act_b_r_en = output_r_en;
    assign act_b_r_addr = output_r_addr;
    assign output_r_data = act_b_r_data;

    mean mean_inst(.clk(clk),
                  .rst(rst),
                  .start(start),
                  .input_base(input_base),
                  .output_base(output_base),
                  .input_data(act_a_r_data),
                  .input_addr(act_a_r_addr),
                  .input_r_en(act_a_r_en),
                  .output_addr(act_b_w_addr),
                  .output_data(act_b_w_data),
                  .output_w_en(act_b_w_en),
                  .multiplier(multiplier),
                  .shift(shift),
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
    
    // activation buffer B
    activation_mem_packed #(.ADDR_WIDTH(18),
                            .COUNT(32768)) 
               activation_b(.clk(clk),
                            .r_en(act_b_r_en),
                            .w_en(act_b_w_en),
                            .r_addr(act_b_r_addr),
                            .w_addr(act_b_w_addr),
                            .w_data(act_b_w_data),
                            .r_data(act_b_r_data));

endmodule
