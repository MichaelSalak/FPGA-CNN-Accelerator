`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/19/2026 10:02:49 PM
// Design Name: 
// Module Name: pointwise_conv
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


// 1x1 pointwise convolution module with variable dimension input support
module pointwise_conv(input clk, rst, start,                     
                      input signed [7:0] input_data,
                      input signed [7:0] weight_data,
                      input signed [31:0] bias_data,  
                      
                      // layer dimensions
                      input [15:0] input_height,
                      input [15:0] input_width,
                      input [15:0] input_channels,
                      input [15:0] output_channels,
                
                      // memory base addresses
                      input [15:0] input_base,
                      input [15:0] weight_base,
                      input [15:0] bias_base,
                      input [15:0] output_base,
                      
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
    
    localparam IDLE = 4'd0, 
               //LOAD_LAYER = 3'd1,   // fetch zero points + other layer config info
               READ_BIAS     = 4'd1,
               WAIT_BIAS     = 4'd2,
               INIT_ACC      = 4'd3,
               READ_OPERANDS = 4'd4,
               WAIT_OPERANDS = 4'd5,
               SUB           = 4'd6,
               MULTIPLY      = 4'd7,
               ADD           = 4'd8,
               REQUANT       = 4'd9, 
               WRITE         = 4'd10,
               NEXT          = 4'd11,
               DONE          = 4'd12;

    // counters to track current pixel index + in/out channels
    reg [15:0] out_y;
    reg [15:0] out_x;
    reg [15:0] out_channel;
    reg [15:0] in_channel;

    // registers to acquire current addresses
    reg [15:0] input_addr_reg, weight_addr_reg, bias_addr_reg, output_addr_reg;

    // connect address registers to output ports
    assign input_addr  = input_addr_reg;
    assign weight_addr = weight_addr_reg;
    assign bias_addr   = bias_addr_reg;
    assign output_addr = output_addr_reg;

    // starting address of current input pixel
    reg [15:0] pixel_base_addr;

    // starting weight address of current output channel
    reg [15:0] weight_channel_base;

    reg signed [31:0] acc;
    reg signed [8:0] corrected_input;
    reg signed [16:0] product;

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
            out_y <= 0;
            out_x <= 0;
            out_channel <= 0;
            in_channel <= 0;
            input_addr_reg <= 0;
            weight_addr_reg <= 0;
            bias_addr_reg <= 0;
            output_addr_reg <= 0;
            pixel_base_addr <= 0;
            weight_channel_base <= 0;
            acc <= 0;
            corrected_input <= 0;
            product <= 0;
            requant_start <= 0;
            output_data <= 0;
            input_r_en <= 0;
            output_w_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            done <= 0;
        end else begin
            case(state)
                IDLE: begin
                    done <= 0;
                    if(start) begin // reset counters + addresses
                        out_y <= 0;
                        out_x <= 0;
                        out_channel <= 0;
                        in_channel <= 0;
                        input_addr_reg <= input_base;
                        weight_addr_reg <= weight_base;
                        bias_addr_reg <= bias_base;
                        output_addr_reg <= output_base;
                        pixel_base_addr <= input_base;
                        weight_channel_base <= weight_base;
                        state <= READ_BIAS;
                    end
                end
                READ_BIAS: begin    // prepare bias to be read
                    bias_r_en <= 1;     // enable bias read enable 
                    state <= WAIT_BIAS;
                end
                WAIT_BIAS: begin    // extra cycle needed to perform sync read
                    state <= INIT_ACC;
                end
                INIT_ACC: begin // init acc to bias value, update input/weight addr
                    acc <= bias_data;
                    bias_r_en <= 0;
                    in_channel <= 0;
                    
                    // restart input + weight traversal for this output channel
                    input_addr_reg <= pixel_base_addr;
                    weight_addr_reg <= weight_channel_base;
                    state <= READ_OPERANDS;
                end
                READ_OPERANDS: begin    // prepare operands to be read
                    input_r_en <= 1;
                    weight_r_en <= 1;
                    state <= WAIT_OPERANDS;
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
                MULTIPLY: begin // multiply read input + weight values
                    product <= corrected_input * weight_data;
                    state <= ADD;
                end
                ADD: begin  // accumulate products for all input channels
                    acc <= acc + product;
                    if(in_channel == input_channels - 1'b1) begin   // finished output ch
                        requant_start <= 1;
                        state <= REQUANT;
                    end else begin  // increment addresses by 1 for next channel
                        in_channel <= in_channel + 1'b1;
                        input_addr_reg <= input_addr_reg + 1'b1;
                        weight_addr_reg <= weight_addr_reg + 1'b1;
                        state <= READ_OPERANDS;
                    end
                end
                REQUANT: begin  // quantize accumulator
                    requant_start <= 0;
                    
                    if(requant_done) begin
                        // zero point handled during requantization
                        output_data <= requant_result;  
                        state <= WRITE;
                    end
                end
                WRITE: begin // prepare result to be written
                    output_w_en <= 1;
                    state <= NEXT;
                end
                NEXT: begin // update output channel + pixel counters 
                    output_w_en <= 0;
                    if(out_channel == output_channels - 1'b1) begin // finished pixel
                        out_channel <= 0;
                        if((out_x == input_width - 1'b1) && 
                           (out_y == input_height - 1'b1)) begin
                            state <= DONE;  // finished after final pixel
                        end else begin
                            // move to next input pixel
                            pixel_base_addr <= pixel_base_addr + input_channels;

                            // start next pixel from input channel 0
                            input_addr_reg <= pixel_base_addr + input_channels;

                            // reset weights and bias to first output channel
                            weight_channel_base <= weight_base;
                            weight_addr_reg <= weight_base;
                            bias_addr_reg <= bias_base;

                            if(out_x == input_width - 1'b1) begin
                                out_x <= 0;
                                out_y <= out_y + 1'b1;
                            end else begin
                                out_x <= out_x + 1'b1;
                            end

                            output_addr_reg <= output_addr_reg + 1'b1;  // increment pixel
                            
                            state <= READ_BIAS;
                        end
                    end else begin  // next output channel, same pixel
                        // move to next output channel
                        out_channel <= out_channel + 1'b1;

                        // next output channel uses the same input pixel
                        input_addr_reg <= pixel_base_addr;

                        // move to next group of input-channel weights
                        weight_channel_base <= weight_channel_base + input_channels;
                        weight_addr_reg <= weight_channel_base + input_channels;

                        // next bias and output
                        bias_addr_reg <= bias_addr_reg + 1'b1;
                        output_addr_reg <= output_addr_reg + 1'b1;

                        state <= READ_BIAS;
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

