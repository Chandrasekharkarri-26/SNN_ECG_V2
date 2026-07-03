`timescale 1ns/1ps

module tb_neuron_ptr_gen;

    // ==================================================
    // PARAMETERS
    // ==================================================
    parameter CLK_PERIOD = 10;
    
    // Override N_NEURON for faster but exhaustive simulation
    parameter N_NEURON   = 5; 
    parameter ID_WIDTH   = 10;

    // ==================================================
    // DUT SIGNALS
    // ==================================================
    reg                 clk;
    reg                 rst_n;
    reg                 start;
    reg                 ready;

    wire [ID_WIDTH-1:0] neuron_ptr;
    wire                valid;
    wire                done;

    // ==================================================
    // TESTBENCH CONTROL SIGNALS
    // ==================================================
    integer pass_count;
    integer fail_count;
    integer i;
    reg [255:0] current_test;

    // ==================================================
    // DUT INSTANTIATION
    // ==================================================
    neuron_ptr_gen #(
        .N_NEURON(N_NEURON),
        .ID_WIDTH(ID_WIDTH)
    ) u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .ready      (ready),
        .neuron_ptr (neuron_ptr),
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
        rst_n = 1'b0;
        start = 1'b0;
        ready = 1'b0;
        
        #(CLK_PERIOD * 3);
        @(negedge clk);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);
    end
    endtask

    // --------------------------------------------------
    // Task: Check cycle-accurate output state
    // --------------------------------------------------
    task check_state;
        input [ID_WIDTH-1:0] exp_ptr;
        input                exp_val;
        input                exp_done;
        input [255:0]        msg;
    begin
        // Check for Unknowns (X/Z)
        if (valid === 1'bx || valid === 1'bz || 
            done === 1'bx  || done === 1'bz  || 
            (^neuron_ptr) === 1'bx) begin
            
            fail_count = fail_count + 1;
            $display("[%0t] [FAIL] %s | X or Z state detected! ptr=%b, val=%b, done=%b", 
                     $time, msg, neuron_ptr, valid, done);
        end
        // Check expected logic levels
        else if (neuron_ptr !== exp_ptr || valid !== exp_val || done !== exp_done) begin
            fail_count = fail_count + 1;
            $display("[%0t] [FAIL] %s", $time, msg);
            $display("         Expected: ptr=%0d, valid=%b, done=%b", exp_ptr, exp_val, exp_done);
            $display("         Got     : ptr=%0d, valid=%b, done=%b", neuron_ptr, valid, done);
        end 
        else begin
            pass_count = pass_count + 1;
            // Uncomment the line below for extremely verbose passing logs:
            // $display("[%0t] [PASS] %s", $time, msg);
        end
    end
    endtask

    // ==================================================
    // MAIN TEST SEQUENCE
    // ==================================================
    initial begin
        // Initialize Tracking
        pass_count = 0;
        fail_count = 0;

        // VCD Dumping
        $dumpfile("neuron_ptr_gen.vcd");
        $dumpvars(0, tb_neuron_ptr_gen);

        $display("========================================");
        $display("Starting Self-Checking Verification...");
        $display("========================================");

        // --------------------------------------------------
        // TEST 1: Reset & Idle Behavior
        // --------------------------------------------------
        current_test = "Reset & Idle";
        apply_reset();
        
        @(negedge clk);
        check_state(0, 1'b0, 1'b0, "Idle state after reset");
        
        // Wait multiple cycles to ensure it doesn't spontaneously start
        for (i = 0; i < 5; i = i + 1) begin
            @(negedge clk);
            check_state(0, 1'b0, 1'b0, "Stable Idle state");
        end

        // --------------------------------------------------
        // TEST 2: Fast Scan (ready always 1)
        // --------------------------------------------------
        current_test = "Fast Scan";
        @(negedge clk);
        start = 1'b1;
        ready = 1'b1; // Always ready
        
        @(negedge clk);
        start = 1'b0;
        
        // FSM iterates from 0 to N_NEURON-1 exactly 1 cycle per increment
        for (i = 0; i < N_NEURON; i = i + 1) begin
            check_state(i, 1'b1, 1'b0, "Fast Scan: Active ptr iteration");
            @(negedge clk);
        end
        
        // After reaching N-1, the next cycle MUST be the 1-cycle 'done' state
        check_state(0, 1'b0, 1'b1, "Fast Scan: Done pulse");
        
        // The cycle after 'done', everything should return to idle
        @(negedge clk);
        check_state(0, 1'b0, 1'b0, "Fast Scan: Return to idle");

        // --------------------------------------------------
        // TEST 3: Slow Scan, Held States & Ignored Start
        // --------------------------------------------------
        current_test = "Slow Scan & Ignored Start";
        @(negedge clk);
        start = 1'b1;
        ready = 1'b0; // Not ready initially
        
        @(negedge clk);
        start = 1'b0;
        
        // Cycle 1: ptr=0, valid=1. Ready is 0, so it should HOLD state.
        check_state(0, 1'b1, 1'b0, "Slow Scan: Ptr 0 initiated");
        
        @(negedge clk);
        check_state(0, 1'b1, 1'b0, "Slow Scan: Ptr 0 held due to !ready");
        
        // Assert start mid-scan; RTL should ignore it
        start = 1'b1;
        ready = 1'b1; // Allow advance to ptr 1
        @(negedge clk);
        start = 1'b0;
        ready = 1'b0; // Stop at ptr 1
        
        check_state(1, 1'b1, 1'b0, "Slow Scan: Ptr 1 reached, start ignored safely");
        
        // Hold ptr 1 for 3 cycles
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk);
            check_state(1, 1'b1, 1'b0, "Slow Scan: Ptr 1 holding state");
        end
        
        // Resume and flush remaining fast
        ready = 1'b1;
        for (i = 1; i < N_NEURON; i = i + 1) begin
            @(negedge clk);
            if (i < N_NEURON - 1) begin
                check_state(i + 1, 1'b1, 1'b0, "Slow Scan: Resumed fast scan");
            end else begin
                check_state(0, 1'b0, 1'b1, "Slow Scan: Done pulse");
            end
        end
        
        @(negedge clk);
        ready = 1'b0;
        check_state(0, 1'b0, 1'b0, "Slow Scan: Return to idle");

        // --------------------------------------------------
        // TEST 4: Back-to-Back Scans
        // --------------------------------------------------
        current_test = "Back-to-Back Scans";
        @(negedge clk);
        start = 1'b1;
        ready = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        // Wait for scan to complete (i from 0 to N_NEURON-1)
        for (i = 0; i < N_NEURON; i = i + 1) begin
            @(negedge clk);
        end
        
        // We are now evaluating the 'done' cycle
        check_state(0, 1'b0, 1'b1, "Back-to-Back: Done pulse of first scan");
        
        // Assert start EXACTLY during the done pulse
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        // Next cycle should immediately be valid=1, ptr=0 for the new scan
        check_state(0, 1'b1, 1'b0, "Back-to-Back: Immediate restart successful");
        
        // Flush second scan
        for (i = 0; i < N_NEURON - 1; i = i + 1) begin
            @(negedge clk);
        end
        @(negedge clk); // Done cycle
        check_state(0, 1'b0, 1'b1, "Back-to-Back: Done pulse of second scan");
        @(negedge clk);

        // --------------------------------------------------
        // TEST 5: Mid-operation Reset
        // --------------------------------------------------
        current_test = "Mid-op Reset";
        @(negedge clk);
        start = 1'b1;
        ready = 1'b1;
        @(negedge clk);
        start = 1'b0;
        
        // Let it scan a couple of cycles
        @(negedge clk);
        @(negedge clk);
        check_state(2, 1'b1, 1'b0, "Mid-op Reset: Active state before reset");
        
        // Hit async reset
        rst_n = 1'b0;
        @(negedge clk);
        check_state(0, 1'b0, 1'b0, "Mid-op Reset: Outputs immediately cleared");
        
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        // --------------------------------------------------
        // SUMMARY
        // --------------------------------------------------
        $display("========================================");
        if (fail_count == 0) begin
            $display("VERIFICATION SUCCESSFUL");
        end else begin
            $display("VERIFICATION FAILED");
        end
        $display("PASSED : %0d", pass_count);
        $display("FAILED : %0d", fail_count);
        $display("========================================");
        
        $finish;
    end

endmodule