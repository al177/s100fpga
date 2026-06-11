# Lesson 8: FPGA Integration

## Objective

Integrate the SPI front panel module into the actual FPGA design in `altair.v` and create the pin constraints file for programming the ESP32 and FPGA.

## Background

This lesson covers:
1. Adding the SPI front panel instantiation to `altair.v`
2. Connecting the SPI signals to the ICE40UP5K hard IP SPI interface
3. Updating the pin constraint files
4. Building and programming the FPGA

## Part 1: Review altair.v Structure

First, examine the existing `rtl/altair.v` to understand where to add the SPI front panel:

```verilog
// altair.v structure:
module altair(
    input wire clk,           // 16MHz system clock
    input wire reset,         // Reset button
    
    // S100 Bus signals
    inout wire [7:0] data_bus,
    output wire [15:0] addr_bus,
    // ... other S100 signals
    
    // USB UART
    output wire tx,
    input wire rx
);
```

### Key Areas to Modify

1. **SPI Interface Pins**: Add SPI signal declarations
2. **SPI Front Panel Instance**: Add the `spi_front_panel` module
3. **Clock Domain**: The SPI runs at up to 4MHz, system clock is 16MHz

## Part 2: Updated altair.v with SPI Front Panel

Add these sections to `rtl/altair.v`:

```verilog
module altair(
    input wire clk,
    input wire reset,

    // S100 Bus
    inout wire [7:0] data_bus,
    output wire [15:0] addr_bus,
    output wire [7:0] paddr_bus,
    input wire [7:0] addr_bus_in,
    
    // S100 Control signals
    output wire IOI_n,
    output wire WOI_n,
    output wire ROI_n,
    output wire MEMR_n,
    output wire MEMW_n,
    output wire AHE_n,
    output wire F1_n,
    output wire F2_n,
    output wire CLK_6_n,
    output wire RESET_n,
    output wire HLDA_n,
    output wire [7:0] status,
    
    // SPI Front Panel Interface (to ESP32)
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output wire spi_ss,
    
    // FPGA INT (FPGA to ESP32 interrupt)
    output wire fpga_int,
    
    // USB UART
    output wire uart_tx,
    input wire uart_rx
);

    // =============================
    // SPI Front Panel Signals
    // =============================
    wire [7:0]  fp_data_out;
    wire        fp_data_oe;
    wire [15:0] fp_addr_out;
    wire        fp_addr_oe;
    wire        fp_memr_n;
    wire        fp_memw_n;
    wire        fp_ior_n;
    wire        fp_iow_n;
    wire        fp_cpu_run_n;
    wire        fp_s100_reset_n;

    // SPI clock divider (system clock is 16MHz, SPI max 4MHz)
    reg [1:0] clk_div;
    always @(posedge clk) begin
        if (reset)
            clk_div <= 0;
        else
            clk_div <= clk_div + 1;
    end
    wire spi_clk_sys = clk_div[1];  // 4MHz from 16MHz

    // SPI Front Panel Instance
    spi_front_panel u_spi_front_panel (
        .clk(clk),
        .reset(reset),
        .spi_ss_n(~spi_ss),      // Active low
        .spi_sclk(spi_clk_sys),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .fp_data_out(fp_data_out),
        .fp_data_oe(fp_data_oe),
        .fp_data_in(data_bus),
        .fp_addr_out(fp_addr_out),
        .fp_addr_oe(fp_addr_oe),
        .fp_memr_n(fp_memr_n),
        .fp_memw_n(fp_memw_n),
        .fp_ior_n(fp_ior_n),
        .fp_iow_n(fp_iow_n),
        .fp_cpu_run_n(fp_cpu_run_n),
        .fp_s100_reset_n(fp_s100_reset_n)
    );
```

## Part 3: Bus Merging

When both the CPU and SPI front panel try to drive the bus, you need to merge the signals. The CPU has priority; the SPI front panel only drives when requested:

```verilog
    // Bus merging - CPU has priority
    // When fp_addr_oe is high, SPI front panel is driving
    // Otherwise, CPU is driving (from existing altair logic)
    
    assign data_bus = (fp_data_oe & ~cpu_data_tri) ? fp_data_out : 8'hZZ;
    assign addr_bus = (fp_addr_oe & ~cpu_addr_tri) ? fp_addr_out : 16'hZZZZ;
    
    // Merge control signals (SPI asserts = CPU would assert)
    assign MEMR_n = MEMR_n & fp_memr_n;    // Both must assert for active
    assign MEMW_n = MEMW_n & fp_memw_n;
    assign IOI_n = IOI_n & fp_ior_n;
    assign WOI_n = WOI_n & fp_iow_n;
```

**Important**: For a proper implementation, you'll need to create a bus arbiter that prevents conflicts. The simplest approach is to have the SPI front panel operate in a "monitor-only" mode during normal CPU operation, with explicit control commands taking priority when the CPU is halted.

## Part 4: Pin Constraints File

Create or update the pin constraint file. The board uses a board.pcf file:

```pcf
# board.pcf - ESP32 + ICE40UP5K SPI Front Panel

# System clock (from ESP32 GPIO)
set_pin_location -c 33 -d CLOCK_0  # Or appropriate clock pin
set_io -c 33 clk;

# Reset
set_pin_location -c XX -d RESET  # Reset button
set_io -c XX reset;

# SPI Interface (to ESP32)
# According to AGENTS.md:
# SPI clock: 34
# SPI MOSI: 33
# SPI MISO: 32
# SPI SS: 35

set_io -c 34 spi_sclk;
set_io -c 33 spi_mosi;
set_io -c 32 spi_miso;
set_io -c 35 spi_ss;

# FPGA INT (FPGA to ESP32 interrupt)
set_io -c 22 fpga_int;

# USB UART (if used)
set_io -c XX uart_tx;
set_io -c XX uart_rx;

# S100 Bus connections
# These connect to the S100 bus edge connector
# Data bus (bidirectional)
set_io -c XX data_bus[0];
set_io -c XX data_bus[1];
...
set_io -c XX data_bus[7];

# Address bus
set_io -c XX addr_bus[0];
...
set_io -c XX addr_bus[15];

# S100 control signals
set_io -c XX MEMR_n;
set_io -c XX MEMW_n;
set_io -c XX IOI_n;
set_io -c XX WOI_n;
...
```

## Part 5: Updating the Makefile

Add targets for building the SPI front panel design:

```makefile
# SPI Front Panel RTL files
SPI_FRONT_PANEL_RTL=spi_educational/rtl/spi_target.v \
                    spi_educational/rtl/spi_cmd_interpreter.v \
                    spi_educational/rtl/spi_bus_interface.v \
                    spi_educational/rtl/spi_front_panel.v

# Default target - Altair with SPI front panel
all: build/bitstream/altair.bin

# Build with SPI front panel
build/bitstream/altair_spi.bin: rtl/altair_spi.v $(SPI_FRONT_PANEL_RTL) board_v1.pcf
	mkdir -p build/bitstream
	iverilog -g2012 -o build/altair_spi.sim \
	    rtl/altair_spi.v $(SPI_FRONT_PANEL_RTL) rtl/*.v top/top_altair.v
	vvp build/altair_spi.sim
	yosys -p "read_verilog -sv build/altair_spi.sim; synth_ice40 -top altair -blif build/altair_spi.blif"
	nextpnr-ice40 --up5k --package CG4K --asc build/altair_spi.asc \
	    --pcf board_v1.pcf --json build/altair_spi.json
	icepack build/altair_spi.asc build/bitstream/altair_spi.bin

# Run SPI educational tests
test-spi:
	$(MAKE) test_spi_target
	$(MAKE) test_spi_cmd_interpreter
	$(MAKE) test_spi_bus_interface
	$(MAKE) test_spi_front_panel
```

## Part 6: altair_spi.v Wrapper

For the actual FPGA build, create `rtl/altair_spi.v` that wraps the altair module with the SPI front panel:

```verilog
// rtl/altair_spi.v
// Wrapper that adds SPI front panel to the altair design

`include "altair.v"

module altair_spi(
    input wire clk,
    input wire reset,
    
    // S100 Bus
    inout wire [7:0] data_bus,
    output wire [15:0] addr_bus,
    // ... other S100 signals
    
    // SPI to ESP32
    output wire spi_sclk,
    output wire spi_mosi,
    input wire spi_miso,
    output wire spi_ss,
    
    // FPGA INT
    output wire fpga_int,
    
    // UART
    output wire uart_tx,
    input wire uart_rx
);

    // Instantiate SPI front panel and connect
    // This is similar to the code shown in Part 2
    
    // The key difference from altair.v is:
    // 1. Add SPI port declarations
    // 2. Add spi_front_panel instantiation
    // 3. Merge bus signals appropriately
    
endmodule
```

## Part 7: Programming the FPGA

Once the bitstream is built:

```bash
# Build the bitstream
make build/bitstream/altair_spi.bin

# Upload to FPGA via ESP32 (using iceboot.py)
cd blinkencard/micropython
python3 iceboot.py build/bitstream/altair_spi.bin

# Or use direct SPI programming
iceprog build/bitstream/altair_spi.bin
```

## Part 8: Testing on Hardware

1. **Connect ESP32 Telnet**:
   ```bash
   telnet <esp32_ip> 23
   ```

2. **Test SPI Commands**:
   ```
   # Read control register
   > 2000
   
   # Set address
   > 00AB
   > 01CD
   
   # Read memory
   > 0200
   ```

3. **Verify Front Panel LEDs**:
   The S100 bus state should be reflected in the virtual front panel via the ESP32.

## Part 9: Self-Check Questions

- [ ] Are the SPI pins correctly mapped in the PCF file?
- [ ] Does the SPI front panel instantiate within altair.v without conflicts?
- [ ] Is the clock divider correctly generating a 4MHz SPI clock?
- [ ] Does the bus merging prevent contention between CPU and SPI?
- [ ] Can you build the bitstream without errors?
- [ ] Does the FPGA program successfully via ESP32?

## Troubleshooting

### SPI not responding
- Check that CPOL=0, CPHA=0 matches the ESP32 SPI configuration
- Verify the SS pin is correctly connected and active low

### Bus contention
- If you see X values on the bus, both CPU and SPI are driving
- Implement proper arbitration to prevent simultaneous access

### Timing violations
- The ICE40UP5K has limited timing margins at 16MHz
- Consider adding pipeline stages if needed

### ESP32 connection issues
- Verify the SPI frequency is ≤ 4MHz
- Check that the iceboot.py configuration matches your ESP32 pins

## Summary

You've now completed the full SPI front panel design:
1. ✅ Created the SPI target module (Lesson 1)
2. ✅ Built test benches in SystemVerilog (Lesson 2)
3. ✅ Implemented the command interpreter (Lesson 3-4)
4. ✅ Created the S100 bus interface (Lesson 5)
5. ✅ Integrated all modules (Lesson 6)
6. ✅ System-level testing (Lesson 7)
7. ✅ FPGA integration (Lesson 8)

Congratulations on completing the educational series!