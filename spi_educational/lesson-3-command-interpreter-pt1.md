# Lesson 3: Command Interpreter Part 1 - Register Architecture

## Objective

Create the command interpreter module that receives commands from the SPI target and manages the internal registers used by the SPI front panel system. This lesson focuses on the register architecture; command parsing comes in Lesson 4.

## Background: The Command Interpreter

The command interpreter sits between the SPI target and the S100 bus interface. Its job is to:

1. Receive commands from the SPI target via `tx_complete` signals
2. Store command data in appropriate registers
3. Provide a SENSE register readable via IO port 0xFF
4. Manage control registers that affect system behavior

### System Overview

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────┐
│  SPI Target  │────▶│  Command         │────▶│  Bus        │
│  (Lesson 1)  │     │  Interpreter     │     │  Interface  │
│              │◀────│  (Lessons 3-5)   │◀────│  (Lesson 6) │
└──────────────┘     └──────────────────┘     └─────────────┘
                          │
                          ▼
                    ┌──────────────┐
                    │  Registers   │
                    │  Architecture│
                    └──────────────┘
```

## Part 1: Register Definitions

### Command Byte Map

Here are the commands we'll implement (organized by category):

**Address Commands:**
| Command | Description | Data Direction |
|---------|-------------|----------------|
| 0x00 | Set address high | In |
| 0x01 | Set address low | In |

**Memory Commands:**
| Command | Description        | Data Direction |
|---------|--------------------|----------------|
| 0x02    | Read byte (memory) | Out            |
| 0x03    | Write byte (memory)| In             |

**Sense Register:**
| Command | Description         | Data Direction |
|---------|---------------------|----------------|
| 0x10    | Read SENSE register | Out            |
| 0x11    | Write SENSE register| In             |

**Control Register:**
| Command | Description           | Data Direction |
|---------|-----------------------|----------------|
| 0x20    | Read control register | Out            |
| 0x21    | Write control register| In             |

**Bus State Sampling:**
| Command | Description               | Data Direction |
|---------|---------------------------|----------------|
| 0x30    | Latch bus state           | In (no data)   |
| 0x31    | Read latched address high | Out            |
| 0x32    | Read latched address low  | Out            |
| 0x33    | Read latched data         | Out            |
| 0x34    | Read latched status       | Out            |
| 0x35    | Read latched signals      | Out            |

### Register Architecture

The command interpreter contains the following internal registers:

#### Address Pointer Register (16 bits)

Used by read/write byte commands as the target memory address.

```verilog
reg [15:0] addr_ptr;        // Full 16-bit address pointer
reg [7:0]  addr_ptr_hi;     // High byte (for read-back)
reg [7:0]  addr_ptr_lo;     // Low byte (for read-back)
```

#### SENSE Register (8 bits)

This register is mapped to IO port 0xFF. When the CPU performs an IO read to 0xFF, it reads this register. The ESP32 can write to this register to communicate status back to the system.

```verilog
reg [7:0]  sense_reg;       // SENSE register value
```

Per the requirements:
- **IO read cycles** to 0xFF are mediated by `STATUS[6]` in the STATUS latch in `altair.v`
- SPI can write to SENSE register (no need to read back via SPI - the CPU reads it)
- The sense register captures information about the current bus state

#### Control Register (8 bits)

Controls various system behaviors:

```verilog
reg [7:0]  ctrl_reg;        // Control register

// Control register bit definitions:
// Bit 0: CPU_RUN_N          - 0 = CPU halted, 1 = CPU running (active high)
// Bit 1: CPU_SINGLE_STEP    - 1 = enable single step (auto-clears after trigger)
// Bit 2: ADDR_ADV_ON_XFER   - 1 = advance address pointer on each read/write
// Bit 3: S100_RESET_N       - 0 = assert S100 reset, 1 = normal operation (active low)
// Bits 7:4: Reserved
```

#### Bus State Latch Registers (for sampling)

These capture the S100 bus state when the "Latch bus state" command is received:

```verilog
reg [7:0]  bus_addr_hi;     // Latched address high byte
reg [7:0]  bus_addr_lo;     // Latched address low byte
reg [7:0]  bus_data;        // Latched data bus value
reg [7:0]  bus_status;      // Latched STATUS latch value
reg [7:0]  bus_signals;     // Packed signals byte

// Bus signals byte format:
// Bit 0: INTE (Interrupt enabled)
// Bit 1: PROT (Protection)
// Bit 2: WAIT
// Bit 3: HLDA (Hold Acknowledge)
// Bits 7:4: Reserved (zero)
```

#### Command State

Track the current command and data flow:

```verilog
reg [7:0]  cmd_reg;         // Current command from SPI
reg [7:0]  cmd_data_in;     // Data received from SPI (write)
reg [7:0]  cmd_data_out;    // Data to send via SPI (read)
reg        cmd_valid;       // Command is valid/ready
reg        cmd_ready;       // Interpreter is ready for new command
```

## Part 2: Creating the Module

Create `spi_educational/rtl/spi_cmd_interpreter.v`:

```verilog
module spi_cmd_interpreter(
    input  wire        clk,
    input  wire        reset,

    // SPI target interface
    input  wire        spi_tx_complete,
    input  wire [7:0]  spi_cmd,
    input  wire [7:0]  spi_data_in,
    output reg  [7:0]  spi_data_out,

    // Control register output
    output wire [7:0]  ctrl_reg_out,

    // SENSE register
    output wire [7:0]  sense_reg_out,

    // Address pointer output
    output wire [15:0] addr_ptr_out,

    // Bus state latch interface
    input  wire        bus_latch_en,
    input  wire [7:0]  bus_latch_addr_hi,
    input  wire [7:0]  bus_latch_addr_lo,
    input  wire [7:0]  bus_latch_data,
    input  wire [7:0]  bus_latch_status,
    input  wire [7:0]  bus_latch_signals,

    // Bus state read interface
    output wire [7:0]  bus_latch_addr_hi_out,
    output wire [7:0]  bus_latch_addr_lo_out,
    output wire [7:0]  bus_latch_data_out,
    output wire [7:0]  bus_latch_status_out,
    output wire [7:0]  bus_latch_signals_out,

    // Status flags
    output wire        cmd_ready_out,
    output wire        bus_latched
);
```

## Part 3: Command Processing Logic

### Command Reception

When `spi_tx_complete` is asserted, capture the command and data:

```verilog
// Capture command on SPI transaction complete
always @(posedge clk) begin
    if (reset) begin
        cmd_reg <= 8'b0;
        cmd_data_in <= 8'b0;
        cmd_valid <= 1'b0;
    end else if (spi_tx_complete) begin
        cmd_reg <= spi_cmd;
        cmd_data_in <= spi_data_in;
        cmd_valid <= 1'b1;
    end else begin
        cmd_valid <= 1'b0;  // Clear after one cycle
    end
end
```

### Command Decode

Use a case statement to decode commands and set appropriate outputs:

```verilog
// Command decode logic
always @(*) begin
    // Default assignments
    spi_data_out = 8'b0;
    addr_ptr_out = addr_ptr;
    ctrl_reg_out = ctrl_reg;
    sense_reg_out = sense_reg;
    bus_latch_addr_hi_out = 8'b0;
    bus_latch_addr_lo_out = 8'b0;
    bus_latch_data_out = 8'b0;
    bus_latch_status_out = 8'b0;
    bus_latch_signals_out = 8'b0;
    bus_latch_en = 1'b0;

    case (cmd_reg)
        // Address set commands
        8'h00: begin
            // Set address high
            addr_ptr[15:8] = cmd_data_in;
        end
        8'h01: begin
            // Set address low
            addr_ptr[7:0] = cmd_data_in;
        end

        // Memory read/write
        8'h02: begin
            // Read byte - output data from addr_ptr
            spi_data_out = mem_data_at_addr;  // To be implemented in bus interface
        end
        8'h03: begin
            // Write byte - data in cmd_data_in at addr_ptr
            // Action passed to bus interface
        end

        // Sense register
        8'h10: begin
            // Read SENSE register
            spi_data_out = sense_reg;
        end
        8'h11: begin
            // Write SENSE register
            sense_reg = cmd_data_in;
        end

        // Control register
        8'h20: begin
            // Read control register
            spi_data_out = ctrl_reg;
        end
        8'h21: begin
            // Write control register
            ctrl_reg = cmd_data_in;
        end

        // Bus state sampling
        8'h30: begin
            // Latch bus state
            bus_latch_en = 1'b1;
        end
        8'h31: begin
            // Read latched address high
            spi_data_out = bus_addr_hi;
        end
        8'h32: begin
            // Read latched address low
            spi_data_out = bus_addr_lo;
        end
        8'h33: begin
            // Read latched data
            spi_data_out = bus_data;
        end
        8'h34: begin
            // Read latched status
            spi_data_out = bus_status;
        end
        8'h35: begin
            // Read latched signals
            spi_data_out = bus_signals;
        end

        default: begin
            // Unknown command - output 0xFF as error indicator
            spi_data_out = 8'hFF;
        end
    endcase
end
```

## Part 4: Your Task

Create `spi_educational/rtl/spi_cmd_interpreter.v` with:

1. **All the registers** defined above
2. **Command reception logic** that captures commands on `spi_tx_complete`
3. **Command decode logic** that handles the commands listed above
4. **Control register bit handling**:
   - `CPU_SINGLE_STEP` should auto-clear after being written
   - `S100_RESET_N` should auto-clear after being written
5. **Address pointer increment** when `ADDR_ADV_ON_XFER` is set (for read/write commands)

### Implementation Hints

For the control register auto-clear bits:

```verilog
// Auto-clear single step after write
if (cmd_reg == 8'h21) begin
    if (cmd_data_in[1]) begin  // Single step bit
        ctrl_reg[1] <= 1'b1;
        // Schedule auto-clear
        auto_clear_single_step <= 1'b1;
    end
    if (cmd_data_in[3]) begin  // Reset bit
        ctrl_reg[3] <= 1'b0;  // Active low, write 1 to assert
        // Schedule auto-clear
        auto_clear_reset <= 1'b1;
    end
    // ... other control bits
end
```

For address pointer auto-advance:

```verilog
if (cmd_reg == 8'h02 || cmd_reg == 8'h03) begin  // Read or write
    if (ctrl_reg[2]) begin  // ADDR_ADV_ON_XFER
        addr_ptr <= addr_ptr + 1;
    end
end
```

## Part 5: Self-Check Questions

- [ ] Do you understand the purpose of each register in the command interpreter?
- [ ] Can you explain how the command decode logic works?
- [ ] Does your control register handle auto-clear bits correctly?
- [ ] Does the address pointer advance work as expected?
- [ ] Are all command codes correctly handled?

## What's Next

In Lesson 4, you'll add test bench coverage for the command interpreter and verify all commands work correctly. In Lesson 5, you'll add the bus state sampling commands and complete the command interpreter.