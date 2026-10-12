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


/*
3 CONV_2D inputs: [111 42 77] outputs: [112]

Tensor	Shape	         Meaning
111	    [1, 60, 80, 8]	 Input activation
42	    [8, 1, 1, 8]	 Weights
77	    [8]	             Biases
112	    [1, 60, 80, 8]	 Output activation
*/



module conv1x1_small(input clk, rst, start,
                     output reg signed [31:0] result,
                     output reg done
);
    reg signed [7:0] inputs [0:7];
    reg signed [7:0] weights [0:7];
    reg signed [31:0] acc;
    reg [2:0] channel;
    reg [1:0] state;

    // states
    localparam IDLE = 2'd0,
               INIT = 2'd1,
               MAC  = 2'd2,
               DONE = 2'd3;



    // hardcoded example input values
    initial begin
        inputs[0] =  2;  weights[0] =  1;
        inputs[1] = -1;  weights[1] =  2;
        inputs[2] =  3;  weights[2] = -1;
        inputs[3] =  4;  weights[3] =  1;
        inputs[4] =  0;  weights[4] =  3;
        inputs[5] = -2;  weights[5] = -2;
        inputs[6] =  1;  weights[6] =  2;
        inputs[7] =  5;  weights[7] = -1;
    end


    // using 1 mac for now
    wire signed [15:0] product;
    assign product = inputs[channel] * weights[channel];


    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            channel <= 0;
            acc <= 0;
            result <= 0;
            done <= 0;
        end else begin
            case(state)
                IDLE: begin
                    done <= 0;
                    if(start)
                        state <= INIT;
                end
                INIT: begin
                    acc <= 32'sd3; // bias (hardcoded for now)
                    
                    
                    
                    channel <= 0;
                    state <= MAC;
                end
                MAC: begin
                    acc <= acc + product;
                    if(channel == 7)
                        state <= DONE;
                    else
                        channel <= channel + 1;
                end
                DONE: begin
                    result <= acc;
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

