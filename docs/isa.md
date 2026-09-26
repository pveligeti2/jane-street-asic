# ISA Specification — tt_um_pveligeti_protoemu

Version 0.1 · 2026-09-25 · Status: **draft, novelty decision pending (due Oct 4)**

## 1. Summary

The core is **binary-compatible with the RP2040 PIO instruction set** (RP2040 datasheet, section 3.4).
Programs assembled with the official `pioasm` or Adafruit's `adafruit_pioasm` run unmodified on the
implemented subset. Our additions live only in encodings that PIO marks *reserved*, so compatibility
is never broken.

Why PIO-compatible:
- The spec, assembler, and example programs (pico-examples: UART, SPI, I2C, WS2812…) already exist.
- Existing PIO software emulators can serve as a second, independent golden model.
- Novelty budget goes into the additions and the verification, not re-inventing a basic ISA.

## 2. Programmer's model (per state machine)

| State | Width | Description |
|---|---|---|
| PC | 5 | Program counter, 32-entry instruction memory |
| X, Y | 32 | Scratch registers / loop counters |
| OSR | 32 | Output shift register (data from host TX FIFO) + 6-bit shift count |
| ISR | 32 | Input shift register (data to host RX FIFO) + 6-bit shift count |
| Delay counter | 5 | Cycles remaining in the current instruction's delay |
| TX FIFO / RX FIFO | 4 × 32 each | Host ↔ state machine data buffers |
| Pins / Pindirs | 8 + 8 | Output values and output-enables (see section 7) |

Instruction memory: 32 × 16-bit words, written by the host. Shared by all state machines (v0 has 1 SM).

## 3. Instruction format

Every instruction is 16 bits:

```
 15  13 12     8 7                0
+------+--------+------------------+
|opcode| dly/ss |     operand      |
+------+--------+------------------+
```

- **[15:13] opcode** — 8 instructions (PUSH and PULL share opcode 100).
- **[12:8] delay / side-set** — 5 bits split by config: the top `SIDESET_COUNT` bits are side-set
  (if `SIDE_EN`, the MSB of those is an enable bit), the rest is delay (0–31 extra cycles).
- **[7:0] operand** — instruction-specific.

## 4. Instruction set

| Opcode | Instr | Operand [7:0] | Phase |
|---|---|---|---|
| 000 | **JMP** | [7:5] condition, [4:0] address | v0 |
| 001 | **WAIT** | [7] polarity, [6:5] source, [4:0] index | v1 |
| 010 | **IN** | [7:5] source, [4:0] bit count (0 = 32) | v1 |
| 011 | **OUT** | [7:5] destination, [4:0] bit count (0 = 32) | v0 |
| 100 | **PUSH** | [7]=0, [6] IfFull, [5] Block, [4:0]=0 | v1 |
| 100 | **PULL** | [7]=1, [6] IfEmpty, [5] Block, [4:0]=0 | v0 |
| 101 | **MOV** | [7:5] dest, [4:3] op, [2:0] source | v1 (NOP = `mov y, y` in v0) |
| 110 | **IRQ** | [7]=0, [6] Clr, [5] Wait, [4:0] index | v2 |
| 111 | **SET** | [7:5] destination, [4:0] data | v0 |

### Operand field tables

**JMP condition [7:5]:** 000 always · 001 `!X` · 010 `X--` · 011 `!Y` · 100 `Y--` · 101 `X!=Y` · 110 `PIN` · 111 `!OSRE`
(`X--`/`Y--`: jump if nonzero *before* the decrement; decrement always happens.)

**WAIT source [6:5]:** 00 GPIO · 01 PIN (relative to IN_BASE) · 10 IRQ · 11 *reserved*

**IN source [7:5]:** 000 PINS · 001 X · 010 Y · 011 NULL · 100 *reserved* · 101 *reserved* · 110 ISR · 111 OSR

**OUT destination [7:5]:** 000 PINS · 001 X · 010 Y · 011 NULL · 100 PINDIRS · 101 PC · 110 ISR · 111 EXEC

**MOV dest [7:5]:** 000 PINS · 001 X · 010 Y · 011 *reserved* · 100 EXEC · 101 PC · 110 ISR · 111 OSR
**MOV op [4:3]:** 00 none · 01 invert · 10 bit-reverse · 11 *reserved*
**MOV source [2:0]:** 000 PINS · 001 X · 010 Y · 011 NULL · 100 *reserved* · 101 STATUS · 110 ISR · 111 OSR

**SET destination [7:5]:** 000 PINS · 001 X · 010 Y · 011 *reserved* · 100 PINDIRS · 101–111 *reserved*

## 5. Timing rules (must hold exactly — these become formal properties)

1. Every instruction executes in **1 SM cycle**, then waits `delay` extra SM cycles.
2. An SM cycle occurs once every `CLKDIV` system clocks (v0: integer divider 1–65535; PIO's fractional part not implemented).
3. **Stalls:** blocking PULL on empty TX FIFO, blocking PUSH on full RX FIFO, and WAIT hold the PC.
   The delay starts only after the stall ends.
4. **Side-set takes effect on the first cycle of the instruction, even if it stalls.**
5. **Wrap:** after executing the instruction at `WRAP_TOP`, PC goes to `WRAP_BOTTOM` at no cost
   (unless the instruction itself jumped).
6. **Reserved encodings execute as NOP** (defined behavior, no X-propagation). *Deviation from PIO,
   which leaves them undefined.*

## 6. Configuration registers (per SM, written by host)

| Register | Fields |
|---|---|
| CLKDIV | 16-bit integer divider |
| EXECCTRL | SIDE_EN, SIDE_PINDIR, JMP_PIN, WRAP_TOP, WRAP_BOTTOM |
| SHIFTCTRL | AUTOPULL, AUTOPUSH, PULL_THRESH, PUSH_THRESH, OUT_SHIFTDIR, IN_SHIFTDIR |
| PINCTRL | OUT_BASE, OUT_COUNT, SET_BASE, SET_COUNT, SIDESET_BASE, SIDESET_COUNT, IN_BASE |
| CTRL | SM_ENABLE, SM_RESTART |

## 7. Pin mapping (Tiny Tapeout, draft — finalize in week 7)

| TT pins | Use |
|---|---|
| `uio[7:0]` | **PIO GPIO 0–7**: bidirectional, per-pin output-enable (needed for I2C open-drain) |
| `ui_in[3:0]` | Host SPI slave: SCK, CS_N, MOSI, spare |
| `uo_out[0]` | Host SPI slave: MISO |
| `ui_in[7:4]` | PIO GPIO 8–11, input-only (extra inputs for WAIT / IN) |
| `uo_out[7:1]` | Status / debug (SM running, FIFO flags, PC low bits) |

## 8. Implementation phases

| Phase | Due | Scope | Proof it works |
|---|---|---|---|
| **v0** | Oct 18 | JMP (all conditions except PIN), OUT (PINS, X, Y, NULL, PINDIRS), PULL (block/noblock, ifempty), SET (PINS, X, Y, PINDIRS), NOP, delay, side-set, wrap, integer CLKDIV, 1 SM, TX FIFO | pico-examples `uart_tx` runs, existing UART cocotb test passes |
| **v1** | Nov 8 | IN, PUSH, WAIT (GPIO/PIN), MOV (all ops), JMP PIN, OUT PC/ISR, autopull/autopush, RX FIFO | `uart_rx`, `spi` programs pass |
| **v2** | Nov 22 | IRQ, OUT/MOV EXEC, STATUS, host SPI loader, 2+ SMs if area allows | `i2c` program passes, chip driven only through pins |
| **Novelty** | Dec 6 | See section 9 | Stretch protocol in sim |

Not planned: fractional clock divider, FIFO join, DMA.

## 9. Novelty — candidates (decide by Oct 4)

All use only reserved encodings or config bits, so PIO programs still run unchanged.

| Candidate | How it fits | Unlocks | Cost |
|---|---|---|---|
| **A. CRC snoop unit** (recommended) | Config-selectable CRC (CRC5/CRC16/CRC-15-CAN) automatically absorbs every bit shifted by OUT/IN. Read with `mov isr, crc` (MOV source 100). Clear with `mov crc, null` (MOV dest 011). | USB low-speed, CAN, SD — protocols PIO cannot finish alone | ~few hundred cells |
| **B. WAIT with timeout** | WAIT source 11: wait for pin, but give up when X reaches 0 (X decrements each cycle). Program checks `jmp !x timeout` afterwards. | Robust I2C clock-stretch, bus-hang recovery | Small |
| **C. Larger program memory** | Page register selects 32-word bank; JMP stays 5-bit within page. | Longer protocols (USB) | SRAM macro + more complexity |

Recommendation: **A**, optionally plus **B**. Directly answers "what would you do differently" —
the missing piece for USB/CAN is CRC, and it costs zero ISA compatibility.

## 10. Verification hooks

- **Architected state for golden-model compare (every SM cycle):** PC, X, Y, OSR, ISR, shift counts,
  delay counter, pins, pindirs, FIFO levels.
- **Encoding check:** every program is assembled with `pioasm` and must match our assembler/decoder bit-for-bit.
- **Reference:** UART TX (pico-examples) assembles to `9fa0 f727 6001 0642` (verified with `adafruit_pioasm`) — first regression test.
- **Formal properties (candidates):** delay is exact; wrap is correct; reserved = NOP;
  side-set applies during stalls; `X--` loop runs exactly X+1 times.

## References

- RP2040 datasheet, ch. 3: https://datasheets.raspberrypi.com/rp2040/rp2040-datasheet.pdf
- pico-examples PIO programs: https://github.com/raspberrypi/pico-examples/tree/master/pio
- lawrie/fpga_pio (Verilog PIO): https://github.com/lawrie/fpga_pio
