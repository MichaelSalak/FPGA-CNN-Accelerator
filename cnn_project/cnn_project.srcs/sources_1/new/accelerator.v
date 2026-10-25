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



// use bram for 2 activation memory buffers for ping pong buffering
// use bram for weight/bias memory
// have main controller to coordinate everything
// components: convolution engine, 



/*
3 CONV_2D inputs: [111 42 77] outputs: [112]

Tensor	Shape	         Meaning
111	    [1, 60, 80, 8]	 Input activation
42	    [8, 1, 1, 8]	 Weights
77	    [8]	             Biases
112	    [1, 60, 80, 8]	 Output activation
*/




module top_depthwise(input clk, rst, start, output done);
    wire input_r_en, weight_r_en, bias_r_en, output_w_en;
    wire [15:0] input_addr, weight_addr, bias_addr, output_addr;
    wire signed [7:0] input_data, output_data;
    wire signed [7:0] weight_data;
    wire signed [31:0] bias_data;

    // Input: 4x4x2
    // Kernel: 3x3
    // Stride: 1
    // Padding: VALID
    // Output: 2x2x2
    // WORKS CORRECTLY ^^^
    
    // Input: 4x4x2
    // Kernel: 3x3
    // Stride: 2
    // Padding: SAME
    // Output: 2x2x2
    // WORKS CORRECTLY ^^^
    
    // Input: 4x4x2
    // Kernel: 3x3
    // Stride: 1
    // Padding: SAME
    // Output: 4x4x2
    // 

    localparam [15:0] INPUT_HEIGHT  = 16'd4;
    localparam [15:0] INPUT_WIDTH   = 16'd4;
    localparam [15:0] CHANNELS      = 16'd2;
    localparam [15:0] OUTPUT_HEIGHT = 16'd4;
    localparam [15:0] OUTPUT_WIDTH  = 16'd4;

    // each memory is separate in this test, so all base addresses are zero
    localparam [15:0] INPUT_BASE  = 16'd0;
    localparam [15:0] WEIGHT_BASE = 16'd0;
    localparam [15:0] BIAS_BASE   = 16'd0;
    localparam [15:0] OUTPUT_BASE = 16'd0;


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
                        .input_data(input_data),
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
                        .input_addr(input_addr),
                        .output_addr(output_addr),
                        .weight_addr(weight_addr),
                        .bias_addr(bias_addr),
                        .input_r_en(input_r_en),
                        .output_w_en(output_w_en),
                        .weight_r_en(weight_r_en),
                        .bias_r_en(bias_r_en),
                        .output_data(output_data),
                        .done(done)
    );

    // 4x4x2 = 32 INT8 input activations
    activation_mem #(.DATA_WIDTH(8),
                     .COUNT(32),
                     .INIT_FILE("input_4x4x2.mem")) 
                 am0(.clk(clk),
                     .w_en(1'b0),
                     .r_en(input_r_en),
                     .w_addr(5'd0),
                     .r_addr(input_addr),
                     .w_data(8'd0),
                     .r_data(input_data)
    );

    // 4x4x2 = 32 INT8 output activations
    activation_mem #(.DATA_WIDTH(8),
                     .COUNT(32)) 
                 am1(.clk(clk),
                     .w_en(output_w_en),
                     .r_en(1'b0),
                     .w_addr(output_addr),
                     .r_addr(5'd0),
                     .w_data(output_data),
                     .r_data()
    );

    // 3x3 kernel for each of 2 channels = 18 weights
    weight_mem #(.COUNT(18),
                 .INIT_FILE("weights_3x3x2.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data)
    );

    // One INT32 bias per channel = 2 biases
    bias_mem #(.COUNT(2),
               .INIT_FILE("bias_2.mem")) 
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data)
    );

endmodule





module top_pointwise(input clk, rst, start, output done);
    wire input_r_en, output_w_en;
    wire [4:0] input_addr, output_addr;      // 2x2x8 for now = 32
    wire signed [7:0] input_data, output_data;
    
    wire signed [31:0] multiplier;
    wire signed [7:0] shift, output_zero_point, activation_min, activation_max;   
    
    
    // assign requant parameters to values (temporary)
    assign multiplier = 32'h40000000;       // 0.5
    assign shift = -2;                      // divide by 4
    assign output_zero_point = 0;
    assign activation_min = -128;
    assign activation_max = 127;
    

    
    
    
    wire weight_r_en;
    wire [5:0] weight_addr;     // 64 weights for now
    wire signed [7:0] weight_data;
    
    wire bias_r_en;
    wire [2:0] bias_addr;       // 8 bias values for now
    wire signed [31:0] bias_data;      // 32 bit bias values (not INT8)

    pointwise_conv conv(.clk(clk),
                        .rst(rst),
                        .start(start),                     
                        .input_data(input_data),                     
                        .weight_data(weight_data),
                        .bias_data(bias_data),
                        .multiplier(multiplier),
                        .shift(shift),
                        .output_zero_point(output_zero_point),
                        .activation_min(activation_min),
                        .activation_max(activation_max),
                        .input_addr(input_addr),
                        .output_addr(output_addr),
                        .weight_addr(weight_addr),
                        .bias_addr(bias_addr),
                        .output_data(output_data),
                        .input_r_en(input_r_en),
                        .output_w_en(output_w_en),
                        .weight_r_en(weight_r_en),
                        .bias_r_en(bias_r_en),
                        .done(done));
                    
    // initial input buffer: loads data from file for now    
    // not using dual port functionality yet           
    activation_mem #(.DATA_WIDTH(8),
                     .COUNT(32),
                     .INIT_FILE("input_2x2x8.mem"))
                 am0(.clk(clk), 
                     .w_en(0),
                     .r_en(input_r_en),
                     .w_addr(0),
                     .r_addr(input_addr),
                     .w_data(0),
                     .r_data(input_data));

    // initial output buffer: does not use file parameter
    // not using dual port functionality yet           
    activation_mem #(.DATA_WIDTH(8),
                     .COUNT(32))
                 am1(.clk(clk), 
                     .w_en(output_w_en),
                     .r_en(0),
                     .w_addr(output_addr),
                     .r_addr(0),
                     .w_data(output_data),
                     .r_data());

    // currently 64 example weights
    weight_mem #(.COUNT(64),
                 .INIT_FILE("weights_8x8.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data));

    // currently 8 example bias values
    bias_mem #(.COUNT(8),
               .INIT_FILE("bias_8.mem"))
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data));

endmodule





// for later:
// layer configuration module: keep convolution module layer-independent
// store zero points, tensor dimensions, parameter base address for current layer
// 




