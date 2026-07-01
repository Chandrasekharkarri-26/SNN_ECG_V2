`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : spike_iterator
// Description  : Hardware scanner that serializes a 1024-bit parallel 
//                spike bus into a sequence of active neuron identifiers.
//                Implements a snapshot-and-scan mechanism.
// ============================================================================

module spike_iterator #(
    parameter N          = 1024,
    parameter ID_WIDTH   = 10
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Spike bus input
    input  wire [N-1:0]         spike_bus,
    input  wire                 start,
    
    // Serialized output stream
    output reg  [ID_WIDTH-1:0]  neuron_id,
    output reg                  valid,
    output reg                  done
);

    // ========================================================================
    // Internal Registers
    // ========================================================================
    reg [ID_WIDTH-1:0] ptr;
    reg                active;
    reg [N-1:0]        spike_snapshot;

    // ========================================================================
    // Scan Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr            <= {ID_WIDTH{1'b0}};
            active         <= 1'b0;
            valid          <= 1'b0;
            done           <= 1'b0;
            neuron_id      <= {ID_WIDTH{1'b0}};
            spike_snapshot <= {N{1'b0}};
        end else begin
            // Reset control pulses each cycle
            valid <= 1'b0;
            done  <= 1'b0;

            if (start) begin
                // Latch the current spike bus state to prevent race conditions 
                // during the scan serialization process.
                spike_snapshot <= spike_bus;
                ptr            <= {ID_WIDTH{1'b0}};
                active         <= 1'b1;
            end else if (active) begin
                // Identify the firing neuron at the current pointer index
                if (spike_snapshot[ptr]) begin
                    neuron_id <= ptr;
                    valid     <= 1'b1;
                end
                
                // Advance pointer and check for scan completion
                if (ptr == N - 1) begin
                    done   <= 1'b1;
                    active <= 1'b0;
                    ptr    <= {ID_WIDTH{1'b0}};
                end else begin
                    ptr <= ptr + 1;
                end
            end
        end
    end

endmodule
