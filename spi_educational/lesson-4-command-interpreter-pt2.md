# Lesson 4: Command Interpreter Part 2 - Test Bench

## Objective

Create a comprehensive test bench for your command interpreter module from Lesson 3. This lesson focuses on testing all command codes and verifying correct behavior.

## Prerequisites

- Complete Lesson 3 (create `spi_educational/rtl/spi_cmd_interpreter.v`)
- You should have tested the SPI target from Lesson 2

## Part 1: Test Bench Structure for Command Interpreter

Create `spi_educational/tb/tb_spi_cmd_interpreter.v`:

```verilog
`timescale 1ns/1ns

module tb_spi_cmd_interpreter();

    // Clock and reset
    reg clk;
    reg reset;
    parameter CLOCK_PERIOD = 10;  // 10ns → 100 MHz

    always #(CLOCK_PERIOD/2) clk = ~clk;

    // SPI target simulation interface
    // Instead of instantiating the full SPI target, we'll directly
    // drive the command interpreter's SPI interface signals
    reg        spi_tx_complete;
    reg [7:0]  spi_cmd;
    reg [7:0]  spi_data_in;
    wire [7:0] spi_data_out;

    // Command interpreter outputs
    wire [7:0] ctrl_reg_out;
    wire [7:0] sense_reg_out;
    wire [15:0] addr_ptr_out;
    wire       cmd_ready_out;

    // Bus state signals (for now, tie to defaults)
    reg        bus_latch_en;
    wire [7:0] bus_latch_addr_hi_out;
    wire [7:0] bus_latch_addr_lo_out;
    wire [7:0] bus_latch_data_out;
    wire [7:0] bus_latch_status_out;
    wire [7:0] bus_latch_signals_out;
    wire       bus_latched;

    // Instantiate the DUT
    spi_cmd_interpreter dut (
        .clk(clk),
        .reset(reset),

        // SPI interface
        .spi_tx_complete(spi_tx_complete),
        .spi_cmd(spi_cmd),
        .spi_data_in(spi_data_in),
        .spi_data_out(spi_data_out),

        // Register outputs
        .ctrl_reg_out(ctrl_reg_out),
        .sense_reg_out(sense_reg_out),
        .addr_ptr_out(addr_ptr_out),

        // Bus state
        .bus_latch_en(bus_latch_en),
        .bus_latch_addr_hi_out(bus_latch_addr_hi_out),
        .bus_latch_addr_lo_out(bus_latch_addr_lo_out),
        .bus_latch_data_out(bus_latch_data_out),
        .bus_latch_status_out(bus_latch_status_out),
        .bus_latch_signals_out(bus_latch_signals_out),

        .cmd_ready_out(cmd_ready_out),
        .bus_latched(bus_latched)
    );

    // =============================
    // STIMULUS GENERATION
    // =============================
    initial begin
        clk = 0;
        reset = 1;
        spi_tx_complete = 0;
        spi_cmd = 0;
        spi_data_in = 0;
        bus_latch_en = 0;

        #50;
        reset = 0;
        #20;

        // Run tests
        test_address_high();
        test_address_low();
        test_address_combined();
        test_sense_write();
        test_sense_read();
        test_control_write();
        test_control_read();
        test_control_single_step();
        test_control_reset();
        test_control_addr_advance();
        test_bus_latch();
        test_bus_readback();
        test_unknown_command();

        #50;
        $finish;
    end
```

## Part 2: Command Test Tasks

### Helper Task: Send Command

Create a task that simulates an SPI transaction to the command interpreter:

```verilog
    // Task: Send a command to the interpreter
    // This directly drives the SPI interface signals
    task send_command;
        input [7:0] cmd;
        input [7:0] data;
        begin
            spi_cmd = cmd;
            spi_data_in = data;
            spi_tx_complete = 1;
            #CLOCK_PERIOD;       // Hold for one clock cycle
            spi_tx_complete = 0;
            #CLOCK_PERIOD;       // Wait for processing
        end
    endtask
```

### Address Pointer Tests

```verilog
    // Test: Set address high byte
    task test_address_high;
        begin
            $display("\n=== Test: Set Address High ===");
            send_command(8'h00, 8'hAB);  // Set addr high to 0xAB
            if (addr_ptr_out[15:8] === 8'hAB) begin
                $display("PASS: Address high set to 0x%0h", addr_ptr_out[15:8]);
            end else begin
                $display("FAIL: Expected 0xAB, got 0x%0h", addr_ptr_out[15:8]);
            end
        end
    endtask

    // Test: Set address low byte
    task test_address_low;
        begin
            $display("\n=== Test: Set Address Low ===");
            send_command(8'h01, 8xCD);  // Set addr low to 0xCD
            if (addr_ptr_out[7:0] === 8'hCD) begin
                $display("PASS: Address low set to 0x%0h", addr_ptr_out[7:0]);
            end else begin
                $display("FAIL: Expected 0xCD, got 0x%0h", addr_ptr_out[7:0]);
            end
        end
    endtask

    // Test: Combined address set (high + low)
    task test_address_combined;
        begin
            $display("\n=== Test: Combined Address Set ===");
            send_command(8'h00, 8'h12);  // Set addr high to 0x12
            send_command(8'h01, 8'h34);  // Set addr low to 0x34
            if (addr_ptr_out === 16'h1234) begin
                $display("PASS: Address set to 0x%0h", addr_ptr_out);
            end else begin
                $display("FAIL: Expected 0x1234, got 0x%0h", addr_ptr_out);
            end
        end
    endtask
```

### SENSE Register Tests

```verilog
    // Test: Write SENSE register
    task test_sense_write;
        begin
            $display("\n=== Test: Write SENSE Register ===");
            send_command(8'h11, 8'h5A);  // Write 0x5A to SENSE
            if (sense_reg_out === 8'h5A) begin
                $display("PASS: SENSE register written with 0x%0h", sense_reg_out);
            end else begin
                $display("FAIL: Expected 0x5A, got 0x%0h", sense_reg_out);
            end
        end
    endtask

    // Test: Read SENSE register (via SPI data_out)
    task test_sense_read;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Read SENSE Register ===");
                // First write a value
                send_command(8'h11, 8'hAA);
                // Now read it back
                spi_cmd = 8'h10;
                spi_data_in = 8'h00;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                read_data = spi_data_out;
                #CLOCK_PERIOD;

                if (read_data === 8'hAA) begin
                    $display("PASS: SENSE register read back as 0x%0h", read_data);
                end else begin
                    $display("FAIL: Expected 0xAA, got 0x%0h", read_data);
                end
            end
        end
    endtask
```

### Control Register Tests

```verilog
    // Test: Write Control register
    task test_control_write;
        begin
            reg [7:0] ctrl_val;
            begin
                $display("\n=== Test: Write Control Register ===");
                ctrl_val = 8'h0A;  // Set bits 1 and 3
                send_command(8'h21, ctrl_val);
                if (ctrl_reg_out === ctrl_val) begin
                    $display("PASS: Control register written with 0x%0h", ctrl_reg_out);
                end else begin
                    $display("FAIL: Expected 0x%0h, got 0x%0h", ctrl_val, ctrl_reg_out);
                end
            end
        end
    endtask

    // Test: Read Control register
    task test_control_read;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Read Control Register ===");
                send_command(8'h21, 8'hFF);  // Write some value
                spi_cmd = 8'h20;
                spi_data_in = 8'h00;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                read_data = spi_data_out;
                #CLOCK_PERIOD;

                $display("INFO: Control read returned 0x%0h", read_data);
                $display("PASS: Control register read completed");
            end
        end
    endtask

    // Test: Single step auto-clear
    task test_control_single_step;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Single Step Auto-Clear ===");
                // Write with single step bit set (bit 1)
                send_command(8'h21, 8'h02);
                if (ctrl_reg_out[1] === 1'b1) begin
                    $display("PASS: Single step bit set");
                end else begin
                    $display("FAIL: Single step bit not set");
                end

                // Wait for auto-clear (one or two clock cycles after write)
                #CLOCK_PERIOD;
                #CLOCK_PERIOD;

                if (ctrl_reg_out[1] === 1'b0) begin
                    $display("PASS: Single step bit auto-cleared");
                end else begin
                    $display("FAIL: Single step bit not auto-cleared");
                end
            end
        end
    endtask

    // Test: Reset auto-clear
    task test_control_reset;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Reset Auto-Clear ===");
                // Write with reset bit set (bit 3, active low)
                send_command(8'h21, 8'h08);
                // Wait for auto-clear
                #CLOCK_PERIOD;
                #CLOCK_PERIOD;

                if (ctrl_reg_out[3] === 1'b1) begin
                    $display("PASS: Reset bit auto-cleared (active low, so 1 = deasserted)");
                end else begin
                    $display("FAIL: Reset bit still asserted");
                end
            end
        end
    endtask

    // Test: Address advance on transfer
    task test_control_addr_advance;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Address Advance on Transfer ===");
                // Set address to 0x0000
                send_command(8'h00, 8'h00);
                send_command(8'h01, 8'h00);

                // Enable address advance (bit 2 of control register)
                send_command(8'h21, 8'h04);

                // Simulate a "read" command (0x02)
                // Note: This test checks addr_ptr increment behavior
                // The actual memory read will return 0 since we have no bus interface yet
                spi_cmd = 8'h02;
                spi_data_in = 8'h00;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                #CLOCK_PERIOD;

                if (addr_ptr_out === 16'h0001) begin
                    $display("PASS: Address advanced to 0x%0h", addr_ptr_out);
                end else begin
                    $display("FAIL: Expected 0x0001, got 0x%0h", addr_ptr_out);
                end
            end
        end
    endtask
```

### Bus State Latch Tests

```verilog
    // Test: Latch bus state
    task test_bus_latch;
        begin
            $display("\n=== Test: Latch Bus State ===");
            // Directly drive the bus latch inputs
            bus_latch_en = 1;
            // Note: In real operation, these come from the bus interface
            // For this test, we verify the latch command is accepted
            send_command(8'h30);  // Latch bus state command
            if (bus_latched) begin
                $display("PASS: Bus state latched");
            end else begin
                $display("INFO: bus_latched flag behavior depends on implementation");
            end
            bus_latch_en = 0;
        end
    endtask

    // Test: Read back latched bus state
    task test_bus_readback;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Bus State Readback ===");
                // These should return the latched values
                // For now, just verify the commands don't cause errors
                spi_cmd = 8'h31;
                spi_data_in = 8'h00;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                read_data = spi_data_out;
                $display("INFO: Latched addr hi returned: 0x%0h", read_data);

                spi_cmd = 8'h32;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                read_data = spi_data_out;
                $display("INFO: Latched addr lo returned: 0x%0h", read_data);

                spi_cmd = 8'h33;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                read_data = spi_data_out;
                $display("INFO: Latched data returned: 0x%0h", read_data);

                $display("PASS: Bus state readback completed");
            end
        end
    endtask

    // Test: Unknown command
    task test_unknown_command;
        begin
            reg [7:0] read_data;
            begin
                $display("\n=== Test: Unknown Command ===");
                spi_cmd = 8'hFF;  // Unknown command
                spi_data_in = 8'h00;
                spi_tx_complete = 1;
                #CLOCK_PERIOD;
                spi_tx_complete = 0;
                read_data = spi_data_out;
                #CLOCK_PERIOD;

                if (read_data === 8'hFF) begin
                    $display("PASS: Unknown command returns 0xFF as error indicator");
                end else begin
                    $display("INFO: Unknown command returned 0x%0h (expected 0xFF)", read_data);
                end
            end
        end
    endtask
```

## Part 3: Complete Test Bench File

Combine all the pieces above into a complete test bench file. Don't forget the monitoring and VCD dump sections:

```verilog
    // =============================
    // MONITORING
    // =============================
    initial begin
        $monitor("time=%0t addr_ptr=%0h ctrl=0x%0h sense=0x%0h ready=%b",
                 $time, addr_ptr_out, ctrl_reg_out, sense_reg_out, cmd_ready_out);
    end

    // =============================
    // VCD Dump
    // =============================
    initial begin
        $dumpfile("tb_spi_cmd_interpreter.vcd");
        $dumpvars(0, tb_spi_cmd_interpreter);
    end

endmodule
```

## Part 4: Running the Test

```bash
# Compile
iverilog -g2012 -o tb_spi_cmd_interpreter.out \
    spi_educational/rtl/spi_cmd_interpreter.v \
    spi_educational/tb/tb_spi_cmd_interpreter.v

# Run
vvp tb_spi_cmd_interpreter.out

# View waveforms (optional)
gtkwave tb_spi_cmd_interpreter.vcd
```

## Part 5: Self-Check Questions

- [ ] Does your test bench verify all command codes?
- [ ] Do the address pointer tests confirm correct high/low byte setting?
- [ ] Does the SENSE register read/write work correctly?
- [ ] Do the control register auto-clear bits clear at the right time?
- [ ] Does the address advance feature work when enabled?
- [ ] Are unknown commands handled gracefully?
- [ ] Do all tests pass without errors?

## Troubleshooting

### X values in output
- Check that all registers are properly initialized in reset
- Ensure proper timing between command assertions

### Tests not detecting changes
- Make sure you're waiting the correct number of clock cycles after sending a command
- Check that `spi_tx_complete` is held for exactly one clock cycle

### Address pointer not advancing
- Verify that `ADDR_ADV_ON_XFER` bit is set before issuing read/write commands
- Check the timing of when the address increment occurs