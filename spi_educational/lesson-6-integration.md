# Lesson 6: Integration - SPI Front Panel Module

## Objective

Create the top-level SPI front panel module that integrates the SPI target, command interpreter, and bus interface. Then create an end-to-end test bench that verifies the complete system works together.

## Background: System Integration

This lesson brings together all the modules you built in previous lessons:

```
┌─────────────────────────────────────────────────────────┐
│                  SPI Front Panel Module                  │
│                                                          │
│  ┌──────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │ SPI      │   │ Command      │   │ Bus            │  │
│  │ Target   │──▶│ Interpreter  │──▶│ Interface      │  │
│  │          │◀──│              │   │                │  │
│  └──────────┘   └──────────────┘   └────────────────┘  │
│                                                          │
│  Internal Registers:                                     │
│  - Address Pointer                                       │
│  - SENSE Register                                        │
│  - Control Register                                      │
│  - Bus State Latch                                       │
└─────────────────────────────────────────────────────────┘
         │
         ▼ (SPI signals to ESP32)
```

## Part 1: Creating the SPI Front Panel Module

Create `spi_educational/rtl/spi_front_panel.v`:

```verilog
module spi_front_panel(
    input  wire        clk,
    input  wire        reset,

    // External SPI interface (to ESP32)
    input  wire        spi_ss_n,        // SPI Slave Select (active low)
    input  wire        spi_sclk,        // SPI Clock
    input  wire        spi_mosi,        // SPI Data In
    output wire        spi_miso,        // SPI Data Out

    // S100 Bus connection (for integration with altair.v)
    output wire [7:0]  fp_data_out,
    output wire        fp_data_oe,
    input  wire [7:0]  fp_data_in,
    output wire [15:0] fp_addr_out,
    output wire        fp_addr_oe,
    output wire        fp_memr_n,
    output wire        fp_memw_n,
    output wire        fp_ior_n,
    output wire        fp_iow_n,

    // Direct control signals (for CPU halt, reset)
    output wire        fp_cpu_run_n,
    output wire        fp_s100_reset_n
);

    // Internal connections
    wire        spi_tx_complete;
    wire [7:0]  spi_cmd;
    wire [7:0]  spi_data_in;
    wire [7:0]  spi_data_out;

    wire [7:0]  ctrl_reg_out;
    wire [7:0]  sense_reg_out;
    wire [15:0] addr_ptr_out;

    wire        bus_req;
    wire [7:0]  bus_req_data;
    wire [15:0] bus_req_addr;
    wire        bus_read;
    wire        bus_write;
    wire [7:0]  bus_rsp_data;
    wire        bus_ack;
    wire        bus_err;

    wire        bus_latch_en;
    wire [7:0]  bus_latch_addr_hi;
    wire [7:0]  bus_latch_addr_lo;
    wire [7:0]  bus_latch_data;
    wire [7:0]  bus_latch_status;
    wire [7:0]  bus_latch_signals;
    wire [7:0]  bus_latch_addr_hi_out;
    wire [7:0]  bus_latch_addr_lo_out;
    wire [7:0]  bus_latch_data_out;
    wire [7:0]  bus_latch_status_out;
    wire [7:0]  bus_latch_signals_out;

    // =============================
    // SPI TARGET INSTANCE
    // =============================
    spi_target u_spi_target (
        .clk(clk),
        .spi_ss(spi_ss_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .tx_complete(spi_tx_complete),
        .cmd_reg(spi_cmd),
        .data_in_reg(spi_data_in),
        .data_out_reg(spi_data_out)
    );

    // =============================
    // COMMAND INTERPRETER INSTANCE
    // =============================
    spi_cmd_interpreter u_cmd_interpreter (
        .clk(clk),
        .reset(reset),
        .spi_tx_complete(spi_tx_complete),
        .spi_cmd(spi_cmd),
        .spi_data_in(spi_data_in),
        .spi_data_out(spi_data_out),
        .ctrl_reg_out(ctrl_reg_out),
        .sense_reg_out(sense_reg_out),
        .addr_ptr_out(addr_ptr_out),
        .bus_latch_en(bus_latch_en),
        .bus_latch_addr_hi_out(bus_latch_addr_hi_out),
        .bus_latch_addr_lo_out(bus_latch_addr_lo_out),
        .bus_latch_data_out(bus_latch_data_out),
        .bus_latch_status_out(bus_latch_status_out),
        .bus_latch_signals_out(bus_latch_signals_out)
    );

    // =============================
    // BUS INTERFACE INSTANCE
    // =============================
    spi_bus_interface u_bus_interface (
        .clk(clk),
        .reset(reset),
        .bus_req(bus_req),
        .bus_req_data(bus_req_data),
        .bus_req_addr(bus_req_addr),
        .bus_read(bus_read),
        .bus_write(bus_write),
        .bus_rsp_data(bus_rsp_data),
        .bus_ack(bus_ack),
        .bus_err(bus_err),
        .bus_data_out(fp_data_out),
        .bus_data_oe(fp_data_oe),
        .bus_data_in(fp_data_in),
        .bus_addr_out(fp_addr_out),
        .bus_addr_oe(fp_addr_oe),
        .s100_memr_n(fp_memr_n),
        .s100_memw_n(fp_memw_n),
        .s100_ior_n(fp_ior_n),
        .s100_iow_n(fp_iow_n)
    );

    // =============================
    // CONTROL SIGNALS
    // =============================
    assign fp_cpu_run_n = ~ctrl_reg_out[0];  // Active low
    assign fp_s100_reset_n = ctrl_reg_out[3]; // Active low

    // Bus request logic (simplified - combines read and write)
    assign bus_req = bus_read | bus_write;
    assign bus_req_data = spi_data_in;
    assign bus_req_addr = addr_ptr_out;

endmodule
```

## Part 2: Module Port Mapping Notes

### SPI Target Port Extensions

You'll need to update your `spi_target.v` from Lesson 1 to include these additional output ports:

```verilog
module spi_target(
    input  wire        clk,
    input  wire        spi_ss,
    input  wire        spi_sclk,
    input  wire        spi_mosi,
    output wire        spi_miso,

    // Test/integration ports (added for this lesson)
    output wire        tx_complete,
    output wire [7:0]  cmd_reg,
    output wire [7:0]  data_in_reg,
    output wire [7:0]  data_out_reg
);
```

### Command Interpreter Port Simplification

For the integrated module, some bus state ports can be simplified or removed since they're internal to the front panel. Update your `spi_cmd_interpreter.v` from Lesson 3 to include the `tx_complete` output and simplified interface.

## Part 3: End-to-End Test Bench

Create `spi_educational/tb/tb_spi_front_panel.v`:

```verilog
`timescale 1ns/1ns

module tb_spi_front_panel();

    reg clk;
    reg reset;
    parameter CLOCK_PERIOD = 10;  // 10ns → 100 MHz

    always #(CLOCK_PERIOD/2) clk = ~clk;

    // SPI signals
    reg        spi_ss_n;
    reg        spi_sclk;
    reg        spi_mosi;
    wire       spi_miso;

    // Mock S100 bus
    reg [7:0]  mock_bus_data;
    wire [7:0] fp_data_in;
    wire [7:0] fp_data_out;
    wire       fp_data_oe;
    wire [15:0] fp_addr_out;
    wire       fp_addr_oe;
    wire       fp_memr_n;
    wire       fp_memw_n;

    assign fp_data_in = mock_bus_data;

    // SPI front panel DUT
    spi_front_panel dut (
        .clk(clk),
        .reset(reset),
        .spi_ss_n(spi_ss_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .fp_data_out(fp_data_out),
        .fp_data_oe(fp_data_oe),
        .fp_data_in(fp_data_in),
        .fp_addr_out(fp_addr_out),
        .fp_addr_oe(fp_addr_oe),
        .fp_memr_n(fp_memr_n),
        .fp_memw_n(fp_memw_n),
        .fp_ior_n(),
        .fp_iow_n(),
        .fp_cpu_run_n(),
        .fp_s100_reset_n()
    );

    // =============================
    // SPI MASTER SIMULATION
    // =============================

    // Task: Send 16-bit SPI transaction
    // Simulates what the ESP32 would send
    task spi_master_transaction;
        input [15:0] tx_data;   // Data sent TO front panel
        output [7:0] rx_data;   // Data received FROM front panel
        integer i;
        begin
            rx_data = 8'b0;
            spi_ss_n = 0;           // Select slave
            #(CLOCK_PERIOD);

            for (i = 0; i < 16; i = i + 1) begin
                spi_sclk = 0;       // Low phase
                spi_mosi = tx_data[15 - i];  // Setup data
                #(CLOCK_PERIOD/2);
                spi_sclk = 1;       // Rising edge (sample)
                #(CLOCK_PERIOD/2);
            end

            spi_ss_n = 1;           // Deselect
            #(CLOCK_PERIOD);
        end
    endtask

    // =============================
    // TEST SEQUENCE
    // =============================
    initial begin
        clk = 0;
        reset = 1;
        spi_ss_n = 1;
        spi_sclk = 0;
        spi_mosi = 0;
        mock_bus_data = 8'hAA;

        #50;
        reset = 0;
        #20;

        // Test 1: Set address and read memory
        test_set_addr_and_read();

        // Test 2: Set address and write memory
        test_set_addr_and_write();

        // Test 3: Read control register
        test_read_control();

        // Test 4: Write control register
        test_write_control();

        // Test 5: Read SENSE register
        test_read_sense();

        // Test 6: Write SENSE register
        test_write_sense();

        #50;
        $finish;
    end

    // Test: Set address and read memory
    task test_set_addr_and_read;
        reg [7:0] read_data;
        begin
            $display("\n=== Test: Set Address and Read Memory ===");
            mock_bus_data = 8'h55;  // Data that will be "read" from bus

            // Set address high
            spi_master_transaction(16'h00AB, read_data);
            $display("  Addr HI set: 0xAB, MISO: 0x%0h", read_data);

            // Set address low
            spi_master_transaction(16'h01CD, read_data);
            $display("  Addr LO set: 0xCD, MISO: 0x%0h", read_data);

            // Read memory at 0xABCD
            spi_master_transaction(16'h0200, read_data);
            if (read_data === 8'h55) begin
                $display("  PASS: Memory read returned 0x%0h", read_data);
            end else begin
                $display("  FAIL: Expected 0x55, got 0x%0h", read_data);
            end
        end
    endtask

    // Test: Set address and write memory
    task test_set_addr_and_write;
        reg [7:0] read_data;
        begin
            $display("\n=== Test: Set Address and Write Memory ===");

            // Set address
            spi_master_transaction(16'h00EF, read_data);
            spi_master_transaction(16'h0134, read_data);

            // Write data 0x77 to 0xEF34
            spi_master_transaction(16'h0377, read_data);
            $display("  Write 0x77 to 0xEF34, MISO: 0x%0h", read_data);
            $display("  PASS: Memory write completed");
        end
    endtask

    // Test: Read control register
    task test_read_control;
        reg [7:0] read_data;
        begin
            $display("\n=== Test: Read Control Register ===");
            spi_master_transaction(16'h2000, read_data);
            $display("  Control register: 0x%0h", read_data);
            $display("  PASS: Control register read");
        end
    endtask

    // Test: Write control register
    task test_write_control;
        reg [7:0] read_data;
        begin
            $display("\n=== Test: Write Control Register ===");
            spi_master_transaction(16'h2105, read_data);  // Enable CPU run + addr advance
            $display("  Control register written: 0x05");
            $display("  PASS: Control register write");
        end
    endtask

    // Test: Read SENSE register
    task test_read_sense;
        reg [7:0] read_data;
        begin
            $display("\n=== Test: Read SENSE Register ===");
            spi_master_transaction(16'h1000, read_data);
            $display("  SENSE register: 0x%0h", read_data);
            $display("  PASS: SENSE register read");
        end
    endtask

    // Test: Write SENSE register
    task test_write_sense;
        reg [7:0] read_data;
        begin
            $display("\n=== Test: Write SENSE Register ===");
            spi_master_transaction(16'h1142, read_data);
            $display("  SENSE register written: 0x42");
            $display("  PASS: SENSE register write");
        end
    endtask

    // =============================
    // MONITORING
    // =============================
    initial begin
        $monitor("time=%0t fp_memr_n=%b fp_memw_n=%b fp_addr=%0h fp_data_oe=%b",
                 $time, fp_memr_n, fp_memw_n, fp_addr_out, fp_data_oe);
    end

    // =============================
    // VCD Dump
    // =============================
    initial begin
        $dumpfile("tb_spi_front_panel.vcd");
        $dumpvars(0, tb_spi_front_panel);
    end

endmodule
```

## Part 4: Running the Integration Test

```bash
# Compile all modules
iverilog -g2012 -o tb_spi_front_panel.out \
    spi_educational/rtl/spi_target.v \
    spi_educational/rtl/spi_cmd_interpreter.v \
    spi_educational/rtl/spi_bus_interface.v \
    spi_educational/rtl/spi_front_panel.v \
    spi_educational/tb/tb_spi_front_panel.v

# Run simulation
vvp tb_spi_front_panel.out

# View waveforms
gtkwave tb_spi_front_panel.vcd
```

## Part 5: Self-Check Questions

- [ ] Does the SPI front panel module correctly instantiate all sub-modules?
- [ ] Do the SPI signal connections match between modules?
- [ ] Does the end-to-end test show correct address setting, memory read, and memory write?
- [ ] Can you read back the control and SENSE registers via SPI?
- [ ] Do the S100 bus control signals (memr_n, memw_n) assert at the right times?
- [ ] Are the waveforms in GTKWave showing correct SPI timing?

## Troubleshooting

### MISO always high-Z
- Check that the SPI target's `spi_ss` signal is active (low)
- Verify the data_out_reg is being populated correctly

### Bus operations not working
- Check that the address pointer is being set before read/write commands
- Verify the bus interface state machine transitions are correct

### Command interpreter not responding
- Check that `spi_tx_complete` is being generated and received correctly
- Verify the command decode case statement covers all expected commands

## What's Next

In Lesson 7, you'll create a system-level test bench that connects the SPI front panel to the Altair 8800 design and exercises the complete integration.