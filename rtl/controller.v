`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/18/2026 11:49:03 AM
// Design Name: 
// Module Name: controller
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

// initial input should be quantized for operation 0 
// (xor first bit per byte when writing)

// controller for 69 packed 259-bit layer configurations
// reads from config memory to determine current operation and 
module layer_controller #(parameter NUM_LAYERS = 69,
                          parameter INIT_FILE = "layer_config.mem",
                          parameter [2:0] OP_CONV = 3'd0,
                          parameter [2:0] OP_ADD  = 3'd1,
                          parameter [2:0] OP_PAD  = 3'd2,
                          parameter [2:0] OP_MEAN = 3'd3,
                          parameter [2:0] OP_FC   = 3'd4)
                         (input clk, rst, start,
                          input conv_done, add_done, pad_done, mean_done, fc_done,
                          input signed [7:0] fc_result,
                          output conv_start, add_start, pad_start, mean_start, fc_start,
                          output reg [7:0] result,
                          output reg done,
                          output reg error,
                          output [2:0] opcode,
                          output depthwise_mode,
                          output [1:0] kernel_size,
                          output [1:0] input_buffer,
                          output [1:0] output_buffer,
                          output [17:0] input_base,
                          output [17:0] output_base,
                          output [6:0] input_height,
                          output [7:0] input_width,
                          output [10:0] input_channels,
                          output [5:0] output_height,
                          output [6:0] output_width,
                          output [10:0] output_channels,
                          output stride_2,
                          output [1:0] pad_top,
                          output [1:0] pad_bottom,
                          output [1:0] pad_left,
                          output [1:0] pad_right,
                          output [12:0] input_row_stride,
                          output [10:0] output_col_step,
                          output [12:0] output_row_step,
                          output [16:0] weight_base,
                          output [11:0] bias_base,
                          output [11:0] requant_base,
                          output signed [7:0] input_zero_point,
                          output signed [7:0] output_zero_point,
                          output signed [7:0] activation_min,
                          output signed [7:0] activation_max,
                          output [1:0] input2_buffer,
                          output [17:0] input2_base,
                          output signed [7:0] input2_zero_point,
                          output [15:0] element_count
 );
    reg [3:0] state;

    localparam [3:0] IDLE          = 4'd0,
                     READ          = 4'd1,
                     WAIT          = 4'd2,
                     LATCH         = 4'd3,
                     START         = 4'd4,
                     RUN           = 4'd5,
                     LOGISTIC_WAIT = 4'd6,
                     DONE          = 4'd7,
                     ERROR         = 4'd8;
 
    wire [258:0] rom_data;
    wire rom_en;
    reg [6:0] layer_index;
    reg [258:0] config_word;
    
    layer_config #(.CONFIG_WIDTH(259), 
                   .NUM_LAYERS(NUM_LAYERS),
                   .INIT_FILE(INIT_FILE)) 
        config_rom(.clk(clk), 
                   .en(rom_en), 
                   .layer_addr(layer_index),
                   .config_data(rom_data));

    assign rom_en = (state == READ);

    // Config is captured once per operator, then held throughout execution.
    assign opcode = config_word[258:256];
    assign depthwise_mode = config_word[255];
    assign kernel_size = config_word[254:253];
    assign input_buffer = config_word[252:251];
    assign output_buffer = config_word[250:249];
    assign input_base = config_word[248:231];
    assign output_base = config_word[230:213];
    assign input_height = config_word[212:206];
    assign input_width = config_word[205:198];
    assign input_channels = config_word[197:187];
    assign output_height = config_word[186:181];
    assign output_width = config_word[180:174];
    assign output_channels = config_word[173:163];
    assign stride_2 = config_word[162];
    assign pad_top = config_word[161:160];
    assign pad_bottom = config_word[159:158];
    assign pad_left = config_word[157:156];
    assign pad_right = config_word[155:154];
    assign input_row_stride = config_word[153:141];
    assign output_col_step = config_word[140:130];
    assign output_row_step = config_word[129:117];
    assign weight_base = config_word[116:100];
    assign bias_base = config_word[99:88];
    assign requant_base = config_word[87:76];
    assign input_zero_point = config_word[75:68];
    assign output_zero_point = config_word[67:60];
    assign activation_min = config_word[59:52];
    assign activation_max = config_word[51:44];
    assign input2_buffer = config_word[43:42];
    assign input2_base = config_word[41:24];
    assign input2_zero_point = config_word[23:16];
    assign element_count = config_word[15:0];

    wire valid_opcode = (opcode == OP_CONV) || 
                        (opcode == OP_ADD)  ||
                        (opcode == OP_PAD)  || 
                        (opcode == OP_MEAN) ||
                        (opcode == OP_FC);
                        
    wire selected_done = (opcode == OP_CONV) ? conv_done :
                         (opcode == OP_ADD)  ? add_done  :
                         (opcode == OP_PAD)  ? pad_done  :
                         (opcode == OP_MEAN) ? mean_done :
                         (opcode == OP_FC)   ? fc_done   : 1'b0;

    // pulse relevant start signal for 1 cycle when applicable
    assign conv_start = (state == START) && (opcode == OP_CONV);
    assign add_start  = (state == START) && (opcode == OP_ADD);
    assign pad_start  = (state == START) && (opcode == OP_PAD);
    assign mean_start = (state == START) && (opcode == OP_MEAN);
    assign fc_start   = (state == START) && (opcode == OP_FC);

    // get the logistic result after FC operation terminates
    reg signed [7:0] scalar_result;
    wire signed [7:0] logistic_result;

    logistic logistic_inst(.clk(clk),
                           .input_data(scalar_result),
                           .result(logistic_result));

    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            layer_index <= 7'd0;
            config_word <= 259'd0;
            scalar_result <= 8'sd0;
            result <= 8'd0;
            done <= 1'b0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;
            
            case(state)
                IDLE: begin
                    if(start) begin // reset counter and error signal
                        layer_index <= 7'd0;
                        error <= 1'b0;
                        state <= READ;
                    end
                end
                READ: begin  // fetch next layer configuration
                    state <= WAIT;
                end
                WAIT: begin // extra cycle needed to perform sync read
                    state <= LATCH;
                end
                LATCH: begin    // latch the values
                    config_word <= rom_data;
                    state <= START;
                end
                START: begin    // start current operation
                    if(valid_opcode)
                        state <= RUN;
                    else begin
                        error <= 1'b1;
                        state <= ERROR;
                    end
                end
                RUN: begin
                    if(selected_done) begin // wait for op to finish
                        // after fc op (last memory entry), use result
                        // to get logistic value (OP 70)
                        if(layer_index == NUM_LAYERS - 1) begin
                            scalar_result <= fc_result; // schedule read
                            state <= LOGISTIC_WAIT;
                        end else begin
                            layer_index <= layer_index + 7'd1;
                            state <= READ;
                        end
                    end
                end
                LOGISTIC_WAIT: begin // must wait a cycle for sync read
                    state <= DONE;
                end
                DONE: begin   // output final inference result
                    // final quantization op performed via msb xor
                    // (quantize from signed to unsigned) (OP 71)
                    result <= logistic_result ^ 8'h80;
                    done <= 1'b1;
                    state <= IDLE;
                end
                ERROR: begin  // return to idle when invalid opcode 
                    state <= IDLE; 
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
