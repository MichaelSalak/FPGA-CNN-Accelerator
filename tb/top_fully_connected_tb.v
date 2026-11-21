`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:53:14 PM
// Design Name: 
// Module Name: top_fully_connected_tb
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

module top_fully_connected_tb;

    reg clk;
    reg rst;
    reg start;

    // Base addresses
    reg [17:0] input_base;
    reg [16:0] weight_base;
    reg [11:0] bias_base, requant_base;
    
    // Activation buffer initialization
    reg init_w_en;
    reg [17:0] init_w_addr;
    reg signed [7:0] init_w_data;

    // Direct FC result
    wire signed [7:0] result;
    wire done;

    // Test input data
    reg [7:0] input_mem [0:1279];

    // Expected output from Python reference
    localparam signed [7:0] EXPECTED_RESULT = 8'sd61;

    integer i;
    integer cycles;

    // DUT
    top_fully_connected dut (
        .clk(clk),
        .rst(rst),
        .start(start),

        .input_base(input_base),
        .weight_base(weight_base),
        .bias_base(bias_base),
        .requant_base(requant_base),

        .init_w_en(init_w_en),
        .init_w_addr(init_w_addr),
        .init_w_data(init_w_data),

        .result(result),
        .done(done)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // Initialize signals
        rst = 1;
        start = 0;

        input_base = 18'd0;
        weight_base = 17'd0;
        bias_base = 12'd0;
        requant_base = 12'd0;

        init_w_en = 0;
        init_w_addr = 0;
        init_w_data = 0;

        cycles = 0;

        // Load input activations
        $readmemh("fc_input.mem", input_mem);

        // Reset
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Initialize activation buffer A
        $display("Initializing 1280 input activations...");

        for (i = 0; i < 1280; i = i + 1) begin
            @(negedge clk);

            init_w_en = 1;
            init_w_addr = input_base + i;
            init_w_data = input_mem[i];
        end

        // Allow final write to commit
        @(negedge clk);
        init_w_en = 0;

        $display("Initialization complete.");

        // Start fully connected operation
        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        // Wait for completion with timeout
        cycles = 0;

        while (!done && cycles < 20000) begin
            @(negedge clk);
            cycles = cycles + 1;
        end

        if (!done) begin
            $display("FAIL: Timeout waiting for FULLY_CONNECTED");
            $finish;
        end

        $display("FULLY_CONNECTED finished in %0d cycles", cycles);

        // Verify result
        $display("Expected result: %0d (0x%02h)",
                 EXPECTED_RESULT, EXPECTED_RESULT);

        $display("Actual result:   %0d (0x%02h)",
                 result, result);

        if (result === EXPECTED_RESULT) begin
            $display("PASS: FULLY_CONNECTED output matches reference");
        end
        else begin
            $display("FAIL: FULLY_CONNECTED output mismatch");
        end

        $finish;
    end

endmodule
