`timescale 1ns/1ps

module tb_spike_iterator;

    // ==================================================
    // PARAMETERS
    // ==================================================
    parameter CLK_PERIOD = 10;
    parameter N          = 1024;
    parameter ID_WIDTH   = 10;

    // ==================================================
    // DUT SIGNALS
    // ==================================================
    reg                 clk;
    reg                 rst_n;
    reg  [N-1:0]        spike_bus;
    reg                 start;

    wire [ID_WIDTH-1:0] neuron_id;
    wire                valid;
    wire                done;

    // ==================================================
    // TESTBENCH CONTROL SIGNALS
    // ==================================================
    integer pass_count;
    integer fail_count;
    integer test_id;
    integer err_cnt;
    integer i;

    reg [N-1:0] test_pattern;

    // ==================================================
    // DUT INSTANTIATION
    // ==================================================
    spike_iterator #(
        .N(N),
        .ID_WIDTH(ID_WIDTH)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .spike_bus  (spike_bus),
        .start      (start),
        .neuron_id  (neuron_id),
        .valid      (valid),
        .done       (done)
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
        rst_n     = 1'b0;
        start     = 1'b0;
        spike_bus = {N{1'b0}};
        
        #(CLK_PERIOD * 5);
        @(negedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
    end
    endtask

    // --------------------------------------------------
    // Task: Run Scan and Verify Cycle-by-Cycle
    // --------------------------------------------------
    task run_and_check;
        input [N-1:0] pattern;
        input         change_mid_scan;
        
        integer idx;
        integer local_errors;
    begin
        local_errors = 0;
        
        @(negedge clk);
        spike_bus = pattern;
        start     = 1'b1;
        
        @(negedge clk);
        start = 1'b0;
        
        // The RTL scans exactly 1 neuron per cycle for N cycles
        for (idx = 0; idx < N; idx = idx + 1) begin
            @(negedge clk);
            
            // Snapshot Verification: Change input bus completely at midway point
            if (change_mid_scan && (idx == (N / 2))) begin
                spike_bus = ~pattern;
            end
            
            // Check for X or Z states
            if (valid === 1'bx || valid === 1'bz || done === 1'bx || done === 1'bz) begin
                local_errors = local_errors + 1;
                $display("[FAIL] Test %0d: X or Z state detected at index %0d.", test_id, idx);
            end
            
            // Verify 'valid' and 'neuron_id' based on original pattern
            if (pattern[idx] === 1'b1) begin
                if (valid !== 1'b1) begin
                    local_errors = local_errors + 1;
                    $display("[FAIL] Test %0d: valid missing at index %0d.", test_id, idx);
                end
                if (neuron_id !== idx) begin
                    local_errors = local_errors + 1;
                    $display("[FAIL] Test %0d: ID mismatch. Exp: %0d, Got: %0d", test_id, idx, neuron_id);
                end
            end else begin
                if (valid !== 1'b0) begin
                    local_errors = local_errors + 1;
                    $display("[FAIL] Test %0d: valid incorrectly high at index %0d.", test_id, idx);
                end
            end
            
            // Verify 'done' timing (only high on the very last cycle of scan)
            if (idx == N - 1) begin
                if (done !== 1'b1) begin
                    local_errors = local_errors + 1;
                    $display("[FAIL] Test %0d: done NOT asserted at end of scan.", test_id);
                end
            end else begin
                if (done !== 1'b0) begin
                    local_errors = local_errors + 1;
                    $display("[FAIL] Test %0d: done asserted early at index %0d.", test_id, idx);
                end
            end
        end
        
        // Verify pulse widths (1 cycle only)
        @(negedge clk);
        if (done !== 1'b0) begin
            local_errors = local_errors + 1;
            $display("[FAIL] Test %0d: done pulse wider than 1 cycle.", test_id);
        end
        if (valid !== 1'b0) begin
            local_errors = local_errors + 1;
            $display("[FAIL] Test %0d: valid pulse wider than 1 cycle.", test_id);
        end
        
        if (local_errors == 0) begin
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d: Scan verified successfully.", test_id);
        end else begin
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: Scan failed with %0d errors.", test_id, local_errors);
        end
        
        // Restore bus to zero
        spike_bus = {N{1'b0}};
    end
    endtask

    // ==================================================
    // MAIN TEST SEQUENCE
    // ==================================================
    initial begin
        // Initialize
        pass_count = 0;
        fail_count = 0;
        test_id    = 0;

        // VCD Dumping
        $dumpfile("spike_iterator.vcd");
        $dumpvars(0, tb_spike_iterator);

        // --------------------------------------------------
        // TEST 1: Reset Behavior
        // --------------------------------------------------
        test_id = 1;
        apply_reset();
        @(negedge clk);
        
        if (valid !== 1'b0 || done !== 1'b0 || neuron_id !== 0) begin
            fail_count = fail_count + 1;
            $display("[FAIL] Test %0d: Outputs not fully cleared after reset.", test_id);
        end else begin
            pass_count = pass_count + 1;
            $display("[PASS] Test %0d: Reset cleared all outputs correctly.", test_id);
        end

        // --------------------------------------------------
        // TEST 2: Empty Spike Bus
        // --------------------------------------------------
        test_id = 2;
        test_pattern = {N{1'b0}};
        run_and_check(test_pattern, 1'b0);

        // --------------------------------------------------
        // TEST 3: Single Spike (Mid-range)
        // --------------------------------------------------
        test_id = 3;
        test_pattern = {N{1'b0}};
        test_pattern[512] = 1'b1;
        run_and_check(test_pattern, 1'b0);

        // --------------------------------------------------
        // TEST 4: Multiple Sparse Spikes
        // --------------------------------------------------
        test_id = 4;
        test_pattern = {N{1'b0}};
        test_pattern[10]  = 1'b1;
        test_pattern[256] = 1'b1;
        test_pattern[789] = 1'b1;
        run_and_check(test_pattern, 1'b0);

        // --------------------------------------------------
        // TEST 5: Consecutive Spikes (Burst)
        // --------------------------------------------------
        test_id = 5;
        test_pattern = {N{1'b0}};
        test_pattern[100] = 1'b1;
        test_pattern[101] = 1'b1;
        test_pattern[102] = 1'b1;
        test_pattern[103] = 1'b1;
        run_and_check(test_pattern, 1'b0);

        // --------------------------------------------------
        // TEST 6: Boundary Addresses (0 and 1023)
        // --------------------------------------------------
        test_id = 6;
        test_pattern = {N{1'b0}};
        test_pattern[0]   = 1'b1;
        test_pattern[N-1] = 1'b1;
        run_and_check(test_pattern, 1'b0);

        // --------------------------------------------------
        // TEST 7: Dense Spike Bus (All 1s)
        // --------------------------------------------------
        test_id = 7;
        test_pattern = {N{1'b1}};
        run_and_check(test_pattern, 1'b0);

        // --------------------------------------------------
        // TEST 8: Snapshot Verification
        // --------------------------------------------------
        test_id = 8;
        test_pattern = {N{1'b0}};
        test_pattern[10]  = 1'b1;
        test_pattern[800] = 1'b1;
        // The task will invert the input bus at cycle N/2 to ensure outputs remain unaffected
        run_and_check(test_pattern, 1'b1);

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