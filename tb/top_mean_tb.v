`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:53:14 PM
// Design Name: 
// Module Name: top_mean_tb
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

module top_mean_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, start = 0;
    reg [17:0] input_base = 18'd17;
    reg [17:0] output_base = 18'd31;
    reg signed [31:0] multiplier = 32'sd1155693653;
    reg signed [7:0] shift = -8'sd2;

    reg init_w_en = 0;
    reg [17:0] init_w_addr = 0;
    reg signed [7:0] init_w_data = 0;
    reg output_r_en = 0;
    reg [17:0] output_r_addr = 0;
    wire signed [7:0] output_r_data;
    wire done;

    reg [7:0] input_mem [0:25599];
    reg [7:0] expected_mem [0:1279];
    integer i, cycles, failures;

    top_mean dut (
        .clk(clk), .rst(rst), .start(start),
        .input_base(input_base), .output_base(output_base),
        .multiplier(multiplier), .shift(shift),
        .init_w_en(init_w_en), .init_w_addr(init_w_addr),
        .init_w_data(init_w_data),
        .output_r_en(output_r_en), .output_r_addr(output_r_addr),
        .output_r_data(output_r_data), .done(done)
    ); 

    initial begin
        $readmemh("mean_input.mem", input_mem);
        $readmemh("mean_expected.mem", expected_mem);
        failures = 0;

        repeat (4) @(negedge clk);
        rst = 0;

        // Initialize all 25,600 bytes. Drive on falling edges so
        // the memory captures every byte at the following rising edge.
        for (i = 0; i < 25600; i = i + 1) begin
            @(negedge clk);
            init_w_en = 1;
            init_w_addr = input_base + i;
            init_w_data = input_mem[i];
        end
        // IMPORTANT: let the final byte be written before disabling enable.
        @(negedge clk);
        init_w_en = 0;
        $display("Initialized 25600 input bytes");

        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;

        cycles = 0;
        while (done !== 1'b1 && cycles < 250000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (done !== 1'b1) begin
            $display("FAIL: MEAN timeout after %0d cycles", cycles);
            $finish;
        end
        $display("MEAN finished after %0d cycles", cycles);

        // Read the synchronous output memory, one byte at a time.
        for (i = 0; i < 1280; i = i + 1) begin
            @(negedge clk);
            output_r_en = 1;
            output_r_addr = output_base + i;
            @(posedge clk);
            #1;
            if (output_r_data !== expected_mem[i]) begin
                failures = failures + 1;
                if (failures <= 25)
                    $display("FAIL channel=%0d expected=%0d (0x%02h) got=%0d (0x%02h)",
                        i, $signed(expected_mem[i]), expected_mem[i],
                        $signed(output_r_data), output_r_data);
            end
        end
        @(negedge clk);
        output_r_en = 0;

        if (failures == 0)
            $display("PASS: all 1280 MEAN outputs match fixed-point reference");
        else
            $display("FAIL: %0d / 1280 MEAN outputs mismatched", failures);
        $finish;
    end
endmodule
