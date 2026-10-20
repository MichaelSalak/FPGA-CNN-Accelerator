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


// 1x1 pointwise convolution module     will update again later to support model
module pointwise_conv(input clk, rst, start,                     
                      input signed [7:0] input_data,
                      input signed [7:0] weight_data,
                      input signed [31:0] bias_data,    
                      input signed [31:0] multiplier,
                      input signed [7:0] shift,
                      input signed [7:0] output_zero_point, 
                      input signed [7:0] activation_min, activation_max,   
                     
                      // will need multiplier, shift, zp, min/max memory address outputs
                        
                      output [4:0] input_addr, 
                      output [4:0] output_addr,
                      output [5:0] weight_addr,
                      output [2:0] bias_addr,
                      output reg signed [7:0] output_data,
                      output reg input_r_en,
                      output reg output_w_en,
                      output reg weight_r_en, bias_r_en,
                      output reg done
);



    // fixed dimensions for now
    // zero point likely fixed per layer
    // activation min/max, multiplier, shift may need to be fetched each output
    
    
    
    reg signed [31:0] acc;
    reg [1:0] pixel;    // currently using 2x2 pixel test
    reg [2:0] in_ch, out_ch;    // input/output channels
    reg [3:0] state;

    // using 1 mac for now
    reg signed [15:0] product;
    
    // signals to guide requantization FSM + extract result
    reg requant_start;
    wire requant_done;
    wire signed [7:0] requant_result;

    localparam IDLE = 4'd0, 
               //LOAD_LAYER = 3'd1,   // fetch zero points + other layer config info
               READ_BIAS = 4'd1,
               WAIT_BIAS = 4'd2,
               INIT_ACC = 4'd3,
               READ_OPERANDS = 4'd4,
               WAIT_OPERANDS = 4'd5,
               MULTIPLY = 4'd6,
               ADD = 4'd7,
               REQUANT = 4'd8,  // requantize 32 bit acc to 8 bit int before storing
               WRITE = 4'd9,
               NEXT = 4'd10,
               DONE = 4'd11;

    assign input_addr = {pixel, in_ch};     // iterate across pixels
    assign weight_addr = {out_ch, in_ch};   // weight does not depend on pixel
    assign bias_addr = out_ch;              // 1 bias value per output channel
    assign output_addr = {pixel, out_ch};   // iterate across pixels

    /*  eventually, when dimensions are not fixed: 
        input_addr = input_base + pixel * Cin + in_ch
        weight_addr = weight_base + out_ch * Cin + in_ch
        bias_addr = bias_base + out_ch
        output_addr = output_base + pixel * Cout + out_ch
    */

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
            pixel <= 0;
            in_ch <= 0;
            out_ch <= 0;
            acc <= 0;
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
                    if(start) begin // reset pixel + channel counters
                        pixel <= 0;
                        in_ch <= 0;
                        out_ch <= 0;
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
                INIT_ACC: begin // init acc to read bias value, enable input + weight reads
                    acc <= bias_data;
                    bias_r_en <= 0; 
                    in_ch <= 0;
                    state <= READ_OPERANDS;
                end
                READ_OPERANDS: begin    // prepare operands to be read
                    // enable input and weight reads 
                    input_r_en <= 1;
                    weight_r_en <= 1;
                    state <= WAIT_OPERANDS;
                end
                WAIT_OPERANDS: begin    // extra cycle needed to perform sync reads
                    state <= MULTIPLY;
                end
                MULTIPLY: begin // multiply read input + weight values
                    product <= input_data * weight_data;
                    state <= ADD;
                end
                ADD: begin  // accumulate products for all input channels
                    acc <= acc + product;
                    
                    // disable reads after reading final input channel
                    if(in_ch == 3'd7) begin
                        input_r_en <= 0;
                        weight_r_en <= 0;
                        requant_start <= 1; // enable requant next cycle
                        state <= REQUANT;
                    end else begin
                        in_ch <= in_ch + 1;
                        state <= READ_OPERANDS;
                    end
                end
                REQUANT: begin  // quantize accumulator
                    requant_start <= 0;
                    
                    // initialize output to zero point to then add result
                    output_data <= output_zero_point;
                    
                    // wait for requant to finish for now
                    // will likely pipeline to compute next MAC during requant
                    if(requant_done) begin
                        output_data <= output_data + requant_result;
                        state <= WRITE;
                    end
                end
                WRITE: begin // prepare result to be written
                    output_w_en <= 1;
                    state <= NEXT;
                end
                NEXT: begin // update output channel + pixel counters 
                    output_w_en <= 0;
                    
                    if(out_ch == 3'd7) begin    // if on final output channel: 
                        out_ch <= 0;    // reset to output channel 0 for next pixel
                        
                        if(pixel == 2'd3) begin
                            state <= DONE;  // done when on final output of final pixel
                        end else begin
                            pixel <= pixel + 1; // increment pixel and reset output channel
                            state <= READ_BIAS;
                        end
                    end else begin
                        out_ch <= out_ch + 1;   // go to next output channel if not done
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

