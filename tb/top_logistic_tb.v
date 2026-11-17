`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:53:14 PM
// Design Name: 
// Module Name: top_logistic_tb
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

module top_logistic_tb;

    reg clk;
    reg signed [7:0] input_data;
    wire signed [7:0] result;

    // TFLite reference LUT
    reg signed [7:0] expected_lut [0:255];

    integer i;
    integer pass_count;
    integer fail_count;

    // DUT
    top_logistic dut (
        .clk(clk),
        .input_data(input_data),
        .result(result)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        input_data = 0;
        pass_count = 0;
        fail_count = 0;

        // Load reference LUT generated from TFLite
        $readmemh("logistic_lut.mem", expected_lut);

        repeat (2) @(posedge clk);

        $display("====================================");
        $display("LOGISTIC EXHAUSTIVE VERIFICATION");
        $display("====================================");

        // Test all 256 possible signed int8 inputs
        for (i = -128; i <= 127; i = i + 1) begin

            // Apply input before rising edge
            @(negedge clk);
            input_data = i;

            // Wait for synchronous ROM read
            @(posedge clk);
            #1;

            // Compare against TFLite reference
            if (result === expected_lut[i + 128]) begin
                pass_count = pass_count + 1;
            end
            else begin
                fail_count = fail_count + 1;

                $display(
                    "FAIL: Input=%0d | Expected=%0d (0x%02h) | Actual=%0d (0x%02h)",
                    i,
                    expected_lut[i + 128],
                    expected_lut[i + 128],
                    result,
                    result
                );
            end

        end

        $display("\n====================================");
        $display("TEST SUMMARY");
        $display("====================================");
        $display("Total tests: %0d", pass_count + fail_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);

        if (fail_count == 0)
            $display("PASS: All 256 LOGISTIC inputs match TFLite");
        else
            $display("FAIL: LOGISTIC verification failed");

        $finish;
    end

endmodule
