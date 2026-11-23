`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/19/2026 03:27:10 PM
// Design Name: 
// Module Name: requantizer
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


// may need to break up critical path to meet timing


// INT32 accumulator to INT8, using either TFLite-style single or double rounding
// matches TFLite's behavior for each operation type:
// single rounding operations: standard conv, pointwise conv, fully connected
// double rounding operations: depthwise conv, residual add, mean
module requantize(input clk, rst, start, double_rounding,
                  input signed [31:0] acc, multiplier,
                  input signed [7:0] shift,
                  input signed [7:0] output_zero_point,
                  input signed [7:0] activation_min, activation_max,
                  output reg signed [7:0] result,
                  output reg done
);
    reg [2:0] state;

    localparam IDLE     = 3'd0,
               SHIFT    = 3'd1,
               MULTIPLY = 3'd2,
               RESCALE  = 3'd3,
               DONE     = 3'd4;

    // registered input parameters
    reg signed [31:0] acc_reg, multiplier_reg;
    reg signed [7:0] shift_reg;
    reg signed [7:0] zero_point_reg;
    reg signed [7:0] min_reg, max_reg;
    reg double_rounding_reg;

    // intermediate results
    reg signed [31:0] shifted_acc;
    reg signed [63:0] product;
    reg signed [31:0] scaled_result;

    // positive shifts applied before multiplication
    wire [7:0] left_shift = (shift_reg > 0) ? shift_reg : 8'd0;

    // negative shifts increase the total division exponent
    wire [7:0] right_shift = (shift_reg < 0) ? -shift_reg : 8'd0;

    // SINGLE ROUNDING
    // round the full 64-bit product only once
    wire [7:0] total_shift = 8'd31 + right_shift;

    wire signed [63:0] single_offset = 64'sd1 <<< (total_shift - 1'b1);

    wire signed [63:0] single_rounded = (product + single_offset) >>> total_shift;

    // DOUBLE ROUNDING
    // stage 1: SaturatingRoundingDoublingHighMul
    // rounds the high 32 bits of the Q31 multiplication
    // signed division truncates toward zero, matching the
    // reference high-multiply rounding behavior
    wire signed [63:0] high_nudge = (product >= 0) ? 64'sd1073741824 : 64'sd1073741823;

    wire signed [63:0] high_rounded = (product + high_nudge) / 64'sd2147483648;

    wire signed [31:0] high_result = high_rounded[31:0];

    // stage 2: RoundingDivideByPOT
    // rounds the high result after the remaining right shift
    wire [31:0] mask = (right_shift == 0) ? 32'd0 :
                       (32'hFFFFFFFF >> (32 - right_shift));

    wire [31:0] remainder = high_result & mask;

    wire [31:0] threshold = (mask >> 1) + ((high_result < 0) ? 32'd1 : 32'd0);

    wire signed [31:0] double_rounded = (high_result >>> right_shift) +
                                        ((remainder > threshold) ? 32'sd1 : 32'sd0);
        
    // extend before adding output zero point
    wire signed [32:0] offset_result = $signed({scaled_result[31], scaled_result}) +
                                       $signed(zero_point_reg);

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            done <= 0;
            result <= 0;
            acc_reg <= 0;
            multiplier_reg <= 0;
            shift_reg <= 0;
            zero_point_reg <= 0;
            min_reg <= 0;
            max_reg <= 0;
            double_rounding_reg <= 0;
            shifted_acc <= 0;
            product <= 0;
            scaled_result <= 0;
        end else begin
            done <= 0;

            case(state)
                IDLE: begin
                    if(start) begin
                        acc_reg <= acc;
                        multiplier_reg <= multiplier;
                        shift_reg <= shift;
                        zero_point_reg <= output_zero_point;
                        min_reg <= activation_min;
                        max_reg <= activation_max;
                        double_rounding_reg <= double_rounding;
                        state <= SHIFT;
                    end
                end
                SHIFT: begin
                    shifted_acc <= acc_reg <<< left_shift;
                    state <= MULTIPLY;
                end
                MULTIPLY: begin
                    product <= shifted_acc * multiplier_reg;
                    state <= RESCALE;
                end
                RESCALE: begin
                    if(double_rounding_reg)
                        scaled_result <= double_rounded;
                    else
                        scaled_result <= single_rounded[31:0];
                    state <= DONE;
                end
                DONE: begin
                    if(offset_result < $signed(min_reg))
                        result <= min_reg;
                    else if(offset_result > $signed(max_reg))
                        result <= max_reg;
                    else
                        result <= offset_result[7:0];

                    done <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
