`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:37:32 PM
// Design Name: 
// Module Name: top_standard
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

// test wrapper for old/depricated designated standard convolution
// engine
module top_standard(input clk, rst, start, 
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
    
    // activation buffer C (residual buffer, may reduce size later)
    wire act_c_r_en, act_c_w_en;
    wire [17:0] act_c_r_addr, act_c_w_addr;
    wire signed [7:0] act_c_r_data, act_c_w_data;
    
    // weight memory
    wire weight_r_en;
    wire [16:0] weight_addr;
    wire signed [7:0] weight_data;
    
    // bias memory
    wire bias_r_en;
    wire [11:0] bias_addr;
    wire signed [31:0] bias_data;

    // memory base addresses
    localparam [18:0] INPUT_BASE  = 18'd0;
    localparam [17:0] WEIGHT_BASE = 17'd0;
    localparam [15:0] BIAS_BASE   = 12'd0;
    localparam [18:0] OUTPUT_BASE = 18'd0;
    
    wire signed [31:0] multiplier;
    wire signed [7:0] shift;
    wire signed [7:0] input_zero_point;
    wire signed [7:0] output_zero_point;
    wire signed [7:0] activation_min;
    wire signed [7:0] activation_max;
    
    // assign requant parameters to values (temporary)
    assign multiplier = 32'h40000000;       // 0.5
    assign shift = -2;                      // divide by 4
    assign input_zero_point = -14;
    assign output_zero_point = 3;
    assign activation_min = -128;
    assign activation_max = 127;
    
    standard_conv conv(.clk(clk),
                       .rst(rst),
                       .start(start),
                       .done(done), 
                       .input_data(act_a_r_data),  // buffer a read
                       .weight_data(weight_data),
                       .bias_data(bias_data), 
                       .input_base(INPUT_BASE),
                       .weight_base(WEIGHT_BASE),
                       .bias_base(BIAS_BASE),
                       .output_base(OUTPUT_BASE),
                       .multiplier(multiplier),
                       .shift(shift),
                       .input_zero_point(input_zero_point),
                       .output_zero_point(output_zero_point),
                       .activation_min(activation_min),
                       .activation_max(activation_max),
                       .input_addr(act_a_r_addr),  // buffer a read
                       .weight_addr(weight_addr),
                       .bias_addr(bias_addr),
                       .output_addr(act_b_w_addr), // buffer b write
                       .output_data(act_b_w_data), // buffer b write     
                       .input_r_en(act_a_r_en),    // buffer a read
                       .weight_r_en(weight_r_en),
                       .bias_r_en(bias_r_en),
                       .output_w_en(act_b_w_en));  // buffer b write
                       
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

    weight_mem #(.COUNT(216),
                 .INIT_FILE("standard_weights.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data));

    bias_mem #(.COUNT(8),
               .INIT_FILE("standard_bias.mem"))
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data));

endmodule
