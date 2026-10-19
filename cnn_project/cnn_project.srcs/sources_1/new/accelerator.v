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



// use bram for 2 activation memory buffers for ping pong buffering
// use bram for weight/bias memory
// have main controller to coordinate everything
// components: convolution engine, 



/*
3 CONV_2D inputs: [111 42 77] outputs: [112]

Tensor	Shape	         Meaning
111	    [1, 60, 80, 8]	 Input activation
42	    [8, 1, 1, 8]	 Weights
77	    [8]	             Biases
112	    [1, 60, 80, 8]	 Output activation
*/



module top(input clk, rst, start, output done);
    wire input_r_en, output_w_en;
    wire [4:0] input_addr, output_addr;      // 2x2x8 for now = 32
    wire signed [7:0] input_data;
    
    wire signed [31:0] output_data;     // UNQUANTIZED FOR NOW
    
    
    
    wire weight_r_en;
    wire [5:0] weight_addr;     // 64 weights for now
    wire signed [7:0] weight_data;
    
    wire bias_r_en;
    wire [2:0] bias_addr;       // 8 bias values for now
    wire signed [31:0] bias_data;      // 32 bit bias values (not INT8)

    conv1x1_small conv(.clk(clk),
                       .rst(rst),
                       .start(start),                     
                       .input_data(input_data),                     
                       .weight_data(weight_data),
                       .bias_data(bias_data),
                       .input_addr(input_addr),
                       .output_addr(output_addr),
                       .weight_addr(weight_addr),
                       .bias_addr(bias_addr),
                       .output_data(output_data),
                       .input_r_en(input_r_en),
                       .output_w_en(output_w_en),
                       .weight_r_en(weight_r_en),
                       .bias_r_en(bias_r_en),
                       .done(done));
                    
    // initial input buffer: loads data from file for now    
    // not using dual port functionality yet           
    activation_mem #(.DATA_WIDTH(8),
                     .COUNT(32),
                     .INIT_FILE("input_2x2x8.mem"))
                 am0(.clk(clk), 
                     .w_en(0),
                     .r_en(input_r_en),
                     .w_addr(0),
                     .r_addr(input_addr),
                     .w_data(0),
                     .r_data(input_data));

    // initial output buffer: does not use file parameter
    // not using dual port functionality yet           
    activation_mem #(.DATA_WIDTH(32),   // RESULTS NOT QUANTIZED YET
                     .COUNT(32))
                 am1(.clk(clk), 
                     .w_en(output_w_en),
                     .r_en(0),
                     .w_addr(output_addr),
                     .r_addr(0),
                     .w_data(output_data),
                     .r_data());

    // currently 64 example weights
    weight_mem #(.COUNT(64),
                 .INIT_FILE("weights_8x8.mem"))
              wm(.clk(clk),
                 .r_en(weight_r_en),
                 .addr(weight_addr),
                 .data_out(weight_data));

    // currently 8 example bias values
    bias_mem #(.COUNT(8),
               .INIT_FILE("bias_8.mem"))
            bm(.clk(clk),
               .r_en(bias_r_en),
               .addr(bias_addr),
               .data_out(bias_data));

endmodule






// layer configuration module: keep convolution module layer-independent
// store zero points, tensor dimensions, parameter base address for current layer
// 








module conv1x1_small(input clk, rst, start,                     
                     input signed [7:0] input_data,
                     input signed [7:0] weight_data,
                     input signed [31:0] bias_data,                 
                     output [4:0] input_addr, 
                     output [4:0] output_addr,
                     output [5:0] weight_addr,
                     output [2:0] bias_addr,
                     output reg [31:0] output_data,     // UNQUANTIZED FOR NOW
                     output reg input_r_en,
                     output reg output_w_en,
                     output reg weight_r_en, bias_r_en,
                     output reg done
);

    // fixed dimensions for now
    
    reg signed [31:0] acc;
    reg [1:0] pixel;    // currently using 2x2 pixel test
    reg [2:0] in_ch, out_ch;    // input/output channels
    reg [3:0] state;

    // using 1 mac for now
    reg signed [15:0] product;

    localparam IDLE = 4'd0, 
               //LOAD_LAYER = 3'd1,   // fetch zero points + other layer config info
               READ_BIAS = 4'd1,
               WAIT_BIAS = 4'd2,
               INIT_ACC = 4'd3,
               READ_OPERANDS = 4'd4,
               WAIT_OPERANDS = 4'd5,
               MULTIPLY = 4'd6,
               ADD = 4'd7,
               //REQUANT = 3'd3,  // may need to expand to multiple stages
               WRITE = 4'd8,
               NEXT = 4'd9,
               DONE = 4'd10;

  
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

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            pixel <= 0;
            in_ch <= 0;
            out_ch <= 0;
            acc <= 0;
            product <= 0;
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
                        state <= WRITE;
                    end else begin
                        in_ch <= in_ch + 1;
                        state <= READ_OPERANDS;
                    end
                end
                WRITE: begin // prepare accumulator to be written
                    
                
                    // will need to quantize later
                    output_data <= acc;
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












