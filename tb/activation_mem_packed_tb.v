`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/16/2026 10:03:49 PM
// Design Name: 
// Module Name: activation_mem_packed_tb
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
