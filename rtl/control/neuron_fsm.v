`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : neuron_fsm
// Description  : Per-neuron Leaky Integrate-and-Fire (LIF) state machine.
//                Timeshares SRAM to perform Weight Accumulation (W_ACC) and
//                Membrane Potential Update/Leak/Thresholding (V_CALCU).
// Reference    : IEEE TBCAS 2022, Fig 9(c) Neuron_FSM
// ============================================================================

module neuron_fsm #(
    parameter V_WIDTH  = 8,
    parameter W_WIDTH  = 6,
    parameter ID_WIDTH = 10
)(
    // Clock and Reset
    input  wire                       clk,
    input  wire                       rst_n,
    
    // Mode Controls
    input  wire                       mode_wacc,
    input  wire                       mode_vcalcu,
    
    // Datapath: Weight Accumulation (W_ACC)
    input  wire signed [W_WIDTH-1:0]  weight_in,
    input  wire [ID_WIDTH-1:0]        dst_id,
    input  wire                       weight_valid,
    
    // Datapath: Voltage Calculation (V_CALCU)
    input  wire [ID_WIDTH-1:0]        neuron_ptr,
    input  wire                       nptr_valid,
    
    // Network Parameters
    input  wire signed [V_WIDTH-1:0]  v_threshold,
    
    // Neuron_State SRAM Interface
    output reg  [ID_WIDTH-1:0]        ns_addr,
    output reg                        ns_ce,
    output reg                        ns_we,
    output reg  [V_WIDTH+W_WIDTH:0]   ns_wdata,
    input  wire [V_WIDTH+W_WIDTH:0]   ns_rdata,
    
    // Spike Output and Status Handshakes
    output reg  [ID_WIDTH-1:0]        spike_id,
    output reg                        spike_valid,
    output reg                        wacc_done,
    output reg                        vcalcu_done,
    output wire                       ready
);

    localparam NS_WIDTH = V_WIDTH + W_WIDTH + 1;

    // ========================================================================
    // State Encoding
    // ========================================================================
    localparam ST_IDLE    = 3'd0;
    localparam ST_RD_REQ  = 3'd1;  // Issue SRAM read address
    localparam ST_WAIT_NS = 3'd2;  // Wait 1 cycle for SRAM data propagation
    localparam ST_J_ACC   = 3'd3;  // W_ACC mode: Accumulate synaptic weight
    localparam ST_V_BIAS  = 3'd4;  // V_CALCU mode: Add neuron bias
    localparam ST_SPKCHK  = 3'd5;  // V_CALCU mode: Threshold compare (Spike)
    localparam ST_LEAK    = 3'd6;  // V_CALCU mode: Apply membrane potential leak
    localparam ST_WR_NS   = 3'd7;  // Write back updated state to SRAM

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [2:0]                 state;
    reg                       wacc_mode;  // 1 = W_ACC path, 0 = V_CALCU path
    reg                       spiked;     // Internal spike flag for leak prevention
    
    reg signed [V_WIDTH-1:0]  J_reg;      // Current Membrane Potential
    reg signed [W_WIDTH-1:0]  w_latch;    // Latched Synaptic Weight
    reg signed [W_WIDTH-1:0]  bias_latch; // Latched Neuron Bias
    reg                       en_latch;   // Latched Neuron Enable Flag
    reg [ID_WIDTH-1:0]        id_latch;   // Latched Neuron Target ID

    // ========================================================================
    // Combinational Sign Extensions
    // ========================================================================
    wire signed [V_WIDTH-1:0] w_ext = {{(V_WIDTH-W_WIDTH){w_latch[W_WIDTH-1]}}, w_latch};
    wire signed [V_WIDTH-1:0] b_ext = {{(V_WIDTH-W_WIDTH){bias_latch[W_WIDTH-1]}}, bias_latch};

    // ========================================================================
    // Main Neuron State Machine
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            ns_ce       <= 1'b0;
            ns_we       <= 1'b0;
            ns_addr     <= {ID_WIDTH{1'b0}};
            ns_wdata    <= {NS_WIDTH{1'b0}};
            spike_valid <= 1'b0;
            spike_id    <= {ID_WIDTH{1'b0}};
            wacc_done   <= 1'b0;
            vcalcu_done <= 1'b0;
            J_reg       <= {V_WIDTH{1'b0}};
            w_latch     <= {W_WIDTH{1'b0}};
            bias_latch  <= {W_WIDTH{1'b0}};
            en_latch    <= 1'b0;
            id_latch    <= {ID_WIDTH{1'b0}};
            wacc_mode   <= 1'b0;
            spiked      <= 1'b0;
        end else begin
            // Default 1-cycle strobe clear to prevent unwanted control assertions
            ns_ce       <= 1'b0;
            ns_we       <= 1'b0;
            spike_valid <= 1'b0;
            wacc_done   <= 1'b0;
            vcalcu_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (mode_wacc && weight_valid) begin
                        id_latch  <= dst_id;
                        w_latch   <= weight_in;
                        wacc_mode <= 1'b1;
                        state     <= ST_RD_REQ;
                    end else if (mode_vcalcu && nptr_valid) begin
                        id_latch  <= neuron_ptr;
                        wacc_mode <= 1'b0;
                        state     <= ST_RD_REQ;
                    end
                end

                ST_RD_REQ: begin
                    // Step 1: Drive Address phase for synchronous SRAM read
                    ns_ce   <= 1'b1;
                    ns_we   <= 1'b0;
                    ns_addr <= id_latch;
                    state   <= ST_WAIT_NS;
                end

                ST_WAIT_NS: begin
                    // Step 2: Capture data from SRAM. Data is valid 1 cycle after RD_REQ.
                    J_reg      <= $signed(ns_rdata[NS_WIDTH-1 : W_WIDTH+1]); // Membrane Potential (V)
                    bias_latch <= ns_rdata[W_WIDTH : 1];                     // Bias constant
                    en_latch   <= ns_rdata[0];                               // Neuron validity flag
                    
                    // Fork execution based on the current processing phase
                    state      <= wacc_mode ? ST_J_ACC : ST_V_BIAS;
                end

                // ------------------------------------------------------------
                // W_ACC Execution Path: Synaptic Integration
                // ------------------------------------------------------------
                ST_J_ACC: begin
                    if (en_latch) begin
                        J_reg <= J_reg + w_ext;
                    end
                    state <= ST_WR_NS;
                end

                // ------------------------------------------------------------
                // V_CALCU Execution Path: Bias, Threshold, and Leak
                // ------------------------------------------------------------
                ST_V_BIAS: begin
                    if (en_latch) begin
                        J_reg <= J_reg + b_ext;
                    end
                    state <= ST_SPKCHK;
                end

                ST_SPKCHK: begin
                    spiked <= 1'b0;
                    
                    // LIF Model Check: If membrane potential exceeds threshold, generate a spike
                    if (en_latch && (J_reg >= v_threshold)) begin
                        spike_id    <= id_latch;
                        spike_valid <= 1'b1;
                        spiked      <= 1'b1;
                        J_reg       <= {V_WIDTH{1'b0}}; // Hard reset to resting potential (0)
                    end
                    state <= ST_LEAK;
                end

                ST_LEAK: begin
                    // Apply membrane leakage using an arithmetic right shift (divide by 4 approximation).
                    // Apply leakage only if the neuron did not just spike/reset.
                    if (!spiked) begin
                        J_reg <= {{2{J_reg[V_WIDTH-1]}}, J_reg[V_WIDTH-1:2]};
                    end
                    state <= ST_WR_NS;
                end

                // ------------------------------------------------------------
                // Converged Write-Back Path
                // ------------------------------------------------------------
                ST_WR_NS: begin
                    // Step 3: Write the updated potential and unmodified constants back to SRAM
                    ns_ce    <= 1'b1;
                    ns_we    <= 1'b1;
                    ns_addr  <= id_latch;
                    ns_wdata <= {J_reg, bias_latch, en_latch};
                    
                    // Handshake completion back to the datapath dispatchers
                    if (wacc_mode) begin
                        wacc_done <= 1'b1;
                    end else begin
                        vcalcu_done <= 1'b1;
                    end
                    
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

    // ========================================================================
    // Status Outputs
    // ========================================================================
    assign ready = (state == ST_IDLE);

endmodule
