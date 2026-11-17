`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/06/2026 05:05:14 PM
// Design Name: 
// Module Name: pad
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

// padding module: adds a layer of padding to each indicated input edge
// padded value is the zero point, pad_value
module pad(input clk, rst, start,
           // input tensor dimensions
           input [15:0] input_height,
           input [15:0] input_width,
           input [15:0] input_channels,
                    
           // padding configuration
           input [1:0] pad_top,
           input [1:0] pad_bottom,
           input [1:0] pad_left,
           input [1:0] pad_right,
           input signed [7:0] pad_value,
        
           // base addresses
           input [17:0] input_base,
           input [17:0] output_base,
        
           // input activation memory
           input signed [7:0] input_data,
           output reg [17:0] input_addr,
           output reg input_r_en,
        
           // output activation memory
           output reg [17:0] output_addr,
           output reg signed [7:0] output_data,
           output reg output_w_en,
           output reg done
);
    reg [2:0] state;

    localparam IDLE      = 3'd0,
               CHECK_POS = 3'd1,
               READ      = 3'd2,
               WAIT      = 3'd3,
               WRITE     = 3'd4,
               NEXT      = 3'd5,
               DONE      = 3'd6;

    // output dimensions, including padding
    wire [16:0] output_height = {1'b0, input_height} + pad_top + pad_bottom;
    wire [16:0] output_width = {1'b0, input_width} + pad_left + pad_right;

    // current output position (NHWC order)
    reg [16:0] out_y, out_x;
    reg [15:0] channel;

    // current element is inside the original input tensor
    wire valid_position =
        (out_y >= {15'd0, pad_top}) &&
        (out_y < ({15'd0, pad_top} + {1'b0, input_height})) &&
        (out_x >= {15'd0, pad_left}) &&
        (out_x < ({15'd0, pad_left} + {1'b0, input_width}));

    // indicates whether the output should copy input_data 
    // or use the padding constant
    reg copy_input;

    // stores data returned by synchronous input memory
    reg signed [7:0] input_reg;

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            out_y <= 0;
            out_x <= 0;
            channel <= 0;
            input_addr <= 0;
            output_addr <= 0;
            input_reg <= 0;
            copy_input <= 0;
            input_r_en <= 0;
            output_w_en <= 0;
            output_data <= 0;
            done <= 0;
        end else begin
            // default control signals
            input_r_en <= 0;
            output_w_en <= 0;
            done <= 0;

            case(state)
                IDLE: begin
                    if(start) begin // reset counters, addresses
                        out_y <= 0;
                        out_x <= 0;
                        channel <= 0;
                        input_addr <= input_base;
                        output_addr <= output_base;
                        copy_input <= 0;
                        state <= CHECK_POS;
                    end
                end
                CHECK_POS: begin    // determine if valid index or padding
                    if(valid_position) begin
                        copy_input <= 1;
                        state <= READ;
                    end else begin
                        copy_input <= 0;
                        state <= WRITE;
                    end
                end
                READ: begin // prepare operands to be read
                    input_r_en <= 1;
                    state <= WAIT;
                end
                WAIT: begin // extra cycle needed to perform sync reads
                    state <= WRITE;
                end
                WRITE: begin    // write data: previous or padded value
                    if(copy_input) begin
                        output_data <= input_data;
                    end else begin
                        output_data <= pad_value;
                    end

                    output_w_en <= 1;
                    state <= NEXT;
                end
                NEXT: begin
                    output_addr <= output_addr + 1;

                    // only advance input address when actual input activations
                    // are copied
                    if(copy_input)
                        input_addr <= input_addr + 1;

                    // advance channel counter
                    if(channel < input_channels - 1) begin
                        channel <= channel + 1;
                        state <= CHECK_POS;
                    end else begin
                        channel <= 0;
                        
                        // advance width counter
                        if(out_x < output_width - 1) begin
                            out_x <= out_x + 1;
                            state <= CHECK_POS;
                        end else begin
                            out_x <= 0;

                            // advance height counter
                            if(out_y < output_height - 1) begin
                                out_y <= out_y + 1;
                                state <= CHECK_POS;
                            end else begin
                                state <= DONE;
                            end
                        end
                    end
                end
                DONE: begin // output done signal
                    done <= 1;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
