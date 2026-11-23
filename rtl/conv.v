`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 05:54:00 PM
// Design Name: 
// Module Name: conv
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

// mode: 0 = standard convolution (kernel 1x1 or 3x3),
//       1 = depthwise convolution (depth multiplier 1)
// tensor layout: HWC 
// weight layout:
//   standard/pointwise: [Cout, Kh, Kw, Cin]
//   depthwise:          [1, Kh, Kw, Cout]
module unified_conv(input clk, rst, start,
                    input depthwise_mode,   // determine conv type for addressing
                    input [1:0] kernel_size,       // 1 or 3
                    input stride_2,               // 0 -> 1, 1 -> 2
                    input [1:0] pad_top, pad_left,
                    input [6:0] input_height, 
                    input [7:0] input_width, 
                    input [10:0] input_channels,
                    input [5:0] output_height, 
                    input [6:0] output_width, 
                    input [10:0] output_channels,
                    input [17:0] input_base, output_base,
                    input [16:0] weight_base,
                    input [11:0] bias_base, requant_base,
                    // precomputed for HWC input, in units of int8 elements:
                    // input_row_stride = input_width * input_channels
                    // output_col_step  = stride * input_channels
                    // output_row_step  = stride * input_row_stride
                    input [12:0] input_row_stride, 
                    input [10:0] output_col_step, 
                    input [12:0] output_row_step,
                    input signed [7:0] input_data, weight_data,
                    input signed [31:0] bias_data,                
                    input signed [31:0] multiplier,
                    input signed [7:0] shift,                  
                    input signed [7:0] input_zero_point, output_zero_point,
                    input signed [7:0] activation_min, activation_max,
                    output [17:0] input_addr, output_addr,
                    output [16:0] weight_addr,
                    output [11:0] bias_addr, requant_addr,
                    output reg signed [7:0] output_data,
                    output reg input_r_en, weight_r_en, bias_r_en, 
                    output reg requant_r_en, output_w_en,
                    output reg done
);
    reg [4:0] state;

    localparam [4:0] IDLE          = 0, 
                     READ_BIAS     = 1, 
                     WAIT_BIAS     = 2,
                     INIT_ACC      = 3,
                     READ_OPERANDS = 4,
                     WAIT_OPERANDS = 5, 
                     SUB           = 6, 
                     MULTIPLY      = 7,
                     ACC           = 8, 
                     ADVANCE       = 9, 
                     REQUANT       = 10,
                     WRITE         = 11, 
                     NEXT          = 12, 
                     DONE          = 13;
     
    reg [6:0] out_x;   // output pixel index
    reg [5:0] out_y;  
    reg [10:0] out_ch, in_ch; // output and input channels
    reg [1:0] kx, ky;   // kernel index
    
    // input coordinates where current convolution window begins
    reg signed [8:0] origin_x;
    reg signed [7:0] origin_y;   
    
    // coordinates of current element within window
    // logical_x = origin_x + kx, same for y
    reg signed [8:0] logical_x;
    reg signed [7:0] logical_y;
    
    // row/pixel/kernel bases are updated incrementally via counters
    reg [17:0] row_base, pixel_base, kernel_row_base;
    
    // starting weight address for current output channel
    reg [16:0] filter_weight_base;
    
    // registers for storing new address values
    reg [17:0] input_addr_r, output_addr_r;
    reg [16:0] weight_addr_r; 
    reg [11:0] bias_addr_r;
    
    reg signed [8:0] corrected_input;
    reg signed [16:0] product;
    reg signed [31:0] acc;
    
    reg requant_start;
    wire requant_done;
    wire signed [7:0] requant_result;
    
    // determine whether current logical input coordinates are out of bounds
    // indicate need for padding if so
    wire padded = logical_x < 0 || logical_y < 0 ||
        logical_x >= $signed({1'b0,input_width}) ||
        logical_y >= $signed({1'b0,input_height});
        
    // determine offsets based on padding amount (0,1,2)
    wire [17:0] row_stride_ext = {5'd0, input_row_stride};
    wire [17:0] channels_ext   = {7'd0, input_channels};
    
    wire [17:0] top_offset = (pad_top == 2) ? (row_stride_ext << 1) :
                             (pad_top == 1) ? row_stride_ext : 18'd0;
    
    wire [17:0] left_offset = (pad_left == 2) ? (channels_ext << 1) :
                              (pad_left == 1) ? channels_ext : 18'd0;
        
    // intial window address, including padding                           
    wire [17:0] start_window = input_base - top_offset - left_offset;
    
    // fix channel count to 1 for depthwise
    wire [10:0] channel_count = depthwise_mode ? 11'd1 : input_channels;
    
    assign input_addr = input_addr_r;
    assign output_addr = output_addr_r;
    assign weight_addr = weight_addr_r;
    assign bias_addr = bias_addr_r;
    assign requant_addr = requant_base + {1'b0, out_ch};

    requantize req(.clk(clk),
                   .rst(rst),
                   .start(requant_start),
                   .double_rounding(depthwise_mode),
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
            out_ch <= 0; 
            in_ch <= 0;
            kx <= 0; 
            ky <= 0;
            origin_x <= 0; 
            origin_y <= 0;
            logical_x <= 0; 
            logical_y <= 0;
            row_base <= 0; 
            pixel_base <= 0;
            kernel_row_base <= 0;
            input_addr_r <= 0; 
            output_addr_r <= 0;
            weight_addr_r <= 0; 
            filter_weight_base <= 0;
            bias_addr_r <= 0;
            corrected_input <= 0; 
            product <= 0; 
            acc <= 0;
            requant_start <= 0; 
            output_data <= 0;
            input_r_en <= 0; 
            weight_r_en <= 0;
            bias_r_en <= 0; 
            requant_r_en <= 0;
            output_w_en <= 0; 
            done <= 0;
        end else begin
            // default values
            input_r_en <= 0;
            weight_r_en <= 0;
            bias_r_en <= 0;
            requant_r_en <= 0;
            output_w_en <= 0;
            requant_start <= 0;
            done <= 0;
            
            case(state)
                IDLE: begin
                    if(start) begin // reset counters, addresses, check bounds
                        out_x <= 0; out_y <= 0; out_ch <= 0; in_ch <= 0;
                        kx <= 0; ky <= 0;
                        row_base <= start_window;
                        pixel_base <= start_window;
                        kernel_row_base <= start_window;
                        input_addr_r <= start_window;
                        output_addr_r <= output_base;
                        weight_addr_r <= weight_base;
                        filter_weight_base <= weight_base;
                        bias_addr_r <= bias_base;
                        origin_x <= -$signed({7'd0,pad_left});
                        origin_y <= -$signed({6'd0,pad_top});
                        logical_x <= -$signed({7'd0,pad_left});
                        logical_y <= -$signed({6'd0,pad_top});
                        if(input_height != 0 && input_width != 0 &&
                            input_channels != 0 && output_height != 0 &&
                            output_width != 0 && output_channels != 0 &&
                            (kernel_size == 1 || kernel_size == 3) &&
                            (!depthwise_mode || input_channels == output_channels))
                            state <= READ_BIAS;
                        else
                            state <= DONE; // invalid configuration: no writes
                    end
                end
                READ_BIAS: begin    // prepare bias to be read
                    bias_addr_r <= bias_base + out_ch;
                    bias_r_en <= 1;
                    requant_r_en <= 1;  // fetch requant values simultaneously
                    state <= WAIT_BIAS;
                end
                WAIT_BIAS: begin    // extra cycle needed to perform sync read
                    state <= INIT_ACC;
                end
                INIT_ACC: begin // initialize acc with bias
                    acc <= bias_data;   
                    
                    // reset channel and kernel counters
                    in_ch <= 0; kx <= 0; ky <= 0;
                        
                    // alter kernel and input addressing for depthwise 
                    kernel_row_base <= pixel_base + 
                                       (depthwise_mode ? out_ch : 16'd0);
                    input_addr_r <= pixel_base + 
                                    (depthwise_mode ? out_ch : 16'd0);
                                    
                    weight_addr_r <= filter_weight_base;
                    logical_x <= origin_x;
                    logical_y <= origin_y;
                    state <= READ_OPERANDS;
                end
                READ_OPERANDS: begin    // prepare operands to be read
                    // padded inputs = input zero point, so product will be 
                    // "zero": current input computations can be skipped
                    if(padded)
                        state <= ADVANCE;
                    else begin
                        input_r_en <= 1;
                        weight_r_en <= 1;
                        state <= WAIT_OPERANDS;
                    end      
                end
                WAIT_OPERANDS: begin  // extra cycle needed to perform sync reads
                    state <= SUB;
                end
                SUB: begin  // subtract input zero point from input
                    corrected_input <= $signed(input_data) - 
                                       $signed(input_zero_point);
                    state <= MULTIPLY;
                end
                MULTIPLY: begin // multiply read input with weight 
                    product <= corrected_input * weight_data;
                    state <= ACC;
                end
                ACC: begin  // accumulate products
                    acc <= acc + product;
                    state <= ADVANCE;
                end
                ADVANCE: begin  // advance kernel + address counters
                    // next input channel (if applicable)
                    if(in_ch + 1 < channel_count) begin
                        in_ch <= in_ch + 1'b1;
                        input_addr_r <= input_addr_r + 1'b1;
                        weight_addr_r <= weight_addr_r + 1'b1;
                        state <= READ_OPERANDS;
                    // next kernel col
                    end else if(kx + 1 < kernel_size) begin
                        in_ch <= 0;
                        kx <= kx + 1'b1;
                        
                        // previous address is at last input channel (standard),
                        // or the sole channel (depthwise)
                        input_addr_r <= input_addr_r +
                                        (depthwise_mode ? input_channels : 18'd1);
                        weight_addr_r <= weight_addr_r +
                                         (depthwise_mode ? output_channels : 16'd1);
                        logical_x <= logical_x + 1;
                        state <= READ_OPERANDS;
                    // next kernel row
                    end else if(ky + 1 < kernel_size) begin
                        in_ch <= 0; 
                        kx <= 0; 
                        ky <= ky + 1'b1;
                        kernel_row_base <= kernel_row_base + input_row_stride;
                        input_addr_r <= kernel_row_base + input_row_stride;
                        weight_addr_r <= weight_addr_r +
                                         (depthwise_mode ? output_channels : 16'd1);
                        logical_x <= origin_x;
                        logical_y <= logical_y + 1;
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
                WRITE: begin    // prepare result to be written
                    output_w_en <= 1;
                    state <= NEXT;
                end
                NEXT: begin // advance output counters
                    output_addr_r <= output_addr_r + 1'b1;
                    // next output channel
                    if(out_ch + 1 < output_channels) begin
                        out_ch <= out_ch + 1'b1;
                        // for standard conv the last weight visited is the last
                        // entry of the filter; next filter begins at +1
                        // for depthwise, channel is innermost in weight layout
                        filter_weight_base <= depthwise_mode ?
                            filter_weight_base + 1'b1 : weight_addr_r + 1'b1;
                        state <= READ_BIAS;
                    end else begin
                        out_ch <= 0;
                        filter_weight_base <= weight_base;
                        // next col
                        if(out_x + 1 < output_width) begin
                            out_x <= out_x + 1'b1;
                            pixel_base <= pixel_base + output_col_step;
                            origin_x <= origin_x + (stride_2 ? 9'sd2 : 9'sd1);
                            state <= READ_BIAS;
                        // next row
                        end else if(out_y + 1 < output_height) begin
                            out_x <= 0;
                            out_y <= out_y + 1'b1;
                            row_base <= row_base + output_row_step;
                            pixel_base <= row_base + output_row_step;
                            origin_x <= -$signed({7'd0,pad_left});
                            origin_y <= origin_y + (stride_2 ? 8'sd2 : 8'sd1);
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
