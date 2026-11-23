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

// outputs one activation dump file, one progress log, and one summary file
module accelerator_tb;
    parameter integer NUM_LAYERS = 69;
    parameter integer ACT_COUNT = 32768;  // 64-bit words per buffer
    parameter integer INPUT_ELEMENTS = 57600; // number of input INT8 bytes (120x160x3)
    parameter CONFIG_FILE = "layer_config.mem";
    parameter WEIGHTS_FILE = "weights.mem";
    parameter BIAS_FILE = "bias.mem";
    parameter REQUANT_FILE = "requant.mem";
    parameter integer MAX_LAYER_CYCLES = 50000000;
    parameter integer MAX_TOTAL_CYCLES = 1000000000;
    
    parameter INPUT_FILE = "img1.mem"; // one 8-bit hex value per line
    parameter integer STOP_AFTER_LAYER = 0; // 1-based, 0=all

    localparam [2:0] OP_CONV=3'd0, OP_ADD=3'd1, OP_PAD=3'd2,
                     OP_MEAN=3'd3, OP_FC=3'd4;
    localparam integer CAPACITY = ACT_COUNT * 8;
    localparam [3:0] CTRL_RUN = 4'd5; // Update if controller state encoding changes

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst = 1'b1, start = 1'b0;
    wire [7:0] result;
    wire done, error;

    accelerator #(.NUM_LAYERS(NUM_LAYERS), .CONFIG_FILE(CONFIG_FILE),
        .WEIGHTS_FILE(WEIGHTS_FILE), .BIAS_FILE(BIAS_FILE),
        .REQUANT_FILE(REQUANT_FILE), .ACT_COUNT(ACT_COUNT)) dut (
        .clk(clk), .rst(rst), .start(start),
        .result(result), .done(done), .error(error)
    );

    reg [7:0] input_bytes [0:CAPACITY-1];
    integer outputs_fd, progress_fd, summary_fd;
    integer total_cycles = 0, layer_start_cycle = 0, completed = 0;
    integer stop_layer, layer_limit, layer_watchdog;
    integer i, word_idx, byte_idx;
    reg [63:0] packed_word;
    reg [7:0] raw_byte;
    integer signed_byte;
    integer last_layer = -1;
    reg finished = 1'b0;
    reg [2:0] current_opcode;
    reg [1:0] current_buffer;
    reg [17:0] current_base;
    integer current_count;
    integer current_layer;
    integer current_height, current_width, current_channels;

    // Read one byte directly from the packed memory hierarchy. Simulation only.
    task read_activation_byte;
        input integer buffer_id;
        input integer byte_address;
        output reg [7:0] value;
        reg [63:0] word_value;
        begin
            word_value = 64'hxxxxxxxxxxxxxxxx;
            if (byte_address >= 0 && byte_address < CAPACITY) begin
                case (buffer_id)
                    0: word_value = dut.activation_a.mem[byte_address >> 3];
                    1: word_value = dut.activation_b.mem[byte_address >> 3];
                    2: word_value = dut.activation_c.mem[byte_address >> 3];
                    default: word_value = 64'hxxxxxxxxxxxxxxxx;
                endcase
            end
            value = word_value[(byte_address & 7)*8 +: 8];
        end
    endtask

    // Capture the entire output tensor at zero simulation time after final write.
    // Incomplete layer records have no END_LAYER marker and are ignored by checker.
    task dump_layer_output;
        input integer layer_number;
        input [2:0] op;
        input [1:0] buffer_id;
        input integer base;
        input integer count;
        integer j;
        reg [7:0] byte_value;
        begin
            $fdisplay(outputs_fd, "LAYER %0d", layer_number);
            $fdisplay(outputs_fd, "OPCODE %0d", op);
            if (op == OP_FC) begin
                $fdisplay(outputs_fd, "BUFFER SCALAR");
                $fdisplay(outputs_fd, "BASE 0");
                $fdisplay(outputs_fd, "ELEMENTS 1");
                $fdisplay(outputs_fd, "DATA");
                $fdisplay(outputs_fd, "%0d", $signed(dut.fc_result));
            end else begin
                $fdisplay(outputs_fd, "BUFFER %0d", buffer_id);
                $fdisplay(outputs_fd, "BASE %0d", base);
                $fdisplay(outputs_fd, "ELEMENTS %0d", count);
                $fdisplay(outputs_fd, "DATA");
                if (buffer_id > 2 || base < 0 || count < 1 || base + count > CAPACITY) begin
                    $display("ERROR: layer %0d invalid dump region buffer=%0d base=%0d count=%0d capacity=%0d",
                        layer_number, buffer_id, base, count, CAPACITY);
                    $fdisplay(progress_fd, "ERROR layer=%0d invalid output region", layer_number);
                    $fflush(progress_fd);
                    $fatal(1, "Invalid activation output region");
                end
                for (j=0; j<count; j=j+1) begin
                    read_activation_byte(buffer_id, base+j, byte_value);
                    if (^byte_value === 1'bx) begin
                        $display("ERROR: unknown activation layer=%0d index=%0d addr=%0d", layer_number, j, base+j);
                        $fatal(1, "Uninitialized or unknown output activation");
                    end
                    $fdisplay(outputs_fd, "%0d", $signed(byte_value));
                end
            end
            $fdisplay(outputs_fd, "END_LAYER %0d", layer_number);
            $fflush(outputs_fd);
        end
    endtask
    
    // Dump final model output after LOGISTIC and QUANTIZE.
    // Unlike layer activations, the final output is UINT8.
    task dump_final_output;
        begin
            if (^result === 1'bx)
                $fatal(1, "Unknown final inference result");
    
            $fdisplay(outputs_fd, "FINAL_OUTPUT");
            $fdisplay(outputs_fd, "DTYPE UINT8");
            $fdisplay(outputs_fd, "ELEMENTS 1");
            $fdisplay(outputs_fd, "DATA");
            $fdisplay(outputs_fd, "%0d", $unsigned(result));
            $fdisplay(outputs_fd, "END_FINAL_OUTPUT");
    
            $fflush(outputs_fd);
        end
    endtask

    // Number of bytes produced by the completed operation.
    // MEAN output is one value per input channel for global average pooling.
    function integer output_elements;
        input [2:0] op;
        input integer oh, ow, oc, ih, iw, ic;
        input integer pt, pb, pl, pr, add_count;
        begin
            case (op)
                OP_CONV: output_elements = oh * ow * oc;
                OP_ADD:  output_elements = add_count;
                OP_PAD:  output_elements = (ih+pt+pb)*(iw+pl+pr)*ic;
                OP_MEAN: output_elements = ic;
                OP_FC:   output_elements = 1;
                default: output_elements = -1;
            endcase
        end
    endfunction

    // Main execution control and logging.
    initial begin
        stop_layer = STOP_AFTER_LAYER;
        layer_watchdog = MAX_LAYER_CYCLES;
        if ($value$plusargs("STOP_AFTER_LAYER=%d", stop_layer)) begin end
        if ($value$plusargs("MAX_LAYER_CYCLES=%d", layer_watchdog)) begin end
        if (stop_layer < 0 || stop_layer > NUM_LAYERS) $fatal(1, "Invalid STOP_AFTER_LAYER");
        if (INPUT_ELEMENTS < 1 || INPUT_ELEMENTS > CAPACITY)
            $fatal(1, "Set INPUT_ELEMENTS to the input tensor byte count (1..ACT_COUNT*8)");
        outputs_fd = $fopen("inference_outputs.txt", "w");
        progress_fd = $fopen("inference_progress.log", "w");
        summary_fd = $fopen("inference_summary.txt", "w");
        if (!outputs_fd || !progress_fd || !summary_fd) $fatal(1, "Cannot open output files");
        $fdisplay(progress_fd, "START num_layers=%0d input_elements=%0d", NUM_LAYERS, INPUT_ELEMENTS);
        $fflush(progress_fd);

        // Initialize ONLY the required input tensor bytes, in physical buffer A.
        // Packed memory layout: 8 consecutive INT8 activations per 64-bit word.
        $readmemh(INPUT_FILE, input_bytes, 0, INPUT_ELEMENTS-1);
        for (i=0; i<INPUT_ELEMENTS; i=i+1) begin
            word_idx = i >> 3;
            byte_idx = i & 7;
            dut.activation_a.mem[word_idx][byte_idx*8 +: 8] = input_bytes[i];
        end
        repeat (5) @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
    end

    // Watchdog. $fatal ensures files already flushed remain usable.
    always @(posedge clk) begin
        if (!rst && !finished) begin
            total_cycles = total_cycles + 1;
            if (total_cycles > MAX_TOTAL_CYCLES) begin
                $fdisplay(progress_fd, "TIMEOUT total_cycles=%0d layer=%0d", total_cycles, dut.controller.layer_index+1);
                $fflush(progress_fd);
                $fatal(1, "Total inference timeout");
            end
            if (dut.controller.state == CTRL_RUN &&
                total_cycles-layer_start_cycle > layer_watchdog) begin
                $fdisplay(progress_fd, "TIMEOUT layer=%0d opcode=%0d cycles=%0d",
                    dut.controller.layer_index+1, dut.opcode, total_cycles-layer_start_cycle);
                $fflush(progress_fd);
                $fatal(1, "Layer watchdog timeout");
            end
        end
    end

    // Track operation starts. The top-level controller uses a one-cycle start pulse.
    always @(posedge clk) begin
        if (!rst && !finished &&
            (dut.conv_start || dut.add_start || dut.pad_start || dut.mean_start || dut.fc_start)) begin
            layer_start_cycle = total_cycles;
            $display("START layer=%0d/%0d opcode=%0d time=%0t", dut.controller.layer_index+1,
                NUM_LAYERS, dut.opcode, $time);
            $fdisplay(progress_fd, "START layer=%0d opcode=%0d cycle=%0d",
                dut.controller.layer_index+1, dut.opcode, total_cycles);
            $fflush(progress_fd);
        end
    end

    // Detect an operation's completion at the same clock edge the controller
    // consumes its done pulse. Snapshot metadata BEFORE the controller advances.
    // After #1, the final synchronous write has committed; dump without clocking.
    always @(posedge clk) begin
        if (!rst && !finished && dut.controller.state == CTRL_RUN &&
            ((dut.opcode==OP_CONV && dut.conv_done) ||
             (dut.opcode==OP_ADD  && dut.add_done)  ||
             (dut.opcode==OP_PAD  && dut.pad_done)  ||
             (dut.opcode==OP_MEAN && dut.mean_done) ||
             (dut.opcode==OP_FC   && dut.fc_done))) begin
            current_layer = dut.controller.layer_index + 1;
            current_opcode = dut.opcode;
            current_buffer = dut.output_buffer;
            current_base = dut.output_base;
            current_height = dut.output_height;
            current_width = dut.output_width;
            current_channels = dut.output_channels;
            current_count = output_elements(dut.opcode,
                dut.output_height, dut.output_width, dut.output_channels,
                dut.input_height, dut.input_width, dut.input_channels,
                dut.pad_top, dut.pad_bottom, dut.pad_left, dut.pad_right,
                dut.element_count);
            #1;
            if (current_layer != last_layer + 2)
                $fatal(1, "Unexpected completion order layer=%0d last=%0d", current_layer, last_layer);
            dump_layer_output(current_layer, current_opcode, current_buffer,
                current_base, current_count);
            completed = completed + 1;
            last_layer = current_layer-1;
            $fdisplay(progress_fd,
                "COMPLETE layer=%0d opcode=%0d buffer=%0d base=%0d elements=%0d cycles=%0d total_cycles=%0d",
                current_layer, current_opcode, current_buffer, current_base,
                current_count, total_cycles-layer_start_cycle, total_cycles);
            $fflush(progress_fd);
            $display("COMPLETE layer=%0d/%0d elements=%0d cycles=%0d",
                current_layer, NUM_LAYERS, current_count, total_cycles-layer_start_cycle);
            if (stop_layer != 0 && completed >= stop_layer) begin
                finished = 1'b1;
                $fdisplay(summary_fd, "PARTIAL completed_layers=%0d total_cycles=%0d", completed, total_cycles);
                $fflush(summary_fd);
                $fclose(outputs_fd); $fclose(progress_fd); $fclose(summary_fd);
                $display("PARTIAL STOP after layer %0d. Files are complete through that layer.", completed);
                $finish;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst && !finished && error) begin
            $fdisplay(progress_fd, "CONTROLLER_ERROR layer=%0d total_cycles=%0d",
                dut.controller.layer_index+1, total_cycles);
            $fflush(progress_fd);
            $fatal(1, "Accelerator controller error");
        end
        if (!rst && !finished && done) begin
            #1;

            if (completed != NUM_LAYERS)
                $fatal(1, "Inference finished before all layers completed");

            // Capture final UINT8 output
            dump_final_output();
    
            finished = 1'b1;
    
            $fdisplay(summary_fd,
                "PASS completed_layers=%0d total_cycles=%0d result_uint8=%0d result_hex=%02h",
                completed, total_cycles, result, result);
    
            $fdisplay(progress_fd,
                "INFERENCE_DONE result_uint8=%0d total_cycles=%0d",
                result, total_cycles);
    
            $fflush(summary_fd);
            $fflush(progress_fd);
    
            $display("INFERENCE DONE result=%0d (0x%02h), completed=%0d",
                result, result, completed);
    
            $fclose(outputs_fd);
            $fclose(progress_fd);
            $fclose(summary_fd);
    
            $finish;
        end
    end
endmodule
