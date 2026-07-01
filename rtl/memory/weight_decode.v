`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : weight_decode
// Description  : Synaptic weight retrieval engine. Performs a two-stage 
//                indirect SRAM lookup to stream weight/destination pairs.
//                1. Weight_Entrance (WE): Maps Neuron ID to {base_ptr, count}
//                2. Weight_Connection (WC): Stores sequences of {weight, dst_id}
// ============================================================================

module weight_decode #(
    parameter W_WIDTH   = 6,
    parameter ID_WIDTH  = 10,
    parameter WE_AWIDTH = 10,
    parameter WC_AWIDTH = 15
)(
    input  wire                 clk,
    input  wire                 rst_n,
    
    // Request Interface
    input  wire [ID_WIDTH-1:0]  req_neuron_id,
    input  wire                 req_valid,
    
    // Stream Output Interface
    output reg  [W_WIDTH-1:0]   out_weight,
    output reg  [ID_WIDTH-1:0]  out_dst_id,
    output reg                  out_valid,
    output reg                  out_last,
    output wire                 ready
);

    // ========================================================================
    // Internal Constants
    // ========================================================================
    localparam WE_DWIDTH = WC_AWIDTH + ID_WIDTH; // 25 bits
    localparam WC_DWIDTH = W_WIDTH  + ID_WIDTH;  // 16 bits

    // ========================================================================
    // SRAM Instances
    // ========================================================================
    reg  [WE_AWIDTH-1:0] we_addr;
    reg                  we_ce, we_we;
    wire [WE_DWIDTH-1:0] we_rdata;

    sram_1rw #(
        .DATA_WIDTH (WE_DWIDTH),
        .ADDR_WIDTH (WE_AWIDTH),
        .INIT_FILE  ("Weight_Entrance.mem")
    ) u_went (
        .clk(clk), .ce(we_ce), .we(we_we),
        .addr(we_addr), .wdata({WE_DWIDTH{1'b0}}), .rdata(we_rdata)
    );

    reg  [WC_AWIDTH-1:0] wc_addr;
    reg                  wc_ce, wc_we;
    wire [WC_DWIDTH-1:0] wc_rdata;

    sram_1rw #(
        .DATA_WIDTH (WC_DWIDTH),
        .ADDR_WIDTH (WC_AWIDTH),
        .INIT_FILE  ("Weight_Connection.mem")
    ) u_wcon (
        .clk(clk), .ce(wc_ce), .we(wc_we),
        .addr(wc_addr), .wdata({WC_DWIDTH{1'b0}}), .rdata(wc_rdata)
    );

    // ========================================================================
    // FSM States
    // ========================================================================
    localparam ST_IDLE       = 3'd0;
    localparam ST_WAIT_ENT   = 3'd1;
    localparam ST_LATCH_ENT  = 3'd2;
    localparam ST_WAIT_CONN  = 3'd3;
    localparam ST_OUT_CONN   = 3'd4;

    reg [2:0]           state;
    reg [WC_AWIDTH-1:0] connection_addr;
    reg [ID_WIDTH-1:0]  remaining_connections;

    assign ready = (state == ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                 <= ST_IDLE;
            out_valid             <= 1'b0;
            out_last              <= 1'b0;
            out_weight            <= {W_WIDTH{1'b0}};
            out_dst_id            <= {ID_WIDTH{1'b0}};
            connection_addr       <= {WC_AWIDTH{1'b0}};
            remaining_connections <= {ID_WIDTH{1'b0}};
            we_ce <= 1'b0; we_we <= 1'b0; we_addr <= {WE_AWIDTH{1'b0}};
            wc_ce <= 1'b0; wc_we <= 1'b0; wc_addr <= {WC_AWIDTH{1'b0}};
        end else begin
           out_valid <= 1'b0;
	   out_last  <= 1'b0;
           we_ce     <= 1'b0;
           we_we     <= 1'b0;
           wc_ce     <= 1'b0;
           wc_we     <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (req_valid) begin
                        we_ce   <= 1'b1;
                        we_we   <= 1'b0;
                        we_addr <= req_neuron_id[WE_AWIDTH-1:0];
                        state   <= ST_WAIT_ENT;
                    end
                end

                ST_WAIT_ENT: begin
                    // Wait one clock cycle for synchronous SRAM read
                    state <= ST_LATCH_ENT;
                end

                ST_LATCH_ENT: begin
                    connection_addr       <= we_rdata[WE_DWIDTH-1:ID_WIDTH];
                    remaining_connections <= we_rdata[ID_WIDTH-1:0];

                    if (we_rdata[ID_WIDTH-1:0] == 0) begin
                        state <= ST_IDLE;
                    end else begin
                        wc_ce   <= 1'b1;
                        wc_we   <= 1'b0;
                        wc_addr <= we_rdata[WE_DWIDTH-1:ID_WIDTH];
                        state   <= ST_WAIT_CONN;
                    end
                end

                ST_WAIT_CONN: begin
                    // Wait one clock cycle for synchronous SRAM read
                    state <= ST_OUT_CONN;
                end

                ST_OUT_CONN: begin
                    // One weight/destination pair is streamed each clock cycle
                    // until all connections have been processed.
                    out_weight <= wc_rdata[WC_DWIDTH-1:ID_WIDTH];
                    out_dst_id <= wc_rdata[ID_WIDTH-1:0];
                    out_valid  <= 1'b1;

                    if (remaining_connections == 1) begin
                        out_last <= 1'b1;
                        state    <= ST_IDLE;
                    end else begin
                        remaining_connections <= remaining_connections - 1;
                        connection_addr       <= connection_addr + 1;
                        wc_ce                 <= 1'b1;
                        wc_we                 <= 1'b0;
                        wc_addr               <= connection_addr + 1;
                        state                 <= ST_WAIT_CONN;
                    end
                end

                default: begin
    state <= ST_IDLE;
    out_valid <= 1'b0;
    out_last  <= 1'b0;
end
            endcase
        end
    end

endmodule
