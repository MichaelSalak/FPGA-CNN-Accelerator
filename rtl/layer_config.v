`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/28/2026 03:49:06 PM
// Design Name: 
// Module Name: layer_config
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

// 72 total model layers, only 69 layer config entries:
// inital quantize, logistic, and final quantize operations do not need layer config data

// largest intermediate activation: 60 * 80 * 48 = 230,400 bytes
// largest explicit padded tensor: 237,168 --> lg(237,168) = 18 bit address widths
// INT8 weight values: 80,128 --> lg(80,128) = 17 bit weight addr widths
// bias + requant output channels: 3617 --> lg(3617) = 12 bit bias, quant mem addr widths

/*       layer configuration formatting:
      signal      :  width  :      purpose

Operator selection		
opcode            : 4 bits  : selects CONV type, ADD, PAD, MEAN, FC, LOGISTIC, etc.
depthwise_mode    : 1 bit   : distinguishes depthwise from standard convolution
kernel_size	      : 3 bits  : kernel dimension (1 or 3)

Activation memory		
input_buffer      : 2 bits  : select A, B, or C
output_buffer     : 2 bits  : select A, B, or C
input_base        : 18 bits : first input activation base address
output_base	      : 18 bits : output activation base address

Tensor dimensions		
input_height      : 16 bits : input height 
input_width	      : 16 bits : input width
input_channels    : 16 bits : input channel count
output_height     : 16 bits : output height
output_width      : 16 bits : output width
output_channels	  : 16 bits : output channel count

Convolution addressing		
stride_2          : 1 bit   : select stride 1 or 2
pad_top	          : 2 bits  : top padding
pad_left          : 2 bits  : left padding
input_row_stride  : 18 bits : address increment between input rows
output_col_step   : 18 bits : input-window address increment between output columns
output_row_step	  : 18 bits : input-window address increment between output rows

Address bases		
weight_base       : 17 bits : base address in weight memory
bias_base         : 12 bits : base address in bias memory
requant_base      : 18 bits : base record index in requantization memory

Quantization		
input_zero_point  : 8 bits  : first input tensor zero point
output_zero_point : 8 bits  : output tensor zero point
activation_min    : 8 bits  : lower output clamp
activation_max    : 8 bits  : upper output clamp

Residual add
input2_buffer     : 2 bits  : second buffer input for ADD
input2_base	      : 18 bits : second input activation base address
input2_zero_point : 8 bits  : second input tensor zero point 
element_count     : 18 bits : element count for ADD (precomputed H*W*C)

// derive pad_right, pad_bottom in controller

*/
// layer configuration memory, 328 configuration bits per layer
// stores 69 layers, operations 1 through 69
// ROM address = TFLite operator index - 1
module layer_config #(
    parameter CONFIG_WIDTH = 328,
    parameter NUM_LAYERS   = 72
)(
    input clk, en,
    input [6:0] layer_addr,
    output reg [CONFIG_WIDTH-1:0] config_data
);



endmodule
