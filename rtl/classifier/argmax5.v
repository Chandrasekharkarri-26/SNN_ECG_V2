`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : argmax5
// Description  : Returns the index (0-4) of the maximum among 5 signed 
//                membrane potentials. Uses a 3-stage combinational comparator 
//                tree with a registered output
//                Classes: 0=N, 1=V, 2=S, 3=F, 4=Q
// ============================================================================

module argmax5 #(
    parameter V_WIDTH = 8
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      valid_in,
    
    // Signed membrane potentials from output_reader
    input  wire signed [V_WIDTH-1:0] v0,
    input  wire signed [V_WIDTH-1:0] v1,
    input  wire signed [V_WIDTH-1:0] v2,
    input  wire signed [V_WIDTH-1:0] v3,
    input  wire signed [V_WIDTH-1:0] v4,
    
    // Classification result
    output reg  [2:0]                idx,
    output reg                       valid
);

    // ========================================================================
    // Combinational Comparator Tree
    // ========================================================================
    
    // Stage 1: Compare pairs (v0, v1) and (v2, v3)
    wire signed [V_WIDTH-1:0] max01 = (v0 >= v1) ? v0 : v1;
    wire [2:0]                idx01 = (v0 >= v1) ? 3'd0 : 3'd1;

    wire signed [V_WIDTH-1:0] max23 = (v2 >= v3) ? v2 : v3;
    wire [2:0]                idx23 = (v2 >= v3) ? 3'd2 : 3'd3;

    // Stage 2: Compare winners of Stage 1
    wire signed [V_WIDTH-1:0] max0123 = (max01 >= max23) ? max01 : max23;
    wire [2:0]                idx0123 = (max01 >= max23) ? idx01 : idx23;

    // Stage 3: Compare Stage 2 winner against v4
    wire [2:0] idx_all = (max0123 >= v4) ? idx0123 : 3'd4;

    // ========================================================================
    // Output Register
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx   <= 3'd0;
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (valid_in) begin
                idx   <= idx_all;
                valid <= 1'b1;
            end
        end
    end

endmodule
