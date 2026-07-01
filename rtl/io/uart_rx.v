`timescale 1ns/1ps

// ============================================================================
// Project      : SNN_ECG_V2
// Module       : uart_rx
// Description  : Asynchronous UART receiver with Stop-bit validation.
//                Synchronizes RX line and deserializes 8-bit data.
// ============================================================================

module uart_rx #(
    parameter CLK_HZ = 100000000,
    parameter BAUD   = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid
);

    localparam integer PERIOD = CLK_HZ / BAUD;
    localparam integer HALF   = PERIOD / 2;

    reg [19:0] baud_cnt;
    reg [3:0]  bit_cnt;
    reg [7:0]  shift;
    reg        active;
    reg        rx_s0, rx_s1;

    // ========================================================================
    // Input Synchronizer
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_s0 <= 1'b1;
            rx_s1 <= 1'b1;
        end else begin
            rx_s0 <= rx;
            rx_s1 <= rx_s0;
        end
    end

    // ========================================================================
    // UART Deserializer with Stop-Bit Verification
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active     <= 1'b0;
            baud_cnt   <= 20'd0;
            bit_cnt    <= 4'd0;
            shift      <= 8'd0;
            data_out   <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;

            if (!active) begin
                if (!rx_s1) begin
                    active   <= 1'b1;
                    baud_cnt <= HALF;
                    bit_cnt  <= 4'd0;
                end
            end else begin
                if (baud_cnt == 0) begin
                    baud_cnt <= PERIOD - 1;
                    
                    if (bit_cnt < 8) begin
                        // Deserialize 8 data bits
                        shift   <= {rx_s1, shift[7:1]};
                        bit_cnt <= bit_cnt + 1;
                    end else begin
                        // Verify Stop Bit (9th bit index)
                        if (rx_s1) begin
                            data_out   <= shift;
                            data_valid <= 1'b1;
                        end else begin
                            // Framing Error: stop bit was 0, discard data
                        end
                       bit_cnt <= 4'd0;
		       active  <= 1'b0;
                        
                    end
                end else begin
                    baud_cnt <= baud_cnt - 1;
                end
            end
        end
    end

endmodule
