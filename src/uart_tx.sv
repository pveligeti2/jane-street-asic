`default_nettype none
// Plain hardware UART transmitter (8N1). Milestone 1: the reference we will
// later re-implement as firmware on the programmable sequencer.
module uart_tx #(
    parameter int unsigned CLKS_PER_BIT = 87   // 10 MHz / 115200 baud
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] data,
    input  logic       start,   // pulse (or hold) high to send `data`
    output logic       tx,
    output logic       busy
);
  typedef enum logic {IDLE, SEND} state_t;

  state_t      state;
  logic [9:0]  frame;      // {stop, data[7:0], start}, shifted out LSB first
  logic [3:0]  bit_idx;
  logic [15:0] clk_cnt;

  assign busy = (state == SEND);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state   <= IDLE;
      tx      <= 1'b1;
      frame   <= '1;
      bit_idx <= '0;
      clk_cnt <= '0;
    end else begin
      unique case (state)
        IDLE: begin
          tx <= 1'b1;
          if (start) begin
            frame   <= {1'b1, data, 1'b0};
            bit_idx <= '0;
            clk_cnt <= '0;
            state   <= SEND;
          end
        end
        SEND: begin
          tx <= frame[0];
          if (clk_cnt == 16'(CLKS_PER_BIT - 1)) begin
            clk_cnt <= '0;
            frame   <= {1'b1, frame[9:1]};
            if (bit_idx == 4'd9) state <= IDLE;
            else                 bit_idx <= bit_idx + 4'd1;
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end

`ifdef FORMAL
  // ---- SVA properties, proven with SymbiYosys (see formal/) ----
  logic past_valid = 1'b0;
  always_ff @(posedge clk) past_valid <= 1'b1;
  initial assume (!rst_n);

  // 1. Line is idle-high whenever we were idle on the previous cycle.
  always_ff @(posedge clk)
    if (past_valid && $past(rst_n) && $past(state) == IDLE) assert (tx == 1'b1);

  // 2. Counters never leave their legal range.
  always_comb if (rst_n) assert (clk_cnt < CLKS_PER_BIT);
  always_comb if (rst_n) assert (bit_idx <= 4'd9);

  // 3. A start request while idle always begins a frame next cycle.
  always_ff @(posedge clk)
    if (past_valid && $past(rst_n) && rst_n && $past(state) == IDLE && $past(start))
      assert (state == SEND);

  // 4. Liveness-ish: a transmission is reachable and can finish.
  always_ff @(posedge clk) if (rst_n) cover (past_valid && $past(state) == SEND && state == IDLE);
`endif
endmodule
