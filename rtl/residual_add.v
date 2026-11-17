`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/03/2026 04:53:51 PM
// Design Name: 
// Module Name: residual_add
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


// adds two tensors together
// each tensor may have a unique zero point and scale, requiring inputs to be 
// rescaled prior to addition
module residual_add(input clk, rst, start,

                    // tensor configuration
                    input [17:0] element_count,
                    input [17:0] input_a_base,
                    input [17:0] input_b_base,
                    input [17:0] output_base,
                
                    // input activation A
                    input signed [7:0] input_a_data,
                    output reg [17:0] input_a_addr,
                    output reg input_a_r_en,
                
                    // input activation B
                    input signed [7:0] input_b_data,
                    output reg [17:0] input_b_addr,
                    output reg input_b_r_en,
                
                    // output activation
                    output reg [17:0] output_addr,
                    output reg signed [7:0] output_data,
                    output reg output_w_en,
                
                    // scaling zero points
                    input signed [7:0] input_a_zero_point,
                    input signed [7:0] input_b_zero_point,
                    input signed [7:0] output_zero_point,
                
                    // fixed-point scaling parameters
                    input signed [31:0] input_a_multiplier,
                    input signed [7:0] input_a_shift,
                    input signed [31:0] input_b_multiplier,
                    input signed [7:0] input_b_shift,
                    input signed [31:0] output_multiplier,
                    input signed [7:0] output_shift,
                
                    input [5:0] left_shift,
                
                    // activation limits
                    input signed [7:0] activation_min,
                    input signed [7:0] activation_max,
                
                    output reg done
);
    reg [3:0] state;
    
    localparam IDLE          = 4'd0,
               READ_INPUTS   = 4'd1,
               WAIT_INPUTS   = 4'd2,
               SUB_ZP_A      = 4'd3,
               START_SCALE_A = 4'd4,
               WAIT_SCALE_A  = 4'd5,
               SCALE_B       = 4'd6,
               ADD           = 4'd7,
               SCALE_OUT     = 4'd8,
               WRITE         = 4'd9,
               NEXT          = 4'd10,
               DONE          = 4'd11;

    // current index
    reg [17:0] idx;
    
    // subtract input zero points from inputs
    reg signed [8:0] corrected_a, corrected_b;
    
    // scale corrected inputs
    reg signed [31:0] scaled_a, scaled_b;
    
    // shared fixed-point scaling module
    reg scale_start;
    reg signed [31:0] scale_value;
    reg signed [31:0] scale_multiplier;
    reg signed [7:0] scale_shift;

    wire signed [31:0] scale_result;
    wire scale_done;

    fixed_point_scale scale(.clk(clk),
                            .rst(rst),
                            .start(scale_start),
                            .value(scale_value),
                            .multiplier(scale_multiplier),
                            .shift(scale_shift),
                            .result(scale_result),
                            .done(scale_done));

    // sign extension for left shifting
    wire signed [31:0] extended_a = {{23{corrected_a[8]}}, corrected_a};
    wire signed [31:0] extended_b = {{23{corrected_b[8]}}, corrected_b};

    // output zero-point addition
    wire signed [31:0] shifted_output = scale_result + $signed(output_zero_point);

    // clamp to activation range
    wire signed [7:0] clamped_output =
        (shifted_output > $signed(activation_max)) ? activation_max :
        (shifted_output < $signed(activation_min)) ? activation_min : 
        shifted_output[7:0];

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            idx <= 0;
            input_a_addr <= 0;
            input_b_addr <= 0;
            output_addr <= 0;
            input_a_r_en <= 0;
            input_b_r_en <= 0;
            output_w_en <= 0;
            output_data <= 0;
            done <= 0;
            corrected_a <= 0;
            corrected_b <= 0;
            scaled_a <= 0;
            scaled_b <= 0;
            scale_start <= 0;
            scale_value <= 0;
            scale_multiplier <= 0;
            scale_shift <= 0;
        end else begin
            // default control values
            input_a_r_en <= 0;
            input_b_r_en <= 0;
            output_w_en <= 0;
            scale_start <= 0;
            done <= 0;

            case(state)
                IDLE: begin
                    if(start) begin // reset index and address bases
                        idx <= 0;
                        input_a_addr <= input_a_base;
                        input_b_addr <= input_b_base;
                        output_addr <= output_base;

                        if(element_count == 0)
                            state <= DONE;
                        else
                            state <= READ_INPUTS;
                    end
                end
                READ_INPUTS: begin  // enable reads for 1 cycle
                    input_a_r_en <= 1;
                    input_b_r_en <= 1;

                    state <= WAIT_INPUTS;
                end
                WAIT_INPUTS: begin  // wait for synchronous reads
                    state <= SUB_ZP_A;
                end
                SUB_ZP_A: begin // subtract zero point from a
                    corrected_a <=
                        $signed({input_a_data[7], input_a_data}) -
                        $signed({input_a_zero_point[7], input_a_zero_point});

                    state <= START_SCALE_A;
                end
                START_SCALE_A: begin    // prepare extended a for scaling
                    // perform subtraction in next state to require only 1 subtractor
                    corrected_b <=
                        $signed({input_b_data[7], input_b_data}) -
                        $signed({input_b_zero_point[7], input_b_zero_point});
                
                    scale_value <= extended_a <<< left_shift;
                    scale_multiplier <= input_a_multiplier;
                    scale_shift <= input_a_shift;
                    scale_start <= 1;
                    state <= WAIT_SCALE_A;
                end
                WAIT_SCALE_A: begin // wait for scaling to complete
                    if(scale_done) begin
                        scaled_a <= scale_result;
                        
                        // prepare b for scaling, bypassing additional wait state
                        scale_value <= extended_b <<< left_shift;
                        scale_multiplier <= input_b_multiplier;
                        scale_shift <= input_b_shift;
                        scale_start <= 1;
                        state <= SCALE_B;
                    end
                end
                SCALE_B: begin  // wait for scaling to complete
                    if(scale_done) begin
                        scaled_b <= scale_result;
                        state <= ADD;
                    end
                end
                ADD: begin  // add scaled inputs and prepare sum for scaling
                    scale_value <= scaled_a + scaled_b;
                    scale_multiplier <= output_multiplier;
                    scale_shift <= output_shift;
                    scale_start <= 1;
                    state <= SCALE_OUT;
                end
                SCALE_OUT: begin    // wait for scaling to complete
                    if(scale_done) begin
                        output_data <= clamped_output;
                        state <= WRITE;
                    end
                end
                WRITE: begin    // write result
                    output_w_en <= 1;
                    state <= NEXT;
                end
                NEXT: begin // increment addresses until done
                    if(idx == element_count - 1) begin
                        state <= DONE;
                    end else begin
                        idx <= idx + 1;
                        input_a_addr <= input_a_addr + 1;
                        input_b_addr <= input_b_addr + 1;
                        output_addr <= output_addr + 1;
                        state <= READ_INPUTS;
                    end
                end
                DONE: begin // output done
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule





// fixed point scaling unit 
// reuses requantizater unit logic (omitting zero point addition, precision reduction)
module fixed_point_scale(input clk, rst, start,
                         input signed [31:0] value,
                         input signed [31:0] multiplier,
                         input signed [7:0] shift,
                         output reg signed [31:0] result,
                         output reg done
);
    reg [2:0] state;

    localparam IDLE      = 3'd0,
               SHIFT     = 3'd1,
               MULTIPLY  = 3'd2,
               HIGH_MUL  = 3'd3,
               ROUND_DIV = 3'd4,
               DONE      = 3'd5;

    // registered input parameters
    reg signed [31:0] value_reg;
    reg signed [31:0] multiplier_reg;
    reg signed [7:0] shift_reg;

    // intermediate results
    reg signed [31:0] shifted_value;
    reg signed [63:0] product;
    reg signed [31:0] high_result;

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

    // saturating high-multiply special case
    wire multiply_overflow = (shifted_value == 32'sh80000000) &&
        (multiplier_reg == 32'sh80000000);

    // second rounding stage
    wire signed [31:0] divided_result;

    rounding_divide u_rounding_divide(.value(high_result),
                                      .exponent(right_shift),
                                      .result(divided_result));

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            done <= 0;
            result <= 0;
            value_reg <= 0;
            multiplier_reg <= 0;
            shift_reg <= 0;
            shifted_value <= 0;
            product <= 0;
            high_result <= 0;
        end else begin
            done <= 0;

            case(state)
                IDLE: begin
                    if(start) begin // load inputs into registers
                        value_reg <= value;
                        multiplier_reg <= multiplier;
                        shift_reg <= shift;
                        state <= SHIFT;
                    end
                end
                SHIFT: begin    // apply left shift to input value
                    shifted_value <= value_reg <<< left_shift;
                    state <= MULTIPLY;
                end
                MULTIPLY: begin // multiply shifted value by multiplier
                    product <= shifted_value * multiplier_reg;
                    state <= HIGH_MUL;
                end
                HIGH_MUL: begin // check for overflow, apply nudge, truncate
                    // !!! may need to break apart critical path
                    
                    if(multiply_overflow)
                        high_result <= 32'sh7FFFFFFF;
                    else
                        high_result <= rounded_high[31:0];

                    state <= ROUND_DIV;
                end
                ROUND_DIV: begin    // execute rounding divide
                    result <= divided_result;
                    state <= DONE;
                end
                DONE: begin // output done signal
                    done <= 1'b1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
