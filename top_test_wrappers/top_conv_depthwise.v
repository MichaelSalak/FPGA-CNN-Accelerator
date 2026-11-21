`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:21:11 PM
// Design Name: 
// Module Name: top_conv_depthwise
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

// test wrapper for depthwise convolution using unified 
// convolution engine
module top_conv_depthwise(input clk, rst, start,
                          input init_w_en,
                          input [17:0] init_w_addr,
                          input signed [7:0] init_w_data,
                          input output_r_en,
                          input [17:0] output_r_addr,
                          output signed [7:0] output_r_data,
                          output done
);
    wire act_a_r_en, act_a_w_en;
    wire [17:0] act_a_r_addr, act_a_w_addr;
    wire signed [7:0] act_a_r_data, act_a_w_data;

    assign act_a_w_en = init_w_en;
    assign act_a_w_addr = init_w_addr;
    assign act_a_w_data = init_w_data;

    wire act_b_r_en, act_b_w_en;
    wire [17:0] act_b_r_addr, act_b_w_addr;
    wire signed [7:0] act_b_r_data, act_b_w_data;

    assign act_b_r_en = output_r_en;
    assign act_b_r_addr = output_r_addr;
    assign output_r_data = act_b_r_data;

    wire weight_r_en;
    wire [16:0] weight_addr;
    wire signed [7:0] weight_data;

    wire bias_r_en;
    wire [11:0] bias_addr;
    wire signed [31:0] bias_data;
    
    wire requant_r_en;
    wire [11:0] requant_addr;
    wire signed [31:0] multiplier;
    wire signed [7:0] shift;

    localparam [17:0] INPUT_BASE   = 18'd0;
    localparam [16:0] WEIGHT_BASE  = 17'd0;
    localparam [11:0] BIAS_BASE    = 12'd0;
    localparam [11:0] REQUANT_BASE = 12'd0;
    localparam [17:0] OUTPUT_BASE  = 18'd0;

    // depthwise SAME convolution: 4x4x2 -> 4x4x2, 3x3 kernel, stride 1.
    localparam [6:0] INPUT_HEIGHT     = 7'd4;
    localparam [7:0] INPUT_WIDTH      = 8'd4;
    localparam [10:0] INPUT_CHANNELS  = 11'd2;
    localparam [5:0] OUTPUT_HEIGHT    = 6'd4;
    localparam [6:0] OUTPUT_WIDTH     = 7'd4;
    localparam [10:0] OUTPUT_CHANNELS = 11'd2;

    localparam [12:0] INPUT_ROW_STRIDE = 13'd8; // 4 * 2
    localparam [10:0] OUTPUT_COL_STEP  = 11'd2; // stride 1 * 2
    localparam [12:0] OUTPUT_ROW_STEP  = 13'd8; // stride 1 * 8

    wire signed [7:0] input_zero_point = 8'sd10;
    wire signed [7:0] output_zero_point = -8'sd4;
    wire signed [7:0] activation_min = -8'sd128;
    wire signed [7:0] activation_max = 8'sd127;

    unified_conv conv(.clk(clk), 
                      .rst(rst), 
                      .start(start), 
                      .done(done),
                      .depthwise_mode(1'b1),
                      .kernel_size(2'd3),
                      .stride_2(1'b0),
                      .pad_top(2'd1),
                      .pad_left(2'd1),
                      .input_height(INPUT_HEIGHT),
                      .input_width(INPUT_WIDTH),
                      .input_channels(INPUT_CHANNELS),
                      .output_height(OUTPUT_HEIGHT),
                      .output_width(OUTPUT_WIDTH),
                      .output_channels(OUTPUT_CHANNELS),
                      .input_base(INPUT_BASE),
                      .weight_base(WEIGHT_BASE),
                      .bias_base(BIAS_BASE),
                      .output_base(OUTPUT_BASE),
                      .input_row_stride(INPUT_ROW_STRIDE),
                      .output_col_step(OUTPUT_COL_STEP),
                      .output_row_step(OUTPUT_ROW_STEP),
                      .requant_base(REQUANT_BASE),
                      .requant_addr(requant_addr),
                      .requant_r_en(requant_r_en),
                      .multiplier(multiplier),
                      .shift(shift),
                      .input_zero_point(input_zero_point),
                      .output_zero_point(output_zero_point),
                      .activation_min(activation_min),
                      .activation_max(activation_max),
                      .input_data(act_a_r_data),
                      .weight_data(weight_data),
                      .bias_data(bias_data),
                      .input_addr(act_a_r_addr),
                      .weight_addr(weight_addr),
                      .bias_addr(bias_addr),
                      .output_addr(act_b_w_addr),
                      .output_data(act_b_w_data),
                      .input_r_en(act_a_r_en),
                      .weight_r_en(weight_r_en),
                      .bias_r_en(bias_r_en),
                      .output_w_en(act_b_w_en));

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
    
    // 3x3 kernel for each of 2 channels = 18 weights
    weight_mem #(.COUNT(18),
                 .INIT_FILE("weights_3x3x2.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data));

    // One INT32 bias per channel = 2 biases
    bias_mem #(.COUNT(2),
               .INIT_FILE("bias_2.mem")) 
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data));
               
    quant_param_mem #(.COUNT(4),
                      .INIT_FILE("requant_2.mem")) 
                   rm(.clk(clk),
                      .r_en(requant_r_en),
                      .addr(requant_addr),
                      .multiplier(multiplier),
                      .shift(shift));
               
endmodule
