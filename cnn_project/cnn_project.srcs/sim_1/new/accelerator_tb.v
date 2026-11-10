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
















module top_standard_tb;
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

    top_standard dut(.clk(clk),
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
            $display("Elapsed cycles: %0d", cycles);
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





module top_residual_add_tb;
    localparam integer N = 64;
    localparam integer TIMEOUT_CYCLES = 10000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg start = 1'b0;
    wire done;
    reg [17:0] element_count = N;

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
    localparam signed [31:0] M_A = 32'sh40000000;
    localparam signed [7:0] S_A = 8'sd0;
    localparam signed [31:0] M_B = 32'sh60000000;
    localparam signed [7:0] S_B = 8'sd0;
    localparam signed [31:0] M_OUT = 32'sh40000000;
    localparam signed [7:0] S_OUT = -8'sd3;
    localparam [5:0] LEFT_SHIFT = 6'd4;
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
        .input_a_multiplier(M_A),
        .input_a_shift(S_A),
        .input_b_multiplier(M_B),
        .input_b_shift(S_B),
        .output_multiplier(M_OUT),
        .output_shift(S_OUT),
        .left_shift(LEFT_SHIFT),
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




















module pointwise_conv_tb();
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg init_w_en = 0;
    reg [17:0] init_w_addr = 0;
    reg signed [7:0] init_w_data = 0;
    reg output_r_en = 0;
    reg [17:0] output_r_addr = 0;
    wire [7:0] output_r_data;
    wire done;
                 
    top_pointwise dut(.clk(clk),
                      .rst(rst),
                      .start(start),
                      .init_w_en(init_w_en),
                      .init_w_addr(init_w_addr),
                      .init_w_data(init_w_data),
                      .output_r_en(output_r_en),
                      .output_r_addr(output_r_addr),
                      .output_r_data(output_r_data),
                      .done(done));
    
    always #5 clk = ~clk;
    
    reg signed [7:0] input_values [0:31];

    initial begin
        $readmemh("input_3x3x2.mem", input_values);
    end
    
    integer i;

    initial begin
        #20 rst = 0;
        
        // populate input uram buffer before testing
        for(i = 0; i < 18; i = i + 1) begin
            @(negedge clk);
            init_w_en   = 1;
            init_w_addr = i;
            init_w_data = input_values[i];
        end
            
        @(negedge clk);
        init_w_en = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);
        
        // ensure final write has completed
        @(posedge clk);
        #1;

        // print output memory
        $display("\n========== OUTPUT ==========");

        // iterate across output memory (64 bit words per memory index)
        for(i = 0; i < 5; i = i + 1) begin
            $write("%02h ", dut.activation_b.mem[i]);
        end

        $display("\n======================================");

        $finish;
    end
endmodule





module depthwise_conv_tb();
    reg clk = 0;
    reg rst = 1;
    reg start = 0;
    reg init_w_en = 0;
    reg [17:0] init_w_addr = 0;
    reg signed [7:0] init_w_data = 0;
    reg output_r_en = 0;
    reg [17:0] output_r_addr = 0;
    wire [7:0] output_r_data;
    wire done;
                 
    top_depthwise dut(.clk(clk),
                      .rst(rst),
                      .start(start),
                      .init_w_en(init_w_en),
                      .init_w_addr(init_w_addr),
                      .init_w_data(init_w_data),
                      .output_r_en(output_r_en),
                      .output_r_addr(output_r_addr),
                      .output_r_data(output_r_data),
                      .done(done));
    
    always #5 clk = ~clk;
    
    reg signed [7:0] input_values [0:31];

    initial begin
        $readmemh("input_4x4x2.mem", input_values);
    end
    
    integer i;

    initial begin
        #20 rst = 0;
        
        // populate input uram buffer before testing
        for(i = 0; i < 32; i = i + 1) begin
            @(negedge clk);
            init_w_en   = 1;
            init_w_addr = i;
            init_w_data = input_values[i];
        end
            
        @(negedge clk);
        init_w_en = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        wait(done);
        
        // ensure final write has completed
        @(posedge clk);
        #1;

        // print output memory
        $display("\n========== OUTPUT ==========");

        // iterate across output memory (64 bit words per memory index)
        for(i = 0; i < 4; i = i + 1) begin
            $write("%02h ", dut.activation_b.mem[i]);
        end

        $display("\n======================================");

        $finish;
    end
endmodule





module activation_mem_packed_tb;

    localparam ADDR_WIDTH = 18;
    localparam COUNT = 32768;

    reg clk;
    reg r_en;
    reg w_en;

    reg [ADDR_WIDTH-1:0] r_addr;
    reg [ADDR_WIDTH-1:0] w_addr;

    reg signed [7:0] w_data;
    wire signed [7:0] r_data;

    integer pass_count;
    integer fail_count;
    integer i;

    // DUT
    activation_mem_packed #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .COUNT(COUNT)
    ) dut (
        .clk(clk),
        .r_en(r_en),
        .w_en(w_en),
        .r_addr(r_addr),
        .w_addr(w_addr),
        .w_data(w_data),
        .r_data(r_data)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------
    // Write one INT8 value
    // ---------------------------------------------------------
    task write_byte;
        input [ADDR_WIDTH-1:0] addr;
        input signed [7:0] data;
        begin
            @(negedge clk);

            w_en   = 1;
            w_addr = addr;
            w_data = data;

            @(negedge clk);

            w_en = 0;
        end
    endtask

    // ---------------------------------------------------------
    // Read one INT8 value and compare with expected
    // ---------------------------------------------------------
    task check_byte;
        input [ADDR_WIDTH-1:0] addr;
        input signed [7:0] expected;

        begin
            @(negedge clk);

            r_en   = 1;
            r_addr = addr;

            // Synchronous memory read
            @(posedge clk);
            #1;

            if (r_data === expected) begin
                $display(
                    "PASS: addr=%0d expected=%0d actual=%0d",
                    addr, expected, r_data
                );

                pass_count = pass_count + 1;
            end
            else begin
                $display(
                    "FAIL: addr=%0d expected=%0d actual=%0d",
                    addr, expected, r_data
                );

                fail_count = fail_count + 1;
            end

            @(negedge clk);
            r_en = 0;
        end
    endtask

    // ---------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------
    initial begin

        r_en = 0;
        w_en = 0;

        r_addr = 0;
        w_addr = 0;
        w_data = 0;

        pass_count = 0;
        fail_count = 0;

        repeat (3) @(negedge clk);

        // =====================================================
        // TEST 1: Write eight bytes into one 64-bit word
        // =====================================================

        $display("\nTEST 1: Eight bytes in one word");

        write_byte(0,  8'sd10);
        write_byte(1,  8'sd20);
        write_byte(2,  8'sd30);
        write_byte(3,  8'sd40);
        write_byte(4,  8'sd50);
        write_byte(5,  8'sd60);
        write_byte(6,  8'sd70);
        write_byte(7,  8'sd80);

        check_byte(0, 8'sd10);
        check_byte(1, 8'sd20);
        check_byte(2, 8'sd30);
        check_byte(3, 8'sd40);
        check_byte(4, 8'sd50);
        check_byte(5, 8'sd60);
        check_byte(6, 8'sd70);
        check_byte(7, 8'sd80);

        // =====================================================
        // TEST 2: Word boundary
        // =====================================================

        $display("\nTEST 2: Word boundary");

        write_byte(8,  8'sd90);
        write_byte(9,  8'sd100);
        write_byte(15, 8'sd110);
        write_byte(16, 8'sd120);

        check_byte(7,  8'sd80);
        check_byte(8,  8'sd90);
        check_byte(9,  8'sd100);
        check_byte(15, 8'sd110);
        check_byte(16, 8'sd120);

        // =====================================================
        // TEST 3: Overwrite individual byte
        // =====================================================

        $display("\nTEST 3: Byte overwrite");

        write_byte(3, -8'sd25);

        check_byte(2, 8'sd30);
        check_byte(3, -8'sd25);
        check_byte(4, 8'sd50);

        // =====================================================
        // TEST 4: Signed INT8 values
        // =====================================================

        $display("\nTEST 4: Signed values");

        write_byte(32, -8'sd128);
        write_byte(33, -8'sd1);
        write_byte(34, 8'sd0);
        write_byte(35, 8'sd127);

        check_byte(32, -8'sd128);
        check_byte(33, -8'sd1);
        check_byte(34, 8'sd0);
        check_byte(35, 8'sd127);

        // =====================================================
        // TEST 5: Different word addresses
        // =====================================================

        $display("\nTEST 5: Different memory locations");

        write_byte(100, 8'sd11);
        write_byte(1000, 8'sd22);
        write_byte(10000, 8'sd33);
        write_byte(50000, 8'sd44);

        check_byte(100, 8'sd11);
        check_byte(1000, 8'sd22);
        check_byte(10000, 8'sd33);
        check_byte(50000, 8'sd44);

        // =====================================================
        // TEST 6: Final valid memory address
        // =====================================================

        $display("\nTEST 6: Final address");

        write_byte(262143, -8'sd42);

        check_byte(262143, -8'sd42);

        // =====================================================
        // TEST 7: Simultaneous read and write
        // Different memory words
        // =====================================================

        $display("\nTEST 7: Simultaneous read/write");

        write_byte(200, 8'sd55);

        @(negedge clk);

        r_en = 1;
        w_en = 1;

        r_addr = 200;
        w_addr = 300;
        w_data = 8'sd66;

        @(posedge clk);
        #1;

        if (r_data === 8'sd55) begin
            $display("PASS: Simultaneous read returned correct data");
            pass_count = pass_count + 1;
        end
        else begin
            $display("FAIL: Simultaneous read returned %0d", r_data);
            fail_count = fail_count + 1;
        end

        @(negedge clk);

        r_en = 0;
        w_en = 0;

        check_byte(300, 8'sd66);

        // =====================================================
        // TEST 8: Sequential byte writes
        // =====================================================

        $display("\nTEST 8: Sequential writes");

        for (i = 0; i < 32; i = i + 1) begin
            write_byte(1000 + i, i - 16);
        end

        for (i = 0; i < 32; i = i + 1) begin
            check_byte(1000 + i, i - 16);
        end

        // =====================================================
        // Summary
        // =====================================================

        $display("\n=================================");
        $display("Activation Memory Test Summary");
        $display("=================================");
        $display("PASS: %0d", pass_count);
        $display("FAIL: %0d", fail_count);
        $display("=================================");

        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;

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

