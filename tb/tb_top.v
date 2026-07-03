// ========================================================
// SNN_ECG_V2 - Professional Verilog Testbench (Vivado Compatible)
// ========================================================

`timescale 1ns/1ps

module tb_snn_ecg_top;

    // Parameters
    parameter CLK_HZ     = 100_000_000;
    parameter CLK_PERIOD = 1_000_000_000 / CLK_HZ;
    parameter BAUD       = 115200;
    parameter TIMEOUT    = 1_000_000;   // cycles

    // Signals
    reg         clk;
    reg         rst_n;
    reg         uart_rx;
    wire        uart_tx;
    wire [2:0]  class_out;
    wire        class_valid;

    integer inference_cnt = 0;
    integer pass_cnt      = 0;

    // DUT
    snn_ecg_top #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (BAUD)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .uart_rx    (uart_rx),
        .uart_tx    (uart_tx),
        .class_out  (class_out),
        .class_valid(class_valid)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Reset Task
    task reset_dut;
        begin
            rst_n = 0;
            repeat(20) @(posedge clk);
            rst_n = 1;
            repeat(10) @(posedge clk);
        end
    endtask

    // Send one UART byte
    task send_uart_byte(input [7:0] data);
        integer i;
        begin
            uart_rx = 0;                    // Start bit
            #(1_000_000_000/BAUD);
            for (i = 0; i < 8; i = i+1) begin
                uart_rx = data[i];
                #(1_000_000_000/BAUD);
            end
            uart_rx = 1;                    // Stop bit
            #(1_000_000_000/BAUD);
        end
    endtask

    // Send one 96-bit spike window (12 bytes)
    task send_spike_window(input [95:0] data);
        integer i;
        begin
            for (i = 0; i < 12; i = i + 1) begin
                send_uart_byte(data[(i*8) +: 8]);
            end
        end
    endtask

 

    // Main Test
    initial begin
        $display("=== SNN_ECG_V2 Testbench Started ===");
        uart_rx = 1'b1;
        reset_dut();

        // === Basic Test: One full inference (3 timesteps) ===
        $display("Sending first test inference...");
        send_spike_window(96'h0000_0000_0000_0000_0000_0001); // TS0
        repeat(100) @(posedge clk);
        send_spike_window(96'h0000_0000_0000_0000_0000_0002); // TS1
        send_spike_window(96'h0000_0000_0000_0000_0000_0003); // TS2

        repeat(20000) @(posedge clk);

        if (pass_cnt > 0) begin
            $display("=== TEST PASSED (%0d inferences) ===", pass_cnt);
        end else begin
            $error("=== TEST FAILED: No output received ===");
        end

        #50000;
        $finish;
    end

    // Timeout
    initial begin
        repeat(TIMEOUT) @(posedge clk);
        $error("=== SIMULATION TIMEOUT ===");
        $finish;
    end

endmodule