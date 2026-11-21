`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:53:14 PM
// Design Name: 
// Module Name: top_residual_add_tb
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

module top_residual_add_tb;
    localparam integer N = 64;
    localparam integer TIMEOUT_CYCLES = 10000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg start = 1'b0;
    wire done;
    reg [15:0] element_count = N;

    reg init_a_w_en = 0;
    reg [17:0] init_a_w_addr = 0;
    reg signed [7:0] init_a_w_data = 0;
    reg init_c_w_en = 0;
    reg [17:0] init_c_w_addr = 0;
    reg signed [7:0] init_c_w_data = 0;
    reg output_r_en = 0;
    reg [17:0] output_r_addr = 0;
    wire signed [7:0] output_r_data;

    localparam signed [7:0] Z_A = -8'sd7;
    localparam signed [7:0] Z_B =  8'sd11;
    localparam signed [7:0] Z_OUT = 8'sd3;
    localparam signed [7:0] ACT_MIN = -8'sd128;
    localparam signed [7:0] ACT_MAX =  8'sd127;

    reg [7:0] input_a [0:N-1];
    reg [7:0] input_c [0:N-1];
    reg [7:0] expected [0:N-1];
    integer i;
    integer errors = 0;
    integer cycles = 0;

    top_residual_add dut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .element_count(element_count),
        .init_a_w_en(init_a_w_en),
        .init_a_w_addr(init_a_w_addr),
        .init_a_w_data(init_a_w_data),
        .init_c_w_en(init_c_w_en),
        .init_c_w_addr(init_c_w_addr),
        .init_c_w_data(init_c_w_data),
        .output_r_en(output_r_en),
        .output_r_addr(output_r_addr),
        .output_r_data(output_r_data),
        .input_a_zero_point(Z_A),
        .input_b_zero_point(Z_B),
        .output_zero_point(Z_OUT),
        .activation_min(ACT_MIN),
        .activation_max(ACT_MAX)
    );

    initial begin
        $readmemh("input_a.mem", input_a);
        $readmemh("input_c.mem", input_c);
        $readmemh("expected_b.mem", expected);

        repeat (4) @(negedge clk);
        rst = 0;

        // Both independent input buffers can be initialized in parallel.
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            init_a_w_en = 1;
            init_c_w_en = 1;
            init_a_w_addr = i;
            init_c_w_addr = i;
            init_a_w_data = input_a[i];
            init_c_w_data = input_c[i];
        end
        @(negedge clk);
        init_a_w_en = 0;
        init_c_w_en = 0;
        $display("Loaded %0d elements into each input buffer", N);

        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;

        // Sample done at falling edges, safely after sequential updates.
        cycles = 0;
        while (done !== 1'b1 && cycles < TIMEOUT_CYCLES) begin
            @(negedge clk);
            cycles = cycles + 1;
        end
        if (done !== 1'b1) begin
            $display("FAIL: timeout after %0d cycles", cycles);
            $finish;
        end
        $display("Residual ADD completed after %0d cycles", cycles);

        // Output buffer has a synchronous read: sample after the rising edge.
        for (i = 0; i < N; i = i + 1) begin
            @(negedge clk);
            output_r_en = 1;
            output_r_addr = i;
            @(negedge clk);
            if (output_r_data !== expected[i]) begin
                $display("FAIL [%0d]: A=%0d C=%0d expected=%0d actual=%0d",
                    i, $signed(input_a[i]), $signed(input_c[i]),
                    $signed(expected[i]), $signed(output_r_data));
                errors = errors + 1;
            end else begin
                $display("PASS [%0d]: A=%0d C=%0d output=%0d",
                    i, $signed(input_a[i]), $signed(input_c[i]),
                    $signed(output_r_data));
            end
        end
        output_r_en = 0;
        if (errors == 0)
            $display("ALL %0d TESTS PASSED", N);
        else
            $display("FAILED: %0d / %0d outputs incorrect", errors, N);
        $finish;
    end
endmodule
