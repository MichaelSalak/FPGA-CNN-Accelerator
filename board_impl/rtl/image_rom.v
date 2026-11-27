`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/27/2026 12:20:35 PM
// Design Name: 
// Module Name: image_rom
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


// simple hardcoded image rom for intial activation buffer loading
// for preliminary hardware testing
module image_rom #(parameter COUNT = 57600,
                   parameter ADDR_WIDTH = 16,
                   parameter INIT_FILE = "img4.mem")
                  (input clk, r_en,
                   input [ADDR_WIDTH-1:0] addr,
                   output reg [7:0] data
);
    reg [7:0] mem [0:COUNT-1];

    initial begin
        $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) begin
        if(r_en)
            data <= mem[addr];
    end
endmodule
