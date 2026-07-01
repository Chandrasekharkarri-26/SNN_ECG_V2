`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : neuron_ptr_gen
// Description  : Sequential neuron index generator. Iterates from 0 to 
//                N_NEURON-1 to trigger membrane potential updates in the NPU.
//                Uses ready/valid handshaking to ensure NPU throughput.
// ============================================================================

module neuron_ptr_gen #(
    parameter N_NEURON = 271,
    parameter ID_WIDTH = 10
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Control handshakes
    input  wire                 start,
    input  wire                 ready,
    
    // Pointer output
    output reg  [ID_WIDTH-1:0]  neuron_ptr,
    output reg                  valid,
    output reg                  done
);

    reg is_scanning;

    // ========================================================================
    // Pointer Generation Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            neuron_ptr  <= {ID_WIDTH{1'b0}};
            valid       <= 1'b0;
            done        <= 1'b0;
            is_scanning <= 1'b0;
        end else begin
            // Clear transient signals
            valid <= 1'b0;
            done  <= 1'b0;

            if (start && !is_scanning) begin
                // Initialize scan sequence
                neuron_ptr  <= {ID_WIDTH{1'b0}};
                is_scanning <= 1'b1;
                valid       <= 1'b1;
            end else if (is_scanning) begin
                // Maintain valid signal while scanning
                valid <= 1'b1;

                if (ready) begin
                    if (neuron_ptr == N_NEURON - 1) begin
                        // Scan reached target; signal done and reset
                        done        <= 1'b1;
                        is_scanning <= 1'b0;
                        valid       <= 1'b0;
                        neuron_ptr  <= {ID_WIDTH{1'b0}};
                    end else begin
                        // Advance to next neuron
                        neuron_ptr <= neuron_ptr + 1;
                    end
                end
            end
        end
    end

endmodule
