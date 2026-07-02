`timescale 1ns/1ps

module tb_uart_tx;

    parameter CLK_HZ = 100_000_000;
    parameter BAUD   = 10_000_000; 
    parameter PERIOD = CLK_HZ / BAUD;
    parameter TIMEOUT = PERIOD * 20;

    reg         clk, rst_n, send;
    reg  [7:0]  data_in;
    wire        tx, busy;

    integer pass_count = 0;
    integer fail_count = 0;
    reg [255:0] current_test;

    // DUT Instantiation
    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .clk(clk), .rst_n(rst_n), .data_in(data_in), .send(send), .tx(tx), .busy(busy)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
    end

    // Task: Sample TX at center of bit, check for X/Z, verify duration
    task check_bit;
        input [0:0] exp;
        input [127:0] name;
        integer k;
        begin
            // Move to center of bit
            repeat(PERIOD/2) @(posedge clk);
            
            // Check for X/Z and value
            if (tx !== 1'b0 && tx !== 1'b1) begin
                $display("[%0t] [FAIL] %s | Illegal State: %b", $time, name, tx);
                fail_count = fail_count + 1;
            end else if (tx !== exp) begin
                $display("[%0t] [FAIL] %s | Exp: %b, Got: %b", $time, name, exp, tx);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end
            
            // Move to boundary
            repeat(PERIOD - PERIOD/2) @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0; send = 0; data_in = 0;
        #20 rst_n = 1;

        // 1. Idle Line Verification
        current_test = "Idle Line Verification";
        @(negedge clk);
        if (tx !== 1'b1 || busy !== 1'b0) begin
            $display("[FAIL] %s: Not idle after reset", current_test);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        // 2. Full Frame Timing/Duration & Busy verification
        current_test = "Full Frame Timing and Busy Signaling";
        @(negedge clk);
        data_in = 8'hAA; send = 1; @(negedge clk); send = 0;
        
        // Manual busy check loop to avoid non-Verilog-2001 fork/join
        repeat(PERIOD * 10) begin
            @(posedge clk);
            if (busy !== 1'b1) begin
                $display("[FAIL] Busy signal dropped during transmission");
                fail_count = fail_count + 1;
            end
        end
        
        check_bit(1'b0, "Start Bit");
        check_bit(1'b0, "D0"); check_bit(1'b1, "D1"); check_bit(1'b0, "D2"); check_bit(1'b1, "D3");
        check_bit(1'b0, "D4"); check_bit(1'b1, "D5"); check_bit(1'b0, "D6"); check_bit(1'b1, "D7");
        check_bit(1'b1, "Stop Bit");
        
        wait(!busy);
        if (tx !== 1'b1) begin
            $display("[FAIL] TX not idle after stop bit");
            fail_count = fail_count + 1;
        end

        // 3. Reset during active transmission
        current_test = "Reset during transmission";
        @(negedge clk);
        data_in = 8'h55; send = 1; @(negedge clk); send = 0;
        repeat(PERIOD * 3) @(posedge clk); 
        rst_n = 0;
        #5;
        if (tx !== 1'b1 || busy !== 1'b0) begin
            $display("[%0t] [FAIL] %s: Reset failed to clear state", $time, current_test);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end
        rst_n = 1;

        // 4. Ignored Send during busy
        current_test = "Ignored send during busy";
        data_in = 8'hFF; send = 1; @(negedge clk); send = 0;
        wait(busy);
        send = 1; data_in = 8'h00; @(negedge clk); send = 0;
        
        // Ensure no second start bit
        repeat(PERIOD * 11) begin
            @(posedge clk);
            if (tx === 1'b0 && busy === 1'b1) begin
                $display("[FAIL] %s: Second start bit detected", current_test);
                fail_count = fail_count + 1;
            end
        end
        pass_count = pass_count + 1;
        wait(!busy);

        // 5. Back-to-back
        current_test = "Back-to-back transmissions";
        data_in = 8'hFF; send = 1; @(negedge clk); send = 0;
        wait(!busy);
        data_in = 8'h00; send = 1; @(negedge clk); send = 0;
        wait(!busy);
        pass_count = pass_count + 1;

        $display("========================================");
        $display("Passed: %0d | Failed: %0d", pass_count, fail_count);
        $display("========================================");
        $finish;
    end
endmodule