# SPI Front Panel FPGA Development - Skills Reference

This file provides concise context references for asking about specific lessons in the SPI educational series. Use these identifiers when seeking help with a particular lesson.

## Quick Reference: Lesson IDs

| Lesson | File | Topic |
|--------|------|-------|
| 1 | `lesson-1-spi-target.md` | Basic SPI Target Module |
| 2 | `lesson-2-sv-spi-testbench.md` | SystemVerilog Basics & Testbench |
| 3 | `lesson-3-command-interpreter-pt1.md` | Command Interpreter - Register Architecture |
| 4 | `lesson-4-command-interpreter-pt2.md` | Command Interpreter - Test Bench |
| 5 | `lesson-5-bus-interface.md` | S100 Bus Interface Module |
| 6 | `lesson-6-integration.md` | Integration - SPI Front Panel Module |
| 7 | `lesson-7-system-test.md` | System Test |
| 8 | `lesson-8-fpga-integration.md` | FPGA Integration |

## Skill Identifiers

Use these skill IDs to reference specific lessons when asking for help:

### `/spi-lesson-1` - SPI Target Module
- Creating a SPI target module in Verilog
- SPI timing with CPOL=0, CPHA=0
- 16-bit transaction format (8-bit command + 8-bit data)
- MOSI sampling and MISO driving on SPI clock edges
- Test bench basics for SPI modules

**Common Issues:**
- SPI clock polarity/phase mismatch
- MISO timing relative to clock edges
- Transaction completion detection

### `/spi-lesson-2` - SystemVerilog Test Bench
- Writing test benches in SystemVerilog
- `$display`, `$monitor`, `$dumpfile`, `$dumpvars`
- Task definitions for reusable test stimulus
- Compiling with `iverilog -g2012`
- Running simulations with `vvp`
- Viewing waveforms with `gtkwave`

**Common Issues:**
- Forgetting `-g2012` flag for SystemVerilog
- VCD files not being generated
- Timing issues in test bench (clock delays)
- Using `==` instead of `===` for X comparison

### `/spi-lesson-3` - Command Interpreter
- Register architecture design
- Command byte map and decoding
- Control register bit definitions
- Auto-clear bits (single step, reset)
- Address pointer management
- SENSE register for IO port 0xFF

**Command Codes:**
| Command | Description | Data Direction |
|---------|-------------|----------------|
| 0x00 | Set address high | In |
| 0x01 | Set address low | In |
| 0x02 | Read byte (memory) | Out |
| 0x03 | Write byte (memory) | In |
| 0x10 | Read SENSE register | Out |
| 0x11 | Write SENSE register | In |
| 0x20 | Read control register | Out |
| 0x21 | Write control register | In |
| 0x30 | Latch bus state | In (no data) |
| 0x31-0x35 | Read latched values | Out |

**Control Register Bits:**
| Bit | Name | Description |
|-----|------|-------------|
| 0 | CPU_RUN_N | 0 = CPU halted, 1 = running (active high) |
| 1 | CPU_SINGLE_STEP | 1 = enable single step (auto-clears) |
| 2 | ADDR_ADV_ON_XFER | 1 = advance address on read/write |
| 3 | S100_RESET_N | 0 = assert reset (active low, auto-clears) |

**Common Issues:**
- Auto-clear bits not clearing at correct time
- Address pointer not incrementing with ADDR_ADV_ON_XFER
- Command valid/ready handshake timing

### `/spi-lesson-4` - Command Interpreter Test Bench
- Testing all command codes
- Address pointer verification
- SENSE register read/write testing
- Control register auto-clear testing
- Bus state latch testing
- Unknown command handling

**Common Issues:**
- Not waiting correct number of clock cycles
- spi_tx_complete timing (must be 1 clock cycle)
- Test task parameter passing

### `/spi-lesson-5` - S100 Bus Interface
- State machine design (IDLE → ADDRESS → READ/WRITE → IDLE)
- Tri-state bus driving
- Bus monitoring outputs
- Error handling for invalid operations

**Common Issues:**
- Tri-state control (oe vs data)
- State machine not returning to IDLE
- Bus contention in test bench

### `/spi-lesson-6` - Integration
- Instantiating multiple modules in top-level
- SPI front panel module design
- End-to-end test bench with SPI master simulation
- Signal merging between modules

**Common Issues:**
- Port mapping mismatches between modules
- SPI master simulation timing in test bench
- Internal wire declarations

### `/spi-lesson-7` - System Test
- System-level test bench design
- Connecting SPI front panel to Altair 8800 simulation
- Testing with CPU running
- Bus arbitration concepts

**Common Issues:**
- Bus contention between CPU and SPI interface
- Timing conflicts
- Reset synchronization

### `/spi-lesson-8` - FPGA Integration
- Adding SPI front panel to altair.v
- Pin constraint (PCF) file creation
- Clock domain handling (16MHz system → 4MHz SPI)
- Bus merging for FPGA implementation
- Building and programming the FPGA

**Common Issues:**
- PCF pin assignments
- Clock divider calculation
- Bus arbitration in hardware
- Timing violations in synthesis

## General Verilog/SystemVerilog Tips

### Simulation vs Synthesis
- `reg` in `always @(posedge clk)` = flip-flop (synthesizable)
- `reg` in `always @(*)` = combinational logic (synthesizable)
- `wire` = continuous assignment or port connection

### Test Bench Best Practices
- Always use `===` to compare with possible X values
- Use `#delay` for time stepping
- Dump VCD for waveform viewing
- Use `$finish` to end simulation

### Common Icarus Verilog Commands
```bash
# Compile
iverilog -g2012 -o output.out design.v tb.v

# Run simulation
vvp output.out

# Generate VCD (add to test bench)
$dumpfile("waves.vcd");
$dumpvars(0, top_module);
```

### ICE40 FPGA Tips
- Use `nextpnr-ice40` for place and route
- Use `icepack` to convert ASC to BIN
- Check timing reports for violations
- ICE40UP5K has 80 Kbits of SRAM for block RAM

## Debugging Commands

```bash
# Find X values in simulation
vvp output.out 2>&1 | grep -i "x\|z"

# Check VCD file size
ls -la *.vcd

# List modules in compiled file
iverilog -t modules design.v

# Synthesis check (Yosys)
yosys -p "synth_ice40 -top my_module -json out.json" design.v