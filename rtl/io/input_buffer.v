`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : input_buffer
// Description  : Receives 8-bit UART bytes and packs them into 96-bit words.
//                12 bytes = 96 bits = one window of input spikes (X^t).
//                Tracks 3 consecutive time steps per ECG inference cycle.
// Reference    : IEEE TBCAS 2022, Section II-A "FIFO based buffer structure"
// ============================================================================

module input_buffer (
    input  wire        clk,
    input  wire        rst_n,
    
    // UART interface
    input  wire [7:0]  byte_in,
    input  wire        byte_valid,
    
    // Processor interface
    output reg  [95:0] spike_word,
    output reg         spike_valid, // 1-cycle pulse
    output reg  [1:0]  time_step    // 0, 1, or 2
);

    localparam BYTES_PER_WORD = 4'd11; // 0 to 11 = 12 bytes
    localparam MAX_TIME_STEPS = 2'd2;  // 0 to 2 = 3 steps

    reg [95:0] shift_reg;
    reg [3:0]  byte_cnt;
    reg [1:0]  ts_cnt;

    // ========================================================================
    // Packing Logic
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg   <= 96'd0;
            byte_cnt    <= 4'd0;
            ts_cnt      <= 2'd0;
            spike_word  <= 96'd0;
            spike_valid <= 1'b0;
            time_step   <= 2'd0;
        end else begin
            spike_valid <= 1'b0;

            if (byte_valid) begin
                // Shift in new byte (First byte ends up at LSB, last at MSB)
                shift_reg <= {byte_in, shift_reg[95:8]};

                if (byte_cnt == BYTES_PER_WORD) begin
                    // 96 bits assembled. Output immediately using look-ahead logic.
                    spike_word  <= {byte_in, shift_reg[95:8]};
                    spike_valid <= 1'b1;
                    
                    // Track time steps for the FSM
                    time_step   <= ts_cnt;
                    ts_cnt      <= (ts_cnt == MAX_TIME_STEPS) ? 2'd0 : ts_cnt + 2'd1;
                    
                    // Reset byte counter
                    byte_cnt    <= 4'd0;
                end else begin
                    byte_cnt <= byte_cnt + 4'd1;
                end
            end
        end
    end

endmodule
