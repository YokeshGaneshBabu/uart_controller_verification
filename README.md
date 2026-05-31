# UART Controller Verification — UVM Testbench

**SystemVerilog | UVM 1.2 | Aldec Riviera-PRO | EDA Playground**

---

## Results

| Test | Transactions | Pass | Fail | Coverage | UVM_ERROR |
|------|-------------|------|------|----------|-----------|
| `uart_rand_test` | 20 | 20 | 0 | 75% | 0 |
| `uart_directed_test` | 28 | 28 | 0 | **100%** | 0 |

---

## What This Project Does

A complete UVM verification environment for a UART controller RTL. The testbench drives the `uart_tx` module with randomized and directed stimulus, the serial output passes through `uart_rx`, and the recovered byte is compared against what was sent. Bugs in the RTL serialization, parity logic, or baud counter would cause scoreboard failures.

---

## Architecture

```
                  ┌─────────────────────────────────────┐
                  │            uart_directed_test       │
                  │              uart_rand_test         │
                  └──────────────┬──────────────────────┘
                                 │
                  ┌──────────────▼──────────────────────┐
                  │               uart_env              │
                  │                                     │
                  │  ┌─────────────────────────────┐    │
                  │  │         uart_agent          │    │
                  │  │  driver → sequencer         │    │
                  │  │  monitor ←────────────────  │    │
                  │  └──────┬──────────────┬───────┘    │
                  │         │              │            │
                  │  ┌──────▼──────┐  ┌───▼──────────┐  │
                  │  │ scoreboard  │  │   coverage   │  │
                  │  └─────────────┘  └──────────────┘  │
                  └─────────────────────────────────────┘
                                 │
              ┌──────────────────▼─────────────────────┐
              │                tb_top                  │
              │                                        │
              │   driver → [uart_tx RTL] ──serial──→   │
              │             [uart_rx RTL] → rx_done    │
              │                          → rx_data     │
              │                          → rx_err flags│
              │                                        │
              │   uart_sva bound here (assertions)     │
              └────────────────────────────────────────┘
```

---

## File Structure

```
├── uart_design.sv
│   ├── uart_if        signal bundle + clocking block + DUT control signals
│   ├── uart_tx        RTL: serializes byte → START + DATA + PARITY + STOP
│   ├── uart_rx        RTL: deserializes serial input, flags parity/framing errors
│   └── uart_sva       SVA protocol assertions bound to tb_top
│
└── uart_testbench.sv
    ├── uart_seq_item  transaction: data[7:0], parity_mode, baud_rate
    ├── uart_config    shared object: driver writes baud_rate, monitor reads it
    ├── uart_rand_seq  20 constrained-random frames
    ├── uart_directed_seq  8 corner-case frames (0x00/0xFF/0xAA/0x55 × both baud rates)
    ├── uart_b2b_seq   10 back-to-back frames
    ├── uart_sequencer
    ├── uart_driver    drives tx_valid/tx_data/parity_sel/baud_sel, waits for tx_busy
    ├── uart_monitor   waits for rx_done from RTL, reads rx_data and error flags
    ├── uart_scoreboard  dual analysis ports: driver (expected) vs monitor (actual)
    ├── uart_coverage  covergroups: baud rate × parity mode × data patterns
    ├── uart_env
    ├── uart_rand_test
    ├── uart_directed_test
    ├── uart_b2b_test
    └── tb_top         instantiates uart_tx + uart_rx RTL, binds SVA
```

---

## RTL: uart_tx

State machine: `IDLE → START → DATA → PARITY → STOP`

- Configurable baud rate via `baud_sel` (9600 or 115200 at 50MHz clock)
- Configurable parity via `parity_sel` (NONE / EVEN / ODD)
- Serializes data byte LSB-first
- Asserts `tx_busy` while transmitting, deasserts when done

## RTL: uart_rx

State machine: `IDLE → START → DATA → PARITY → STOP`

- Detects start bit falling edge
- Samples at mid-bit (baud/2 offset from start) for reliability
- Two-flop synchronizer on `rx_in` to avoid metastability
- Asserts `rx_done` for one cycle when frame received
- Sets `rx_parity_err` and `rx_frame_err` flags on protocol violations

---

## Test Cases

### uart_rand_test
20 constrained-random frames. Both baud rates (9600, 115200) and all parity modes (NONE, EVEN, ODD) randomized within constraints. Exercises broad stimulus space.

### uart_directed_test
8 fixed corner-case frames followed by 20 random frames:

| Data | Parity | Baud | Targets |
|------|--------|------|---------|
| 0x00 | EVEN | 115200 | All-zeros byte |
| 0xFF | ODD | 115200 | All-ones byte |
| 0xAA | NONE | 115200 | Alternating 10101010 |
| 0x55 | EVEN | 115200 | Alternating 01010101 |
| 0x00 | NONE | 9600 | All-zeros at low baud |
| 0xFF | EVEN | 9600 | All-ones at low baud |
| 0xAA | ODD | 9600 | Alternating at low baud |
| 0x55 | ODD | 9600 | Alternating at low baud |

### uart_b2b_test
10 back-to-back frames at 115200 baud with minimal inter-frame gap.

---

## Functional Coverage

| Coverpoint | Bins | Closure |
|------------|------|---------|
| `cp_baud` | 9600, 115200 | ✓ |
| `cp_parity` | NONE, EVEN, ODD | ✓ |
| `cp_data` | 0x00, 0xFF, 0xAA, 0x55, others | ✓ |
| `cx_baud_parity` | 6 cross bins (2 baud × 3 parity) | ✓ |

**100% coverage achieved with `uart_directed_test`.**

---

## SVA Assertions

| Assertion | Checks |
|-----------|--------|
| `a_tx_no_x` | TX serial line never goes unknown (X/Z) |
| `a_tx_idle` | TX returns HIGH within 10 clocks after reset |
| `a_rx_no_x` | RX line never goes unknown (X/Z) |
| `c_frame_started` | Cover: counts UART frames transmitted |

Zero assertion violations across all test runs.

---

## Running on EDA Playground

1. Go to [edaplayground.com](https://edaplayground.com)
2. Languages: **SystemVerilog/Verilog** — UVM/OVM: **UVM 1.2**
3. Simulator: **Aldec Riviera-PRO**
4. Design tab: `uart_design.sv` (uart_if + uart_tx + uart_rx + uart_sva)
5. Testbench tab: `uart_testbench.sv`
6. Run options: `+UVM_TESTNAME=uart_directed_test +UVM_VERBOSITY=UVM_MEDIUM`
7. Click Run

To switch tests change `+UVM_TESTNAME` to `uart_rand_test` or `uart_b2b_test`.
