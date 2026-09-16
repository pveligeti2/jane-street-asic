`default_nettype none
// Plain hardware UART transmitter (8N1). Milestone 1: the reference we will
// later re-implement as firmware on the programmable sequencer.
module uart_tx #(
    parameter integer CLKS_PER_BIT = 87   // 10 MHz / 115200 baud
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,   // pulse (or hold) high to send `data`
    output reg        tx,
    output wire       busy
);
  localparam IDLE = 1'b0, SEND = 1'b1;
  reg        state;
  reg [9:0]  frame;      // {stop, data[7:0], start} shifted out LSB first
  reg [3:0]  bit_idx;
  reg [15:0] clk_cnt;

  assign busy = (state == SEND);

  always @(posedge clk) begin
    if (!rst_n) begin
      state <= IDLE; tx <= 1'b1; frame <= 10'h3FF; bit_idx <= 0; clk_cnt <= 0;
    end else case (state)
      IDLE: begin
        tx <= 1'b1;
        if (start) begin
          frame   <= {1'b1, data, 1'b0};
          bit_idx <= 0;
          clk_cnt <= 0;
          state   <= SEND;
        end
      end
      SEND: begin
        tx <= frame[0];
        if (clk_cnt == CLKS_PER_BIT - 1) begin
          clk_cnt <= 0;
          frame   <= {1'b1, frame[9:1]};
          if (bit_idx == 9) state <= IDLE;
          else bit_idx <= bit_idx + 1'b1;
        end else clk_cnt <= clk_cnt + 1'b1;
      end
    endcase
  end
endmodule
