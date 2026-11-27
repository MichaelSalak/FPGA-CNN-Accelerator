`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/27/2026 12:46:45 PM
// Design Name: 
// Module Name: board_top
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


// top level module for connecting desing to the KV260
// includes the image rom, image loader, and accelerator
// *using rom for now, may update to use uart/zynq ps to allow for multiple
// images to be written per bitstream
module board_top(input clk, rst, start,
                 // status outputs for VIO
                 output busy,
                 output loading,
                 output reg image_loaded,
                 output reg done,
                 output reg error,
                 output reg [7:0] result
);
    reg [2:0] state;

    localparam IDLE        = 3'd0,
               LOAD_START  = 3'd1,
               LOAD_WAIT   = 3'd2,
               INFER_START = 3'd3,
               INFER_WAIT  = 3'd4;

    localparam IMAGE_SIZE = 57600;

    // VIO start edge detection
    reg start_d;
    wire start_pulse;

    always @(posedge clk) begin
        if(rst)
            start_d <= 1'b0;
        else
            start_d <= start;
    end

    // pulse start for 1 cycle regardless of high duration
    assign start_pulse = start & ~start_d;

    // image ROM interface
    wire [15:0] rom_addr;
    wire [7:0] rom_data;
    wire rom_r_en;

    // image loader interface
    wire loader_start;
    wire loader_done;
    wire loader_active;

    wire [17:0] loader_w_addr;
    wire signed [7:0] loader_w_data;
    wire loader_w_en;

    // accelerator interface
    wire accelerator_start;
    wire accelerator_done;
    wire accelerator_error;
    wire [7:0] accelerator_result;

    // control signals
    assign loader_start = (state == LOAD_START) && !rst;
    assign accelerator_start = (state == INFER_START) && !rst;

    // status signals
    assign busy = (state != IDLE);
    assign loading = loader_active;

    // initialized input image ROM
    image_rom #(.COUNT(IMAGE_SIZE),
                .ADDR_WIDTH(16),
                .INIT_FILE("img4.mem")) 
       img_rom(.clk(clk),
               .r_en(rom_r_en),
               .addr(rom_addr),
               .data(rom_data));

    // copies image ROM into activation buffer A
    image_loader #(.IMAGE_SIZE(IMAGE_SIZE),
                   .ACT_ADDR_WIDTH(18)) 
        img_loader(.clk(clk),
                   .rst(rst),
                   .start(loader_start),
                   .rom_data(rom_data),
                   .rom_addr(rom_addr),
                   .rom_r_en(rom_r_en),
                   .write_addr(loader_w_addr),
                   .write_data(loader_w_data),
                   .write_en(loader_w_en),
                   .loading(loader_active),
                   .done(loader_done));

    // inference accelerator
    accelerator cnn(.clk(clk),
                    .rst(rst),
                    .start(accelerator_start),
                    .loader_active(loader_active),
                    .loader_w_addr(loader_w_addr),
                    .loader_w_data(loader_w_data),
                    .loader_w_en(loader_w_en && !rst),
                    .done(accelerator_done),
                    .error(accelerator_error),
                    .result(accelerator_result));
            
    // board control FSM
    always @(posedge clk) begin
        if(rst) begin
            state <= IDLE;
            image_loaded <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            result <= 8'd0;
        end else begin
            case(state)
                IDLE: begin
                    if(start_pulse) begin   // reset outputs
                        image_loaded <= 1'b0;
                        done <= 1'b0;
                        error <= 1'b0;
                        result <= 8'd0;
                        state <= LOAD_START;
                    end
                end
                LOAD_START: begin   // begin image loading
                    state <= LOAD_WAIT;
                end
                LOAD_WAIT: begin    // wait for image loading to finish
                    if(loader_done) begin
                        image_loaded <= 1'b1;
                        state <= INFER_START;
                    end
                end
                INFER_START: begin  // begin inference
                    state <= INFER_WAIT;
                end
                INFER_WAIT: begin   // wait for inference to finish
                    if(accelerator_error) begin
                        error <= 1'b1;
                        state <= IDLE;
                    end else if(accelerator_done) begin
                        result <= accelerator_result;
                        done <= 1'b1;
                        state <= IDLE;
                    end
                end
                default: begin
                    state <= IDLE;
                    error <= 1'b1;
                end
            endcase
        end
    end
endmodule
