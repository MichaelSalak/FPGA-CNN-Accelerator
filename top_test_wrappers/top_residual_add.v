`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:30:22 PM
// Design Name: 
// Module Name: top_residual_add
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

// test wrapper for residual add operation
module top_residual_add(input clk, rst, start,
                        // tensor configuration
                        input [15:0] element_count,
                    
                        // initialize activation buffer A
                        input init_a_w_en,
                        input [17:0] init_a_w_addr,
                        input signed [7:0] init_a_w_data,
                    
                        // initialize activation buffer C
                        input init_c_w_en,
                        input [17:0] init_c_w_addr,
                        input signed [7:0] init_c_w_data,
                    
                        // read output activation buffer B
                        input output_r_en,
                        input [17:0] output_r_addr,
                        output signed [7:0] output_r_data,
                    
                        // zero points
                        input signed [7:0] input_a_zero_point,
                        input signed [7:0] input_b_zero_point,
                        input signed [7:0] output_zero_point,
                    
                        // activation limits
                        input signed [7:0] activation_min, 
                        input signed [7:0] activation_max,
                        
                        output done
);
    wire [17:0] input_a_addr, input_b_addr, output_addr;
    wire input_a_r_en, input_b_r_en, output_w_en;
    wire signed [7:0] input_a_data, input_b_data, output_data;
    
    // requantization ROM connections
    wire [11:0] requant_addr;
    wire requant_r_en;
    wire signed [31:0] multiplier;
    wire signed [7:0] shift;

    // buffer A: first input
    activation_mem_packed buffer_a(.clk(clk),
                                   .r_en(input_a_r_en),
                                   .r_addr(input_a_addr),
                                   .r_data(input_a_data),
                                   .w_en(init_a_w_en),
                                   .w_addr(init_a_w_addr),
                                   .w_data(init_a_w_data));

    // buffer C: second input
    activation_mem_packed buffer_c(.clk(clk),
                                   .r_en(input_b_r_en),
                                   .r_addr(input_b_addr),
                                   .r_data(input_b_data),
                                   .w_en(init_c_w_en),
                                   .w_addr(init_c_w_addr),
                                   .w_data(init_c_w_data));

    // buffer B: output
    activation_mem_packed buffer_b(.clk(clk),
                                   .r_en(output_r_en),
                                   .r_addr(output_r_addr),
                                   .r_data(output_r_data),
                                   .w_en(output_w_en),
                                   .w_addr(output_addr),
                                   .w_data(output_data));

    // residual add
    residual_add dut(.clk(clk),
                     .rst(rst),
                     .start(start),
                     .element_count(element_count),
                     .input_a_base(18'd0),   // use local addresses for testing
                     .input_b_base(18'd0),
                     .requant_base(12'd0),
                     .output_base(18'd0),
                     .input_a_data(input_a_data),
                     .input_a_addr(input_a_addr),
                     .input_a_r_en(input_a_r_en),
                     .input_b_data(input_b_data),
                     .input_b_addr(input_b_addr),
                     .input_b_r_en(input_b_r_en),
                     .output_data(output_data),
                     .output_addr(output_addr),
                     .output_w_en(output_w_en),
                     .input_a_zero_point(input_a_zero_point),
                     .input_b_zero_point(input_b_zero_point),
                     .output_zero_point(output_zero_point),
                     .requant_addr(requant_addr),
                     .requant_r_en(requant_r_en),
                     .multiplier(multiplier),
                     .shift(shift),                
                     .activation_min(activation_min),
                     .activation_max(activation_max),
                     .done(done));

    // 3 param sets for 3 scales
    quant_param_mem #(.COUNT(3),
                      .INIT_FILE("requant_3.mem")) 
                   rm(.clk(clk),
                      .r_en(requant_r_en),
                      .addr(requant_addr),
                      .multiplier(multiplier),
                      .shift(shift));

endmodule
