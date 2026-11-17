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



// 72 operators

// largest intermediate activation: 60 * 80 * 48 = 230,400 bytes
// largest explicit padded tensor: 237,168 --> lg(237,168) = 18 bit address widths
// INT8 weight values: 80,128 --> lg(80,128) = 17 bit weight addr widths
// bias + requant output channels: 3617 --> lg(3617) = 12 bit bias, quant mem addr widths

/*
layer
input_height
input_width
input_channels
output_height
output_width
output_channels
stride
padding
input_base
output_base
weight_base
bias_base
quant_base
input_zero_point
output_zero_point
activation_min
activation_max

for residual additions, the record would also need a second input address 
and the relevant input quantization parameters

*/



// possible revision:
/*
// Operation selection
opcode
input_buffer
output_buffer

// Base addresses
input_base
output_base
weight_base
bias_base
requant_base

// Tensor dimensions
input_height
input_width
input_channels
output_height
output_width
output_channels

// Convolution parameters
stride_2
pad_top
pad_left

// Quantization parameters
input_zero_point
output_zero_point
activation_min
activation_max

// Residual ADD input
input2_buffer
input2_base
input2_zero_point

// Reserved bits / ADD-specific parameters
*/

// need to update functional units to support per channel quantization:
// include requant base address


 
module layer_config();




endmodule
