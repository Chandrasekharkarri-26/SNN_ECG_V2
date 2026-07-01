`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : output_reader
// Description  : Sequential reader that extracts membrane potentials for 
//                the output neuron cluster (OUT_START to OUT_START+4).
// ============================================================================

module output_reader #(
    parameter V_WIDTH   = 8,
    parameter ID_WIDTH  = 10,
    parameter OUT_START = 266,
    parameter N_CLASSES = 5
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 trigger,
    
    // Neuron_State SRAM read interface
    output reg  [ID_WIDTH-1:0]  ns_addr,
    output reg                  ns_ce,
    input  wire [14:0]          ns_rdata,
    
    // Flattened output potential registers
    output reg  [V_WIDTH-1:0]   v0,
    output reg  [V_WIDTH-1:0]   v1,
    output reg  [V_WIDTH-1:0]   v2,
    output reg  [V_WIDTH-1:0]   v3,
    output reg  [V_WIDTH-1:0]   v4,
    output reg                  valid_out
);

    // ========================================================================
    // Internal Control Registers
    // ========================================================================
    reg [2:0] cnt;
    reg       active;
    reg       latch_phase; // 0: Address issued, 1: Data capture cycle

    // ========================================================================
    // Read Controller
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active      <= 1'b0;
            valid_out   <= 1'b0;
            cnt         <= 3'd0;
            latch_phase <= 1'b0;
            ns_ce       <= 1'b0;
            ns_addr     <= {ID_WIDTH{1'b0}};
            v0 <= 0; v1 <= 0; v2 <= 0; v3 <= 0; v4 <= 0;
        end else begin
            valid_out <= 1'b0;
            ns_ce     <= 1'b0;

            if (trigger && !active) begin
                active      <= 1'b1;
                cnt         <= 3'd0;
                latch_phase <= 1'b0;
                
                // Initiate first read
                ns_addr <= OUT_START[ID_WIDTH-1:0];
                ns_ce   <= 1'b1;
            end else if (active) begin
                if (!latch_phase) begin
                    // Wait for SRAM read access (1 cycle latency)
                    latch_phase <= 1'b1;
                end else begin
                    // Data available; latch into appropriate register
                    case (cnt)
                        3'd0: v0 <= ns_rdata[14:7];
                        3'd1: v1 <= ns_rdata[14:7];
                        3'd2: v2 <= ns_rdata[14:7];
                        3'd3: v3 <= ns_rdata[14:7];
                        3'd4: v4 <= ns_rdata[14:7];
                    endcase

                    // Check for sequence completion
                    if (cnt == (N_CLASSES - 1)) begin
                        active    <= 1'b0;
                        valid_out <= 1'b1;
                    end else begin
                        // Advance to next neuron
                        cnt         <= cnt + 3'd1;
                        ns_addr     <= ns_addr + 1'b1;
                        ns_ce       <= 1'b1;
                        latch_phase <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
