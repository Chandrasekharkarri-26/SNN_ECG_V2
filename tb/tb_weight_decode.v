`timescale 1ns/1ps

// ============================================================================
// Testbench    : tb_weight_decode
// Description  : Complete self-checking testbench for the weight_decode FSM.
//                Assumes memory files are pre-loaded via Vivado sources.
//                Verifies FSM states, streaming outputs, edge cases, and 
//                includes strict timeout mechanisms to prevent hangs.
// ============================================================================

module tb_weight_decode;

    // ------------------------------------------------------------------------
    // Parameters & Timing
    // ------------------------------------------------------------------------
    parameter CLK_PERIOD = 10;
    parameter W_WIDTH    = 6;
    parameter ID_WIDTH   = 10;
    parameter WE_AWIDTH  = 10;
    parameter WC_AWIDTH  = 15;
    parameter TIMEOUT    = 50; // Max cycles to wait for events

    // ------------------------------------------------------------------------
    // DUT Signals
    // ------------------------------------------------------------------------
    reg                 clk;
    reg                 rst_n;
    
    reg  [ID_WIDTH-1:0] req_neuron_id;
    reg                 req_valid;
    
    wire [W_WIDTH-1:0]  out_weight;
    wire [ID_WIDTH-1:0] out_dst_id;
    wire                out_valid;
    wire                out_last;
    wire                ready;

    // ------------------------------------------------------------------------
    // Testbench Variables
    // ------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer initial_fail_count;
    integer wait_cnt;
    integer i;
    reg [255:0] current_test;

    // ------------------------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------------------------
    weight_decode #(
        .W_WIDTH   (W_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .WE_AWIDTH (WE_AWIDTH),
        .WC_AWIDTH (WC_AWIDTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .req_neuron_id (req_neuron_id),
        .req_valid     (req_valid),
        .out_weight    (out_weight),
        .out_dst_id    (out_dst_id),
        .out_valid     (out_valid),
        .out_last      (out_last),
        .ready         (ready)
    );

    // ------------------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // VCD Dump
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("weight_decode.vcd");
        $dumpvars(0, tb_weight_decode);
    end

    // ------------------------------------------------------------------------
    // Checking Logic Tasks
    // ------------------------------------------------------------------------
    task verify_output;
        input [W_WIDTH-1:0]  exp_weight;
        input [ID_WIDTH-1:0] exp_dst_id;
        input                exp_last;
        begin
            if ((out_weight !== exp_weight) || (out_dst_id !== exp_dst_id) || (out_last !== exp_last)) begin
                $display("[%0t] [FAIL] %s | Exp: W=%0d ID=%0d L=%0b | Got: W=%0d ID=%0d L=%0b", 
                         $time, current_test, exp_weight, exp_dst_id, exp_last, out_weight, out_dst_id, out_last);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] [PASS] %s", $time, current_test);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task wait_for_valid;
        begin
            wait_cnt = 0;
            while (!out_valid && wait_cnt < TIMEOUT) begin
                @(negedge clk);
                wait_cnt = wait_cnt + 1;
            end
            if (wait_cnt >= TIMEOUT) begin
                $display("[%0t] [FAIL] %s | TIMEOUT: out_valid did not assert within %0d cycles.", $time, current_test, TIMEOUT);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task wait_for_ready;
        begin
            wait_cnt = 0;
            while (!ready && wait_cnt < TIMEOUT) begin
                // If out_valid asserts unexpectedly while waiting for ready
                if (out_valid) begin
                    $display("[%0t] [FAIL] %s | out_valid asserted unexpectedly while waiting for ready!", $time, current_test);
                    fail_count = fail_count + 1;
                end
                @(negedge clk);
                wait_cnt = wait_cnt + 1;
            end
            
            if (wait_cnt >= TIMEOUT) begin
                $display("[%0t] [FAIL] %s | TIMEOUT: FSM did not return to ready within %0d cycles.", $time, current_test, TIMEOUT);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] [PASS] %s", $time, current_test);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Verification Sequence
    // ------------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;
        
        req_neuron_id = 0;
        req_valid     = 0;
        
        // Assert Reset
        rst_n = 1'b0;
        #(CLK_PERIOD * 2);
        rst_n = 1'b1;

        $display("=================================================");
        $display(" Starting Verification: weight_decode");
        $display("=================================================");

        // --------------------------------------------------------------------
        // TEST 0: Reset State Verification
        // --------------------------------------------------------------------
        current_test = "Verify ready == 1 immediately after reset";
        if (ready !== 1'b1) begin
            $display("[%0t] [FAIL] %s | Expected ready=1, Got ready=0", $time, current_test);
            fail_count = fail_count + 1;
        end else begin
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 1: Zero Connections (Early Exit Check)
        // --------------------------------------------------------------------
        current_test = "Neuron 0 (0 connections) - FSM should return to IDLE without out_valid";
        @(negedge clk);
        req_neuron_id = 10'd0;
        req_valid     = 1'b1;
        @(negedge clk);
        req_valid     = 1'b0;
        
        // Wait for FSM to process and return to IDLE (also checks for unexpected out_valid)
        wait_for_ready();

        // --------------------------------------------------------------------
        // TEST 2: Single Connection & Ready=0 Check & Pulse Width Check
        // --------------------------------------------------------------------
        current_test = "Neuron 1 (1 connection) - Checking output & out_last";
        @(negedge clk);
        req_neuron_id = 10'd1;
        req_valid     = 1'b1;
        @(negedge clk);
        req_valid     = 1'b0;

        current_test = "Verify ready == 0 while FSM is busy";
        if (ready !== 1'b0) begin
            $display("[%0t] [FAIL] %s | Expected ready=0, Got ready=1", $time, current_test);
            fail_count = fail_count + 1;
        end else begin
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end

        current_test = "Neuron 1 (1 connection) - Data Validation";
        wait_for_valid();
        verify_output(6'd11, 10'd111, 1'b1); // Exp: Weight 11, Dest 111, Last 1
        
        // Check that out_valid is strictly a 1-cycle pulse
        current_test = "Verify out_valid is a one-clock-cycle pulse";
        @(negedge clk);
        if (out_valid !== 1'b0) begin
            $display("[%0t] [FAIL] %s | out_valid remained high for multiple cycles!", $time, current_test);
            fail_count = fail_count + 1;
        end else begin
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end
        
        // Wait for FSM to return to IDLE safely
        current_test = "FSM returned to IDLE after 1-connection stream";
        wait_for_ready();

        // --------------------------------------------------------------------
        // TEST 3: Multiple Connections & Busy-Request Ignore Strengthening
        // --------------------------------------------------------------------
        current_test = "Neuron 2 (3 connections) - Checking output 1";
        @(negedge clk);
        req_neuron_id = 10'd2;
        req_valid     = 1'b1;
        @(negedge clk);
        req_valid     = 1'b0;

        // Inject an invalid request while FSM is busy
        @(negedge clk);
        req_neuron_id = 10'd99;
        req_valid     = 1'b1;
        @(negedge clk);
        req_valid     = 1'b0; 

        // Check Connection 1
        wait_for_valid();
        verify_output(6'd21, 10'd201, 1'b0); // Last = 0

        // Check Connection 2
        current_test = "Neuron 2 (3 connections) - Checking output 2";
        @(negedge clk); // Step past current valid
        wait_for_valid();
        verify_output(6'd22, 10'd202, 1'b0); // Last = 0

        // Check Connection 3
        current_test = "Neuron 2 (3 connections) - Checking output 3 (Last)";
        @(negedge clk); // Step past current valid
        wait_for_valid();
        verify_output(6'd23, 10'd203, 1'b1); // Last = 1

        // --------------------------------------------------------------------
        // TEST 4: Prove ignored request yields no extra outputs
        // --------------------------------------------------------------------
        current_test = "Verify request issued while busy was ignored (no ghost streams)";
        initial_fail_count = fail_count; 
        
        @(negedge clk); // Step past the last valid cycle
        for (i = 0; i < 20; i = i + 1) begin
            if (out_valid) begin
                $display("[%0t] [FAIL] %s | Unexpected out_valid detected!", $time, current_test);
                fail_count = fail_count + 1;
            end
            @(negedge clk);
        end
        
        // If fail_count hasn't increased, the loop passed cleanly
        if (fail_count == initial_fail_count) begin
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end

        // Verify FSM returned to IDLE safely
        current_test = "FSM returned to IDLE after multi-connection stream";
        wait_for_ready();

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
