`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/21/2026 09:56:24 PM
// Design Name: 
// Module Name: activation_router
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

// routes activation memory requests between one active functional unit
// and three independent single-read/single-write-port activation buffers
// buffer encoding: 0=A, 1=B, 2=C; 3=invalid
module activation_router #(parameter [2:0] OP_CONV = 3'd0,
                           parameter [2:0] OP_ADD  = 3'd1,
                           parameter [2:0] OP_PAD  = 3'd2,
                           parameter [2:0] OP_MEAN = 3'd3,
                           parameter [2:0] OP_FC   = 3'd4)
                          (input [2:0] opcode,
                           input [1:0] input_buffer,
                           input [1:0] input2_buffer,
                           input [1:0] output_buffer,
                        
                           // unified convolution activation interface
                           input [17:0] conv_input_addr,
                           input conv_input_r_en,
                           output signed [7:0] conv_input_data,
                           input [17:0] conv_output_addr,
                           input signed [7:0] conv_output_data,
                           input conv_output_w_en,
                        
                           // residual add activation interfaces (two independent reads)
                           input [17:0] add_input_a_addr,
                           input add_input_a_r_en,
                           output signed [7:0] add_input_a_data,
                           input [17:0] add_input_b_addr,
                           input add_input_b_r_en,
                           output signed [7:0] add_input_b_data,
                           input [17:0] add_output_addr,
                           input signed [7:0] add_output_data,
                           input add_output_w_en,
                        
                           // pad activation interface
                           input [17:0] pad_input_addr,
                           input pad_input_r_en,
                           output signed [7:0] pad_input_data,
                           input [17:0] pad_output_addr,
                           input signed [7:0] pad_output_data,
                           input pad_output_w_en,
                        
                           // mean activation interface
                           input [17:0] mean_input_addr,
                           input mean_input_r_en,
                           output signed [7:0] mean_input_data,
                           input [17:0] mean_output_addr,
                           input signed [7:0] mean_output_data,
                           input mean_output_w_en,
                        
                           // fully connected activation interface (only reads)
                           input [17:0] fc_input_addr,
                           input fc_input_r_en,
                           output signed [7:0] fc_input_data,
                        
                           // activation memory A
                           output reg [17:0] a_r_addr,
                           output reg a_r_en,
                           input signed [7:0] a_r_data,
                           output reg [17:0] a_w_addr,
                           output reg signed [7:0] a_w_data,
                           output reg a_w_en,
                        
                           // activation memory B
                           output reg [17:0] b_r_addr,
                           output reg b_r_en,
                           input signed [7:0] b_r_data,
                           output reg [17:0] b_w_addr,
                           output reg signed [7:0] b_w_data,
                           output reg b_w_en,
                        
                            // activation memory C
                           output reg [17:0] c_r_addr,
                           output reg c_r_en,
                           input signed [7:0] c_r_data,
                           output reg [17:0] c_w_addr,
                           output reg signed [7:0] c_w_data,
                           output reg c_w_en,
                           
                           // external activation loading interface
                           input loader_active,
                           input [17:0] loader_w_addr,
                           input signed [7:0] loader_w_data,
                           input loader_w_en
);
    // first logical read port (all functional units)
    reg [17:0] read1_addr;
    reg read1_en;
    // second logical read port (ADD only)
    reg [17:0] read2_addr;
    reg read2_en;
    // logical write port (all units except FC)
    reg [17:0] write_addr;
    reg signed [7:0] write_data;
    reg write_en;

    always @(*) begin
        read1_addr = 0;
        read1_en = 0;
        read2_addr = 0;
        read2_en = 0;
        write_addr = 0;
        write_data = 0;
        write_en = 0;
        
        case(opcode)
            OP_CONV: begin
                read1_addr = conv_input_addr;
                read1_en = conv_input_r_en;
                write_addr = conv_output_addr;
                write_data = conv_output_data;
                write_en = conv_output_w_en;
            end
            OP_ADD: begin
                read1_addr = add_input_a_addr;
                read1_en = add_input_a_r_en;
                read2_addr = add_input_b_addr;
                read2_en = add_input_b_r_en;
                write_addr = add_output_addr;
                write_data = add_output_data;
                write_en = add_output_w_en;
            end
            OP_PAD: begin
                read1_addr = pad_input_addr;
                read1_en = pad_input_r_en;
                write_addr = pad_output_addr;
                write_data = pad_output_data;
                write_en = pad_output_w_en;
            end
            OP_MEAN: begin
                read1_addr = mean_input_addr;
                read1_en = mean_input_r_en;
                write_addr = mean_output_addr;
                write_data = mean_output_data;
                write_en = mean_output_w_en;
            end
            OP_FC: begin
                read1_addr = fc_input_addr;
                read1_en = fc_input_r_en;
            end
            default: begin end
        endcase
    end

    // read port assignment
    always @(*) begin
        a_r_addr = 0; 
        a_r_en = 0;
        b_r_addr = 0; 
        b_r_en = 0;
        c_r_addr = 0; 
        c_r_en = 0;
        
        if(read1_en && !loader_active) begin
            case(input_buffer)
                2'd0: begin 
                    a_r_addr = read1_addr; 
                    a_r_en = 1'b1; 
                end
                2'd1: begin 
                    b_r_addr = read1_addr; 
                    b_r_en = 1'b1; 
                end
                2'd2: begin 
                    c_r_addr = read1_addr; 
                    c_r_en = 1'b1; 
                end
                default: begin end
            endcase
        end
        if(read2_en && !loader_active) begin
            case(input2_buffer)
                2'd0: begin 
                    a_r_addr = read2_addr; 
                    a_r_en = 1'b1; 
                end
                2'd1: begin 
                    b_r_addr = read2_addr; 
                    b_r_en = 1'b1; 
                end
                2'd2: begin 
                    c_r_addr = read2_addr; 
                    c_r_en = 1'b1; 
                end
                default: begin end
            endcase
        end
    end

    // independent write port of selected activation buffer
    always @(*) begin
        a_w_addr = 18'd0; 
        a_w_data = 8'sd0; 
        a_w_en = 1'b0;
        b_w_addr = 18'd0; 
        b_w_data = 8'sd0; 
        b_w_en = 1'b0;
        c_w_addr = 18'd0; 
        c_w_data = 8'sd0; 
        c_w_en = 1'b0;
        
        // prioritze initial activation buffer loading
        if(loader_active) begin
            a_w_addr = loader_w_addr;
            a_w_data = loader_w_data;
            a_w_en = loader_w_en;
        end else if(write_en) begin
            case(output_buffer)
                2'd0: begin 
                    a_w_addr = write_addr; 
                    a_w_data = write_data; 
                    a_w_en = 1'b1; 
                end
                2'd1: begin 
                    b_w_addr = write_addr; 
                    b_w_data = write_data; 
                    b_w_en = 1'b1; 
                end
                2'd2: begin 
                    c_w_addr = write_addr; 
                    c_w_data = write_data; 
                    c_w_en = 1'b1; 
                end
                default: begin end
            endcase
        end
    end

    // return data from the activation buffers
    wire signed [7:0] read1_data = (input_buffer == 2'd0) ? a_r_data :
                                   (input_buffer == 2'd1) ? b_r_data :
                                   (input_buffer == 2'd2) ? c_r_data : 8'sd0;
                                   
    wire signed [7:0] read2_data = (input2_buffer == 2'd0) ? a_r_data :
                                   (input2_buffer == 2'd1) ? b_r_data :
                                   (input2_buffer == 2'd2) ? c_r_data : 8'sd0;

    assign conv_input_data = read1_data;
    assign add_input_a_data = read1_data;
    assign add_input_b_data = read2_data;
    assign pad_input_data = read1_data;
    assign mean_input_data = read1_data;
    assign fc_input_data = read1_data;
    
endmodule
