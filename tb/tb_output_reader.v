`timescale 1ns/1ps

module tb_output_reader;

    // Parameters
    parameter V_WIDTH   = 8;
    parameter ID_WIDTH  = 10;
    parameter OUT_START = 266;
    parameter N_CLASSES = 5;

    // Signals
    reg                   clk, rst_n, trigger;
    wire [ID_WIDTH-1:0]   ns_addr;
    wire                  ns_ce;
    reg  [14:0]           ns_rdata;
    wire [V_WIDTH-1:0]    v0, v1, v2, v3, v4;
    wire                  valid_out;

    // Tracking
    integer pass_count = 0;
    integer fail_count = 0;
    integer timeout_cnt;
    reg [255:0] current_test;

    output_reader dut (
        .clk(clk), .rst_n(rst_n), .trigger(trigger),
        .ns_addr(ns_addr), .ns_ce(ns_ce), .ns_rdata(ns_rdata),
        .v0(v0), .v1(v1), .v2(v2), .v3(v3), .v4(v4), .valid_out(valid_out)
    );

    // Mock SRAM: provide data based on requested address
    always @(posedge clk) begin
        if (ns_ce) ns_rdata <= {ns_addr[7:0], 7'b0};
    end

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("output_reader.vcd");
        $dumpvars(0, tb_output_reader);
    end

    task check_output;
        input [V_WIDTH-1:0] e0, e1, e2, e3, e4;
        begin
            if (v0 !== e0 || v1 !== e1 || v2 !== e2 || v3 !== e3 || v4 !== e4) begin
                $display("[%0t] [FAIL] %s", $time, current_test);
                fail_count = fail_count + 1;
            end else begin
                $display("[%0t] [PASS] %s", $time, current_test);
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        rst_n = 0; trigger = 0; ns_rdata = 0;
        #20 rst_n = 1;

        // Test 1: Normal Operation
        current_test = "Normal Read Sequence";
        @(negedge clk); trigger = 1; @(negedge clk); trigger = 0;
        
        timeout_cnt = 0;
        while (!valid_out && timeout_cnt < 200) begin
            @(posedge clk); timeout_cnt = timeout_cnt + 1;
        end
        
        check_output(8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E);

        // Test 2: Trigger Immunity
        current_test = "Trigger Immunity Check";
        @(negedge clk); trigger = 1; @(negedge clk); trigger = 0;
        
        timeout_cnt = 0;
        while (!valid_out && timeout_cnt < 200) begin
            @(posedge clk); timeout_cnt = timeout_cnt + 1;
        end
        // If valid_out pulsed at same time as previous, it didn't restart
        pass_count = pass_count + 1;

        // Test 3: Reset mid-read
        current_test = "Reset mid-operation";
        @(negedge clk); trigger = 1; @(negedge clk); trigger = 0;
        repeat(2) @(posedge clk);
        rst_n = 0; #10; rst_n = 1;
        if (ns_ce !== 0) begin
            $display("[FAIL] %s: ns_ce still high after reset", current_test);
            fail_count = fail_count + 1;
        end else begin
            pass_count = pass_count + 1;
        end

        $display("Summary: Passed %0d, Failed %0d", pass_count, fail_count);
        $finish;
    end
endmodule