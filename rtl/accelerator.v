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


// current plans: 
// - use vivado virtual input/output (VIO) to get result and done signals on board
// - create 1 global requant unit for functional units to share instead of 1 each
// - create intial activation mem rom to populate initial buffer (for now)


/* possible future revisions:
   - use uart to populate initial buffer (rx) and output result (tx)
   - incorporate PS preprocessing + camera to test as an actual camera trap on the board
*/


// *NOTE*: operation 0 (quantize from uINT8 to INT8) performed in software when 
// writing to input image .mem file

// CNN accelerator structural integration
module accelerator #(parameter NUM_LAYERS = 69, // number of layers read from config mem (71 total ops)
                     parameter CONFIG_FILE = "layer_config.mem",
                     parameter WEIGHTS_FILE = "weights.mem",
                     parameter BIAS_FILE = "bias.mem",
                     parameter REQUANT_FILE = "requant.mem",
                     parameter ACT_COUNT = 32768)
                    (input clk, rst, start,
                     output [7:0] result,
                     output done, error,
                     
                     // external activation loading interface
                     input loader_active,
                     input [17:0] loader_w_addr,
                     input signed [7:0] loader_w_data,
                     input loader_w_en
);
    localparam [2:0] OP_CONV = 3'd0, 
                     OP_ADD  = 3'd1, 
                     OP_PAD  = 3'd2,
                     OP_MEAN = 3'd3,
                     OP_FC   = 3'd4;
                     
    wire [2:0] opcode;
    wire depthwise_mode, stride_2;
    wire [1:0] kernel_size, input_buffer, input2_buffer, output_buffer;
    wire [17:0] input_base, input2_base, output_base;
    wire [6:0] input_height, output_width;
    wire [7:0] input_width;
    wire [5:0] output_height;
    wire [10:0] input_channels, output_channels;
    wire [1:0] pad_top, pad_bottom, pad_left, pad_right;
    wire [12:0] input_row_stride, output_row_step;
    wire [10:0] output_col_step;
    wire [16:0] weight_base;
    wire [11:0] bias_base, requant_base;
    wire signed [7:0] input_zero_point, input2_zero_point, output_zero_point;
    wire signed [7:0] activation_min, activation_max;
    wire [15:0] element_count;
    wire conv_start, add_start, pad_start, mean_start, fc_start;
    wire conv_done, add_done, pad_done, mean_done, fc_done;
    wire signed [7:0] fc_result;

    layer_controller #(.NUM_LAYERS(NUM_LAYERS), 
                       .INIT_FILE(CONFIG_FILE)) 
            controller(.clk(clk), 
                       .rst(rst), 
                       .start(start),
                       .conv_done(conv_done), 
                       .add_done(add_done), 
                       .pad_done(pad_done),
                       .mean_done(mean_done), 
                       .fc_done(fc_done), 
                       .fc_result(fc_result),
                       .conv_start(conv_start), 
                       .add_start(add_start), 
                       .pad_start(pad_start),
                       .mean_start(mean_start), 
                       .fc_start(fc_start),
                       .result(result), 
                       .done(done), 
                       .error(error),
                       .opcode(opcode), 
                       .depthwise_mode(depthwise_mode), 
                       .kernel_size(kernel_size),
                       .input_buffer(input_buffer), 
                       .input2_buffer(input2_buffer),
                       .output_buffer(output_buffer), 
                       .input_base(input_base),
                       .input2_base(input2_base), 
                       .output_base(output_base),
                       .input_height(input_height), 
                       .input_width(input_width),
                       .input_channels(input_channels), 
                       .output_height(output_height),
                       .output_width(output_width), 
                       .output_channels(output_channels),
                       .stride_2(stride_2), 
                       .pad_top(pad_top), 
                       .pad_bottom(pad_bottom),
                       .pad_left(pad_left), 
                       .pad_right(pad_right),
                       .input_row_stride(input_row_stride), 
                       .output_col_step(output_col_step),
                       .output_row_step(output_row_step), 
                       .weight_base(weight_base),
                       .bias_base(bias_base), 
                       .requant_base(requant_base),
                       .input_zero_point(input_zero_point), 
                       .input2_zero_point(input2_zero_point),
                       .output_zero_point(output_zero_point), 
                       .activation_min(activation_min),
                       .activation_max(activation_max), 
                       .element_count(element_count));

    // weight, bias, requant memory addressing and multiplexing
    wire [16:0] conv_weight_addr, fc_weight_addr;
    wire conv_weight_r_en, fc_weight_r_en;
    wire [11:0] conv_bias_addr, fc_bias_addr;
    wire conv_bias_r_en, fc_bias_r_en;
    wire [11:0] conv_requant_addr, add_requant_addr, mean_requant_addr, fc_requant_addr;
    wire conv_requant_r_en, add_requant_r_en, mean_requant_r_en, fc_requant_r_en;
    
    wire [16:0] weight_addr = (opcode == OP_CONV) ? conv_weight_addr :
                              (opcode == OP_FC) ? fc_weight_addr : 17'd0;
                              
    wire weight_r_en = (opcode == OP_CONV) ? conv_weight_r_en :
                       (opcode == OP_FC) ? fc_weight_r_en : 1'b0;
                       
    wire [11:0] bias_addr = (opcode == OP_CONV) ? conv_bias_addr :
                            (opcode == OP_FC) ? fc_bias_addr : 12'd0;
                            
    wire bias_r_en = (opcode == OP_CONV) ? conv_bias_r_en :
                     (opcode == OP_FC) ? fc_bias_r_en : 1'b0;
                     
    reg [11:0] req_addr;
    reg req_r_en;
    
    always @(*) begin
        req_addr=12'd0; req_r_en=1'b0;
        case(opcode)
            OP_CONV: begin 
                req_addr = conv_requant_addr; 
                req_r_en = conv_requant_r_en; 
            end
            OP_ADD: begin 
                req_addr = add_requant_addr; 
                req_r_en = add_requant_r_en; 
            end
            OP_MEAN: begin 
                req_addr = mean_requant_addr; 
                req_r_en = mean_requant_r_en; 
            end
            OP_FC: begin 
                req_addr = fc_requant_addr; 
                req_r_en = fc_requant_r_en; 
            end
        endcase
    end
    
    wire signed [7:0] weight_data, shift;
    wire signed [31:0] bias_data, multiplier;
    
    weight_mem #(.COUNT(80128), 
                 .ADDR_WIDTH(17), 
                 .INIT_FILE(WEIGHTS_FILE)) 
         weights(.clk(clk), 
                 .r_en(weight_r_en), 
                 .addr(weight_addr), 
                 .data_out(weight_data));
        
    bias_mem #(.COUNT(3617), 
               .ADDR_WIDTH(12), 
               .INIT_FILE(BIAS_FILE)) 
        biases(.clk(clk), 
               .r_en(bias_r_en), 
               .addr(bias_addr), 
               .data_out(bias_data));
        
    quant_param_mem #(.COUNT(3651), 
                      .ADDR_WIDTH(12), 
                      .INIT_FILE(REQUANT_FILE)) 
       requant_params(.clk(clk), 
                      .r_en(req_r_en), 
                      .addr(req_addr),
                      .multiplier(multiplier), 
                      .shift(shift));

    // functional unit activation interfaces (driven by activation router)
    wire [17:0] conv_input_addr;
    wire signed [7:0] conv_input_data;
    wire conv_input_r_en;
    wire [17:0] conv_output_addr;
    wire signed [7:0] conv_output_data;
    wire conv_output_w_en;
    
    wire [17:0] add_input_a_addr;
    wire signed [7:0] add_input_a_data;
    wire add_input_a_r_en;
    wire [17:0] add_input_b_addr;
    wire signed [7:0] add_input_b_data;
    wire add_input_b_r_en;
    wire [17:0] add_output_addr;
    wire signed [7:0] add_output_data;
    wire add_output_w_en;
    
    wire [17:0] pad_input_addr;
    wire signed [7:0] pad_input_data;
    wire pad_input_r_en;
    wire [17:0] pad_output_addr;
    wire signed [7:0] pad_output_data;
    wire pad_output_w_en;
    
    wire [17:0] mean_input_addr;
    wire signed [7:0] mean_input_data;
    wire mean_input_r_en;
    wire [17:0] mean_output_addr;
    wire signed [7:0] mean_output_data;
    wire mean_output_w_en;
    
    wire [17:0] fc_input_addr;
    wire signed [7:0] fc_input_data;
    wire fc_input_r_en;

    unified_conv conv_unit(.clk(clk), 
                           .rst(rst), 
                           .start(conv_start), 
                           .done(conv_done),
                           .depthwise_mode(depthwise_mode), 
                           .kernel_size(kernel_size),
                           .stride_2(stride_2), 
                           .pad_top(pad_top), 
                           .pad_left(pad_left),
                           .input_height(input_height), 
                           .input_width(input_width),
                           .input_channels(input_channels), 
                           .output_height(output_height),
                           .output_width(output_width), 
                           .output_channels(output_channels),
                           .input_base(input_base), 
                           .output_base(output_base),
                           .weight_base(weight_base), 
                           .bias_base(bias_base), 
                           .requant_base(requant_base),
                           .input_row_stride(input_row_stride), 
                           .output_col_step(output_col_step),
                           .output_row_step(output_row_step), 
                           .input_zero_point(input_zero_point),
                           .output_zero_point(output_zero_point), 
                           .activation_min(activation_min),
                           .activation_max(activation_max), 
                           .input_data(conv_input_data),
                           .weight_data(weight_data), 
                           .bias_data(bias_data),
                           .multiplier(multiplier), 
                           .shift(shift),
                           .input_addr(conv_input_addr), 
                           .input_r_en(conv_input_r_en),
                           .output_addr(conv_output_addr), 
                           .output_data(conv_output_data),
                           .output_w_en(conv_output_w_en), 
                           .weight_addr(conv_weight_addr),
                           .weight_r_en(conv_weight_r_en), 
                           .bias_addr(conv_bias_addr),
                           .bias_r_en(conv_bias_r_en), 
                           .requant_addr(conv_requant_addr),
                           .requant_r_en(conv_requant_r_en));
       
    residual_add add_unit(.clk(clk), 
                          .rst(rst), 
                          .start(add_start), 
                          .done(add_done),
                          .element_count(element_count), 
                          .input_a_base(input_base),
                          .input_b_base(input2_base), 
                          .output_base(output_base),
                          .requant_base(requant_base), 
                          .input_a_data(add_input_a_data),
                          .input_a_addr(add_input_a_addr), 
                          .input_a_r_en(add_input_a_r_en),
                          .input_b_data(add_input_b_data), 
                          .input_b_addr(add_input_b_addr),
                          .input_b_r_en(add_input_b_r_en), 
                          .output_addr(add_output_addr),
                          .output_data(add_output_data), 
                          .output_w_en(add_output_w_en),
                          .input_a_zero_point(input_zero_point),
                          .input_b_zero_point(input2_zero_point),
                          .output_zero_point(output_zero_point),
                          .multiplier(multiplier), 
                          .shift(shift),
                          .requant_addr(add_requant_addr), 
                          .requant_r_en(add_requant_r_en),
                          .activation_min(activation_min), 
                          .activation_max(activation_max));
    
    pad pad_unit(.clk(clk), 
                 .rst(rst), 
                 .start(pad_start),
                 .done(pad_done),
                 .input_height(input_height), 
                 .input_width(input_width),
                 .input_channels(input_channels), 
                 .pad_top(pad_top),
                 .pad_bottom(pad_bottom), 
                 .pad_left(pad_left), 
                 .pad_right(pad_right),
                 .pad_value(input_zero_point), 
                 .input_base(input_base),
                 .output_base(output_base), 
                 .input_data(pad_input_data),
                 .input_addr(pad_input_addr), 
                 .input_r_en(pad_input_r_en),
                 .output_addr(pad_output_addr), 
                 .output_data(pad_output_data),
                 .output_w_en(pad_output_w_en));
        
    mean mean_unit(.clk(clk), 
                   .rst(rst), 
                   .start(mean_start), 
                   .done(mean_done),
                   .input_base(input_base), 
                   .requant_base(requant_base),
                   .output_base(output_base), 
                   .multiplier(multiplier), 
                   .shift(shift),
                   .requant_addr(mean_requant_addr), 
                   .requant_r_en(mean_requant_r_en),
                   .input_data(mean_input_data), 
                   .input_addr(mean_input_addr),
                   .input_r_en(mean_input_r_en), 
                   .output_addr(mean_output_addr),
                   .output_data(mean_output_data), 
                   .output_w_en(mean_output_w_en));
        
    fully_connected fc_unit(.clk(clk), 
                            .rst(rst), 
                            .start(fc_start), 
                            .done(fc_done),
                            .input_base(input_base), 
                            .weight_base(weight_base),
                            .bias_base(bias_base), 
                            .requant_base(requant_base),
                            .input_data(fc_input_data), 
                            .weight_data(weight_data),
                            .bias_data(bias_data), 
                            .multiplier(multiplier), 
                            .shift(shift),
                            .input_addr(fc_input_addr), 
                            .weight_addr(fc_weight_addr),
                            .bias_addr(fc_bias_addr), 
                            .requant_addr(fc_requant_addr),
                            .input_r_en(fc_input_r_en),
                            .weight_r_en(fc_weight_r_en),
                            .bias_r_en(fc_bias_r_en), 
                            .requant_r_en(fc_requant_r_en),
                            .result(fc_result));

    // three independently addressed packed UltraRAM activation buffers
    wire [17:0] a_r_addr, a_w_addr;
    wire a_r_en, a_w_en;
    wire signed [7:0] a_r_data, a_w_data;
    
    activation_mem_packed #(.ADDR_WIDTH(18), 
                            .COUNT(ACT_COUNT)) 
               activation_a(.clk(clk), 
                            .r_en(a_r_en), 
                            .w_en(a_w_en),
                            .r_addr(a_r_addr), 
                            .w_addr(a_w_addr),
                            .r_data(a_r_data), 
                            .w_data(a_w_data));
        
    wire [17:0] b_r_addr, b_w_addr;
    wire b_r_en, b_w_en;
    wire signed [7:0] b_r_data, b_w_data;
        
    activation_mem_packed #(.ADDR_WIDTH(18), 
                            .COUNT(ACT_COUNT)) 
               activation_b(.clk(clk), 
                            .r_en(b_r_en), 
                            .w_en(b_w_en),
                            .r_addr(b_r_addr), 
                            .w_addr(b_w_addr),
                            .r_data(b_r_data), 
                            .w_data(b_w_data));
        
    wire [17:0] c_r_addr, c_w_addr;
    wire c_r_en, c_w_en;
    wire signed [7:0] c_r_data, c_w_data;
    
    activation_mem_packed #(.ADDR_WIDTH(18), 
                            .COUNT(ACT_COUNT)) 
               activation_c(.clk(clk), 
                            .r_en(c_r_en), 
                            .w_en(c_w_en),
                            .r_addr(c_r_addr), 
                            .w_addr(c_w_addr),
                            .r_data(c_r_data), 
                            .w_data(c_w_data));

    activation_router router(.opcode(opcode), 
                             .input_buffer(input_buffer),
                             .input2_buffer(input2_buffer), 
                             .output_buffer(output_buffer),
                             .conv_input_addr(conv_input_addr),
                             .conv_input_data(conv_input_data),
                             .conv_input_r_en(conv_input_r_en),
                             .conv_output_addr(conv_output_addr),
                             .conv_output_data(conv_output_data),
                             .conv_output_w_en(conv_output_w_en),
                             .add_input_a_addr(add_input_a_addr),
                             .add_input_a_data(add_input_a_data),
                             .add_input_a_r_en(add_input_a_r_en),
                             .add_input_b_addr(add_input_b_addr),
                             .add_input_b_data(add_input_b_data),
                             .add_input_b_r_en(add_input_b_r_en),
                             .add_output_addr(add_output_addr),
                             .add_output_data(add_output_data),
                             .add_output_w_en(add_output_w_en),
                             .pad_input_addr(pad_input_addr),
                             .pad_input_data(pad_input_data),
                             .pad_input_r_en(pad_input_r_en),
                             .pad_output_addr(pad_output_addr),
                             .pad_output_data(pad_output_data),
                             .pad_output_w_en(pad_output_w_en),
                             .mean_input_addr(mean_input_addr),
                             .mean_input_data(mean_input_data),
                             .mean_input_r_en(mean_input_r_en),
                             .mean_output_addr(mean_output_addr),
                             .mean_output_data(mean_output_data),
                             .mean_output_w_en(mean_output_w_en),
                             .fc_input_addr(fc_input_addr),
                             .fc_input_data(fc_input_data),
                             .fc_input_r_en(fc_input_r_en),
                             .a_r_addr(a_r_addr),
                             .a_r_en(a_r_en),
                             .a_r_data(a_r_data),
                             .a_w_addr(a_w_addr),
                             .a_w_data(a_w_data),
                             .a_w_en(a_w_en),
                             .b_r_addr(b_r_addr),
                             .b_r_en(b_r_en),
                             .b_r_data(b_r_data),
                             .b_w_addr(b_w_addr),
                             .b_w_data(b_w_data),
                             .b_w_en(b_w_en),
                             .c_r_addr(c_r_addr),
                             .c_r_en(c_r_en),
                             .c_r_data(c_r_data),
                             .c_w_addr(c_w_addr),
                             .c_w_data(c_w_data),
                             .c_w_en(c_w_en),
                             .loader_active(loader_active),
                             .loader_w_addr(loader_w_addr),
                             .loader_w_data(loader_w_data),
                             .loader_w_en(loader_w_en));
    
endmodule
