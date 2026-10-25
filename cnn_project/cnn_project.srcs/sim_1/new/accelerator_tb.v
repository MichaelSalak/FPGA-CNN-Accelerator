`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/11/2026 10:33:16 PM
// Design Name: 
// Module Name: accelerator_tb
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








module conv_test_tb();
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    wire done;

    /*
    top_pointwise dut(.clk(clk),
                      .rst(rst),
                      .start(start),
                      .done(done));
    */ 
                      
    top_depthwise dut(.clk(clk),
                      .rst(rst),
                      .start(start),
                      .done(done));

    always #5 clk = ~clk;

    initial begin
        #20 rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);

        #30 $finish;
    end
endmodule







module requantize_tb;
    reg clk, rst, start;
    reg signed [31:0] acc, multiplier;
    reg signed [7:0] shift;
    reg signed [7:0] output_zero_point;
    reg signed [7:0] activation_min, activation_max;

    wire signed [7:0] result;
    wire done;

    integer passed = 0;
    integer failed = 0;

    // Device under test
    requantize dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .acc(acc),
        .multiplier(multiplier),
        .shift(shift),
        .output_zero_point(output_zero_point),
        .activation_min(activation_min),
        .activation_max(activation_max),
        .result(result),
        .done(done)
    );

    // 10 ns clock period
    always #5 clk = ~clk;

    // Apply inputs and verify the result
    task run_test;
        input integer test_id;
        input signed [31:0] test_acc;
        input signed [31:0] test_mult;
        input signed [7:0] test_shift;
        input signed [7:0] test_zp;
        input signed [7:0] test_min, test_max;
        input signed [7:0] expected;

        integer cycles;
        begin
            // Apply inputs before rising clock edge
            @(negedge clk);
            acc = test_acc;
            multiplier = test_mult;
            shift = test_shift;
            output_zero_point = test_zp;
            activation_min = test_min;
            activation_max = test_max;
            start = 1;

            // Register inputs in IDLE state
            @(negedge clk);
            start = 0;

            // Wait for computation with timeout
            cycles = 0;
            while (!done && cycles < 10) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            if (!done) begin
                $display("Test %0d: TIMEOUT", test_id);
                failed = failed + 1;
            end
            else if (result !== expected) begin
                $display("Test %0d: FAIL | Expected=%0d, Got=%0d",
                         test_id, expected, result);
                failed = failed + 1;
            end
            else begin
                $display("Test %0d: PASS | Result=%0d",
                         test_id, result);
                passed = passed + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        rst = 1;
        start = 0;

        acc = 0;
        multiplier = 0;
        shift = 0;
        output_zero_point = 0;
        activation_min = -128;
        activation_max = 127;

        repeat(2) @(negedge clk);
        rst = 0;

        // Multiplier 0x40000000 represents ~0.5
        // Multiplier 0x7FFFFFFF represents ~1.0

        // 1. Zero accumulator
        run_test(1, 0, 32'h40000000, 0,
                 0, -128, 127, 0);

        // 2. Positive accumulator: 100 * 0.5 = 50
        run_test(2, 100, 32'h40000000, 0,
                 0, -128, 127, 50);

        // 3. Negative accumulator: -100 * 0.5 = -50
        run_test(3, -100, 32'h40000000, 0,
                 0, -128, 127, -50);

        // 4. Negative shift: 100 * 0.5 / 4 = 12.5
        // Halfway rounding away from zero -> 13
        run_test(4, 100, 32'h40000000, -2,
                 0, -128, 127, 13);

        // 5. Positive shift: (20 << 2) * 0.5 = 40
        run_test(5, 20, 32'h40000000, 2,
                 0, -128, 127, 40);

        // 6. Positive output zero point: 40 + 10 = 50
        run_test(6, 80, 32'h40000000, 0,
                 10, -128, 127, 50);

        // 7. Negative output zero point: 40 - 20 = 20
        run_test(7, 80, 32'h40000000, 0,
                 -20, -128, 127, 20);

        // 8. Upper activation clamp: 100 -> 60
        run_test(8, 200, 32'h40000000, 0,
                 0, -60, 60, 60);

        // 9. Lower activation clamp: -100 -> -60
        run_test(9, -200, 32'h40000000, 0,
                 0, -60, 60, -60);

        // 10. Negative rounding: -100 * 0.5 / 4 = -12.5
        // Halfway rounding away from zero -> -13
        run_test(10, -100, 32'h40000000, -2,
                 0, -128, 127, -13);

        // 11. INT8 upper saturation
        run_test(11, 500, 32'h40000000, 0,
                 0, -128, 127, 127);

        // 12. INT8 lower saturation
        run_test(12, -500, 32'h40000000, 0,
                 0, -128, 127, -128);
                 
        // Additional rounding tests
        // Multiplier = 0.5, shift = -2
        // Effective scale = 0.5 / 4 = 0.125

        // 13. Negative value below halfway
        // -98 * 0.5 / 4 = -12.25 -> -12
        run_test(13, -98, 32'h40000000, -2,
                 0, -128, 127, -12);

        // 14. Negative value exactly halfway
        // -100 * 0.5 / 4 = -12.5 -> -13
        run_test(14, -100, 32'h40000000, -2,
                 0, -128, 127, -13);

        // 15. Negative value above halfway
        // -102 * 0.5 / 4 = -12.75 -> -13
        run_test(15, -102, 32'h40000000, -2,
                 0, -128, 127, -13);

        // 16. Positive value below halfway
        // 98 * 0.5 / 4 = 12.25 -> 12
        run_test(16, 98, 32'h40000000, -2,
                 0, -128, 127, 12);

        // 17. Positive value exactly halfway
        // 100 * 0.5 / 4 = 12.5 -> 13
        run_test(17, 100, 32'h40000000, -2,
                 0, -128, 127, 13);

        // 18. Positive value above halfway
        // 102 * 0.5 / 4 = 12.75 -> 13
        run_test(18, 102, 32'h40000000, -2,
                 0, -128, 127, 13);

        // 19. Negative small value
        // -4 * 0.5 / 4 = -0.5 -> -1
        run_test(19, -4, 32'h40000000, -2,
                 0, -128, 127, -1);

        // 20. Positive small value
        // 4 * 0.5 / 4 = 0.5 -> 1
        run_test(20, 4, 32'h40000000, -2,
                 0, -128, 127, 1);


        $display("--------------------------------");
        $display("Passed: %0d | Failed: %0d", passed, failed);
        $display("--------------------------------");
        $finish;
    end
endmodule






module conv1x1_small_tb();
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    wire done;

    conv1x1_small dut(.clk(clk),
                      .rst(rst),
                      .start(start),
                      .done(done));

    always #5 clk = ~clk;

    initial begin
        #20 rst = 0;

        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);

        #20 $finish;
    end
endmodule
