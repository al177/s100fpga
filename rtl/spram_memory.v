module spram_memory(
  input wire clk,
  input wire [ADDR_WIDTH-1:0] addr,
  input [7:0] data_in,
  input rd,
  input we,
  output reg [7:0] data_out
);
  parameter integer ADDR_WIDTH = 15;

  reg [7:0] ram[0:(2 ** ADDR_WIDTH)-1] /* verilator public_flat */;
  
  SB_SPRAM256KA spram
  (
    .ADDRESS(addr),
    .DATAIN(data_in),
    .MASKWREN({1'b1, 1'b1, 1'b1, 1'b1}),
    .WREN(we),
    .CHIPSELECT(1'b1),
    .CLOCK(clk),
    .STANDBY(1'b0),
    .SLEEP(1'b0),
    .POWEROFF(1'b1),
    .DATAOUT(data_out)
  );

endmodule
