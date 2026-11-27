`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/27/2026 12:14:24 PM
// Design Name: 
// Module Name: image_loader
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


// image loader fsm to load an input image from a rom buffer to 
// activation buffer a prior to inference
// *using rom for now, may update to use uart/zynq ps to allow for multiple
// images to be written per bitstream
module image_loader #(parameter IMAGE_SIZE = 57600,
                      parameter ACT_ADDR_WIDTH = 18)
                     (input clk, rst, start,
                      input [7:0] rom_data,
                      output reg [15:0] rom_addr,
                      output reg rom_r_en,
                      output reg [ACT_ADDR_WIDTH-1:0] write_addr,
                      output reg [7:0] write_data,
                      output reg write_en,
                      output reg loading,
                      output reg done
);

    localparam IDLE  = 3'd0,
               READ  = 3'd1,
               WRITE = 3'd2,
               NEXT  = 3'd3,
               DONE  = 3'd4;

    reg [2:0] state;
    reg [15:0] index;

    // state transitions
    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            index <= 0;
        end else begin
            case(state)
                IDLE: begin
                    if(start) begin
                        index <= 0;
                        state <= READ;
                    end
                end
                READ: begin
                    state <= WRITE;
                end
                WRITE: begin
                    state <= NEXT;
                end
                NEXT: begin
                    if(index == IMAGE_SIZE - 1) begin
                        state <= DONE;
                    end else begin
                        index <= index + 1'b1;
                        state <= READ;
                    end
                end
                DONE: begin
                    if(!start)
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    // combinational output logic
    always @(*) begin
        rom_addr   = index;
        rom_r_en   = 1'b0;
        write_addr = index;
        write_data = rom_data;
        write_en   = 1'b0;
        loading    = 1'b0;
        done       = 1'b0;

        case(state)
            READ: begin
                loading  = 1'b1;
                rom_r_en = 1'b1;
            end
            WRITE: begin
                loading  = 1'b1;
                write_en = 1'b1;
            end
            NEXT: begin
                loading = 1'b1;
            end
            DONE: begin
                done = 1'b1;
            end
            default: begin end
        endcase
    end
endmodule
