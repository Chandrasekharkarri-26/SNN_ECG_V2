`timescale 1ns/1ps

module tb_spike_merge;

    // ==================================================
    // PARAMETERS
    // ==================================================
    parameter CLK_PERIOD  = 10;
    parameter TIMEOUT_MAX = 500;
    parameter EXT_WIDTH   = 96;
    parameter BUS_WIDTH   = 1024;
    parameter PAD_WIDTH   = BUS_WIDTH - EXT_WIDTH;
    
    // ==================================================
    // DUT SIGNALS
    // ==================================================
    // Inputs
    reg                  clk;
    reg                  rst_n;
    reg  [EXT_WIDTH-1:0] ext_spike_word;
    reg                  ext_spike_valid;
    reg  [BUS_WIDTH-1:0] int_spike_bus;
    reg                  int_spike_valid;
    reg                  clear;
    
    // Outputs
    wire [BUS_WIDTH-1:0] merged_spikes;
    wire                 merged_valid;

    // ==================================================
    // TESTBENCH CONTROL SIGNALS
    // ==================================================
    integer pass_count;
    integer fail_count;
    integer test_id;

    // Expected state trackers
    reg [BUS_WIDTH-1:0] exp_spikes;

    // ==================================================
    // DUT INSTANTIATION
    // ==================================================
    spike_merge #(
        .EXT_WIDTH(EXT_WIDTH),
        .BUS_WIDTH(BUS_WIDTH)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .ext_spike_word  (ext_spike_word),
        .ext_spike_valid (ext_spike_valid),
        .int_spike_bus   (int_spike_bus),
        .int_spike_valid (int_spike_valid),
        .merged_spikes   (merged_spikes),
        .merged_valid    (merged_valid),
        .clear           (clear)
    );

    // ==================================================
    // CLOCK GENERATION
    // ==================================================
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2.0) clk = ~clk;
    end

    // ==================================================
    // HELPER TASKS
    // ==================================================

    // --------------------------------------------------
    // Task: System Reset
    // --------------------------------------------------
    task apply_reset;
    begin
        rst_n           = 1'b0;
        ext_spike_word  = {EXT_WIDTH{1'b0}};
        ext_spike_valid = 1'b0;
        int_spike_bus   = {BUS_WIDTH{1'b0}};
        int_spike_valid = 1'b0;
        clear           = 1'b0;
        exp_spikes      = {BUS_WIDTH{1'b0}};
        
        #(CLK_PERIOD * 5);
        @(negedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
    end
    endtask

    // --------------------------------------------------
    // Task: Check output state
    // --------------------------------------------------
    task check_state;
        input [BUS_WIDTH-1:0] expected_data;
        input                 expected_valid;
    begin
        if (merged_spikes === {BUS_WIDTH{1'bx}} || merged_spikes === {BUS_WIDTH{1'bz}}) begin
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: X or Z detected on merged_spikes bus.", test_id);
        end else if (merged_spikes !== expected_data) begin
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: Spikes mismatch.", test_id);
        end else if (merged_valid !== expected_valid) begin
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: Valid mismatch. Expected: %b, Got: %b", test_id, expected_valid, merged_valid);
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d: State match.", test_id);
        end
    end
    endtask

    // --------------------------------------------------
    // Task: Issue clear and check
    // --------------------------------------------------
    task issue_clear;
    begin
        @(negedge clk);
        clear = 1'b1;
        @(negedge clk);
        clear = 1'b0;
        exp_spikes = {BUS_WIDTH{1'b0}};
        check_state(exp_spikes, 1'b0);
    end
    endtask

    // ==================================================
    // MAIN TEST SEQUENCE
    // ==================================================
    initial begin
        // Initialize Variables
        pass_count = 0;
        fail_count = 0;
        test_id    = 0;

        // VCD Dumping for GTKWave/Vivado
        $dumpfile("spike_merge.vcd");
        $dumpvars(0, tb_spike_merge);

        $display("========================================");
        $display("Starting Self-Checking Verification...");
        $display("========================================");

        // --------------------------------------------------
        // TEST 1: Reset Behavior & Idle State
        // --------------------------------------------------
        test_id = 1;
        apply_reset();
        @(negedge clk);
        check_state({BUS_WIDTH{1'b0}}, 1'b0);

        // --------------------------------------------------
        // TEST 2: Single External Spike Word Only
        // --------------------------------------------------
        test_id = 2;
        @(negedge clk);
        ext_spike_word  = {EXT_WIDTH{1'b1}};
        ext_spike_valid = 1'b1;
        @(negedge clk);
        ext_spike_valid = 1'b0;
        
        // Check cycle exactly after valid is asserted (valid should be 1)
        exp_spikes = {{{PAD_WIDTH{1'b0}}, {EXT_WIDTH{1'b1}}}};
        check_state(exp_spikes, 1'b1);
        
        // Check next cycle (valid should drop to 0, data should be held)
        @(negedge clk);
        check_state(exp_spikes, 1'b0);

        // --------------------------------------------------
        // TEST 3: Single Internal Spike Bus Only (Accumulation)
        // --------------------------------------------------
        test_id = 3;
        @(negedge clk);
        // Set MSB of int bus
        int_spike_bus   = {1'b1, {(BUS_WIDTH-1){1'b0}}};
        int_spike_valid = 1'b1;
        @(negedge clk);
        int_spike_valid = 1'b0;
        
        exp_spikes = exp_spikes | {1'b1, {(BUS_WIDTH-1){1'b0}}};
        check_state(exp_spikes, 1'b1);
        
        @(negedge clk);
        check_state(exp_spikes, 1'b0);

        // --------------------------------------------------
        // TEST 4: Simultaneous Internal and External Spikes
        // --------------------------------------------------
        test_id = 4;
        issue_clear(); // Clear the bus first
        
        @(negedge clk);
        ext_spike_word  = {{ (EXT_WIDTH/2){1'b1} }, { (EXT_WIDTH/2){1'b0} }};
        ext_spike_valid = 1'b1;
        int_spike_bus   = { { (BUS_WIDTH/2){1'b1} }, { (BUS_WIDTH/2){1'b0} } };
        int_spike_valid = 1'b1;
        
        @(negedge clk);
        ext_spike_valid = 1'b0;
        int_spike_valid = 1'b0;
        
        exp_spikes = ({{{PAD_WIDTH{1'b0}}, {{ (EXT_WIDTH/2){1'b1} }, { (EXT_WIDTH/2){1'b0} }}}}) |
                     ({ { (BUS_WIDTH/2){1'b1} }, { (BUS_WIDTH/2){1'b0} } });
        check_state(exp_spikes, 1'b1);
        
        @(negedge clk);
        check_state(exp_spikes, 1'b0);

        // --------------------------------------------------
        // TEST 5: Ignore Data when Valid is Low
        // --------------------------------------------------
        test_id = 5;
        @(negedge clk);
        ext_spike_word  = {EXT_WIDTH{1'b1}};
        int_spike_bus   = {BUS_WIDTH{1'b1}};
        ext_spike_valid = 1'b0;
        int_spike_valid = 1'b0;
        
        @(negedge clk);
        // Exp spikes should NOT change, valid should be 0
        check_state(exp_spikes, 1'b0);

        // --------------------------------------------------
        // TEST 6: Continuous Back-to-Back Accumulation
        // --------------------------------------------------
        test_id = 6;
        issue_clear();
        
        @(negedge clk);
        ext_spike_word  = 96'hA;
        ext_spike_valid = 1'b1;
        @(negedge clk);
        check_state({ {(BUS_WIDTH-4){1'b0}}, 4'hA }, 1'b1);
        
        ext_spike_word  = 96'h5;
        ext_spike_valid = 1'b1;
        @(negedge clk);
        check_state({ {(BUS_WIDTH-4){1'b0}}, 4'hF }, 1'b1);
        
        ext_spike_valid = 1'b0;
        int_spike_bus   = { {(BUS_WIDTH-8){1'b0}}, 8'hF0 };
        int_spike_valid = 1'b1;
        @(negedge clk);
        int_spike_valid = 1'b0;
        check_state({ {(BUS_WIDTH-8){1'b0}}, 8'hFF }, 1'b1);
        
        @(negedge clk);
        check_state({ {(BUS_WIDTH-8){1'b0}}, 8'hFF }, 1'b0);

        // --------------------------------------------------
        // TEST 7: Clear Precedence over Valid Inputs
        // --------------------------------------------------
        test_id = 7;
        @(negedge clk);
        ext_spike_word  = {EXT_WIDTH{1'b1}};
        ext_spike_valid = 1'b1;
        int_spike_bus   = {BUS_WIDTH{1'b1}};
        int_spike_valid = 1'b1;
        clear           = 1'b1; // Synchronous clear dominates
        
        @(negedge clk);
        ext_spike_valid = 1'b0;
        int_spike_valid = 1'b0;
        clear           = 1'b0;
        
        // Outputs should be completely 0 despite valid inputs
        check_state({BUS_WIDTH{1'b0}}, 1'b0);

        // --------------------------------------------------
        // TEST 8: All Ones Boundary (Max Values)
        // --------------------------------------------------
        test_id = 8;
        @(negedge clk);
        ext_spike_word  = {EXT_WIDTH{1'b1}};
        ext_spike_valid = 1'b1;
        int_spike_bus   = {BUS_WIDTH{1'b1}};
        int_spike_valid = 1'b1;
        
        @(negedge clk);
        ext_spike_valid = 1'b0;
        int_spike_valid = 1'b0;
        check_state({BUS_WIDTH{1'b1}}, 1'b1);

        // --------------------------------------------------
        // TEST 9: Async Reset during Operation
        // --------------------------------------------------
        test_id = 9;
        @(negedge clk);
        // Start an accumulation but hit async reset
        ext_spike_word  = {EXT_WIDTH{1'b1}};
        ext_spike_valid = 1'b1;
        rst_n           = 1'b0; 
        
        @(negedge clk);
        ext_spike_valid = 1'b0;
        
        // Verify reset worked instantly
        check_state({BUS_WIDTH{1'b0}}, 1'b0);
        
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // --------------------------------------------------
        // SUMMARY
        // --------------------------------------------------
        $display("========================================");
        $display("PASSED : %0d", pass_count);
        $display("FAILED : %0d", fail_count);
        $display("========================================");
        
        $finish;
    end

endmodule