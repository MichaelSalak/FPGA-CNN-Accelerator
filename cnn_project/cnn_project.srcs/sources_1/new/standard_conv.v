`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/04/2026 11:57:32 PM
// Design Name: 
// Module Name: standard_conv
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


// only 1 standard convolution occurs in ecto-trigger inference datapath, so 
// dimensions can be hardcoded
// will remain idle for most of inference: may be worth to integrate this logic
// into pointwise_conv to reduce area, although this could introduce additional overhead
module standard_conv(input clk, rst, start,
                     input signed [7:0] input_data,
                     input signed [7:0] weight_data,
                     input signed [31:0] bias_data,
                
                     // memory base addresses
                     input [17:0] input_base,
                     input [16:0] weight_base,
                     input [11:0] bias_base,
                     input [17:0] output_base,
                
                     // requantization parameters
                     input signed [31:0] multiplier,
                     input signed [7:0] shift,
                     input signed [7:0] input_zero_point,
                     input signed [7:0] output_zero_point,
                     input signed [7:0] activation_min,
                     input signed [7:0] activation_max,
                
                     // memory interface, output data, done signal
                     output [17:0] input_addr,
                     output [16:0] weight_addr,
                     output [11:0] bias_addr,
                     output [17:0] output_addr,
                     output reg signed [7:0] output_data,
                     output reg input_r_en,
                     output reg weight_r_en,
                     output reg bias_r_en,
                     output reg output_w_en,
                     output reg done
);
    reg [3:0] state;

    localparam IDLE          = 4'd0,
               READ_BIAS     = 4'd1,
               WAIT_BIAS     = 4'd2,
               INIT_ACC      = 4'd3,
               READ_OPERANDS = 4'd4,
               WAIT_OPERANDS = 4'd5,
               SUB           = 4'd6,  
               MULTIPLY      = 4'd7,
               ADD           = 4'd8,  
               NEXT_CHANNEL  = 4'd9,
               NEXT_KERNEL   = 4'd10,     
               REQUANT       = 4'd11,
               WRITE         = 4'd12,
               NEXT_OUTPUT   = 4'd13,
               DONE          = 4'd14;
    
    // input & output HWC, kernel size, and stride can be hardcoded to simplify logic
    localparam INPUT_HEIGHT    = 120;
    localparam INPUT_WIDTH     = 160;
    localparam INPUT_CHANNELS  = 3;
    localparam OUTPUT_HEIGHT   = 60;
    localparam OUTPUT_WIDTH    = 80;
    localparam OUTPUT_CHANNELS = 8;
    
    localparam INPUT_ROW_STRIDE   = 480;    // 160 * 3 channels
    localparam INPUT_COL_STRIDE   = 3;      // 3 channels
    localparam OUTPUT_COL_STEP    = 6;      // stride 2 * 3 channels
    localparam OUTPUT_ROW_STEP    = 960;    // stride 2 * 480 (row stride)
    localparam WEIGHTS_PER_FILTER = 27;     // 3x3x3
    
    localparam KERNEL_SIZE     = 3;
    localparam STRIDE          = 2;
    localparam PAD_TOP         = 0;
    localparam PAD_LEFT        = 0;
    localparam PAD_BOTTOM      = 1;
    localparam PAD_RIGHT       = 1;

    // current output coordinates, input + output channel, kernel coordinates
    reg [15:0] out_x, out_y;
    reg [15:0] out_channel;
    reg [15:0] in_channel;
    reg [1:0] kx, ky;
    
    // starting address of the current output pixel row, corresponding to channel 0
    // allows new output row to be reached without carrying over horizontal offset
    reg [17:0] row_base_addr;

    // starting address of the current output pixel in current output row, 
    // corresponding to channel 0
    // allows next pixel to be reached without carrying over channel offset
    reg [17:0] pixel_base_addr;

    // starting address for the current output pixel and channel
    // allows next window to be reached after completing 1 kernel
    reg [17:0] window_base_addr;
    
    // registers to acquire current addresses
    reg [17:0] input_addr_reg, output_addr_reg;
    reg [16:0] weight_addr_reg;
    reg [11:0] bias_addr_reg;

    // connect address registers to output ports
    assign input_addr  = input_addr_reg;
    assign weight_addr = weight_addr_reg;
    assign bias_addr   = bias_addr_reg;
    assign output_addr = output_addr_reg;
    
    // logical input coordinates for padding detection
    // CANNOT be negative due to this particular operation only padding down and right
    reg [8:0] in_x, in_y;
    reg [8:0] pixel_x, row_y;
    
    // only pad down and right in this particular convolution
    wire padding_position = (in_y >= INPUT_HEIGHT) || (in_x >= INPUT_WIDTH);
    
    reg signed [8:0] corrected_input;   // corrected activation, registered in SUB
    reg signed [16:0] product;  // 17 bit result from a 9 bit and 8 bit input
    reg signed [31:0] acc;

    // requantization parameters
    reg requant_start;
    wire requant_done;
    wire signed [7:0] requant_result;

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
                   .done(requant_done));

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            out_x <= 0;
            out_y <= 0;
            out_channel <= 0;
            in_channel <= 0;
            kx <= 0;
            ky <= 0;
            input_addr_reg <= 0;
            weight_addr_reg <= 0;
            bias_addr_reg <= 0;
            output_addr_reg <= 0;
            corrected_input <= 0;
            product <= 0;
            acc <= 0;
            output_data <= 0;
            input_r_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            output_w_en <= 0;
            requant_start <= 0;
            done <= 0;
        end else begin
            // default values
            input_r_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            output_w_en <= 0;
            requant_start <= 0;
            done <= 0;
            
            case(state)
                IDLE: begin
                    if(start) begin // reset counters, addresses, read enables
                        out_x <= 0;
                        out_y <= 0;              
                        out_channel <= 0;
                        in_channel <= 0;              
                        kx <= 0;
                        ky <= 0;               
                        row_base_addr <= input_base;
                        pixel_base_addr <= input_base;
                        window_base_addr <= input_base;               
                        input_addr_reg <= input_base;
                        weight_addr_reg <= weight_base;
                        bias_addr_reg <= bias_base;
                        output_addr_reg <= output_base;          
                        pixel_x <= 0;
                        row_y <= 0;
                        in_x <= 0;
                        in_y <= 0; 
                        state <= READ_BIAS;
                    end
                end
                READ_BIAS: begin    // prepare bias to be read
                    bias_addr_reg <= bias_base + out_channel;
                    bias_r_en <= 1;
                    state <= WAIT_BIAS;
                end
                WAIT_BIAS: begin    // extra cycle needed to perform sync reads
                    state <= INIT_ACC;
                end
                INIT_ACC: begin // init acc to read bias value
                    // reset address counters, kernel pos, and input ch each output ch
                    acc <= bias_data;

                    in_channel <= 0;
                    kx <= 0;
                    ky <= 0;       
                    input_addr_reg <= window_base_addr;
                    weight_addr_reg <= weight_base + out_channel * 27;
                    in_x <= pixel_x;
                    in_y <= row_y;
                
                    state <= READ_OPERANDS;
                end
                READ_OPERANDS: begin    // prepare operands to be read
                    // padded position contributes nothing to acc, skip compute steps
                    if(padding_position) begin 
                        // update addresses to skip unused input channels
                        input_addr_reg <= input_addr_reg + 2;
                        weight_addr_reg <= weight_addr_reg + 2;
                        state <= NEXT_KERNEL;
                    end else begin
                        input_r_en <= 1;
                        weight_r_en <= 1;
                        state <= WAIT_OPERANDS;
                    end 
                end
                WAIT_OPERANDS: begin    // extra cycle needed to perform sync reads
                    state <= SUB;
                end
                SUB: begin  // subtract input zero point from input
                    corrected_input <= $signed({input_data[7], input_data}) -
                                       $signed({input_zero_point[7], input_zero_point});
                    state <= MULTIPLY;
                end
                MULTIPLY: begin // multiply input + weight values
                    product <= corrected_input * weight_data;
                    state <= ADD;
                end
                ADD: begin   
                    // acc products for all kernel pos and output ch for current pixel
                    acc <= acc + product;
                    state <= NEXT_CHANNEL;
                end
                NEXT_CHANNEL: begin // update addresses for next channel
                    if(in_channel < 2) begin    // next channel 
                        in_channel <= in_channel + 1;
                        input_addr_reg <= input_addr_reg + 1;
                        weight_addr_reg <= weight_addr_reg + 1;
                
                        state <= READ_OPERANDS;
                    end else begin
                        in_channel <= 0;    // next kernel
                        state <= NEXT_KERNEL;
                    end
                end
                NEXT_KERNEL: begin  // update addresses for next kernel
                    if(kx < 2) begin
                        kx <= kx + 1;
                        
                        // previous address is at channel 2
                        // next kernel position starts at channel 0
                        input_addr_reg <= input_addr_reg + 1;
                        weight_addr_reg <= weight_addr_reg + 1;
                        in_x <= in_x + 1;
                
                        state <= READ_OPERANDS;
                    end else if(ky < 2) begin
                        ky <= ky + 1;
                        kx <= 0;
                
                        // current position: column 2, channel 2
                        // next position: next row, column 0, channel 0
                        input_addr_reg <= input_addr_reg + INPUT_ROW_STRIDE - 8;
                        weight_addr_reg <= weight_addr_reg + 1;
                        in_x <= pixel_x;
                        in_y <= in_y + 1;
                
                        state <= READ_OPERANDS;
                    end else begin
                        requant_start <= 1;
                        state <= REQUANT;
                    end
                end
                REQUANT: begin  // quantize accumulator
                    if(requant_done) begin
                        output_data <= requant_result;
                        state <= WRITE;
                    end
                end
                WRITE: begin // prepare result to be written
                    output_w_en <= 1;
                    state <= NEXT_OUTPUT;
                end
                NEXT_OUTPUT: begin  // update output channel + pixel
                    if(out_channel < 7) begin   // next output channel, same pixel
                        out_channel <= out_channel + 1;
                        bias_addr_reg <= bias_addr_reg + 1;
                        output_addr_reg <= output_addr_reg + 1;
                
                        state <= READ_BIAS;
                    end else begin  // all 8 output channels completed
                        out_channel <= 0;         
                        bias_addr_reg <= bias_base;
                        output_addr_reg <= output_addr_reg + 1;
                        if(out_x < OUTPUT_WIDTH - 1) begin
                            // next output column
                            out_x <= out_x + 1;   
                            pixel_base_addr <= pixel_base_addr + OUTPUT_COL_STEP;        
                            window_base_addr <= pixel_base_addr + OUTPUT_COL_STEP;
                            pixel_x <= pixel_x + 2;
                
                            state <= READ_BIAS;
                        end else if (out_y < OUTPUT_HEIGHT - 1) begin
                            // next output row
                            out_x <= 0;
                            out_y <= out_y + 1;
                
                            row_base_addr <= row_base_addr + OUTPUT_ROW_STEP;      
                            pixel_base_addr <= row_base_addr + OUTPUT_ROW_STEP;
                            window_base_addr <= row_base_addr + OUTPUT_ROW_STEP;
                            pixel_x <= 0;
                            row_y <= row_y + 2;
                
                            state <= READ_BIAS;
                        end else begin
                            state <= DONE;
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
