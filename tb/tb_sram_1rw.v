`timescale 1ns/1ps

module tb_sram_1rw;

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter CLK_PERIOD = 10;
    parameter ADDR_WIDTH = 4; // 16 words for manageable exhaustive testing
    parameter DATA_WIDTH = 8;
    
    // ========================================================================
    // DUT Signals
    // ========================================================================
    reg                   clk;
    reg                   ce;
    reg                   we;
    reg  [ADDR_WIDTH-1:0] addr;
    reg  [DATA_WIDTH-1:0] wdata;
    wire [DATA_WIDTH-1:0] rdata;

    // ========================================================================
    // Testbench Variables
    // ========================================================================
    integer pass_count;
    integer fail_count;
    integer i;
    reg [255:0] current_test; // String for error reporting

    // ========================================================================
    // DUT Instantiation
    // ========================================================================
    sram_1rw #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .INIT_FILE  ("") // Blank to test internal zero-initialization loop
    ) dut (
        .clk   (clk),
        .ce    (ce),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

    // ========================================================================
    // Clock Generation
    // ========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // ========================================================================
    // VCD Dump Generation
    // ========================================================================
    initial begin
        $dumpfile("sram_1rw.vcd");
        $dumpvars(0, tb_sram_1rw);
        // Dump the internal memory array for GTKWave inspection
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            $dumpvars(0, dut.mem[i]);
        end
    end

    // ========================================================================
    // Verification Tasks
    // ========================================================================
    
    // Task: Perform a write operation
    task write_mem(input [ADDR_WIDTH-1:0] w_addr, input [DATA_WIDTH-1:0] w_data);
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

    // Task: Perform a read operation and check against expected value
    task read_and_check(input [ADDR_WIDTH-1:0] r_addr, input [DATA_WIDTH-1:0] expected);
        begin
            @(negedge clk);
            ce    = 1'b1;
            we    = 1'b0;
            addr  = r_addr;
            
            @(negedge clk);
            ce    = 1'b0; // De-assert CE immediately after read cycle
            
            // Check data (available 1 cycle after CE was high)
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

    // Task: Check that rdata remained unchanged (latched)
    task check_no_change(input [DATA_WIDTH-1:0] expected);
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

    // ========================================================================
    // Main Test Vector Sequence
    // ========================================================================
    initial begin
        // Initialize tracking and inputs
        pass_count = 0;
        fail_count = 0;
        ce         = 1'b0;
        we         = 1'b0;
        addr       = 0;
        wdata      = 0;

        $display("=================================================");
        $display(" Starting Verification: sram_1rw");
        $display("=================================================");

        // Wait for memory to initialize (time 0 logic in DUT)
        #(CLK_PERIOD * 2);

        // --------------------------------------------------------------------
        // TEST 1: Zero-Initialization Verification
        // --------------------------------------------------------------------
        current_test = "Init Check (Address 0)";
        read_and_check(4'h0, 8'h00);
        
        current_test = "Init Check (Address 15 - Upper Boundary)";
        read_and_check(4'hF, 8'h00);

        // --------------------------------------------------------------------
        // TEST 2: Normal Write and Read (Standard Case)
        // --------------------------------------------------------------------
        write_mem(4'h5, 8'hAA);
        current_test = "Normal Read After Write";
        read_and_check(4'h5, 8'hAA);

        // --------------------------------------------------------------------
        // TEST 3: Chip Enable (ce) Disable Check (Corner Case)
        // --------------------------------------------------------------------
        // Attempt to write while CE is 0
        @(negedge clk);
        ce    = 1'b0;
        we    = 1'b1;
        addr  = 4'h5;
        wdata = 8'hFF;
        @(negedge clk);
        we    = 1'b0;
        
        current_test = "Write ignored when CE=0";
        read_and_check(4'h5, 8'hAA); // Should still be AA, not FF

        // --------------------------------------------------------------------
        // TEST 4: Read while CE=0 Behavior (Corner Case)
        // --------------------------------------------------------------------
        // First, do a valid read to prime the output register
        read_and_check(4'h5, 8'hAA);
        
        // Next, try to read a different address but with CE=0
        @(negedge clk);
        ce   = 1'b0;
        we   = 1'b0;
        addr = 4'h0;
        @(negedge clk);
        
        current_test = "RDATA holds previous value when CE=0";
        check_no_change(8'hAA); // Rdata should not have updated to addr 0's data

        // --------------------------------------------------------------------
        // TEST 5: Read-During-Write Behavior (NO_CHANGE architecture)
        // --------------------------------------------------------------------
        // The DUT is designed such that `rdata` is only assigned when `!we`.
        // Therefore, during a write cycle, `rdata` should hold its old value.
        read_and_check(4'h5, 8'hAA); // Prime rdata with AA
        
        @(negedge clk);
        ce    = 1'b1;
        we    = 1'b1;
        addr  = 4'h7;
        wdata = 8'hCC;
        @(negedge clk);
        ce    = 1'b0;
        we    = 1'b0;
        
        current_test = "RDATA does not change during write cycle";
        check_no_change(8'hAA);

        // Verify the write actually succeeded
        current_test = "Verify Write from Read-During-Write test";
        read_and_check(4'h7, 8'hCC);

        // --------------------------------------------------------------------
        // TEST 6: Exhaustive Write/Read Sweep (All Addresses)
        // --------------------------------------------------------------------
        $display("[%0t] [INFO] Starting exhaustive memory sweep...", $time);
        
        // Write unique data to every address
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            write_mem(i[ADDR_WIDTH-1:0], ~i[DATA_WIDTH-1:0]); // Write inverted address as data
        end
        
        // Read back and verify every address
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
            current_test = "Exhaustive Sweep Read";
            read_and_check(i[ADDR_WIDTH-1:0], ~i[DATA_WIDTH-1:0]);
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
        
        $finish;
    end

endmodule
