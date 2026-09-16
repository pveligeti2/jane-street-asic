/*
 * Copyright (c) 2026 Praneeth Veligeti
 * SPDX-License-Identifier: Apache-2.0
 *
 * Protocol emulator ASIC — milestone 1: hardware UART TX reference.
 *   ui_in[7:0]  : byte to send
 *   uio_in[0]   : start strobe
 *   uo_out[0]   : TX line
 *   uo_out[1]   : busy
 */
`default_nettype none

module tt_um_pveligeti_protoemu (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
  wire tx, busy;

  uart_tx #(.CLKS_PER_BIT(87)) u_tx (
      .clk(clk), .rst_n(rst_n), .data(ui_in), .start(uio_in[0]),
      .tx(tx), .busy(busy)
  );

  assign uo_out  = {6'b0, busy, tx};
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  wire _unused = &{ena, uio_in[7:1], 1'b0};
endmodule
