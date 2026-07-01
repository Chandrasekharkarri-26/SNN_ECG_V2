`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : sram_1rw
// Description  : Behavioral model for a synchronous single-port (1RW) SRAM.
//                - FPGA: Infers block RAM (BRAM).
//                - ASIC: Intended to be replaced by a foundry SRAM macro.
//                - Read latency: 1 clock cycle.
// ============================================================================

module sram_1rw #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10,
    parameter INIT_FILE  = "" // Path to initialization memory file
)(
    input  wire                   clk,
    input  wire                   ce,
    input  wire                   we,
    input  wire [ADDR_WIDTH-1:0]  addr,
    input  wire [DATA_WIDTH-1:0]  wdata,
    output reg  [DATA_WIDTH-1:0]  rdata
);

    // BRAM inference attribute for Vivado synthesis
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH) - 1];

    // Synchronous read/write logic
    always @(posedge clk) begin
        if (ce) begin
            if (we) begin
                mem[addr] <= wdata;
            end else begin
                rdata <= mem[addr];
            end
        end
    end

    // ========================================================================
    // Simulation Initialization
    // ========================================================================
    // synthesis translate_off
    integer idx;
    initial begin
        // Initialize memory to zero
        for (idx = 0; idx < (1 << ADDR_WIDTH); idx = idx + 1) begin
            mem[idx] = {DATA_WIDTH{1'b0}};
        end
        
        // Load initial values if file provided
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end
    // synthesis translate_on

endmodule
