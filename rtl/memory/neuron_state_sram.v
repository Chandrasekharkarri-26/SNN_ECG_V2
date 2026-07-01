`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : neuron_state_sram
// Description  : Memory wrapper for Neuron State storage.
//                Configuration: 15-bit word depth (8-bit V, 6-bit Bias, 1-bit En),
//                1024-word address space.
// ============================================================================

module neuron_state_sram (
    input  wire        clk,
    input  wire        ce,
    input  wire        we,
    input  wire [9:0]  addr,
    input  wire [14:0] wdata,
    output wire [14:0] rdata
);

    // ========================================================================
    // SRAM Primitive Instantiation
    // ========================================================================
    sram_1rw #(
        .DATA_WIDTH (15),
        .ADDR_WIDTH (10),
        .INIT_FILE  ("Neuron_State.mem")
    ) u_mem (
        .clk   (clk),
        .ce    (ce),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );

endmodule
