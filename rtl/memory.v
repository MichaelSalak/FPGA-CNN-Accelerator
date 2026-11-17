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


// activation memory designed for UltraRAM inference
// using URAM to keep all memory on-board
// will instantiate 3 activation buffers: 2 for alternating input/output, 
// 1 for residual add operations
// COUNT refers to the number of 64 bit words, not INT8 activations
module activation_mem_packed #(parameter ADDR_WIDTH = 18,
                               parameter COUNT = 32768)
                              (input clk, r_en, w_en,
                               input [ADDR_WIDTH-1:0] r_addr, w_addr,
                               input signed [7:0] w_data,
                               output signed [7:0] r_data
);
    // force URAM synthesis 
    (* ram_style = "ultra" *)   
    reg [63:0] mem [0:COUNT-1];

    wire [ADDR_WIDTH-4:0] read_word_addr, write_word_addr;

    assign read_word_addr  = r_addr[ADDR_WIDTH-1:3];
    assign write_word_addr = w_addr[ADDR_WIDTH-1:3];

    wire [7:0] byte_we;
    assign byte_we = w_en ? (8'b00000001 << w_addr[2:0]) : 8'b0;

    // replicate the write data across all byte lanes
    wire [63:0] write_word = {8{w_data}};

    reg [63:0] read_word;
    reg [2:0] read_byte_index;

    integer i;

    always @(posedge clk) begin
        // byte-enable writes
        for(i = 0; i < 8; i = i + 1) begin
            if(byte_we[i])
                mem[write_word_addr][i*8 +: 8] <= write_word[i*8 +: 8];
        end
        // full-width synchronous read
        if(r_en) begin
            read_word <= mem[read_word_addr];
            read_byte_index <= r_addr[2:0];
        end
    end

    assign r_data = read_word[read_byte_index*8 +: 8];
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

