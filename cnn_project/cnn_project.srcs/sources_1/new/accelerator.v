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



module conv1x1_small(input clk, rst, start,
                     output reg done
);
    // fixed dimensions for now
    reg signed [7:0] inputs [0:7];      // 8 8-bit input vlaues
    reg signed [7:0] weight_mem [0:63]; // 64 8-bit weight values
    reg signed [31:0] bias_mem [0:7];   // 8 32-bit bias values
    reg signed [31:0] acc;
    reg [2:0] in_ch, out_ch;   // input and output channels for indexing input/output vector
    reg [2:0] state;
   
    // input channel handles values 0-7, output channel handles which set of 8 values to use
    wire [5:0] weight_addr = {out_ch, in_ch};   
    
    reg signed [31:0] result [0:7]; // make result internal to allow for array formatting
    
    //wire signed [7:0] weights = weight_mem[weight_addr];

    // states
    localparam IDLE = 3'd0,
               INIT = 3'd1,
               MAC = 3'd2,
               //STORE = 3'd3,
               NEXT = 3'd3,
               DONE = 3'd4;



    // hardcoded example input and weight values
    initial begin
        inputs[0] =  2;  
        inputs[1] = -1;  
        inputs[2] =  3; 
        inputs[3] =  4; 
        inputs[4] =  0;  
        inputs[5] = -2;  
        inputs[6] =  1;  
        inputs[7] =  5;  
        
        // Output channel 0
        weight_mem[0] =  1;
        weight_mem[1] =  2;
        weight_mem[2] = -1;
        weight_mem[3] =  1;
        weight_mem[4] =  3;
        weight_mem[5] = -2;
        weight_mem[6] =  2;
        weight_mem[7] = -1;
    
        // Output channel 1
        weight_mem[8]  =  2;
        weight_mem[9]  = -1;
        weight_mem[10] =  1;
        weight_mem[11] =  0;
        weight_mem[12] = -2;
        weight_mem[13] =  1;
        weight_mem[14] =  3;
        weight_mem[15] = -1;
    
        // Output channel 2
        weight_mem[16] = -1;
        weight_mem[17] =  3;
        weight_mem[18] =  2;
        weight_mem[19] = -2;
        weight_mem[20] =  1;
        weight_mem[21] =  0;
        weight_mem[22] = -1;
        weight_mem[23] =  2;
    
        // Output channel 3
        weight_mem[24] =  3;
        weight_mem[25] =  1;
        weight_mem[26] = -2;
        weight_mem[27] =  2;
        weight_mem[28] = -1;
        weight_mem[29] =  1;
        weight_mem[30] =  0;
        weight_mem[31] = -3;
    
        // Output channel 4
        weight_mem[32] =  1;
        weight_mem[33] = -2;
        weight_mem[34] =  3;
        weight_mem[35] =  0;
        weight_mem[36] =  2;
        weight_mem[37] = -1;
        weight_mem[38] =  1;
        weight_mem[39] =  2;
    
        // Output channel 5
        weight_mem[40] = -2;
        weight_mem[41] =  1;
        weight_mem[42] =  0;
        weight_mem[43] =  3;
        weight_mem[44] = -1;
        weight_mem[45] =  2;
        weight_mem[46] = -3;
        weight_mem[47] =  1;
    
        // Output channel 6
        weight_mem[48] =  2;
        weight_mem[49] =  0;
        weight_mem[50] = -1;
        weight_mem[51] =  1;
        weight_mem[52] =  3;
        weight_mem[53] = -2;
        weight_mem[54] =  1;
        weight_mem[55] = -1;
    
        // Output channel 7
        weight_mem[56] = -1;
        weight_mem[57] =  2;
        weight_mem[58] =  1;
        weight_mem[59] = -3;
        weight_mem[60] =  0;
        weight_mem[61] =  1;
        weight_mem[62] = -2;
        weight_mem[63] =  3;
    
        // Bias values
        bias_mem[0] =  3;
        bias_mem[1] = -2;
        bias_mem[2] =  5;
        bias_mem[3] =  1;
        bias_mem[4] = -3;
        bias_mem[5] =  4;
        bias_mem[6] =  0;
        bias_mem[7] = -1;
    end


    // using 1 mac for now
    wire signed [15:0] product;
    assign product = inputs[in_ch] * weight_mem[weight_addr];

    integer i;

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            in_ch <= 0;
            out_ch <= 0;
            acc <= 0;
            for (i = 0; i < 8; i = i + 1) begin
                result[i] <= 32'd0;  // initialize to 0;
            end
            done <= 0;
        end else begin
            case(state)
                IDLE: begin
                    done <= 0;
                    if(start)
                        out_ch <= 0;
                        state <= INIT;
                end
                INIT: begin
                    acc <= bias_mem[out_ch];    // use output channel to index bias memory
                    in_ch <= 0;
                    state <= MAC;
                end
                MAC: begin
                    acc <= acc + product;
                    if(in_ch == 3'd7)
                        state <= NEXT;
                    else
                        in_ch <= in_ch + 1;
                end
                NEXT: begin
                    result[out_ch] <= acc;
                
                    if(out_ch == 3'd7)
                        state <= DONE;
                    else begin
                        out_ch <= out_ch + 1;
                        state <= INIT;
                    end
                end
                DONE: begin
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

