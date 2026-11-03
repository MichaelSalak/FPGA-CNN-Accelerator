`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/11/2026 10:04:05 PM
// Design Name: 
// Module Name: accelerator
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


// currently exposes buffer a writes for initialization and
// buffer b reads for synthesis uram utilization verification
module top_depthwise(input clk, rst, start, 
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
    assign act_b_r_data = output_r_data;
    
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

    localparam [15:0] INPUT_HEIGHT  = 16'd4;
    localparam [15:0] INPUT_WIDTH   = 16'd4;
    localparam [15:0] CHANNELS      = 16'd2;
    localparam [15:0] OUTPUT_HEIGHT = 16'd4;
    localparam [15:0] OUTPUT_WIDTH  = 16'd4;

    // each memory is separate in this test, so all base addresses are zero
    localparam [18:0] INPUT_BASE  = 18'd0;
    localparam [17:0] WEIGHT_BASE = 17'd0;
    localparam [15:0] BIAS_BASE   = 12'd0;
    localparam [18:0] OUTPUT_BASE = 18'd0;

    // HWC layout:
    // input_row_stride = input_width * channels
    // input_col_stride = channels
    // kernel_row_jump = (input_width - 2) * channels
    // output_col_step = stride * channels
    // output_row_step = stride * input_width * channels

    localparam STRIDE_2 = 1'b0;  // stride 1
    localparam [1:0] PAD_TOP  = 2'd1;
    localparam [1:0] PAD_LEFT = 2'd1;

    localparam [15:0] INPUT_ROW_STRIDE = 16'd8;
    localparam [15:0] INPUT_COL_STRIDE = 16'd2;
    localparam [15:0] KERNEL_ROW_JUMP  = 16'd4;
    localparam [15:0] OUTPUT_COL_STEP  = 16'd2;
    localparam [15:0] OUTPUT_ROW_STEP  = 16'd8;

    // requantization parameters
    wire signed [31:0] multiplier;
    wire signed [7:0] shift;
    wire signed [7:0] input_zero_point;
    wire signed [7:0] output_zero_point;
    wire signed [7:0] activation_min, activation_max;

    // effective scaling factor = 0.5 * 2^-2 = 0.125
    assign multiplier = 32'h40000000;
    assign shift = -8'sd2;
    assign input_zero_point = 8'sd10;
    assign output_zero_point = -8'sd4;
    assign activation_min = -8'sd128;
    assign activation_max = 8'sd127;

    depthwise_conv conv(.clk(clk),
                        .rst(rst),
                        .start(start),
                        .input_data(act_a_r_data),  // buffer a read
                        .weight_data(weight_data),
                        .bias_data(bias_data),
                        .input_height(INPUT_HEIGHT),
                        .input_width(INPUT_WIDTH),
                        .channels(CHANNELS),              
                        .output_height(OUTPUT_HEIGHT),
                        .output_width(OUTPUT_WIDTH),           
                        .stride_2(STRIDE_2),
                        .pad_top(PAD_TOP),
                        .pad_left(PAD_LEFT),
                        .input_base(INPUT_BASE),
                        .weight_base(WEIGHT_BASE),
                        .bias_base(BIAS_BASE),
                        .output_base(OUTPUT_BASE),
                        .input_row_stride(INPUT_ROW_STRIDE),
                        .input_col_stride(INPUT_COL_STRIDE),
                        .kernel_row_jump(KERNEL_ROW_JUMP),
                        .output_col_step(OUTPUT_COL_STEP),
                        .output_row_step(OUTPUT_ROW_STEP),
                        .multiplier(multiplier),
                        .shift(shift),
                        .input_zero_point(input_zero_point),
                        .output_zero_point(output_zero_point),
                        .activation_min(activation_min),
                        .activation_max(activation_max),
                        .input_addr(act_a_r_addr),  // buffer a read
                        .output_addr(act_b_w_addr), // buffer b write
                        .weight_addr(weight_addr),
                        .bias_addr(bias_addr),
                        .input_r_en(act_a_r_en),    // buffer a read
                        .output_w_en(act_b_w_en),   // buffer b write
                        .weight_r_en(weight_r_en),
                        .bias_r_en(bias_r_en),
                        .output_data(act_b_w_data), // buffer b write
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
    
    // activation/residual buffer C
    /*      // (unused for now)
    activation_mem_packed #(.ADDR_WIDTH(18),
                            .COUNT(32768)) 
               activation_c(.clk(clk),
                            .r_en(act_c_r_en),
                            .w_en(act_c_w_en),
                            .r_addr(act_c_r_addr),
                            .w_addr(act_c_w_addr),
                            .w_data(act_c_w_data),
                            .r_data(act_c_r_data));
    */


    // will need to update input file + size later
    
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

endmodule





// currently exposes buffer a writes for initialization and
// buffer b reads for synthesis uram utilization verification
module top_pointwise(input clk, rst, start, 
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
    assign act_b_r_data = output_r_data;
    
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
    
    localparam [15:0] INPUT_HEIGHT    = 16'd3;
    localparam [15:0] INPUT_WIDTH     = 16'd3;
    localparam [15:0] INPUT_CHANNELS  = 16'd2;
    localparam [15:0] OUTPUT_CHANNELS = 16'd4;

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
    
    pointwise_conv conv(.clk(clk),
                        .rst(rst),
                        .start(start),
                        .input_data(act_a_r_data),  // buffer a read
                        .weight_data(weight_data),
                        .bias_data(bias_data),
                        .input_height(INPUT_HEIGHT),
                        .input_width(INPUT_WIDTH),
                        .input_channels(INPUT_CHANNELS),
                        .output_channels(OUTPUT_CHANNELS),
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
                        .output_addr(act_b_w_addr), // buffer b write
                        .weight_addr(weight_addr),
                        .bias_addr(bias_addr),
                        .output_data(act_b_w_data), // buffer b write
                        .input_r_en(act_a_r_en),    // buffer a read
                        .output_w_en(act_b_w_en),   // buffer b write
                        .weight_r_en(weight_r_en),
                        .bias_r_en(bias_r_en),
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
    
    // activation/residual buffer C
    /*      // (unused for now)
    activation_mem_packed #(.ADDR_WIDTH(18),
                            .COUNT(32768)) 
               activation_c(.clk(clk),
                            .r_en(act_c_r_en),
                            .w_en(act_c_w_en),
                            .r_addr(act_c_r_addr),
                            .w_addr(act_c_w_addr),
                            .w_data(act_c_w_data),
                            .r_data(act_c_r_data));
    */

    // will need to update input file + size later

    weight_mem #(.COUNT(8),
                 .INIT_FILE("weights_2x4.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data));

    bias_mem #(.COUNT(4),
               .INIT_FILE("bias_4_3x3x2.mem"))
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data));

endmodule


