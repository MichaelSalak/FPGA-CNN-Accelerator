`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/13/2026 05:59:16 PM
// Design Name: 
// Module Name: mean
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


// only 1 mean operation occurs during inference, so dimensions can be hardcoded
// averages the values across all pixels for each channel 
module mean(input clk, rst, start,
            // activation memory base addresses
            input [17:0] input_base,
            input [17:0] output_base,
        
            // fixed-point requantization parameters
            input signed [31:0] multiplier,
            input signed [7:0] shift,
        
            // input activation memory
            input signed [7:0] input_data,
            output reg [17:0] input_addr,
            output reg input_r_en,
        
            // output activation memory
            output reg [17:0] output_addr,
            output reg signed [7:0] output_data,
            output reg output_w_en,
            
            output reg done
);
    reg [3:0] state;

    localparam IDLE          = 4'd0,
               INIT_CHANNEL  = 4'd1,
               READ          = 4'd2,
               WAIT          = 4'd3,
               SUB           = 4'd4,
               ACC           = 4'd5,
               NEXT_POS      = 4'd6,
               REQUANT       = 4'd7,
               WRITE         = 4'd8,
               NEXT_CHANNEL  = 4'd9,
               DONE          = 4'd10;

    // Fixed model dimensions:
    // Input:  [1, 4, 5, 1280]
    // Output: [1, 1280]
    //
    // NHWC memory layout:
    // address = base + spatial_position * 1280 + channel

    localparam [10:0] CHANNELS = 11'd1280;
    localparam [4:0]  POSITIONS = 5'd20;
    localparam [17:0] SPATIAL_STRIDE = 18'd1280;

    // requantization parameters from TFLite model
    localparam signed [7:0] INPUT_ZERO_POINT  = -8'sd128;
    localparam signed [7:0] OUTPUT_ZERO_POINT = -8'sd128;
    localparam signed [7:0] ACTIVATION_MIN    = -8'sd128;
    localparam signed [7:0] ACTIVATION_MAX    =  8'sd127;

    // current output channel and spatial position
    reg [10:0] channel;
    reg [4:0] position;

    // starting address for the current channel
    reg [17:0] channel_base_addr;

    reg signed [31:0] acc;
    reg signed [8:0] corrected_input;

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
                   .output_zero_point(OUTPUT_ZERO_POINT),
                   .activation_min(ACTIVATION_MIN),
                   .activation_max(ACTIVATION_MAX),
                   .result(requant_result),
                   .done(requant_done));

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            channel <= 0;
            position <= 0;
            channel_base_addr <= 0;
            input_addr <= 0;
            output_addr <= 0;
            acc <= 0;
            input_r_en <= 0;
            output_w_en <= 0;
            output_data <= 0;
            requant_start <= 0;
            done <= 0;
        end else begin
            // default values
            input_r_en <= 0;
            output_w_en <= 0;
            requant_start <= 0;
            done <= 0;

            case(state)
                IDLE: begin
                    if(start) begin // reset counters, addresses
                        channel <= 0;
                        position <= 0;
                        channel_base_addr <= input_base;
                        input_addr <= input_base;
                        output_addr <= output_base;
                        acc <= 0;
                        state <= INIT_CHANNEL;
                    end
                end
                INIT_CHANNEL: begin // initialize current channel 
                    position <= 0;
                    acc <= 0;
                    input_addr <= channel_base_addr;
                    state <= READ;
                end
                READ: begin // prepare operands to be read
                    input_r_en <= 1;
                    state <= WAIT;
                end
                WAIT: begin // extra cycle needed to perform sync reads
                    state <= SUB;
                end        
                SUB: begin  // subtract input zero point from input
                    corrected_input <= $signed(input_data) - $signed(INPUT_ZERO_POINT);
                    state <= ACC;
                end
                ACC: begin  // accumulate across pixels for current channel
                    acc <= acc + corrected_input;
                    state <= NEXT_POS;
                end
                NEXT_POS: begin // update current pixel
                    if(position < POSITIONS - 1) begin
                        position <= position + 1;

                        // next spatial position, same channel
                        input_addr <= input_addr + SPATIAL_STRIDE;

                        state <= READ;
                    end else begin
                        requant_start <= 1;
                        state <= REQUANT;
                    end
                end
                REQUANT: begin  // quantize accumulator
                    if(requant_done) begin
                        output_data <= requant_result;
                        state <= WRITE;
                    end
                end
                WRITE: begin
                    output_w_en <= 1;
                    state <= NEXT_CHANNEL;
                end
                NEXT_CHANNEL: begin // update current output channel
                    if(channel < CHANNELS - 1) begin
                        channel <= channel + 1;

                        // next channel starts one byte later
                        channel_base_addr <= channel_base_addr + 1;

                        // next output element
                        output_addr <= output_addr + 1;

                        state <= INIT_CHANNEL;
                    end else begin
                        state <= DONE;
                    end
                end
                DONE: begin // output done signal
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
