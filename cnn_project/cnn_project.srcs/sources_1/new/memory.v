`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/14/2026 10:19:47 AM
// Design Name: 
// Module Name: memory
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


// dual port memory for activation values
// ADDR_WIDTH: number of bits needed to encode address
// DATA_WIDTH: number of bits needed to store data
// COUNT: number of memory addresses 
// INIT_FILE: file to load initial activations from - will likely change later 

// ******* CURRENTLY USING 32 BIT OUTPUT DATA --> SWITCH TO 8 BITS AFTER REQUANTIZATION

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

    initial begin
        if(INIT_FILE != "") // load input buffer with file data for now
            $readmemh(INIT_FILE, mem);
    end

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





// memory for requantization multiplier + shift values:
// multiplier and shift values are precomputed in python to express the 
// floating point as a normalized significand + power of 2
module quant_param_mem#(parameter COUNT = 8,
                        parameter ADDR_WIDTH = $clog2(COUNT),
                        parameter INIT_FILE = "quant_params.mem")
                       (input clk, r_en,
                        input [ADDR_WIDTH-1:0] addr,
                        output signed [31:0] multiplier,
                        output signed [7:0] shift
);

    // stored as [ multiplier | shift ]
    reg [39:0] mem [0:COUNT-1];
    reg [39:0] read_data;

    initial begin
        $readmemh(INIT_FILE, mem);  // load values from .mem file
    end

    // synchronous reads for BRAM
    always @(posedge clk) begin
        if(r_en)
            read_data <= mem[addr];
    end

    assign multiplier = $signed(read_data[39:8]);
    assign shift = $signed(read_data[7:0]);
endmodule

