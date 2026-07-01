`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : uart_tx
// Description  : Standard UART transmitter. Serializes a 10-bit frame 
//                (1 start, 8 data, 1 stop) using a unified shift register.
// ============================================================================

module uart_tx #(
    parameter CLK_HZ = 100000000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire       send,
    output reg        tx,
    output wire       busy
);

    localparam integer PERIOD = CLK_HZ / BAUD;

    reg [19:0] baud_cnt;
    reg [3:0]  bit_cnt;
    reg [9:0]  shift; // {stop_bit, d7, d6, d5, d4, d3, d2, d1, d0, start_bit}
    reg        active;

    assign busy = active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx       <= 1'b1;
            active   <= 1'b0;
            baud_cnt <= 20'd0;
            bit_cnt  <= 4'd0;
            shift    <= 10'd0;
        end else begin
            if (!active) begin
                tx <= 1'b1; // Idle
                if (send) begin
                    // Load frame: Start(0), Data(8), Stop(1)
                    shift    <= {1'b1, data_in, 1'b0};
                    baud_cnt <= PERIOD - 1;
                    bit_cnt  <= 4'd0;
                    active   <= 1'b1;
                end
            end else begin
                if (baud_cnt == 0) begin
                    baud_cnt <= PERIOD - 1;
                    
                    // Shift out the next bit
                    tx    <= shift[0];
                    shift <= {1'b1, shift[9:1]};
                    
                    if (bit_cnt == 9) begin
                        // Transmission complete after 10 bits shifted
                        active  <= 1'b0;
                        bit_cnt <= 4'd0;
                    end else begin
                        bit_cnt <= bit_cnt + 1;
                    end
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
        end
    end

endmodule
