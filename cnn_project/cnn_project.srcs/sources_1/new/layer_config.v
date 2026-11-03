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

// ****** per output channel quantization multiplier + shift values

// ****** will require additional activation buffer to handle residual adds

// ****** need to implement additional operations (initial conv, residual add, etc)

// ****** memory: 144 BRAM blocks is not enough for on chip memory, incorporating 
// UltraRAM blocks could solve this if utilized correctly
// use (* ram_style = "ultra" *) for activation buffers
// use (* ram_style = "block" *) for weights, bias, requant memories


/*
layer_type
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





 
module layer_config();




endmodule
