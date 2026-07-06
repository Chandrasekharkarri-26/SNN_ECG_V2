`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : top_fsm
// Description  : Global controller for the SNN processor. Manages the 
//                algorithmic phases (Weight Accumulation, Voltage Calculation, 
//                and Output) across multiple timesteps.
// ============================================================================

module top_fsm #(
    parameter N_TIMESTEP = 3
)(
    // Clock and Reset
    input  wire       clk,
    input  wire       rst_n,
    
    // Status Inputs
    input  wire       beat_start,
    input  wire       all_spikes_done,
    input  wire       all_neurons_done,
    input  wire       or_valid,
    
    // Control Outputs
    output reg        mode_wacc,
    output reg        mode_vcalcu,
    output reg        mode_output,
    output reg        spike_merge_clear,
    output reg        iter_start,        // Direct start to spike_iterator
    output reg  [1:0] time_step_reg      // 2 bits because N_TIMESTEP = 3 (supports up to 4 timesteps)
);

    // ========================================================================
    // State Encoding
    // ========================================================================
    localparam ST_IDLE    = 3'd0;
    localparam ST_W_ACC   = 3'd1;
    localparam ST_V_CALCU = 3'd2;
    localparam ST_OUTPUT  = 3'd3;

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [2:0] current_state;
    reg [1:0] current_timestep;

    // ========================================================================
    // Main State Machine (Single-Block Registered Outputs)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state     <= ST_IDLE;
            current_timestep  <= 2'd0;
            mode_wacc         <= 1'b0;
            mode_vcalcu       <= 1'b0;
            mode_output       <= 1'b0;
            spike_merge_clear <= 1'b1;
            iter_start        <= 1'b0;
            time_step_reg     <= 2'd0;
        end else begin
            // Default one-cycle control strobes
            mode_wacc         <= 1'b0;
            mode_vcalcu       <= 1'b0;
            mode_output       <= 1'b0;
            spike_merge_clear <= 1'b0;
            iter_start        <= 1'b0;

            case (current_state)
                ST_IDLE: begin
                    current_timestep <= 2'd0;
                    time_step_reg    <= 2'd0;
                    
                    if (beat_start) begin
                        // Begin synaptic weight accumulation for the first timestep
                        current_state     <= ST_W_ACC;
                        mode_wacc         <= 1'b1; 
                        spike_merge_clear <= 1'b1;
                        iter_start        <= 1'b1; 
                    end
                end

                ST_W_ACC: begin
                    mode_wacc <= 1'b1;
                    
                    if (all_spikes_done) begin
                        // Spikes processed; begin membrane potential update and leakage calculation
                        mode_vcalcu   <= 1'b1;
                        current_state <= ST_V_CALCU;
                    end
                end

                ST_V_CALCU: begin
                    mode_vcalcu <= 1'b1;
                    
                    if (all_neurons_done) begin
                        if (current_timestep == N_TIMESTEP - 1) begin
                            // All timesteps processed; trigger output reader for classification
                            mode_output   <= 1'b1;
                            current_state <= ST_OUTPUT;
                        end else begin
                            // Timestep complete; advance timestep and begin weight accumulation for next iteration
                            current_timestep  <= current_timestep + 1;
                            time_step_reg     <= current_timestep + 1;
                            spike_merge_clear <= 1'b1;
                            iter_start        <= 1'b1; 
                            mode_wacc         <= 1'b1;
                            current_state     <= ST_W_ACC;
                        end
                    end
                end

                ST_OUTPUT: begin
                    mode_output <= 1'b1;
                    
                    if (or_valid) begin 
                        // Classification complete; return to idle and await next inference
                        current_state <= ST_IDLE;
                    end
                end

                default: begin
                    current_state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
