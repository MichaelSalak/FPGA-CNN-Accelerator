`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/15/2026 09:48:45 PM
// Design Name: 
// Module Name: fully_connected
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


// only 1 fully connected operation occurs during inference, so dimensions 
// can be hardcoded
// connects all neurons into a single node (1280 inputs --> 1 output)
module fully_connected(input clk, rst, start,
                      input [17:0] input_base,
                      input [16:0] weight_base,
                      input [11:0] bias_base, requant_base,
                      input signed [7:0] input_data, weight_data,
                      input signed [31:0] bias_data,
                      input signed [31:0] multiplier,
                      input signed [7:0] shift,
                      output reg [17:0] input_addr,
                      output reg [16:0] weight_addr,
                      output reg [11:0] bias_addr, 
                      output [11:0] requant_addr,
                      output reg input_r_en, weight_r_en, bias_r_en, requant_r_en,
                      output reg signed [7:0] result,
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
               ACC           = 4'd8,
               NEXT          = 4'd9,
               REQUANT       = 4'd10,
               DONE          = 4'd11;

    localparam [10:0] INPUT_SIZE = 11'd1280;

    // requantization parameters from TFLite model
    localparam signed [7:0] INPUT_ZERO_POINT  = -8'sd128;
    localparam signed [7:0] OUTPUT_ZERO_POINT = -8'sd12;
    localparam signed [7:0] ACTIVATION_MIN    = -8'sd128;
    localparam signed [7:0] ACTIVATION_MAX    =  8'sd127;

    // current input element
    reg [10:0] index;

    reg signed [31:0] acc;
    reg signed [8:0] corrected_input;
    reg signed [16:0] product;

    // requantization parameters
    reg requant_start;
    wire requant_done;
    wire signed [7:0] requant_result;
    
    // only 1 output channel
    assign requant_addr = requant_base;

    requantize req(.clk(clk),
                   .rst(rst),
                   .start(requant_start),
                   .double_rounding(1'b0),
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
            index <= 0;
            acc <= 0;
            input_addr <= 0;
            weight_addr <= 0;
            bias_addr <= 0;
            input_r_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            requant_r_en <= 0;
            requant_start <= 0;
            done <= 0;
        end
        else begin
            // default values
            input_r_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            requant_r_en <= 0;
            requant_start <= 0;
            done <= 0;

            case(state)
                IDLE: begin
                    if(start) begin // reset counters, addresses
                        index <= 0;
                        acc <= 0;
                        input_addr <= input_base;
                        weight_addr <= weight_base;
                        bias_addr <= bias_base;
                        state <= READ_BIAS;
                    end
                end
                READ_BIAS: begin    // prepare bias to be read
                    bias_r_en <= 1;
                    requant_r_en <= 1;  // fetch requant values simultaneously
                    state <= WAIT_BIAS;
                end
                WAIT_BIAS: begin    // extra cycle needed to perform sync read
                    state <= INIT_ACC;
                end
                INIT_ACC: begin // initialize accumulator with bias
                    acc <= bias_data;
                    state <= READ_OPERANDS;
                end
                READ_OPERANDS: begin    // prepare operands to be read
                    input_r_en <= 1;
                    weight_r_en <= 1;
                    state <= WAIT_OPERANDS;
                end
                WAIT_OPERANDS: begin    // extra cycle needed to perform sync reads
                    state <= SUB;
                end
                SUB: begin  // subtract input zero point from input
                    corrected_input <= $signed(input_data) - $signed(INPUT_ZERO_POINT);
                    state <= MULTIPLY;
                end
                MULTIPLY: begin // multiply read input + weight values
                    product <= corrected_input * weight_data;
                    state <= ACC;
                end
                ACC: begin  // accumulate products
                    acc <= acc + product;
                    state <= NEXT;
                end
                NEXT: begin // update input, weight addresses
                    if(index < INPUT_SIZE - 1) begin
                        index <= index + 1;
                        input_addr <= input_addr + 1;
                        weight_addr <= weight_addr + 1;
                        state <= READ_OPERANDS;
                    end else begin
                        requant_start <= 1;
                        state <= REQUANT;
                    end
                end
                REQUANT: begin  // quantize accumulator
                    if(requant_done) begin
                        result <= requant_result;
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
