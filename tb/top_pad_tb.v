`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:53:14 PM
// Design Name: 
// Module Name: top_pad_tb
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

module top_pad_tb;
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1;
    reg start = 0;
    reg [15:0] input_height = 2;
    reg [15:0] input_width = 3;
    reg [15:0] input_channels = 2;
    reg [1:0] pad_top = 0, pad_bottom = 0, pad_left = 0, pad_right = 0;
    reg signed [7:0] pad_value = -8'sd128;
    reg [17:0] input_base = 0, output_base = 0;
    reg init_w_en = 0;
    reg [17:0] init_w_addr = 0;
    reg signed [7:0] init_w_data = 0;
    reg output_r_en = 0;
    reg [17:0] output_r_addr = 0;
    wire signed [7:0] output_r_data;
    wire done;

    localparam INPUT_SIZE = 12;
    reg [7:0] input_mem [0:INPUT_SIZE-1];
    integer i, y, x, c, idx, in_idx;
    integer out_h, out_w, total, failures, total_failures = 0;
    integer cycles;
    reg signed [7:0] expected;

    top_pad dut (
        .clk(clk), .rst(rst), .start(start),
        .input_height(input_height), .input_width(input_width),
        .input_channels(input_channels),
        .pad_top(pad_top), .pad_bottom(pad_bottom),
        .pad_left(pad_left), .pad_right(pad_right),
        .pad_value(pad_value),
        .input_base(input_base), .output_base(output_base),
        .init_w_en(init_w_en), .init_w_addr(init_w_addr),
        .init_w_data(init_w_data),
        .output_r_en(output_r_en), .output_r_addr(output_r_addr),
        .output_r_data(output_r_data), .done(done)
    );

    task run_test;
        input [1:0] top_pad_rows, bottom_pad_rows;
        input [1:0] left_pad_cols, right_pad_cols;
        input [17:0] output_start;
        begin
            @(negedge clk);
            pad_top = top_pad_rows;
            pad_bottom = bottom_pad_rows;
            pad_left = left_pad_cols;
            pad_right = right_pad_cols;
            output_base = output_start;
            out_h = input_height + top_pad_rows + bottom_pad_rows;
            out_w = input_width + left_pad_cols + right_pad_cols;
            total = out_h * out_w * input_channels;
            failures = 0;

            $display("\nTesting PAD top=%0d bottom=%0d left=%0d right=%0d (%0d bytes)",
                     top_pad_rows, bottom_pad_rows, left_pad_cols, right_pad_cols, total);
            start = 1;
            @(negedge clk);
            start = 0;

            // Avoid a simulation that hangs forever if the FSM fails.
            cycles = 0;
            while (done !== 1'b1 && cycles < 2000) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (done !== 1'b1) begin
                $display("ERROR: timeout waiting for done");
                $finish;
            end
            $display("PAD completed in %0d clock cycles", cycles);

            // Synchronous output RAM read: present address before rising edge,
            // then compare after its registered output has settled.
            idx = 0;
            for (y = 0; y < out_h; y = y + 1) begin
                for (x = 0; x < out_w; x = x + 1) begin
                    for (c = 0; c < input_channels; c = c + 1) begin
                        if (y >= top_pad_rows && y < top_pad_rows + input_height &&
                            x >= left_pad_cols && x < left_pad_cols + input_width) begin
                            in_idx = (((y - top_pad_rows) * input_width) +
                                      (x - left_pad_cols)) * input_channels + c;
                            expected = input_mem[in_idx];
                        end else begin
                            expected = pad_value;
                        end

                        @(negedge clk);
                        output_r_en = 1;
                        output_r_addr = output_start + idx;
                        @(posedge clk);
                        #1;
                        if (output_r_data !== expected) begin
                            $display("FAIL addr=%0d (y=%0d,x=%0d,c=%0d): expected=%0d (0x%02h), actual=%0d (0x%02h)",
                                     output_start + idx, y, x, c, expected, expected,
                                     output_r_data, output_r_data);
                            failures = failures + 1;
                        end
                        idx = idx + 1;
                    end
                end
            end
            @(negedge clk);
            output_r_en = 0;
            total_failures = total_failures + failures;
            $display("Result: PASS=%0d FAIL=%0d", total - failures, failures);
        end
    endtask

    initial begin
        $readmemh("pad_input.mem", input_mem);
        repeat (3) @(negedge clk);
        rst = 0;

        // Load all 12 bytes. Do not deassert enable before the final write.
        $display("Initializing activation buffer A...");
        init_w_en = 1;
        for (i = 0; i < INPUT_SIZE; i = i + 1) begin
            @(negedge clk);
            init_w_addr = input_base + i;
            init_w_data = input_mem[i];
        end
        @(negedge clk);
        init_w_en = 0;
        $display("Initialized %0d input bytes", INPUT_SIZE);

        // Same padding patterns as TFLite tensors 3 and 4.
        // Different output bases prevent the tests from overwriting each other.
        run_test(0, 1, 0, 1, 18'd0);    // output: 3 x 4 x 2 = 24
        run_test(1, 1, 0, 1, 18'd64);   // output: 4 x 4 x 2 = 32

        if (total_failures == 0)
            $display("\nALL PAD TESTS PASSED (56/56 bytes)");
        else
            $display("\nPAD TESTS FAILED: %0d mismatches", total_failures);
        $finish;
    end
endmodule
