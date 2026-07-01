`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : spike_merge
// Description  : Merges external and internal spikes into a unified bus.
//                Implements Algorithm 1 (S^{t-1} = S^{t-1} union X^t) via 
//                combinatorial accumulation. The bus is cleared by the FSM 
//                at the start of every timestep.
// ============================================================================

module spike_merge #(
    parameter EXT_WIDTH = 96,
    parameter BUS_WIDTH = 1024
)(
    input  wire                   clk,
    input  wire                   rst_n,
    
    // Inputs
    input  wire [EXT_WIDTH-1:0]   ext_spike_word,
    input  wire                   ext_spike_valid,
    input  wire [BUS_WIDTH-1:0]   int_spike_bus,
    input  wire                   int_spike_valid,
    
    // Outputs
    output reg  [BUS_WIDTH-1:0]   merged_spikes,
    output reg                    merged_valid,
    
    // Global control (Reset at start of each time step)
    input  wire                   clear
);

    localparam PADDING_WIDTH = BUS_WIDTH - EXT_WIDTH;

    // Accumulate spikes into the merged_spikes register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            merged_spikes <= {BUS_WIDTH{1'b0}};
            merged_valid  <= 1'b0;
        end else begin
            // Default: valid signal is low unless a merge event occurs this cycle
            merged_valid <= 1'b0;

            // Accumulate: OR incoming valid spikes with the existing bus state
            if (ext_spike_valid || int_spike_valid) begin
                merged_spikes <= merged_spikes | 
                                 (int_spike_valid ? int_spike_bus : {BUS_WIDTH{1'b0}}) | 
                                 (ext_spike_valid ? {{PADDING_WIDTH{1'b0}}, ext_spike_word} : {BUS_WIDTH{1'b0}});
                
                merged_valid  <= 1'b1;
            end
        end
    end

endmodule
