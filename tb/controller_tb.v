`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/21/2026 06:34:26 PM
// Design Name: 
// Module Name: controller_tb
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

module controller_tb;
    localparam integer NUM_LAYERS = 69;
    localparam integer MAX_CYCLES = 5000;
    localparam signed [7:0] TEST_FC_RESULT = 8'sd20;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1;
    reg start = 1'b0;
    reg conv_done = 1'b0, add_done = 1'b0, pad_done = 1'b0;
    reg mean_done = 1'b0, fc_done = 1'b0;
    wire conv_start, add_start, pad_start, mean_start, fc_start;
    wire [2:0] opcode;
    wire [7:0] result;
    wire done, error;
    reg signed [7:0] fc_result = TEST_FC_RESULT;

    // Only connect signals required for this control-flow test.
    // All unused decoded configuration outputs are intentionally unconnected.
    layer_controller #(.NUM_LAYERS(NUM_LAYERS),
                       .INIT_FILE("layer_config.mem")) dut (
        .clk(clk), .rst(rst), .start(start),
        .conv_done(conv_done), .add_done(add_done), .pad_done(pad_done),
        .mean_done(mean_done), .fc_done(fc_done),
        .fc_result(fc_result),
        .conv_start(conv_start), .add_start(add_start),
        .pad_start(pad_start), .mean_start(mean_start), .fc_start(fc_start),
        .opcode(opcode), .result(result), .done(done), .error(error)
    );

    // Read an independent reference copy of the configuration memory.
    reg [258:0] expected_config [0:NUM_LAYERS-1];
    reg [7:0] expected_lut [0:255];
    reg [7:0] expected_result;
    integer launches = 0;
    integer cycle_count = 0;
    integer remaining = 0;
    reg [2:0] active_opcode = 0;
    reg active = 1'b0;
    reg [4:0] start_vec;
    reg [2:0] expected_opcode;

    initial begin
        $readmemh("layer_config.mem", expected_config);
        $readmemh("logistic_lut.mem", expected_lut);
        expected_result = expected_lut[TEST_FC_RESULT ^ 8'h80] ^ 8'h80;
        $display("Expected final output: 0x%02h (%0d)", expected_result, expected_result);
        repeat (4) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
    end

    // Drive done pulses on falling edges to avoid races with DUT's rising-edge FSM.
    // A single shared responder is sufficient: the controller runs one unit at a time.
    always @(negedge clk) begin
        if (!rst) begin
            conv_done = 0; add_done = 0; pad_done = 0;
            mean_done = 0; fc_done = 0;
            if (active) begin
                if (remaining > 0)
                    remaining = remaining - 1;
                else begin
                    case (active_opcode)
                        3'd0: conv_done = 1;
                        3'd1: add_done = 1;
                        3'd2: pad_done = 1;
                        3'd3: mean_done = 1;
                        3'd4: fc_done = 1;
                        default: $fatal(1, "Unsupported opcode %0d", active_opcode);
                    endcase
                    active = 1'b0;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (!rst) begin
            start_vec = {fc_start, mean_start, pad_start, add_start, conv_start};
            if (start_vec != 0) begin
                if (active) $fatal(1, "New operation launched while previous operation active");
                if ((start_vec & (start_vec - 1'b1)) != 0)
                    $fatal(1, "Multiple functional-unit start signals asserted");
                if (launches >= NUM_LAYERS)
                    $fatal(1, "Too many launches");
                expected_opcode = expected_config[launches][258:256];
                if (opcode !== expected_opcode)
                    $fatal(1, "Layer %0d opcode mismatch: got %0d expected %0d",
                           launches, opcode, expected_opcode);
                if (start_vec !== (5'b00001 << expected_opcode))
                    $fatal(1, "Layer %0d wrong start signal: opcode %0d, start_vec %b",
                           launches, expected_opcode, start_vec);
                if (dut.config_word !== expected_config[launches])
                    $fatal(1, "Layer %0d configuration word mismatch", launches);
                $display("Layer %0d/%0d: opcode=%0d started", launches + 1, NUM_LAYERS, opcode);
                launches = launches + 1;
                active_opcode = opcode;
                active = 1'b1;
                remaining = 2; // complete after two additional falling edges
            end
            cycle_count <= cycle_count + 1;
            if (cycle_count > MAX_CYCLES)
                $fatal(1, "TIMEOUT: controller did not complete");
            if (error)
                $fatal(1, "Controller asserted error");
            if (done) begin
                if (launches != NUM_LAYERS)
                    $fatal(1, "Completed after %0d launches, expected %0d", launches, NUM_LAYERS);
                if (result !== expected_result)
                    $fatal(1, "Final result mismatch: got 0x%02h expected 0x%02h", result, expected_result);
                $display("PASS: %0d operations, LOGISTIC LUT and QUANTIZE correct; result=0x%02h", launches, result);
                $finish;
            end
        end
    end
endmodule

