`timescale 1ns/1ps

// ============================================================================
// Testbench    : tb_uart_rx
// Description  : Complete self-checking testbench for the uart_rx module.
//                Verifies standard reception, framing errors, and back-to-back 
//                data streaming.
// ============================================================================

module tb_uart_rx;

    // ------------------------------------------------------------------------
    // Parameters & Timing
    // ------------------------------------------------------------------------
    parameter CLK_PERIOD = 10; // 100 MHz clock
    
    // To speed up simulation, we override the BAUD rate to a higher value 
    // resulting in 10 clock cycles per UART bit (PERIOD = 10).
    parameter SIM_CLK_HZ = 100_000_000;
    parameter SIM_BAUD   = 10_000_000;
    parameter BAUD_CLKS  = SIM_CLK_HZ / SIM_BAUD; // 10 cycles per bit

    // ------------------------------------------------------------------------
    // DUT Signals
    // ------------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        rx;
    
    wire [7:0] data_out;
    wire       data_valid;

    // ------------------------------------------------------------------------
    // Verification Tracking Variables
    // ------------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer wait_cnt;
    integer i;
    reg [255:0] current_test;

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    uart_rx #(
        .CLK_HZ (SIM_CLK_HZ),
        .BAUD   (SIM_BAUD)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .rx         (rx),
        .data_out   (data_out),
        .data_valid (data_valid)
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
        $dumpfile("uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
    end

    // ------------------------------------------------------------------------
    // Self-Checking Tasks
    // ------------------------------------------------------------------------
    
    // Task: Simulate UART Transmitter
    task send_uart_frame;
        input [7:0] tx_data;
        input       valid_stop_bit; // 1 = normal, 0 = force framing error
        integer b;
        begin
            // Start bit
            rx = 1'b0;
            #(CLK_PERIOD * BAUD_CLKS);
            
            // 8 Data bits (LSB first)
            for (b = 0; b < 8; b = b + 1) begin
                rx = tx_data[b];
                #(CLK_PERIOD * BAUD_CLKS);
            end
            
            // Stop bit
            rx = valid_stop_bit;
            #(CLK_PERIOD * BAUD_CLKS);
            
            // Return to idle
            rx = 1'b1;
        end
    endtask

    // Task: Wait for data_valid pulse and check output
    task check_received_data;
        input [7:0] exp_data;
        begin
            wait_cnt = 0;
            // Timeout set to slightly more than one full UART frame duration
            while (!data_valid && wait_cnt < (BAUD_CLKS * 12)) begin
                @(negedge clk);
                wait_cnt = wait_cnt + 1;
            end

            if (wait_cnt >= (BAUD_CLKS * 12)) begin
                $display("[%0t] [FAIL] %s | TIMEOUT: data_valid did not assert.", $time, current_test);
                fail_count = fail_count + 1;
            end else begin
                if (data_out !== exp_data) begin
                    $display("[%0t] [FAIL] %s | Exp: %h, Got: %h", $time, current_test, exp_data, data_out);
                    fail_count = fail_count + 1;
                end else begin
                    $display("[%0t] [PASS] %s", $time, current_test);
                    pass_count = pass_count + 1;
                end
                
                // Verify data_valid is exactly a 1-cycle pulse
                @(negedge clk);
                if (data_valid !== 1'b0) begin
                    $display("[%0t] [FAIL] %s | data_valid remained high for multiple cycles!", $time, current_test);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    // Task: Verify framing error (data_valid should NOT assert)
    task check_framing_error;
        begin
            wait_cnt = 0;
            // Wait for duration of a frame to ensure no valid pulse occurs
            while (wait_cnt < (BAUD_CLKS * 12)) begin
                @(negedge clk);
                if (data_valid) begin
                    $display("[%0t] [FAIL] %s | data_valid asserted unexpectedly during a framing error!", $time, current_test);
                    fail_count = fail_count + 1;
                    disable check_framing_error; // Exit early on failure
                end
                wait_cnt = wait_cnt + 1;
            end
            $display("[%0t] [PASS] %s", $time, current_test);
            pass_count = pass_count + 1;
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Vector Sequence
    // ------------------------------------------------------------------------
    initial begin
        // 1. Initialize tracking and inputs
        pass_count = 0;
        fail_count = 0;
        rx         = 1'b1; // UART idle state

        $display("=================================================");
        $display(" Starting Verification: uart_rx");
        $display("=================================================");

        // 2. Apply Reset
        rst_n = 1'b0;
        #(CLK_PERIOD * 2);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        // --------------------------------------------------------------------
        // TEST 1: Normal Byte Reception (Standard Case)
        // --------------------------------------------------------------------
        current_test = "Normal Reception: 8'hA5";
        fork
            send_uart_frame(8'hA5, 1'b1);
            check_received_data(8'hA5);
        join
        #(CLK_PERIOD * 5); // Short idle gap

        // --------------------------------------------------------------------
        // TEST 2: Normal Byte Reception (Alternate Bit Pattern)
        // --------------------------------------------------------------------
        current_test = "Normal Reception: 8'h3C";
        fork
            send_uart_frame(8'h3C, 1'b1);
            check_received_data(8'h3C);
        join
        #(CLK_PERIOD * 5);

        // --------------------------------------------------------------------
        // TEST 3: Framing Error / Invalid Stop Bit (Invalid Case)
        // --------------------------------------------------------------------
        // Receiver should process the frame but discard it because stop bit is 0
        current_test = "Framing Error: Invalid Stop Bit (Data discarded)";
        fork
            send_uart_frame(8'hFF, 1'b0); // Send FF with 0 as stop bit
            check_framing_error();
        join
        
        // Ensure receiver recovers to idle properly after a framing error
        #(CLK_PERIOD * BAUD_CLKS * 2);

        // --------------------------------------------------------------------
        // TEST 4: Back-to-Back Reception (Boundary/Corner Case)
        // --------------------------------------------------------------------
        // Sends two bytes sequentially with zero idle time between stop bit 
        // of first byte and start bit of second byte.
        current_test = "Back-to-Back Reception: 8'h55 followed by 8'hAA";
        fork
            begin
                send_uart_frame(8'h55, 1'b1);
                send_uart_frame(8'hAA, 1'b1);
            end
            begin
                current_test = "Back-to-Back: Byte 1 (8'h55)";
                check_received_data(8'h55);
                
                current_test = "Back-to-Back: Byte 2 (8'hAA)";
                check_received_data(8'hAA);
            end
        join

        // --------------------------------------------------------------------
        // TEST 5: Idle Line Stability
        // --------------------------------------------------------------------
        current_test = "Idle Stability: Line held high for extended period";
        wait_cnt = 0;
        rx = 1'b1;
        while (wait_cnt < (BAUD_CLKS * 20)) begin
            @(negedge clk);
            if (data_valid) begin
                $display("[%0t] [FAIL] %s | Spurious data_valid pulse detected!", $time, current_test);
                fail_count = fail_count + 1;
            end
            wait_cnt = wait_cnt + 1;
        end
        if (wait_cnt == (BAUD_CLKS * 20)) begin
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
        
        #50 $finish;
    end

endmodule
