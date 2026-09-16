# SPDX-License-Identifier: Apache-2.0
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

CLKS_PER_BIT = 87


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 100, unit="ns").start())  # 10 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)


async def uart_receive(dut):
    """Independent UART decoder: find start bit, sample mid-bit."""
    tx = lambda: int(dut.uo_out.value) & 1
    while tx() == 1:
        await FallingEdge(dut.clk)
    await ClockCycles(dut.clk, CLKS_PER_BIT // 2)
    assert tx() == 0, "start bit glitch"
    byte = 0
    for i in range(8):
        await ClockCycles(dut.clk, CLKS_PER_BIT)
        byte |= tx() << i
    await ClockCycles(dut.clk, CLKS_PER_BIT)
    assert tx() == 1, "missing stop bit"
    return byte


async def send(dut, value):
    dut.ui_in.value = value
    dut.uio_in.value = 1
    await RisingEdge(dut.clk)
    dut.uio_in.value = 0


@cocotb.test()
async def test_idle_high(dut):
    await reset(dut)
    await ClockCycles(dut.clk, 200)
    assert int(dut.uo_out.value) & 1 == 1


@cocotb.test()
async def test_uart_tx_random_bytes(dut):
    await reset(dut)
    for value in [0x00, 0xFF, 0x55, 0xA5] + [random.randrange(256) for _ in range(12)]:
        rx = cocotb.start_soon(uart_receive(dut))
        await send(dut, value)
        got = await rx
        assert got == value, f"sent {value:#04x} got {got:#04x}"
        while int(dut.uo_out.value) >> 1 & 1:
            await RisingEdge(dut.clk)
        dut._log.info(f"ok {value:#04x}")
