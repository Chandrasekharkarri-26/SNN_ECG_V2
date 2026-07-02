`timescale 1ns/1ps

// ============================================================================
// Testbench    : tb_input_buffer
// Description  : Complete self-checking testbench for the input_buffer module.
//                Verifies byte packing, time-step tracking, and robust
//                handling of continuous and discontinuous data streams.
// ============================================================================

module tb_input_buffer;

    // ------------------------------------------------------------------------
    // Clock & Timing Parameters
    // ------------------------------------------------------------------------
    parameter CLK_PERIOD = 10;
    
    // ------------------------------------------------------------------------
    // DUT Signals
    // ------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    
    reg  [7:0]  byte_in;
    reg         byte_valid;
    
    wire [95:0] spike_word;
    wire        spike_valid;
    wire [1:0]  time_step;

    // ------------------------------------------------------------------------
    // Verification Tracking Variables
    // ------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer wait_cnt;
    integer i;
    reg [255:0] current_test; // String for error reporting

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    input_buffer dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .byte_in     (byte_in),
        .byte_valid  (byte_valid),
        .spike_word  (spike_word),
        .spike_valid (spike_valid),
        .time_step   (time_step)
    );

    // ------------------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // VCD Dump Generation (Icarus / GTKWave Compatible)
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("input_buffer.vcd");
        $dumpvars(0, tb_input_buffer);
    end

    // ------------------------------------------------------------------------
    // Self-Checking Tasks
    // ------------------------------------------------------------------------
    
    // Task: Wait for spike_valid and verify all outputs
    task wait_and_check;
        input [95:0] exp_word;
        input [1:0]  exp_ts;
        begin
            wait_cnt = 0;
            // Wait for the spike_valid pulse
            while (!spike_valid && wait_cnt < 200) begin
                @(negedge clk);
                wait_cnt = wait_cnt + 1;
            end

            if (wait_cnt >= 200) begin
                $display("[%0t] [FAIL] %s | TIMEOUT: spike_valid did not assert.", $time, current_test);
                fail_count = fail_count + 1;
            end else begin
                // Verify the packed 96-bit word and the time step index
                if ((spike_word !== exp_word) || (time_step !== exp_ts)) begin
                    $display("[%0t] [FAIL] %s", $time, current_test);
                    $display("         Expected Word: %h, TS: %0d", exp_word, exp_ts);
                    $display("         Got      Word: %h, TS: %0d", spike_word, time_step);
                    fail_count = fail_count + 1;
                end else begin
                    $display("[%0t] [PASS] %s", $time, current_test);
                    pass_count = pass_count + 1;
                end
                
                // Verify that spike_valid is strictly a 1-cycle pulse
                @(negedge clk);
                if (spike_valid !== 1'b0) begin
                    $display("[%0t] [FAIL] %s | spike_valid remained high for multiple cycles!", $time, current_test);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    // Task: Stream 12 bytes continuously
    task send_12_bytes_continuous;
        input [7:0] start_val;
        begin
            for (i = 0; i < 12; i = i + 1) begin
                @(negedge clk);
                byte_valid = 1'b1;
                byte_in    = start_val + i;
            end
            @(negedge clk);
            byte_valid = 1'b0;
        end
    endtask

    // Task: Stream 12 bytes with randomized delays (simulates real UART timing)
    task send_12_bytes_fragmented;
        input [7:0] start_val;
        begin
            for (i = 0; i < 12; i = i + 1) begin
                @(negedge clk);
                byte_valid = 1'b1;
                byte_in    = start_val + i;
                
                // Inject varying delays between bytes
                @(negedge clk);
                byte_valid = 1'b0;
                if (i % 3 != 0) begin
                    #(CLK_PERIOD * (i % 4)); 
                end
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Vector Sequence
    // ------------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;
        byte_in    = 8'd0;
        byte_valid = 1'b0;

        $display("=================================================");
        $display(" Starting Verification: input_buffer");
        $display("=================================================");

        // Apply Reset
        rst_n = 1'b0;
        #(CLK_PERIOD * 2);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // --------------------------------------------------------------------
        // TEST 1: Initial Reset State
        // --------------------------------------------------------------------
        current_test = "Reset State Check";
        if (spike_valid !== 1'b0 || spike_word !== 96'd0 || time_step !== 2'd0) begin
            $display("[%0t] [FAIL] %s | Outputs not zeroed after reset.", $time, current_test);
            fail_count = fail_count + 1;
        end else begin
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 2: Continuous Stream (Time Step 0)
        // --------------------------------------------------------------------
        current_test = "Time Step 0: Continuous 12-byte burst";
        fork
            send_12_bytes_continuous(8'h01);
            wait_and_check(96'h0C_0B_0A_09_08_07_06_05_04_03_02_01, 2'd0);
        join

        // --------------------------------------------------------------------
        // TEST 3: Fragmented Stream (Time Step 1)
        // --------------------------------------------------------------------
        current_test = "Time Step 1: Fragmented 12-byte stream (UART simulation)";
        fork
            send_12_bytes_fragmented(8'h11);
            wait_and_check(96'h1C_1B_1A_19_18_17_16_15_14_13_12_11, 2'd1);
        join

        // --------------------------------------------------------------------
        // TEST 4: Continuous Stream (Time Step 2)
        // --------------------------------------------------------------------
        current_test = "Time Step 2: Continuous 12-byte burst";
        fork
            send_12_bytes_continuous(8'h21);
            wait_and_check(96'h2C_2B_2A_29_28_27_26_25_24_23_22_21, 2'd2);
        join

        // --------------------------------------------------------------------
        // TEST 5: Boundary Case - Wrap Around to Time Step 0
        // --------------------------------------------------------------------
        current_test = "Boundary Check: Time Step wraps from 2 to 0";
        fork
            send_12_bytes_continuous(8'h31);
            wait_and_check(96'h3C_3B_3A_39_38_37_36_35_34_33_32_31, 2'd0);
        join

        // --------------------------------------------------------------------
        // TEST 6: Incomplete Packet Check (No premature trigger)
        // --------------------------------------------------------------------
        current_test = "Corner Case: Incomplete packet does not trigger valid";
        @(negedge clk);
        byte_valid = 1'b1;
        byte_in    = 8'hFF;
        
        @(negedge clk);
        byte_valid = 1'b0;
        
        // REFINEMENT: Replaced hardcoded `#` wait with safe synchronous cycle stepping
        repeat(10) @(negedge clk);
        
        if (spike_valid !== 1'b0) begin
            $display("[%0t] [FAIL] %s | spike_valid asserted before 12 bytes received!", $time, current_test);
            fail_count = fail_count + 1;
        end else begin
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end

        // --------------------------------------------------------------------
        // Simulation Summary
        // --------------------------------------------------------------------
        $display("=================================================");
        if (fail_count == 0) begin
            $display(" [SUCCESS] All %0d checks PASSED!", pass_count);
        end else begin
            $display(" [FAILED] %0d out of %0d checks FAILED.", fail_count, (pass_count + fail_count));
        end
        $display("=================================================");
        
        #20 $finish;
    end

endmodule
