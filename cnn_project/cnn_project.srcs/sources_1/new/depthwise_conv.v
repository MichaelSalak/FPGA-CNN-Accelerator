`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/19/2026 10:08:07 PM
// Design Name: 
// Module Name: depthwise_conv
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


// 3x3 depthwise convolution module with variable dimension input support
// supports stride 1, stride 2, same padding, valid padding
// 3 main coordinate systems:
//    1. output coordinates: determine which activation is being calculated currently
//    2. logical input coordinates: which position of the input the current kernel
//       element corresponds to (can exceed boundary indices in physical memory)
//    3. physical memory addresses: where the input stored in flattened HWC memory
module depthwise_conv(input clk, rst, start,
                      input signed [7:0] input_data,
                      input signed [7:0] weight_data,
                      input signed [31:0] bias_data,
                      
                      // layer configuration
                      input [15:0] input_height,
                      input [15:0] input_width,
                      input [15:0] channels,
                      input [15:0] output_height,
                      input [15:0] output_width,
                      input stride_2,  // 0 = stride 1, 1 = stride 2
                      input [1:0] pad_top,  // padding offsets (0 for VALID)
                      input [1:0] pad_left,
                      
                      // memory base addresses
                      input [15:0] input_base,
                      input [15:0] weight_base,
                      input [15:0] bias_base,
                      input [15:0] output_base,
                
                      // precomputed address increments
                      input [15:0] input_row_stride,
                      input [15:0] input_col_stride,
                      input [15:0] kernel_row_jump,
                      input [15:0] output_col_step,
                      input [15:0] output_row_step,
                      
                      // requantization parameters
                      input signed [31:0] multiplier,
                      input signed [7:0] shift,
                      input signed [7:0] input_zero_point, output_zero_point,
                      input signed [7:0] activation_min, activation_max,
                      
                      // memory reads, output data + done signal                 
                      output [15:0] input_addr,
                      output [15:0] output_addr,
                      output [15:0] weight_addr,
                      output [15:0] bias_addr,
                      output reg signed [7:0] output_data,
                      output reg input_r_en,
                      output reg output_w_en,
                      output reg weight_r_en,
                      output reg bias_r_en,
                      output reg done
);
    reg [3:0] state;

    localparam IDLE          = 4'd0,
               READ_BIAS     = 4'd1,
               WAIT_BIAS     = 4'd2,
               INIT_ACC      = 4'd3,
               READ_OPERANDS = 4'd4,
               WAIT_OPERANDS = 4'd5,
               SUB           = 4'd6,  
               MULTIPLY      = 4'd7,
               ADD           = 4'd8,   
               NEXT_KERNEL   = 4'd9,     
               REQUANT       = 4'd10,
               WRITE         = 4'd11,
               NEXT          = 4'd12,
               DONE          = 4'd13;

    reg [15:0] out_x, out_y;    // current output position
    reg [15:0] channel;         // current input/output channel
    reg [1:0] kx, ky;   // current position within the 3x3 kernel

    // starting address of the current output pixel row, corresponding to channel 0
    // allows new output row to be reached without carrying over horizontal offset
    reg [15:0] row_base_addr;

    // starting address of the current output pixel in current output row, 
    // corresponding to channel 0
    // allows next pixel to be reached without carrying over channel offset
    reg [15:0] pixel_base_addr;

    // starting address for the current output pixel and channel
    // allows next window to be reached after completing 1 kernel
    reg [15:0] window_base_addr;

    // registers to acquire current addresses
    reg [15:0] input_addr_reg, weight_addr_reg, bias_addr_reg, output_addr_reg;

    // Connect address registers to output ports
    assign input_addr  = input_addr_reg;
    assign weight_addr = weight_addr_reg;
    assign bias_addr   = bias_addr_reg;
    assign output_addr = output_addr_reg;

    // determine offsets based on padding amount (0,1,2)
    wire [15:0] top_offset =
    (pad_top == 2) ? (input_row_stride << 1) :
    (pad_top == 1) ? input_row_stride : 16'd0;

    wire [15:0] left_offset =
        (pad_left == 2) ? (input_col_stride << 1) :
        (pad_left == 1) ? input_col_stride : 16'd0;
    
    // intial window address, including padding
    wire [15:0] initial_window_addr = input_base - top_offset - left_offset;

    // current logical input coordinates corresponding to current kernel element
    // *can be negative due to SAME padding
    reg signed [16:0] in_x, in_y;
    
    // logical origin of current output window
    reg signed [16:0] pixel_x, row_y;
    
    // corrected activation, registered in SUB
    reg signed [8:0] corrected_input;

    // pad if/when out of bounds
    wire padding_position =
        (in_y < 0) ||
        (in_x < 0) ||
        (in_y >= $signed({1'b0, input_height})) ||
        (in_x >= $signed({1'b0, input_width})); 

    reg signed [16:0] product;  // 17 bit result from a 9 bit and 8 bit input
    reg signed [31:0] acc;

    // requantization parameters
    reg requant_start;
    wire requant_done;
    wire signed [7:0] requant_result;

    requantize req(.clk(clk),
                   .rst(rst),
                   .start(requant_start),
                   .acc(acc),
                   .multiplier(multiplier),
                   .shift(shift),
                   .output_zero_point(output_zero_point),
                   .activation_min(activation_min),
                   .activation_max(activation_max),
                   .result(requant_result),
                   .done(requant_done)
    );

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            out_x <= 0;
            out_y <= 0;
            channel <= 0;
            kx <= 0;
            ky <= 0;
            row_base_addr <= 0;
            pixel_base_addr <= 0;
            window_base_addr <= 0;
            input_addr_reg <= 0;
            weight_addr_reg <= 0;
            bias_addr_reg <= 0;
            output_addr_reg <= 0;
            pixel_x <= 0;
            row_y <= 0;
            in_x <= 0;
            in_y <= 0;
            corrected_input <= 0;
            acc <= 0;
            product <= 0;
            requant_start <= 0;
            output_data <= 0;
            input_r_en <= 0;
            output_w_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            done <= 0;
        end
        else begin
            case(state)
                IDLE: begin
                    done <= 0;
                    if(start) begin // reset counters, addresses, read enables
                        out_x <= 0;
                        out_y <= 0;
                        channel <= 0;
                        kx <= 0;
                        ky <= 0;
                        row_base_addr <= initial_window_addr;
                        pixel_base_addr <= initial_window_addr;
                        window_base_addr <= initial_window_addr;
                        input_addr_reg <= initial_window_addr;
                        weight_addr_reg <= weight_base;
                        bias_addr_reg <= bias_base;
                        output_addr_reg <= output_base;
                        pixel_x <= -$signed({15'd0, pad_left});
                        row_y <= -$signed({15'd0, pad_top});
                        input_r_en <= 0;
                        weight_r_en <= 0;
                        bias_r_en <= 0;
                        output_w_en <= 0;
                        requant_start <= 0;
                        state <= READ_BIAS;
                    end
                end
                READ_BIAS: begin    // prepare bias to be read
                    bias_r_en <= 1;
                    state <= WAIT_BIAS;
                end
                WAIT_BIAS: begin    // extra cycle needed to perform sync read
                    state <= INIT_ACC;
                end
                INIT_ACC: begin // init acc to read bias value
                    acc <= bias_data;
                    bias_r_en <= 0;
                    
                    // reset kernel indices
                    kx <= 0;
                    ky <= 0;
                
                    // update input and weight addresses for new output
                    input_addr_reg <= window_base_addr;
                    weight_addr_reg <= weight_base + channel;
                
                    // update logical input coordinates
                    in_x <= pixel_x;
                    in_y <= row_y;
                    
                    state <= READ_OPERANDS;
                end
                READ_OPERANDS: begin    // prepare operands to be read
                    input_r_en <= 0;
                    weight_r_en <= 0;
                
                    // padded position contributes nothing to acc, skip compute steps
                    if(padding_position) begin
                        state <= NEXT_KERNEL;
                    end else begin
                        // enable input and weight reads 
                        input_r_en <= 1;
                        weight_r_en <= 1;
                        state <= WAIT_OPERANDS;
                    end
                end
                WAIT_OPERANDS: begin    // extra cycle needed to perform sync reads
                    input_r_en <= 0;
                    weight_r_en <= 0;
                    state <= SUB;
                end
                SUB: begin  // subtract input zero point from input
                    corrected_input <= $signed({input_data[7], input_data}) -
                                       $signed({input_zero_point[7], input_zero_point});
                    state <= MULTIPLY;
                end
                MULTIPLY: begin // multiply input + weight values
                    product <= corrected_input * weight_data;
                    state <= ADD;
                end
                ADD: begin  // accumulate products for all kernel positions
                    acc <= acc + product;
                    state <= NEXT_KERNEL;
                end
                NEXT_KERNEL: begin  // update kernel indices, input + weight addresses
                    if(kx < 2) begin
                        kx <= kx + 1;   // next kernel column
                
                        input_addr_reg <= input_addr_reg + input_col_stride;
                        weight_addr_reg <= weight_addr_reg + channels;
                
                        in_x <= in_x + 1;
                
                        state <= READ_OPERANDS;
                    end else if(ky < 2) begin
                        ky <= ky + 1;   // next kernel row
                        kx <= 0;
                
                        input_addr_reg <= input_addr_reg + kernel_row_jump;
                        weight_addr_reg <= weight_addr_reg + channels;
                
                        in_x <= pixel_x;
                        in_y <= in_y + 1;
                
                        state <= READ_OPERANDS;
                    end else begin
                        // all 9 kernel positions have been processed
                        requant_start <= 1;
                        state <= REQUANT;
                    end
                end
                REQUANT: begin  // quantize accumulator
                    requant_start <= 0;

                    if(requant_done) begin
                        output_data <= requant_result;
                        state <= WRITE;
                    end
                end
                WRITE: begin    // prepare result to be written
                    output_w_en <= 1;
                    state <= NEXT;
                end
                NEXT: begin // update input channel + pixel counters 
                    output_w_en <= 0;

                    // output memory is sequential in HWC order
                    output_addr_reg <= output_addr_reg + 1;
                
                    if(channel < channels - 1) begin    // next channel, same pixel
                        // after a channel is completed, increment counters by 1
                        channel <= channel + 1;
                        window_base_addr <= window_base_addr + 1;
                        bias_addr_reg <= bias_addr_reg + 1;
                
                        state <= READ_BIAS;
                    end else begin  // all channels completed for this pixel
                        channel <= 0;
                        bias_addr_reg <= bias_base;
                
                        if(out_x < output_width - 1) begin
                            // next output column
                            out_x <= out_x + 1;
                
                            // after a pixel is completed, increment addresses by
                            // 1 pixel/column step
                            pixel_base_addr <= pixel_base_addr + output_col_step;
                            window_base_addr <= pixel_base_addr + output_col_step;
                
                            pixel_x <= pixel_x + (stride_2 ? 2 : 1);
                
                            state <= READ_BIAS;
                        end else if (out_y < output_height - 1) begin
                            // next output row
                            out_x <= 0;
                            out_y <= out_y + 1;
                
                            // after a pixel row is completed, increment addresses by 
                            // 1 output row step
                            row_base_addr <= row_base_addr + output_row_step;
                            pixel_base_addr <= row_base_addr + output_row_step;
                            window_base_addr <= row_base_addr + output_row_step;
                
                            pixel_x <= -$signed({15'd0, pad_left});
                            row_y <= row_y + (stride_2 ? 2 : 1);
                
                            state <= READ_BIAS;
                        end else begin
                            state <= DONE;
                        end
                    end
                end
                DONE: begin // output done signal when all pixels are handled
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

