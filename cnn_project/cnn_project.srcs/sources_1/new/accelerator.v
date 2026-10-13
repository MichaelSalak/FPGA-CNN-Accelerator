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
    wire signed [7:0] input_data, output_data;
    
    wire weight_r_en;
    wire [5:0] weight_addr;     // 64 weights for now
    wire signed [7:0] weight_data;
    
    wire bias_r_en;
    wire [2:0] bias_addr;       // 8 bias values for now
    wire signed [31:0] bias_data;      // 32 bit bias values (not INT8)

    conv1x1_small conv(.clk(clk),
                       .rst(rst),
                       .start(start),
                       .input_addr(input_addr),
                       .input_data(input_data),
                       .weight_addr(weight_addr),
                       .weight_data(weight_data),
                       .bias_addr(bias_addr),
                       .bias_data(bias_data),
                       .output_addr(output_addr),
                       .output_data(output_data),
                       .input_r_en(input_r_en),
                       .output_r_en(output_r_en),
                       .weight_r_en(weights_r_en),
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
    activation_mem #(.DATA_WIDTH(8),
                     .COUNT(32))
                 am1(.clk(clk), 
                     .w_en(output_w_en),
                     .r_en(0),
                     .w_addr(output_addr),
                     .r_addr(0),
                     .w_data(output_data),
                     .r_data(0));

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





module conv1x1_small(input clk, rst, start,
                     input [4:0] input_addr,
                     input [7:0] input_data,
                     input [5:0] weight_addr,
                     input [7:0] weight_data,
                     input [2:0] bias_addr,
                     input [31:0] bias_data,
                     output reg [4:0] output_addr,
                     output reg [7:0] output_data,
                     output reg input_r_en,
                     output reg output_w_en,
                     output reg weight_r_en, bias_r_en,
                     output reg done
);





    /*  for requantization + zero point 
 
// Layer quantization parameters
input wire signed [7:0] input_zero_point,
input wire signed [7:0] output_zero_point,

// Per-output-channel requantization parameters
output wire [2:0] quant_addr,
input wire signed [31:0] quant_multiplier,
input wire signed [7:0] quant_shift*/








    // fixed dimensions for now
    
    reg signed [31:0] acc;
    reg [2:0] in_ch, out_ch;   // input and output channels for indexing input/output vector
    reg [2:0] state;

    // states
    localparam IDLE = 3'd0,
               INIT = 3'd1,
               MAC = 3'd2,
               NEXT = 3'd3,
               DONE = 3'd4;



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















// dual port memory for activation values
// ADDR_WIDTH: number of bits needed to encode address
// DATA_WIDTH: number of bits needed to store data
// COUNT: number of memory addresses 
// INIT_FILE: file to load initial activations from - will likely change later 

// ******* CURRENTLY USING 32 BIT DATA --> SWITCH TO 8 BITS AFTER REQUANTIZATION

module activation_mem#(parameter DATA_WIDTH = 8,
                       parameter COUNT = 32,
                       parameter ADDR_WIDTH = $clog2(COUNT),
                       parameter INIT_FILE = "")
                      (input clk, w_en, r_en,
                       input [ADDR_WIDTH-1:0] w_addr, r_addr,
                       input [DATA_WIDTH-1:0] w_data,
                       output reg [DATA_WIDTH-1:0] r_data
);
    
    reg [DATA_WIDTH-1:0] mem [0:COUNT-1];

    always @(posedge clk) begin
        if(r_en)
            r_data <= mem[r_addr];

        if(w_en)
            mem[w_addr] <= w_data;
    end
endmodule





// memory for weight values: fixed in memory after synthesis
module weight_mem#(parameter COUNT = 32,
                   parameter ADDR_WIDTH = $clog2(COUNT),
                   parameter INIT_FILE = "weights_8x8.mem")
                  (input clk, r_en,
                   input [ADDR_WIDTH-1:0] addr,
                   output reg signed [7:0] data_out
);

    reg signed [7:0] mem [0:COUNT-1];   // data width is a fixed 8 bits 

    initial begin
        $readmemh(INIT_FILE, mem);  // load values from .mem file
    end

    // synchronous reads for BRAM
    always @(posedge clk) begin
        if(r_en)
            data_out <= mem[addr];
    end
endmodule





// memory for bias values: fixed in memory after synthesis
module bias_mem#(parameter COUNT = 8,
                 parameter ADDR_WIDTH = $clog2(COUNT),
                 parameter INIT_FILE = "bias_8.mem")
                (input clk, r_en,
                 input [ADDR_WIDTH-1:0] addr,
                 output reg signed [31:0] data_out
);

    reg signed [31:0] mem [0:COUNT-1];  // data width is a fixed 32 bits 

    initial begin
        $readmemh(INIT_FILE, mem);  // load values from .mem file
    end

    // synchronous reads for BRAM
    always @(posedge clk) begin
        if(r_en)
            data_out <= mem[addr];
    end
endmodule

