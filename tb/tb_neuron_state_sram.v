`timescale 1ns/1ps

// ============================================================================
// Testbench    : tb_neuron_state_sram
// Description  : Complete self-checking testbench for the Neuron State SRAM wrapper.
//                Assumes Neuron_State.mem is loaded by the Vivado environment.
//                Asserts/deasserts control signals and automatically compares 
//                outputs to expected values.
// ============================================================================

module tb_neuron_state_sram;

    // ------------------------------------------------------------------------
    // Clock & Timing Parameters
    // ------------------------------------------------------------------------
    parameter CLK_PERIOD = 10;
    
    // ------------------------------------------------------------------------
    // DUT Signals
    // ------------------------------------------------------------------------
    reg         clk;
    reg         ce;
    reg         we;
    reg  [9:0]  addr;
    reg  [14:0] wdata;
    wire [14:0] rdata;

    // ------------------------------------------------------------------------
    // Verification Tracking Variables
    // ------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    reg [255:0] current_test; // String for error reporting

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    neuron_state_sram dut (
        .clk   (clk),
        .ce    (ce),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

    // ------------------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // VCD Dump Generation
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("neuron_state_sram.vcd");
        $dumpvars(0, tb_neuron_state_sram);
    end

    // ------------------------------------------------------------------------
    // Self-Checking Tasks
    // ------------------------------------------------------------------------
    
    // Task: Perform a synchronous write operation
    task write_word(input [9:0] w_addr, input [14:0] w_data);
        begin
            @(negedge clk);
            ce    = 1'b1;
            we    = 1'b1;
            addr  = w_addr;
            wdata = w_data;
            @(negedge clk);
            ce    = 1'b0;
            we    = 1'b0;
        end
    endtask

    // Task: Perform a synchronous read and automatically check result
    task read_check(input [9:0] r_addr, input [14:0] expected);
        begin
            @(negedge clk);
            ce   = 1'b1;
            we   = 1'b0;
            addr = r_addr;
            
            @(negedge clk);
            ce   = 1'b0; // De-assert CE immediately after read cycle triggers
            
            // Output is available after the posedge
            if (rdata !== expected) begin
                $display("[%0t] [FAIL] %s | Addr: %h | Exp: %h, Got: %h", 
                         $time, current_test, r_addr, expected, rdata);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] [PASS] %s", $time, current_test);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // Task: Verify that rdata holds its previous value (latched state)
    task check_hold(input [14:0] expected);
        begin
            if (rdata !== expected) begin
                $display("[%0t] [FAIL] %s | Exp Hold: %h, Got: %h", 
                         $time, current_test, expected, rdata);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] [PASS] %s", $time, current_test);
                pass_count = pass_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Vector Sequence
    // ------------------------------------------------------------------------
    initial begin
        // 1. Initialize tracking and input signals
        pass_count = 0;
        fail_count = 0;
        ce         = 1'b0;
        we         = 1'b0;
        addr       = 10'd0;
        wdata      = 15'd0;

        $display("=================================================");
        $display(" Starting Verification: neuron_state_sram");
        $display("=================================================");

        // Wait a few cycles for memory init to settle from Vivado source file
        #(CLK_PERIOD * 4);

        // --------------------------------------------------------------------
        // TEST 0: Initial Memory State Verification (Assumes zero-init)
        // --------------------------------------------------------------------
        current_test = "Init State: Read Addr 0 (Expect 0000)";
        read_check(10'h000, 15'h0000);

        current_test = "Init State: Read Addr 1023 (Expect 0000)";
        read_check(10'h3FF, 15'h0000);

        // --------------------------------------------------------------------
        // TEST 1: Boundary Case - Address 0 (Min)
        // --------------------------------------------------------------------
        current_test = "Boundary: Write/Read Addr 0";
        // Construct 15-bit payload: {V[7:0]=AA, bias[5:0]=2A, en=1} -> 15'h5555
        write_word(10'h000, 15'h5555);
        read_check(10'h000, 15'h5555);

        // --------------------------------------------------------------------
        // TEST 2: Boundary Case - Address 1023 (Max)
        // --------------------------------------------------------------------
        current_test = "Boundary: Write/Read Addr 1023";
        // Construct 15-bit payload: {V[7:0]=55, bias[5:0]=15, en=0} -> 15'h2AAA
        write_word(10'h3FF, 15'h2AAA);
        read_check(10'h3FF, 15'h2AAA);

        // --------------------------------------------------------------------
        // TEST 3: Normal Case - Random Middle Address
        // --------------------------------------------------------------------
        current_test = "Normal: Write/Read Addr 512";
        write_word(10'h200, 15'h7FFF); // All 1s
        read_check(10'h200, 15'h7FFF);

        // --------------------------------------------------------------------
        // TEST 4: Corner Case - Overwrite Existing Data
        // --------------------------------------------------------------------
        current_test = "Corner: Overwrite Addr 512";
        write_word(10'h200, 15'h0000); // All 0s
        read_check(10'h200, 15'h0000);

        // --------------------------------------------------------------------
        // TEST 5: Invalid Case - Write with CE disabled
        // --------------------------------------------------------------------
        current_test = "Invalid: Write completely ignored when CE=0";
        @(negedge clk);
        ce    = 1'b0;     // Disabled
        we    = 1'b1;     // Try to write
        addr  = 10'h200;
        wdata = 15'h3333; // Malicious data injection
        @(negedge clk);
        we    = 1'b0;
        
        // Read back to ensure memory at 0x200 is still 0000 (from Test 4)
        read_check(10'h200, 15'h0000);

        // --------------------------------------------------------------------
        // TEST 6: Invalid Case - Read with CE disabled (Latch Verification)
        // --------------------------------------------------------------------
        // Prime the output register with a known value
        current_test = "Setup: Prime output register for latch test";
        read_check(10'h3FF, 15'h2AAA);

        // Attempt to read Address 0 (which holds 5555) with CE=0
        current_test = "Invalid: Read ignored when CE=0 (Bus holds last value)";
        @(negedge clk);
        ce   = 1'b0;      // Disabled
        we   = 1'b0;
        addr = 10'h000;   // Target addr 0
        @(negedge clk);
        
        // Output should NOT transition to Address 0's data, it should hold 2AAA
        check_hold(15'h2AAA);

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
        
        // Terminate simulation cleanly
        #10 $finish;
    end

endmodule
