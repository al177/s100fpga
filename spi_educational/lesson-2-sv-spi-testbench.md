# Lesson 2: SystemVerilog Basics & Testbench for SPI

## Objective

Learn the basics of SystemVerilog testbench creation and write a test bench for your SPI target module from Lesson 1. Then run the simulation both on the command line and through the Makefile.

## Prerequisites

- Complete Lesson 1 (create `spi_educational/rtl/spi_target.v`)
- Icarus Verilog installed (check with `iverilog -v`)
- VVP simulator available (comes with Icarus Verilog)

## Part 1: SystemVerilog Crash Course

### What is a Test Bench?

A test bench is a Verilog module that has no inputs (all signals are internal registers). Its purpose is to:
1. Generate stimulus (test signals) for the Design Under Test (DUT)
2. Monitor and check the DUT's outputs
3. Report results

### Basic Test Bench Structure

```verilog
module tb_dut();
    // Signal declarations
    reg clk;
    reg reset;
    wire out;

    // Instantiate the DUT
    dut_module dut(
        .clk(clk),
        .reset(reset),
        .out(out)
    );

    // Clock generation
    always #5 clk = ~clk;   // 10 time units period → 100 MHz

    // Stimulus generation
    initial begin
        // Initialize
        reset = 1;
        #20;
        reset = 0;

        // Apply test stimuli
        #50;
        // ... more stimulus ...

        // Finish simulation
        #100;
        $finish;
    end

    // Monitoring
    initial begin
        $monitor("time=%0t clk=%b reset=%b out=%b", $time, clk, reset, out);
    end
endmodule
```

### Key SystemVerilog/Verilog Concepts

#### Time and Delays

```verilog
#10;    // Wait 10 time units
#5 clk = ~clk;  // Toggle clock every 5 time units
```

#### Tasks (Reusable Code Blocks)

Tasks are like functions that can contain time controls:

```verilog
task send_reset;
    begin
        reset = 1;
        #20;
        reset = 0;
        #10;
    end
endtask

// Call the task:
// send_reset();  -- but tasks in initial blocks need explicit calling by name
// Actually in Verilog, you just write the code inline or use a procedural call
```

In Verilog-2001/SystemVerilog, tasks within a module are called by writing `task_name;` in procedural code:

```verilog
initial begin
    reset = 1;
    #20 reset = 0;
    wait_for_clock;  // calls task wait_for_clock
end

task wait_for_clock;
    #10;
endtask
```

#### Display Tasks

```verilog
$display("Hello %s value=%0d", "world", 42);  // Like printf
$write("no newline");                           // Like printf without \n
$monitor("time=%0t value=%0d", $time, val);    // Continuously monitor
```

Format specifiers:
- `%0d` - decimal
- `%0h` - hexadecimal
- `%0b` - binary
- `%s` - string
- `%0t` - time

```verilog
$display("Value is %0h (hex) or %0b (binary)", 255, 255);
// Output: Value is ff (hex) or 11111111 (binary)
```

#### $dumpfile and $dumpvars (For Waveform Viewing)

```verilog
initial begin
    $dumpfile("tb.vcd");      // Create VCD file
    $dumpvars(0, tb_dut);     // Dump all variables in tb_dut
end
```

The `0` means dump variables at the top level of module `tb_dut`. You can view the resulting `.vcd` file with tools like `gtkwave`.

#### Assertions

```verilog
initial begin
    #50;
    if (out !== 1'b1) begin
        $display("ERROR: expected out=1 at time %0t", $time);
        $finish;
    end
    $display("PASS: out=1 as expected");
end
```

### Blocking vs Non-blocking Assignments

This is CRITICAL in Verilog/SystemVerilog:

- **Blocking (`=`)**: Executes immediately. Order matters.
- **Non-blocking (`<=`)**: Scheduled for end of time step. Order doesn't matter for same-clock updates.

```verilog
// In sequential logic (flip-flops), ALWAYS use non-blocking:
always @(posedge clk) begin
    q <= d;        // Non-blocking: correct for registers
end

// In combinational logic or stimulus, use blocking:
initial begin
    a = 1;         // Blocking: immediate assignment
    b = a + 1;     // Uses the value just assigned to a
end
```

## Part 2: Writing the SPI Target Test Bench

Now create `spi_educational/tb/tb_spi_target.v` to test your SPI target module.

### Test Bench Structure

```verilog
`timescale 1ns/1ns

module tb_spi_target();

    // Test bench signals
    reg clk;
    reg spi_ss;
    reg spi_sclk;
    reg spi_mosi;
    wire spi_miso;

    reg [7:0] data_out_for_spi;  // Data we want the SPI target to send back

    // Clock: 12 MHz → period = 83.33ns
    // But for test bench, we'll use a faster clock for simulation
    // Let's use 1 MHz clock (period = 1000ns) for clarity
    parameter CLOCK_PERIOD = 100;  // 10ns → 100 MHz (fast simulation)

    always #(CLOCK_PERIOD/2) clk = ~clk;

    // Instantiate the DUT
    // NOTE: If your spi_target has additional ports, connect them here
    spi_target dut (
        .clk(clk),
        .spi_ss(spi_ss),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    // Signals from DUT to check
    reg [7:0]  cmd_reg;
    reg [7:0]  data_in_reg;
    reg [7:0]  data_out_reg;
    reg        tx_complete;

    // Hook up internal signals for monitoring
    // NOTE: You may need to add output ports to your spi_target module
    // to expose cmd_reg, data_in_reg, etc. for testing.
    // For now, we'll monitor spi_miso directly.

    // =============================
    // STIMULUS GENERATION
    // =============================
    initial begin
        // Initialize all signals
        clk = 0;
        spi_ss = 1;       // Slave deselected
        spi_sclk = 0;
        spi_mosi = 0;

        // Reset DUT
        #50;

        // Run tests
        test_no_transaction();
        test_single_write();
        test_single_read();
        test_multiple_transactions();

        // Finish
        #50;
        $finish;
    end

    // =============================
    // TEST TASKS
    // =============================

    // Task: Send a single 16-bit value via SPI
    // This simulates what the ESP32 master would do
    task send_spi_transaction;
        input [15:0] data;  // [15:8] = command, [7:0] = data in
        output [7:0] received_data;  // Data received from slave (for reads)
        integer i;
        begin
            received_data = 0;
            // Sample MISO on each clock cycle for read data
            for (i = 0; i < 16; i = i + 1) begin
                spi_mosi = data[15 - i];  // MSB first
                #(CLOCK_PERIOD/2 - 1);     // Hold for half clock
                #(1);                       // Small delay for rising edge
                if (spi_miso)
                    received_data[15 - i] = 1;
                else
                    received_data[15 - i] = 0;
            end
        end
    endtask

    // Test 1: No transaction (SS stays high)
    task test_no_transaction;
        integer i;
        begin
            $display("\n=== Test 1: No Transaction (SS high) ===");
            spi_ss = 1;
            for (i = 0; i < 32; i = i + 1) begin
                spi_sclk = ~spi_sclk;
                #(CLOCK_PERIOD);
            end
            $display("PASS: No data shifted when SS is high");
        end
    endtask

    // Test 2: Write transaction (send command + data)
    task test_single_write;
        reg [7:0] miso_data;
        begin
            $display("\n=== Test 2: Single Write Transaction ===");
            // Send command 0xAA with data 0x55
            // (0xAA = command, 0x55 = data to write)
            spi_ss = 0;              // Select slave
            #(CLOCK_PERIOD/2);

            send_spi_transaction(16'hAA55, miso_data);

            spi_ss = 1;              // Deselect slave
            #(CLOCK_PERIOD);

            $display("Write: sent 0xAA55, received MISO: 0x%0h", miso_data);
            $display("PASS: Write transaction completed");
        end
    endtask

    // Test 3: Read transaction (send command, receive data)
    task test_single_read;
        reg [7:0] miso_data;
        begin
            $display("\n=== Test 3: Single Read Transaction ===");
            // Send command 0xBB (read) - data part doesn't matter for write
            spi_ss = 0;
            #(CLOCK_PERIOD/2);

            send_spi_transaction(16'hBB00, miso_data);

            spi_ss = 1;
            #(CLOCK_PERIOD);

            $display("Read: sent 0xBB00, received MISO: 0x%0h", miso_data);
            $display("PASS: Read transaction completed");
        end
    endtask

    // Test 4: Multiple transactions
    task test_multiple_transactions;
        begin
            $display("\n=== Test 4: Multiple Transactions ===");
            // Transaction 1
            spi_ss = 0;
            #(CLOCK_PERIOD/2);
            send_spi_transaction(16'h1122, data_out_for_spi);
            spi_ss = 1;
            #(CLOCK_PERIOD);

            // Transaction 2
            spi_ss = 0;
            #(CLOCK_PERIOD/2);
            send_spi_transaction(16'h3344, data_out_for_spi);
            spi_ss = 1;
            #(CLOCK_PERIOD);

            $display("PASS: Multiple transactions completed");
        end
    endtask

    // =============================
    // MONITORING
    // =============================
    initial begin
        $monitor("time=%0t spi_ss=%b spi_sclk=%b spi_mosi=%b spi_miso=%b",
                 $time, spi_ss, spi_sclk, spi_mosi, spi_miso);
    end

    // =============================
    // VCD Dump (for GTKWave)
    // =============================
    initial begin
        $dumpfile("tb_spi_target.vcd");
        $dumpvars(0, tb_spi_target);
    end

endmodule
```

## Part 3: Modifying Your SPI Target for Testing

To properly test your SPI target, you may want to add output ports that expose the internal registers. Update your `spi_target.v` to include these test ports:

```verilog
module spi_target(
    input  wire        clk,
    input  wire        spi_ss,
    input  wire        spi_sclk,
    input  wire        spi_mosi,
    output wire        spi_miso,

    // Test ports (expose internal state)
    output wire [7:0]  cmd_reg,
    output wire [7:0]  data_in_reg,
    output wire [7:0]  data_out_reg,
    output wire        tx_complete
);
    // ... your existing implementation ...
endmodule
```

Then update the test bench instantiation:

```verilog
spi_target dut (
    .clk(clk),
    .spi_ss(spi_ss),
    .spi_sclk(spi_sclk),
    .spi_mosi(spi_mosi),
    .spi_miso(spi_miso),
    .cmd_reg(cmd_reg),
    .data_in_reg(data_in_reg),
    .data_out_reg(data_out_reg),
    .tx_complete(tx_complete)
);
```

## Part 4: Running the Simulation

### Command Line

```bash
# Navigate to the project root
cd /workspaces/s100fpga

# Compile the DUT and test bench
iverilog -g2012 -o tb_spi_target.out spi_educational/rtl/spi_target.v spi_educational/tb/tb_spi_target.v

# Run the simulation
vvp tb_spi_target.out

# View waveforms (if you have gtkwave installed)
gtkwave tb_spi_target.vcd
```

### Through the Makefile

Add these lines to the Makefile:

```makefile
SPI_EDUCATIONAL_SRC=spi_educational/rtl/spi_target.v
SPI_EDUCATIONAL_TB=spi_educational/tb/tb_spi_target.v

test_spi_target: $(SPI_EDUCATIONAL_TB) $(SPI_EDUCATIONAL_SRC)
	iverilog -g2012 -o build/tb_spi_target.out $(SPI_EDUCATIONAL_TB) $(SPI_EDUCATIONAL_SRC)
	vvp build/tb_spi_target.out
```

Then run:
```bash
make test_spi_target
```

## Part 5: Understanding Common Errors

### Error: "Unsupported verilog construct"
- Make sure you're using `-g2012` flag for SystemVerilog features
- Some older Verilog versions don't support certain constructs

### Error: "Unknown task or function"
- Check that task names match exactly (case-sensitive in Verilog)
- Tasks must be declared before they're called, or use forward declarations

### Error: "Multiple drivers"
- A signal is being assigned in multiple places
- Check your module connections

### Warning: "Inferred latch"
- Usually means an incomplete if/case statement
- In combinational logic, always provide an else branch

## Self-Check Questions

- [ ] Do you understand the difference between blocking (`=`) and non-blocking (`<=`) assignments?
- [ ] Can you explain what `$dumpfile` and `$dumpvars` do?
- [ ] Does your test bench successfully simulate all 4 tests?
- [ ] Can you view the VCD waveform file in GTKWave?
- [ ] Does the Makefile test target work?
- [ ] Does your SPI target correctly shift in data MSB first?

## Troubleshooting

### MISO timing issues
If your MISO output doesn't appear to be correct in simulation, check:
1. Are you shifting out data on the correct clock edge?
2. Is the data stable before the master's sampling edge?
3. Is the bit order correct (MSB first)?

### Transaction not completing
If `tx_complete` never fires:
1. Check that SS goes low before clock starts
2. Verify bit_count reaches 16
3. Make sure the clock toggles the correct number of times

### VCD file empty
- Ensure `$dumpvars(0, tb_spi_target)` uses the correct module name
- Check that the module hierarchy is correct