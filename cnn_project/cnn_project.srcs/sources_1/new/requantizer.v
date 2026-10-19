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


// TFLite-compatible rounding is normally separated into two steps:
// 1. a saturating rounding doubling high multiply, which reduces the 
// multiplication result to approximately 32 bits
// 2. a rounding division by a power of two, which applies the remaining 
// right shift
// positive shifts are applied to the accumulator before the high multiply

// quantize 32 bit accumulator produced during convolution back to INT8
module requantize(input clk, rst, start,
                  input signed [31:0] acc, multiplier,
                  input signed [7:0] shift,
                  input signed [7:0] output_zero_point, 
                  input signed [7:0] activation_min, activation_max,
                  output reg signed [7:0] result,
                  output reg done
);
    reg [2:0] state;

    localparam IDLE = 3'd0, 
               SHIFT = 3'd1,      // shift accumulator
               MULTIPLY = 3'd2,   // multiply accumulator by multiplier
               RESCALE = 3'd3,    // apply shift and round
               ADD = 3'd4,        // add zero point and apply clamp
               DONE = 3'd5;       // prepare output 

    // register input parameters
    reg signed [31:0] acc_reg, multiplier_reg;
    reg signed [7:0] shift_reg;
    reg signed [7:0] zero_point_reg;
    reg signed [7:0] min_reg, max_reg;

    // intermediate results
    reg signed [31:0] shifted_acc; 
    reg signed [63:0] product;
    reg signed [31:0] high_result;
    reg signed [31:0] scaled_result;
    
    // positive shifts are applied before multiplication
    wire [7:0] left_shift = (shift_reg > 0) ? shift_reg : 8'd0;
    
    // negative shifts are used for division
    wire [7:0] right_shift = (shift_reg < 0) ? -shift_reg : 8'd0;

    // TFLite-style rounding high multiply offset: 2^30 : 1- 2^30
    wire signed [63:0] nudge = (product >= 0) ? 64'sd1073741824 : -64'sd1073741823;
    wire signed [63:0] numerator = product + nudge;

    // divide by 2^31, truncating toward zero without using the division operator
    wire signed [63:0] shifted_high = numerator >>> 31;

    wire has_remainder = |numerator[30:0]; // determine if non-zero using reduction OR

    // add 1 to shifted high if there is a remainder for a negative product
    wire signed [63:0] rounded_high = shifted_high +
        ((numerator < 0) && has_remainder);

    // Ssturating high-multiply special case
    wire multiply_overflow = (shifted_acc == 32'sh80000000) &&
        (multiplier_reg == 32'sh80000000);

    // second rounding stage
    wire signed [31:0] divided_result;

    rounding_divide u_rounding_divide(.value(high_result),
                                      .exponent(right_shift),
                                      .result(divided_result));

    // sign-extend operands before adding
    wire signed [32:0] offset_result = $signed({scaled_result[31], scaled_result}) +
        $signed(zero_point_reg);

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            done <= 0;
            result <= 0;

            acc_reg <= 0;
            multiplier_reg <= 0;
            shift_reg <= 0;
            zero_point_reg <= 0;
            min_reg <= 0;
            max_reg <= 0;

            product <= 0;
            high_result <= 0;
            scaled_result <= 0;
        end
        else begin
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
                    if(multiply_overflow)
                        high_result <= 32'sh7FFFFFFF;
                    else
                        high_result <= rounded_high[31:0];

                    state <= ADD;
                end
                ADD: begin
                    scaled_result <= divided_result;
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





// rounding divide used during requantization: 
// rounds to nearest integer, halfway cases rounded up
// uses integer shifts and remainder checking instead of division operator to avoid FP
// result = round(value/(2^exponent))
module rounding_divide(input signed [31:0] value,
                       input [7:0] exponent,
                       output reg signed [31:0] result
);

    reg [31:0] mask;
    reg [31:0] remainder;
    reg [31:0] threshold;
    
    reg signed [31:0] shifted_value;
    reg signed [31:0] rounding_increment;

    always @(*) begin
        mask = 0;
        remainder = 0;
        threshold = 0;
        shifted_value = 0;
        rounding_increment = 0;
        result = 0;

        if(exponent == 0) begin
            result = value;
        end
        else if(exponent <= 31) begin
            mask = (32'd1 << exponent) - 1; // create mask to isolate remainder
            
            // apply mask to extract remainder: any non zero bits after shift/division
            remainder = value & mask;       

            // rounds halfway cases away from zero
            // threshold = 2^(n-1) - 1 for value >= 0
            // threshold = 2^(n-1) for value < 0
            threshold = (mask >> 1) + (value < 0);
            
            // signed arithmetic right shift ("divide" operation)
            shifted_value = value >>> exponent;
            
            // explicitly convert comparison to signed 32-bit value
            if(remainder > threshold)
                rounding_increment = 32'sd1;

            // round result away from 0 if needed (+1)
            result = shifted_value + rounding_increment;
        end
    end
endmodule


