# Lesson 5: S100 Bus Interface Module

## Objective

Create the S100 bus interface module that executes memory read/write operations on behalf of the command interpreter. This module acts as the bridge between the command interpreter and the S100 bus signals.

## Background: The S100 Bus

The S100 bus (also called the Bus Standard or S-100 bus) was the first open-architecture bus, used in Altair 8800 and many other early microcomputers. Key signals relevant to our interface:

### Address Bus
- **A0-A15**: 16-bit address bus (tri-state when not driving)
- Address is driven during memory or IO cycles

### Data Bus
- **D0-D7**: 8-bit data bus (tri-state when not driving)
- Data is driven by the module owning the memory location being accessed

### Control Signals
- **IOI**: IO select (active low) - indicates an IO cycle
- **WOI**: Write output (active low) - indicates write cycle
- **ROI**: Read output (active low) - indicates read cycle
- **MEMR**: Memory read (active low)
- **MEMW**: Memory write (active low)
- **AHE**: Address high enable (latch enable for A8-A15)
- **F1**, **F2**: Function select signals

For our front panel interface, we need to:
1. Monitor bus cycles to detect memory reads/writes at our address
2. Drive data onto the bus for memory read operations
3. Capture data from the bus for memory write operations

## Part 1: Module Interface

Create `spi_educational/rtl/spi_bus_interface.v`:

```verilog
module spi_bus_interface(
    input  wire        clk,
    input  wire        reset,

    // Command interpreter interface
    input  wire        bus_req,           // Bus operation request
    input  wire [7:0]  bus_req_data,      // Data to write (for write operations)
    input  wire [15:0] bus_req_addr,      // Target address
    input  wire        bus_read,          // Read operation
    input  wire        bus_write,         // Write operation
    output wire [7:0]  bus_rsp_data,      // Data read from bus
    output wire        bus_ack,           // Operation complete
    output wire        bus_err,           // Error (no response)

    // S100 Bus connection (for integration with altair.v)
    output reg  [7:0]  bus_data_out,      // Data driven onto S100 bus
    output wire        bus_data_oe,       // Data output enable
    input  wire [7:0]  bus_data_in,       // Data from S100 bus
    output wire [15:0] bus_addr_out,      // Address driven onto S100 bus
    output wire        bus_addr_oe,       // Address output enable
    output wire        s100_memr_n,       // Memory read (active low)
    output wire        s100_memw_n,       // Memory write (active low)
    output wire        s100_ior_n,        // IO read (active low)
    output wire        s100_iow_n,        // IO write (active low)

    // Bus monitoring (for bus state sampling)
    output wire [15:0] monitored_addr,
    output wire [7:0]  monitored_data,
    output wire        monitored_read,
    output wire        monitored_write
);
```

## Part 2: Bus Operation State Machine

The bus interface uses a simple state machine to handle read/write operations:

```verilog
// State definitions
localparam [1:0] IDLE       = 2'b00;
localparam [1:0] ADDRESS    = 2'b01;  // Address is on bus
localparam [1:0] READ_DATA  = 2'b10;  // Waiting for data on read
localparam [1:0] WRITE_DATA = 2'b11;  // Driving data for write

reg [1:0] state, next_state;

// State register
always @(posedge clk) begin
    if (reset)
        state <= IDLE;
    else
        state <= next_state;
end

// State machine
always @(*) begin
    next_state = state;
    bus_ack = 1'b0;
    bus_err = 1'b0;
    bus_data_out = 8'hZZ;
    bus_data_oe = 1'b0;
    bus_addr_out = 16'hZZ;
    bus_addr_oe = 1'b0;
    s100_memr_n = 1'b1;
    s100_memw_n = 1'b1;
    s100_ior_n = 1'b1;
    s100_iow_n = 1'b1;
    bus_rsp_data = 8'h00;

    case (state)
        IDLE: begin
            if (bus_req) begin
                bus_addr_out = bus_req_addr;
                bus_addr_oe = 1'b1;
                next_state = ADDRESS;
            end
        end

        ADDRESS: begin
            // Address is stable, assert appropriate control signals
            if (bus_read) begin
                s100_memr_n = 1'b0;  // Assert memory read
                next_state = READ_DATA;
            end else if (bus_write) begin
                s100_memw_n = 1'b0;  // Assert memory write
                bus_data_out = bus_req_data;
                bus_data_oe = 1'b1;
                next_state = WRITE_DATA;
            end else begin
                bus_err = 1'b1;
                next_state = IDLE;
            end
        end

        READ_DATA: begin
            // Capture data from bus (combinational input)
            bus_rsp_data = bus_data_in;
            s100_memr_n = 1'b1;  // Deassert
            bus_ack = 1'b1;
            next_state = IDLE;
        end

        WRITE_DATA: begin
            s100_memw_n = 1'b1;  // Deassert
            bus_data_oe = 1'b0;
            bus_ack = 1'b1;
            next_state = IDLE;
        end

        default: begin
            next_state = IDLE;
        end
    endcase
end
```

## Part 3: Bus Monitoring

The bus interface also monitors all bus activity for the bus state sampling feature:

```verilog
// Monitor the current bus state for sampling
assign monitored_addr = (bus_addr_oe) ? bus_addr_out : 16'hZZZZ;
assign monitored_data = (bus_data_oe) ? bus_data_out : 8'hZZ;
assign monitored_read = (s100_memr_n == 1'b0);
assign monitored_write = (s100_memw_n == 1'b0);
```

## Part 4: Your Task

Create `spi_educational/rtl/spi_bus_interface.v` with:

1. **The state machine** as described above
2. **Proper tri-state control** for bus driving
3. **Bus monitoring outputs** for the bus state sampling feature
4. **Error handling** for invalid operations

### Enhanced Implementation

For a more complete implementation, add:

```verilog
    // Wait state support (for slower peripherals)
    reg [7:0] wait_count;
    reg       wait_state;

    // Address output (always driven during operation)
    assign bus_addr_out = (bus_addr_oe) ? bus_addr_out_internal : 16'hZZZZ;
    reg [15:0] bus_addr_out_internal;

    // During ADDRESS state, hold the address
    always @(posedge clk) begin
        if (reset) begin
            bus_addr_out_internal <= 16'h0000;
        end else if (bus_req && (state == IDLE)) begin
            bus_addr_out_internal <= bus_req_addr;
        end
    end

    // Data output enable (tri-state control)
    assign bus_data_oe = bus_data_oe_internal;
    reg bus_data_oe_internal;
    assign bus_data_out = bus_data_out_internal;
    reg [7:0] bus_data_out_internal;
```

## Part 5: Test Bench

Create `spi_educational/tb/tb_spi_bus_interface.v`:

```verilog
`timescale 1ns/1ns

module tb_spi_bus_interface();

    reg clk;
    reg reset;
    parameter CLOCK_PERIOD = 10;

    always #(CLOCK_PERIOD/2) clk = ~clk;

    // DUT signals
    reg        bus_req;
    reg [7:0]  bus_req_data;
    reg [15:0] bus_req_addr;
    reg        bus_read;
    reg        bus_write;
    wire [7:0] bus_rsp_data;
    wire       bus_ack;
    wire       bus_err;

    // Mock S100 bus
    reg [7:0]  mock_bus_data;
    wire [7:0] bus_data_in;
    wire [15:0] bus_addr_out;
    wire       bus_addr_oe;
    wire       s100_memr_n;
    wire       s100_memw_n;

    // Connect mock bus: we drive data onto the bus, DUT reads it
    assign bus_data_in = mock_bus_data;

    // Instantiate DUT
    spi_bus_interface dut (
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
        .bus_data_out(),
        .bus_data_oe(),
        .bus_addr_out(bus_addr_out),
        .bus_addr_oe(bus_addr_oe),
        .s100_memr_n(s100_memr_n),
        .s100_memw_n(s100_memw_n),
        .s100_ior_n(),
        .s100_iow_n()
    );

    initial begin
        clk = 0;
        reset = 1;
        bus_req = 0;
        bus_req_data = 0;
        bus_req_addr = 0;
        bus_read = 0;
        bus_write = 0;
        mock_bus_data = 8'hAA;

        #50;
        reset = 0;
        #20;

        test_memory_read();
        test_memory_write();
        test_invalid_operation();

        #50;
        $finish;
    end

    // Test: Memory read
    task test_memory_read;
        begin
            $display("\n=== Test: Memory Read ===");
            mock_bus_data = 8'h55;  // Data the "bus" will return

            bus_req = 1;
            bus_req_addr = 16'h1234;
            bus_req_data = 8'h00;
            bus_read = 1;
            bus_write = 0;

            #CLOCK_PERIOD;
            bus_req = 0;

            // Wait for acknowledgment
            wait(bus_ack);
            #CLOCK_PERIOD;

            if (bus_rsp_data === 8'h55) begin
                $display("PASS: Memory read returned 0x%0h", bus_rsp_data);
            end else begin
                $display("FAIL: Expected 0x55, got 0x%0h", bus_rsp_data);
            end

            bus_read = 0;
        end
    endtask

    // Test: Memory write
    task test_memory_write;
        begin
            $display("\n=== Test: Memory Write ===");
            bus_req = 1;
            bus_req_addr = 16'hABCD;
            bus_req_data = 8'hBB;
            bus_read = 0;
            bus_write = 1;

            #CLOCK_PERIOD;
            bus_req = 0;

            wait(bus_ack);
            #CLOCK_PERIOD;

            if (bus_err == 1'b0) begin
                $display("PASS: Memory write completed");
            end else begin
                $display("FAIL: Write operation errored");
            end

            bus_write = 0;
        end
    endtask

    // Test: Invalid operation (neither read nor write)
    task test_invalid_operation;
        begin
            $display("\n=== Test: Invalid Operation ===");
            bus_req = 1;
            bus_req_addr = 16'h0000;
            bus_req_data = 8'h00;
            bus_read = 0;
            bus_write = 0;

            #CLOCK_PERIOD;
            bus_req = 0;

            wait(bus_ack | bus_err);
            #CLOCK_PERIOD;

            if (bus_err == 1'b1) begin
                $display("PASS: Invalid operation correctly errored");
            end else begin
                $display("FAIL: Expected error for invalid operation");
            end
        end
    endtask

    initial begin
        $dumpfile("tb_spi_bus_interface.vcd");
        $dumpvars(0, tb_spi_bus_interface);
    end

endmodule
```

## Part 6: Running the Test

```bash
iverilog -g2012 -o tb_spi_bus_interface.out \
    spi_educational/rtl/spi_bus_interface.v \
    spi_educational/tb/tb_spi_bus_interface.v

vvp tb_spi_bus_interface.out
```

## Self-Check Questions

- [ ] Does the state machine correctly transition through IDLE → ADDRESS → READ/WRITE → IDLE?
- [ ] Are tri-state controls working properly?
- [ ] Does the memory read return the correct data from the mock bus?
- [ ] Does the memory write complete without error?
- [ ] Are invalid operations correctly detected and reported?
- [ ] Are the bus monitoring signals reflecting the current bus state?

## What's Next

In Lesson 7, you'll integrate the SPI target, command interpreter, and bus interface into a single SPI front panel module and connect it to the Altair design.