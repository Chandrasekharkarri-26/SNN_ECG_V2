`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : snn_ecg_top
// Description  : Top-level integration wrapper for the spike-driven 
//                neuromorphic ECG classification processor. Bridges external 
//                UART I/O to internal datapath and control subsystems.
// Reference    : IEEE TBCAS 2022 "A Neuromorphic Processing System With 
//                Spike-Driven SNN Processor for Wearable ECG Classification"
// ============================================================================

module snn_ecg_top #(
    parameter CLK_HZ     = 100000000,
    parameter BAUD       = 115200,
    parameter N_NEURON   = 271,
    parameter N_MAX      = 1024,
    parameter V_WIDTH    = 8,
    parameter W_WIDTH    = 6,
    parameter ID_WIDTH   = 10,
    parameter N_TIMESTEP = 3,
    parameter OUT_START  = 266,   // Target output neurons [266:270]
    parameter N_CLASSES  = 5,
    parameter WC_AWIDTH  = 15,    // Weight memory address width
    parameter NS_WIDTH   = 15     // Neuron state SRAM data width
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rx,
    output wire       uart_tx,
    output wire [2:0] class_out,
    output wire       class_valid
);

    // ========================================================================
    // Local Configuration
    // ========================================================================
    localparam signed [V_WIDTH-1:0] V_THRESHOLD = 8'sd10;

    // ========================================================================
    // Internal Net Declarations
    // ========================================================================
    // UART Interface
    wire [7:0]          uart_byte;
    wire                uart_byte_valid;

    // Input Spike Buffer
    wire [95:0]         ext_spike_word;
    wire                ext_spike_valid;
    wire [1:0]          ext_time_step;
    wire                beat_start;

    // Top-Level Control (FSM)
    wire                mode_wacc;
    wire                mode_vcalcu;
    wire                mode_output;
    wire                spike_merge_clear;
    wire [1:0]          fsm_ts;
    wire                all_spikes_done;
    wire                all_neurons_done;
    wire                iter_start_pulse;
    wire                or_valid;

    // Spike Aggregation (Merge)
    wire [N_MAX-1:0]    merged_spikes;
    wire                merged_valid;
    wire [N_MAX-1:0]    npu_spike_bus;

    // Spike Dispatch (Iterator)
    wire [ID_WIDTH-1:0] iter_neuron_id;
    wire                iter_valid;

    // Synaptic Weight Decoder
    wire signed [W_WIDTH-1:0] wd_weight;
    wire [ID_WIDTH-1:0]       wd_dst_id;
    wire                      wd_valid;
    wire                      wd_last;
    wire                      wd_ready;

    // Neural Processing Unit (NPU)
    wire                wacc_done;
    wire                vcalcu_done;

    // Classifier (Output Reader)
    wire [ID_WIDTH-1:0]   or_ns_addr;
    wire                  or_ns_ce;
    wire [NS_WIDTH-1:0]   ns_rdata_shared;
    wire [V_WIDTH-1:0]    v_out0;
    wire [V_WIDTH-1:0]    v_out1;
    wire [V_WIDTH-1:0]    v_out2;
    wire [V_WIDTH-1:0]    v_out3;
    wire [V_WIDTH-1:0]    v_out4;

    // ========================================================================
    // Combinational Logic
    // ========================================================================
    // Pulse generated on the arrival of the time_step == 0 spike word
    assign beat_start = ext_spike_valid && (ext_time_step == 2'd0);

    // ========================================================================
    // Subsystem Instantiations
    // ========================================================================

    uart_rx #(
        .CLK_HZ     (CLK_HZ), 
        .BAUD       (BAUD)
    ) u_urx (
        .clk        (clk), 
        .rst_n      (rst_n),
        .rx         (uart_rx),
        .data_out   (uart_byte),
        .data_valid (uart_byte_valid)
    );

    input_buffer u_ibuf (
        .clk        (clk), 
        .rst_n      (rst_n),
        .byte_in    (uart_byte),
        .byte_valid (uart_byte_valid),
        .spike_word (ext_spike_word),
        .spike_valid(ext_spike_valid),
        .time_step  (ext_time_step)
    );

    top_fsm #(
        .N_TIMESTEP (N_TIMESTEP)
    ) u_tfsm (
        .clk              (clk), 
        .rst_n            (rst_n),
        .iter_start       (iter_start_pulse),
        .beat_start       (beat_start),
        .or_valid         (or_valid),
        .all_spikes_done  (all_spikes_done),
        .all_neurons_done (all_neurons_done),
        .mode_wacc        (mode_wacc),
        .mode_vcalcu      (mode_vcalcu),
        .mode_output      (mode_output),
        .spike_merge_clear(spike_merge_clear),
        .time_step_reg    (fsm_ts)
    );

    spike_merge u_smerge (
        .clk            (clk), 
        .rst_n          (rst_n),
        .ext_spike_word (ext_spike_word),
        .ext_spike_valid(ext_spike_valid),
        .int_spike_bus  (npu_spike_bus),
        .int_spike_valid(mode_vcalcu),    // Internal spikes valid post-vcalcu
        .merged_spikes  (merged_spikes),
        .merged_valid   (merged_valid),
        .clear          (spike_merge_clear)
    );

    spike_iterator #(
        .N          (N_MAX), 
        .ID_WIDTH   (ID_WIDTH)
    ) u_siter (
        .clk        (clk), 
        .rst_n      (rst_n),
        .spike_bus  (merged_spikes),
        .start      (iter_start_pulse),
        .neuron_id  (iter_neuron_id),
        .valid      (iter_valid),
        .done       (all_spikes_done)
    );

    weight_decode #(
        .W_WIDTH   (W_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .WE_AWIDTH (ID_WIDTH), 
        .WC_AWIDTH (WC_AWIDTH)
    ) u_wdec (
        .clk           (clk), 
        .rst_n         (rst_n),
        .req_neuron_id (iter_neuron_id),
        .req_valid     (iter_valid),
        .out_weight    (wd_weight),
        .out_dst_id    (wd_dst_id),
        .out_valid     (wd_valid),
        .out_last      (wd_last),
        .ready         (wd_ready)
    );

    npu #(
        .N_NEURON  (N_NEURON),
        .N_MAX     (N_MAX),
        .V_WIDTH   (V_WIDTH),
        .W_WIDTH   (W_WIDTH),
        .ID_WIDTH  (ID_WIDTH)
    ) u_npu (
        .clk              (clk), 
        .rst_n            (rst_n),
        .mode_wacc        (mode_wacc),
        .mode_vcalcu      (mode_vcalcu),
        .mode_output      (mode_output),
        .weight_in        (wd_weight),
        .dst_id           (wd_dst_id),
        .spike_clear      (spike_merge_clear),
        .weight_valid     (wd_valid),
        .v_threshold      (V_THRESHOLD),
        .spike_bus        (npu_spike_bus),
        .wacc_done        (wacc_done),
        .vcalcu_done      (vcalcu_done),
        .all_neurons_done (all_neurons_done),
        .or_ns_addr       (or_ns_addr),
        .or_ns_ce         (or_ns_ce),
        .or_ns_rdata      (ns_rdata_shared)
    );

    output_reader #(
        .V_WIDTH   (V_WIDTH),
        .ID_WIDTH  (ID_WIDTH),
        .OUT_START (OUT_START),
        .N_CLASSES (N_CLASSES)
    ) u_oreader (
        .clk       (clk), 
        .rst_n     (rst_n),
        .trigger   (mode_output),
        .ns_addr   (or_ns_addr),
        .ns_ce     (or_ns_ce),
        .ns_rdata  (ns_rdata_shared),
        .v0        (v_out0), 
        .v1        (v_out1), 
        .v2        (v_out2),
        .v3        (v_out3), 
        .v4        (v_out4),
        .valid_out (or_valid)
    );

    argmax5 #(
        .V_WIDTH (V_WIDTH)
    ) u_amax (
        .clk      (clk), 
        .rst_n    (rst_n),
        .valid_in (or_valid),
        .v0       (v_out0), 
        .v1       (v_out1), 
        .v2       (v_out2),
        .v3       (v_out3), 
        .v4       (v_out4),
        .idx      (class_out),
        .valid    (class_valid)
    );

    uart_tx #(
        .CLK_HZ  (CLK_HZ), 
        .BAUD    (BAUD)
    ) u_utx (
        .clk     (clk), 
        .rst_n   (rst_n),
        .data_in ({5'b00000, class_out}),
        .send    (class_valid),
        .tx      (uart_tx),
        .busy    ()
    );

    // ========================================================================
    // Tie-offs and Linter Warning Suppression
    // ========================================================================
    wire unused_tieoff;
    assign unused_tieoff = wd_last & wd_ready & wacc_done & vcalcu_done & 
                           or_ns_ce & (|or_ns_addr) & (|fsm_ts);

endmodule
