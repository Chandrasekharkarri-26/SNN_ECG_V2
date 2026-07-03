`timescale 1ns/1ps

module tb_neuron_fsm;

    // Parameters
    parameter V_WIDTH  = 8;
    parameter W_WIDTH  = 6;
    parameter ID_WIDTH = 10;
    parameter NS_WIDTH = V_WIDTH + W_WIDTH + 1;
    parameter TIMEOUT  = 2000;

    // DUT Signals
    reg clk, rst_n, mode_wacc, mode_vcalcu, weight_valid, nptr_valid;
    reg signed [W_WIDTH-1:0] weight_in;
    reg [ID_WIDTH-1:0] dst_id, neuron_ptr;
    reg signed [V_WIDTH-1:0] v_threshold;
    
    wire [ID_WIDTH-1:0] ns_addr, spike_id;
    wire ns_ce, ns_we, spike_valid, wacc_done, vcalcu_done, ready;
    wire [NS_WIDTH-1:0] ns_wdata, ns_rdata;

    // SRAM Model
    reg [NS_WIDTH-1:0] sram_array [0:1023];
    reg [NS_WIDTH-1:0] sram_out;
    assign ns_rdata = sram_out;

    // Synchronous SRAM logic
    always @(posedge clk) begin
        if (ns_ce && !ns_we) sram_out <= sram_array[ns_addr];
        if (ns_ce && ns_we)  sram_array[ns_addr] <= ns_wdata;
    end

    // DUT
    neuron_fsm u_dut (
        .clk(clk), .rst_n(rst_n), .mode_wacc(mode_wacc), .mode_vcalcu(mode_vcalcu),
        .weight_in(weight_in), .dst_id(dst_id), .weight_valid(weight_valid),
        .neuron_ptr(neuron_ptr), .nptr_valid(nptr_valid), .v_threshold(v_threshold),
        .ns_addr(ns_addr), .ns_ce(ns_ce), .ns_we(ns_we), .ns_wdata(ns_wdata), .ns_rdata(ns_rdata),
        .spike_id(spike_id), .spike_valid(spike_valid), .wacc_done(wacc_done), 
        .vcalcu_done(vcalcu_done), .ready(ready)
    );

    // Tracking
    integer pass = 0, fail = 0;
    integer t_cnt;

    initial begin clk = 0; forever #5 clk = ~clk; end

    // --- Monitoring ---
    always @(posedge clk) begin
        if (ns_addr === 1'bx || ns_ce === 1'bx || ns_we === 1'bx || ns_wdata === 1'bx ||
            spike_valid === 1'bx || wacc_done === 1'bx || vcalcu_done === 1'bx || ready === 1'bx) begin
            $display("FAIL: X/Z detected at %0t", $time); fail = fail + 1;
        end
    end

    // --- Reusable Tasks ---
    task reset_dut;
    begin
        rst_n = 0; mode_wacc = 0; mode_vcalcu = 0; weight_valid = 0; nptr_valid = 0;
        #25 rst_n = 1; @(posedge clk);
    end
    endtask

    task wait_done;
        input is_wacc;
    begin
        t_cnt = 0;
        while (!((is_wacc ? wacc_done : vcalcu_done)) && t_cnt < TIMEOUT) begin
            @(posedge clk); t_cnt = t_cnt + 1;
        end
        if (t_cnt >= TIMEOUT) begin fail = fail + 1; $display("FAIL: Timeout"); end
    end
    endtask

    task run_wacc;
        input [ID_WIDTH-1:0] id;
        input signed [W_WIDTH-1:0] w;
    begin
        if (!ready) begin fail = fail + 1; $display("FAIL: Not ready for WACC"); end
        @(negedge clk);
        mode_wacc = 1; weight_in = w; dst_id = id; weight_valid = 1;
        @(negedge clk); weight_valid = 0; mode_wacc = 0;
        wait_done(1);
        if (wacc_done) pass = pass + 1; else fail = fail + 1;
    end
    endtask

    // --- Main Test ---
    initial begin
        $dumpfile("neuron_fsm.vcd"); $dumpvars(0, tb_neuron_fsm);
        reset_dut();

        // Test Case: Positive Weight Accumulation
        sram_array[10] = {8'h0A, 6'd2, 1'b1}; // V=10, Bias=2, En=1
        run_wacc(10, 6'd5); // Expect V=15
        
        // Protocol verification: Check WR_NS state contents
        if (sram_array[10][NS_WIDTH-1:W_WIDTH+1] == 8'h0F) begin
            pass = pass + 1;
            $display("[PASS] WACC Positive Weight");
        end else begin
            fail = fail + 1;
            $display("[FAIL] WACC Positive Weight");
        end

        // Test Case: Negative Weight
        sram_array[10] = {8'h0A, 6'd0, 1'b1}; 
        run_wacc(10, -6'd5); // 10 - 5 = 5
        if (sram_array[10][NS_WIDTH-1:W_WIDTH+1] == 8'h05) pass = pass + 1; else fail = fail + 1;

        // Test Case: Spike Generation
        v_threshold = 8'h0A;
        sram_array[20] = {8'h08, 6'd3, 1'b1}; // V=8, B=3 -> 11 (Spike)
        @(negedge clk);
        mode_vcalcu = 1; neuron_ptr = 20; nptr_valid = 1;
        @(negedge clk); nptr_valid = 0; mode_vcalcu = 0;
        wait_done(0);
        
        // Verify spike_valid pulse width
        if (spike_valid == 1) pass = pass + 1; else fail = fail + 1;
        @(posedge clk);
        if (spike_valid == 0) pass = pass + 1; else fail = fail + 1;

        // Test Case: Reset Mid-Operation (RD_REQ)
        sram_array[30] = {8'h05, 6'd0, 1'b1};
        @(negedge clk);
        mode_wacc = 1; weight_in = 6'd1; dst_id = 30; weight_valid = 1;
        @(negedge clk);
        rst_n = 0;
        #10 rst_n = 1;
        if (ready === 1) pass = pass + 1; else begin fail = fail + 1; $display("FAIL: Reset Recovery"); end

        $display("========================================");
        $display("Total: %0d | Passed: %0d | Failed: %0d", (pass+fail), pass, fail);
        $display("========================================");
        $finish;
    end
endmodule
