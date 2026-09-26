<!---
This file is used to generate your project datasheet.
-->

## How it works

Current milestone: a hardware 8N1 UART transmitter (115200 baud at a 10 MHz clock, 87 clocks per bit).
This is the reference design and regression anchor for the upcoming programmable protocol engine,
which will be binary-compatible with the RP2040 PIO instruction set (see `docs/isa.md`).

When `uio_in[0]` (start) pulses high while idle, the byte on `ui_in[7:0]` is latched and sent on
`uo_out[0]` (TX): one start bit (0), 8 data bits LSB first, one stop bit (1). `uo_out[1]` (busy)
is high while a frame is being sent.

## How to test

1. Clock at 10 MHz and release reset.
2. Connect `uo_out[0]` to a USB-UART adapter RX pin, set the terminal to 115200 8N1.
3. Put a byte on `ui_in`, pulse `uio_in[0]` high for one clock, and wait for `uo_out[1]` to go low.
4. The byte appears in the terminal.

## External hardware

USB-to-UART adapter (3.3 V) for viewing the transmitted bytes.
