`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/27/2026 12:59:50 PM
// Design Name: 
// Module Name: board_top_tb
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

// test complete image loading + inference pipeline
// runs inference twice without reset to test for multiple image support
module board_top_tb;

    localparam IMAGE_SIZE = 57600;
    localparam EXPECTED_RESULT = 8'd249;
    localparam CLK_PERIOD = 10;
    localparam IMAGE_FILE = "img4.mem";

    // DUT inputs
    reg clk;
    reg rst;
    reg start;

    // DUT outputs
    wire busy;
    wire loading;
    wire image_loaded;
    wire done;
    wire error;
    wire [7:0] result;

    // reference image for checking loader writes
    reg [7:0] expected_image [0:IMAGE_SIZE-1];

    // verification counters
    integer write_count;
    integer inference_count;
    integer cycle_count;
    integer inference_start_cycle;
    integer load_start_cycle;
    integer run_number;

    board_top dut (
        .clk(clk),
        .rst(rst),
        .start(start),

        .busy(busy),
        .loading(loading),
        .image_loaded(image_loaded),
        .done(done),
        .error(error),
        .result(result)
    );

    // 100 MHz clock
    initial clk = 1'b0;

    always #(CLK_PERIOD / 2)
        clk = ~clk;

    // load reference image into testbench memory
    // does NOT initialize the DUT activation memory
    initial begin
        $readmemh(IMAGE_FILE, expected_image);
    end

    // monitor loading and inference
    always @(posedge clk) begin
        if (rst) begin
            write_count = 0;
            inference_count = 0;
            cycle_count = 0;
            inference_start_cycle = 0;
            load_start_cycle = 0;
        end else begin
            cycle_count = cycle_count + 1;

            // beginning of image loading sequence
            if (dut.loader_start) begin
                write_count = 0;
                load_start_cycle = cycle_count;

                $display("[%0t] Image loading started",
                         $time);
            end

            // verify each loader write
            if (dut.loader_w_en) begin

                if (!dut.loader_active)
                    $fatal(1, "Write occurred while loader inactive");

                if (write_count >= IMAGE_SIZE)
                    $fatal(1, "Too many image writes");

                // verify sequential destination address
                if (dut.loader_w_addr !== write_count[17:0])
                    $fatal(1,
                        "Address mismatch: expected %0d, got %0d",
                        write_count, dut.loader_w_addr);

                // verify data matches original image
                if (dut.loader_w_data !== expected_image[write_count])
                    $fatal(1,
                        "Data mismatch at address %0d: expected %h, got %h",
                        write_count,
                        expected_image[write_count],
                        dut.loader_w_data);

                write_count = write_count + 1;

                // periodic progress update
                if (write_count % 10000 == 0)
                    $display("[%0t] Loaded %0d / %0d bytes",
                             $time, write_count, IMAGE_SIZE);
            end

            // verify loading completion
            if (dut.loader_done) begin
                if (write_count != IMAGE_SIZE)
                    $fatal(1,
                        "Incorrect write count: expected %0d, got %0d",
                        IMAGE_SIZE, write_count);

                $display("[%0t] Image loading complete",
                         $time);

                $display("  Verified bytes: %0d",
                         write_count);

                $display("  Loading cycles: %0d",
                         cycle_count - load_start_cycle);
            end

            // verify inference starts only after loading
            if (dut.accelerator_start) begin

                if (write_count != IMAGE_SIZE)
                    $fatal(1, "Inference started before image was copied");

                if (!image_loaded)
                    $fatal(1, "Inference started before image_loaded");

                if (loading)
                    $fatal(1, "Inference started while loader active");

                inference_count = inference_count + 1;
                inference_start_cycle = cycle_count;

                $display("[%0t] Inference %0d started",
                         $time, inference_count);
            end

            // ensure loader is inactive throughout inference
            if ((dut.state == 3'd3 ||
                 dut.state == 3'd4) && loading)
                $fatal(1, "Loading and inference overlap");

            // report accelerator execution time
            if (dut.accelerator_done &&
                dut.state == 3'd4) begin

                $display("[%0t] Accelerator finished",
                         $time);

                $display("  Inference cycles: %0d",
                         cycle_count - inference_start_cycle);

                $display("  Raw result: %0d (0x%02h)",
                         dut.accelerator_result,
                         dut.accelerator_result);
            end

            if (error)
                $fatal(1, "Board controller reported an error");
        end
    end

    // execute one complete load + inference sequence
    task run_inference;
        input integer run_id;

        begin
            $display("");
            $display("========================================");
            $display("INFERENCE RUN %0d", run_id);
            $display("========================================");

            // emulate VIO: start remains high
            @(negedge clk);
            start = 1'b1;

            // wait for board controller to accept request
            wait (busy === 1'b1);

            // wait for completion or error
            wait (done === 1'b1 || error === 1'b1);

            @(negedge clk);

            if (error)
                $fatal(1, "Inference run %0d failed", run_id);

            if (result !== EXPECTED_RESULT)
                $fatal(1,
                    "Result mismatch: expected %0d, got %0d",
                    EXPECTED_RESULT, result);

            if (busy)
                $fatal(1, "Board still busy after completion");

            if (write_count != IMAGE_SIZE)
                $fatal(1, "Incorrect final image write count");

            if (inference_count != run_id)
                $fatal(1, "Incorrect inference count");

            $display("  Expected result: %0d (0x%02h)",
                     EXPECTED_RESULT, EXPECTED_RESULT);

            $display("  Actual result:   %0d (0x%02h)",
                     result, result);

            // keep start high to verify edge detection
            repeat (20) @(negedge clk);

            if (busy || inference_count != run_id)
                $fatal(1, "Held start caused repeated execution");

            // verify persistent VIO status
            if (!done || result !== EXPECTED_RESULT)
                $fatal(1, "Completion status or result was not retained");

            // return start low before next execution
            start = 1'b0;

            repeat (5) @(negedge clk);

            $display("RUN %0d: PASS", run_id);
        end
    endtask

    // main test sequence
    initial begin
        rst = 1'b1;
        start = 1'b0;

        // initialize system
        repeat (10) @(negedge clk);
        rst = 1'b0;

        repeat (5) @(negedge clk);

        // verify reset behavior
        if ({busy, loading, image_loaded, done, error} !== 5'b0)
            $fatal(1, "Incorrect status after reset");

        if (result !== 8'd0)
            $fatal(1, "Result not cleared after reset");

        $display("Reset verification: PASS");

        // first execution
        run_inference(1);

        // second execution without resetting accelerator
        run_inference(2);

        $display("");
        $display("========================================");
        $display("ALL BOARD-LEVEL TESTS PASSED");
        $display("Total inference runs: %0d", inference_count);
        $display("========================================");

        $finish;
    end

endmodule

