`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 09:59:52 PM
// Design Name: 
// Module Name: top_conv_standard_tb
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

module top_conv_standard_tb;
    localparam INPUT_HEIGHT  = 120;
    localparam INPUT_WIDTH   = 160;
    localparam INPUT_CHANNELS = 3;
    localparam OUTPUT_HEIGHT = 60;
    localparam OUTPUT_WIDTH  = 80;
    localparam OUTPUT_CHANNELS = 8;
    localparam INPUT_SIZE = INPUT_HEIGHT * INPUT_WIDTH * INPUT_CHANNELS;
    localparam OUTPUT_SIZE = OUTPUT_HEIGHT * OUTPUT_WIDTH * OUTPUT_CHANNELS;

    reg clk;
    reg rst;
    reg start;

    // buffer A initialization
    reg init_w_en;
    reg [17:0] init_w_addr;
    reg signed [7:0] init_w_data;

    // buffer B output reads
    reg output_r_en;
    reg [17:0] output_r_addr;
    wire signed [7:0] output_r_data;

    wire done;

    integer y, x, c;
    integer addr;
    integer value;
    integer i;
    integer cycles;
    integer output_file;
    
    reg [7:0] input_mem [0:57599];

    initial begin
        $readmemh("standard_input.mem", input_mem);      
    end
    
    // expected output values from python reference
    reg signed [7:0] expected_output [0:OUTPUT_SIZE-1];
    
    integer pass_count;
    integer fail_count;
    
    // load expected outputs (one 8-bit hex value per line)
    initial begin
        $readmemh("standard_reference.mem", expected_output);
    end

    localparam MAX_CYCLES = 10000000;

    top_conv_standard dut(.clk(clk),
                          .rst(rst),
                          .start(start),
                          .init_w_en(init_w_en),
                          .init_w_addr(init_w_addr),
                          .init_w_data(init_w_data),
                          .output_r_en(output_r_en),
                          .output_r_addr(output_r_addr),
                          .output_r_data(output_r_data),
                          .done(done));

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst = 1;
        start = 0;

        init_w_en = 0;
        init_w_addr = 0;
        init_w_data = 0;

        output_r_en = 0;
        output_r_addr = 0;

        cycles = 0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // initialize input activation buffer A
        $display("Initializing input buffer...");
        init_w_en = 1;

        for(i = 0; i < INPUT_SIZE; i = i + 1) begin
            @(negedge clk);
            init_w_addr = i;
            init_w_data = input_mem[i];
        end
        
        @(negedge clk);
        init_w_en = 0;
        $display("Input initialization complete.");
        $display("Total input bytes: %0d", INPUT_SIZE);

        // start convolution
        @(negedge clk);
        start = 1;

        @(negedge clk);
        start = 0;

        $display("Starting standard convolution...");

        // wait for completion with timeout
        while(!done && cycles < MAX_CYCLES) begin
            @(negedge clk);
            cycles = cycles + 1;
        end

        if(!done) begin
            $display("ERROR: Convolution timed out.");
            $finish;
        end

        $display("Convolution completed.");
        $display("Total cycles: %0d", cycles);

        // read output activation buffer B and verify
        $display("Verifying output buffer...");
        
        pass_count = 0;
        fail_count = 0;
        
        // enable output memory reads
        @(negedge clk);
        output_r_en = 1;
        
        for(i = 0; i < OUTPUT_SIZE; i = i + 1) begin
            // set address before rising edge
            output_r_addr = i;

            @(posedge clk);
            #1;
        
            // compare actual memory output with reference
            if(output_r_data === expected_output[i]) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
        
                // print first 20 mismatches
                if(fail_count <= 20) begin
                    $display(
                        "FAIL addr=%0d: expected=%0d, actual=%0d",
                        i,
                        $signed(expected_output[i]),
                        $signed(output_r_data)
                    );
                end
            end
            // advance on falling edge to avoid races
            @(negedge clk);
        end
        
        // disable memory reads
        output_r_en = 0;
        output_r_addr = 0;
        
        // verification summary
        $display("-----------------------------------");
        $display("Standard Convolution Verification");
        $display("Total outputs: %0d", OUTPUT_SIZE);
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);
        
        if(fail_count == 0)
            $display("ALL OUTPUTS MATCH!");
        else
            $display("VERIFICATION FAILED!");
        
        $display("-----------------------------------");
        $finish;
    end
endmodule
