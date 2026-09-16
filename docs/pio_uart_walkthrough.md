# PIO UART TX, instruction by instruction

The official RP2040 `uart_tx` program (clocked at 8x baud):

```
.program uart_tx
.side_set 1 opt
    pull       side 1 [7]   ; 0: get byte from FIFO (blocks). Pin held HIGH = idle / stop bit
    set x, 7   side 0 [7]   ; 1: x = bit counter. Pin LOW = start bit, held 8 cycles
bitloop:
    out pins, 1             ; 2: shift 1 bit from OSR to pin
    jmp x-- bitloop   [6]   ; 3: loop 8 times; 1 + 6 delay + out = 8 cycles per bit
```

| # | Instr | What the hardware does | Cycles |
|---|-------|------------------------|--------|
| 0 | `pull side 1 [7]` | side-set drives TX=1 *in the same cycle*; OSR <- FIFO (stalls while empty, pin stays 1) | 1 + 7 = 8 (the stop bit) |
| 1 | `set x,7 side 0 [7]` | two effects at once: X=7 and TX=0 | 8 (the start bit) |
| 2 | `out pins,1` | OSR shifts right, LSB -> pin | 1 |
| 3 | `jmp x-- bitloop [6]` | branch if X!=0, then X-- ; delay 6 | 7 -> bit time = 8 |

Four instructions. Tricks worth stealing / improving on:
1. **Side-set** — a pin change piggybacks on any instruction, so no extra cycles.
2. **Delay field** — timing lives in the instruction, not in loops.
3. **Stop bit is free** — it is the delay on the `pull` that begins the next byte.
4. **`jmp x--` is post-decrement** — one instruction is both compare and counter update.

Where PIO hurts (our "what we'd do differently" list):
- 32 instructions total per block, shared by 4 state machines.
- Only X/Y scratch registers, no add/xor -> no CRC, no bit-stuffing counters beyond trivial ones (blocks USB, CAN, Ethernet).
- `wait` has no timeout (a stuck I2C bus hangs the machine).
- Delay max 31 cycles; long delays need nested loops.
