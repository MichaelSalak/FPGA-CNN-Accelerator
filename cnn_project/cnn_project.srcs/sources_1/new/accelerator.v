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



module top(input clk, rst, start, output done);
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




