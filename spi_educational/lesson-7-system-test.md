# Lesson 7: System Test

## Objective

Create a system-level test bench that exercises the SPI front panel when attached to the Altair 8800 S100 bus simulation. This verifies the complete integration works correctly.

## Background

Now that all individual modules are complete and tested, we need to verify they work together within the actual Altair 8800 design context. This lesson creates a test bench that:

1. Instantiates the `altair_tb.v` (Altair 8800 simulation)
2. Attaches the SPI front panel module
3. Exercises SPI commands while the 8080 CPU is running
4. Verifies memory operations through the SPI interface

## Part 1: Understanding the Existing Test Bench

Look at the existing `tb/altair_tb.v` to understand the test structure:

```verilog
// Key signals in altair_tb.v
reg clk_sys;
wire [7:0] data_bus;
wire [15:0] addr_bus;
// ... other bus control signals
```

The test bench runs the ZEXALL or BASIC test ROM through the 8080 CPU simulation. We'll attach our SPI front panel to monitor and interact with this simulation.

## Part 2: System Test Bench Structure

Create `spi_educational/tb/tb_spi_system.v`:

```verilog
`timescale 1ns/1ns

module tb_spi_system();

    // System clock
    reg clk_sys;
    parameter CLOCK_PERIOD = 16.67;  // 6 MHz → 16.67ns period

    always #(CLOCK_PERIOD/2) clk_sys = ~clk_sys;

    // SPI master simulation (ESP32 model)
    reg        spi_ss_n;
    reg        spi_sclk;
    reg        spi_mosi;
    wire       spi_miso;

    // =============================
    // SPI MASTER TASKS
    // =============================

    // Task: Send 16-bit SPI transaction
    task spi_master_transaction;
        input [15:0] tx_data;
        output [7:0] rx_data;
        integer i;
        begin
            rx_data = 8'b0;
            spi_ss_n = 0;
            #(CLOCK_PERIOD);

            for (i = 0; i < 16; i = i + 1) begin
                spi_sclk = 0;
                spi_mosi = tx_data[15 - i];
                #(CLOCK_PERIOD/2);
                spi_sclk = 1;
                #(CLOCK_PERIOD/2);
                if (spi_miso)
                    rx_data[15 - i] = 1'b1;
            end

            spi_ss_n = 1;
            #(CLOCK_PERIOD);
        end
    endtask

    // =============================
    // ALTAIR SYSTEM INSTANCE
    // =============================

    // We instantiate the altair test bench module directly
    // and connect our SPI front panel to its bus signals

    wire [7:0]  sys_data_bus;
    wire [15:0] sys_addr_bus;

    // Instantiate the SPI front panel
    spi_front_panel u_spi_front_panel (
        .clk(clk_sys),
        .reset(~sys_reset_n),
        .spi_ss_n(spi_ss_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .fp_data_out(),
        .fp_data_oe(sys_data_oe),
        .fp_data_in(sys_data_bus),
        .fp_addr_out(sys_addr_spi),
        .fp_addr_oe(),
        .fp_memr_n(sys_memr_n_spi),
        .fp_memw_n(sys_memw_n_spi),
        .fp_ior_n(),
        .fp_iow_n(),
        .fp_cpu_run_n(),
        .fp_s100_reset_n()
    );

    // =============================
    // SYSTEM TEST SEQUENCE
    // =============================
    initial begin
        clk_sys = 0;
        spi_ss_n = 1;
        spi_sclk = 0;
        spi_mosi = 0;

        #100;

        $display("=== System Test: SPI Front Panel with Altair 8800 ===");

        // Test 1: Read control register while CPU is running
        test_read_while_running();

        // Test 2: Set address and perform memory read
        test_memory_access();

        // Test 3: Latch bus state
        test_bus_latch();

        $display("=== System Test Complete ===");
        #1000;
        $finish;
    end

    task test_read_while_running;
        reg [7:0] read_data;
        begin
            $display("\n--- Test: Read Control While CPU Running ---");
            spi_master_transaction(16'h2000, read_data);
            $display("  Control register: 0x%0h", read_data);
        end
    endtask

    task test_memory_access;
        reg [7:0] read_data;
        begin
            $display("\n--- Test: Memory Access via SPI ---");
            // Set address to 0x0000
            spi_master_transaction(16'h0000, read_data);  // Addr HI = 0x00
            spi_master_transaction(16'h0000, read_data);  // Addr LO = 0x00
            $display("  Address set to 0x0000");

            // Read memory
            spi_master_transaction(16'h0200, read_data);
            $display("  Memory read at 0x0000: 0x%0h", read_data);
        end
    endtask

    task test_bus_latch;
        reg [7:0] read_data;
        begin
            $display("\n--- Test: Bus State Latch ---");
            // Latch current bus state
            spi_master_transaction(16'h3000, read_data);
            $display("  Bus state latched");

            // Read latched address high
            spi_master_transaction(16'h3100, read_data);
            $display("  Latched addr HI: 0x%0h", read_data);

            // Read latched address low
            spi_master_transaction(16'h3200, read_data);
            $display("  Latched addr LO: 0x%0h", read_data);

            // Read latched data
            spi_master_transaction(16'h3300, read_data);
            $display("  Latched data: 0x%0h", read_data);
        end
    endtask

    initial begin
        $dumpfile("tb_spi_system.vcd");
        $dumpvars(0, tb_spi_system);
    end

endmodule
```

## Part 3: Alternative - Using top_altair.v

A more realistic approach is to use `top/top_altair.v` which connects all the RTL modules together. Create a wrapper test bench:

```verilog
`timescale 1ns/1ns

module tb_spi_system_top();

    reg clk_sys;
    reg reset;
    parameter CLOCK_PERIOD = 16.67;  // 6 MHz

    always #(CLOCK_PERIOD/2) clk_sys = ~clk_sys;

    // SPI signals
    reg        spi_ss_n;
    reg        spi_sclk;
    reg        spi_mosi;
    wire       spi_miso;

    // Bus signals for monitoring
    wire [7:0]  data_bus;
    wire [15:0] addr_bus;

    // Instantiate top-level Altair with SPI front panel attached
    // This requires modifying top_altair.v to include the SPI front panel

    top_altair_spi u_top (
        .clk(clk_sys),
        .reset(reset),
        .spi_ss_n(spi_ss_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .data_bus(data_bus),
        .addr_bus(addr_bus)
    );

    // ... same SPI master tasks and test sequences as above ...

endmodule
```

## Part 4: Modifying top_altair.v

To integrate the SPI front panel into the top-level design, create `top/top_altair_spi.v`:

```verilog
module top_altair_spi(
    input  wire        clk,
    input  wire        reset,

    // SPI interface to ESP32
    input  wire        spi_ss_n,
    input  wire        spi_sclk,
    input  wire        spi_mosi,
    output wire        spi_miso,

    // S100 Bus (passed through to altair module)
    output wire [7:0]  data_bus,
    output wire [15:0] addr_bus,
    // ... other S100 signals
);

    // SPI Front Panel
    wire [7:0]  fp_data_out;
    wire        fp_data_oe;
    wire [15:0] fp_addr_out;
    wire        fp_addr_oe;
    wire        fp_memr_n;
    wire        fp_memw_n;
    wire        fp_ior_n;
    wire        fp_iow_n;

    spi_front_panel u_spi_front_panel (
        .clk(clk),
        .reset(reset),
        .spi_ss_n(spi_ss_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .fp_data_out(fp_data_out),
        .fp_data_oe(fp_data_oe),
        .fp_data_in(data_bus_internal),
        .fp_addr_out(fp_addr_out),
        .fp_addr_oe(fp_addr_oe),
        .fp_memr_n(fp_memr_n),
        .fp_memw_n(fp_memw_n),
        .fp_ior_n(fp_ior_n),
        .fp_iow_n(fp_iow_n),
        .fp_cpu_run_n(),
        .fp_s100_reset_n()
    );

    // Altair 8800 top level
    top_altair u_altair (
        .clk(clk),
        .reset(reset),
        .data_bus(data_bus),
        .addr_bus(addr_bus),
        // ... other signals, with SPI front panel signals merged
    );

endmodule
```

## Part 5: Makefile Integration

Add to the Makefile:

```makefile
SPI_EDUCATIONAL_RTL=spi_educational/rtl/spi_target.v \
                    spi_educational/rtl/spi_cmd_interpreter.v \
                    spi_educational/rtl/spi_bus_interface.v \
                    spi_educational/rtl/spi_front_panel.v

SPI_EDUCATIONAL_TB=spi_educational/tb/tb_spi_system.v

test_spi_system: $(SPI_EDUCATIONAL_TB) $(SPI_EDUCATIONAL_RTL) rtl/altair.v rtl/i8080.v \
                 rtl/ram_memory.v rtl/rom_memory.v rtl/simpleuart.v \
                 top/top_altair.v
	iverilog -g2012 -o build/tb_spi_system.out \
	    $(SPI_EDUCATIONAL_TB) $(SPI_EDUCATIONAL_RTL) \
	    rtl/altair.v rtl/i8080.v rtl/ram_memory.v rtl/rom_memory.v \
	    rtl/simpleuart.v top/top_altair.v
	vvp build/tb_spi_system.out
```

## Part 6: Running the System Test

```bash
make test_spi_system
# or
iverilog -g2012 -o tb_spi_system.out spi_educational/tb/tb_spi_system.v \
    spi_educational/rtl/*.v rtl/*.v top/top_altair.v
vvp tb_spi_system.out
```

## Part 7: Self-Check Questions

- [ ] Does the SPI front panel work within the Altair 8800 simulation?
- [ ] Can you read memory while the CPU is running?
- [ ] Does the bus latch capture the current bus state?
- [ ] Are there any timing conflicts between the CPU and SPI interface?
- [ ] Do the waveforms show correct coexistence of CPU and SPI bus access?

## Troubleshooting

### Bus contention
- If both the CPU and SPI front panel try to drive the data bus, you'll see X values
- The bus interface needs proper arbitration (only drive bus when it has a valid request)

### Timing issues
- The SPI clock (4 MHz max) is faster than the system clock (6 MHz)
- Ensure SPI sampling happens at the right time relative to system operations

### Reset synchronization
- The SPI front panel reset should be synchronized with the system reset
- Ensure both modules reset at the same time

## What's Next

In the final lesson (Lesson 8), you'll integrate the SPI front panel module into `altair.v` and create the pin constraints for programming the actual FPGA.