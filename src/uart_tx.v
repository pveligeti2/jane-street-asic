`default_nettype none
// Plain hardware UART transmitter (8N1). Milestone 1: the reference we will
// later re-implement as firmware on the programmable sequencer.
module uart_tx #(
    parameter CLKS_PER_BIT = 87   // 10 MHz / 115200 baud
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       start,   // pulse (or hold) high to send `data`
    output reg        tx,
    output wire       busy
);
  localparam IDLE = 1'b0;
  localparam SEND = 1'b1;

  reg        state;
  reg [9:0]  frame;      // {stop, data[7:0], start}, shifted out LSB first
  reg [3:0]  bit_idx;
  reg [15:0] clk_cnt;

  assign busy = (state == SEND);

  always @(posedge clk) begin
    if (!rst_n) begin
      state   <= IDLE;
      tx      <= 1'b1;
      frame   <= 10'h3FF;
      bit_idx <= 4'd0;
      clk_cnt <= 16'd0;
    end else begin
      case (state)
        IDLE: begin
          tx <= 1'b1;
          if (start) begin
            frame   <= {1'b1, data, 1'b0};
            bit_idx <= 4'd0;
            clk_cnt <= 16'd0;
            state   <= SEND;
          end
        end
        SEND: begin
          tx <= frame[0];
          if (clk_cnt == CLKS_PER_BIT - 1) begin
            clk_cnt <= 16'd0;
            frame   <= {1'b1, frame[9:1]};
            if (bit_idx == 4'd9) state <= IDLE;
            else                 bit_idx <= bit_idx + 4'd1;
          end else begin
            clk_cnt <= clk_cnt + 16'd1;
          end
        end
      endcase
    end
  end

`ifdef FORMAL
  // ---- Formal properties, proven with SymbiYosys (see formal/) ----
  // Immediate assert/assume/cover inside always blocks: supported by
  // `read_verilog -formal`, no SystemVerilog needed.
  reg past_valid = 1'b0;
  always @(posedge clk) past_valid <= 1'b1;
  initial assume (!rst_n);

  // 1. Line is idle-high whenever we were idle on the previous cycle.
  always @(posedge clk)
    if (past_valid && $past(rst_n) && $past(state) == IDLE) assert (tx == 1'b1);

  // 2. Counters never leave their legal range.
  always @(*) if (rst_n) assert (clk_cnt < CLKS_PER_BIT);
  always @(*) if (rst_n) assert (bit_idx <= 4'd9);

  // 3. A start request while idle always begins a frame next cycle.
  always @(posedge clk)
    if (past_valid && $past(rst_n) && rst_n && $past(state) == IDLE && $past(start))
      assert (state == SEND);

  // 4. A full transmission is reachable and can finish.
  always @(posedge clk) if (rst_n) cover (past_valid && $past(state) == SEND && state == IDLE);
`endif
endmodule
