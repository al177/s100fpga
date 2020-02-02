module top
(
  input rx,
  output reg tx,
  output sync,
  output reg [4:0] led_row,
  output reg [7:0] led_col,
);
  wire clk;  

  SB_HFOSC #(.CLKHF_DIV("0b10")) u_SB_HFOSC(.CLKHFPU(1), .CLKHFEN(1), .CLKHF(clk));
	
  reg [15:0] reset_cnt = 0;
  wire resetn = &reset_cnt;

  always @(posedge clk) begin
   	reset_cnt <= reset_cnt + !resetn;
  end

  reg [7:0] machine_data;
  reg [15:0] machine_addr;
  reg [7:0] control_leds;
  wire [7:0] machine_status;
  reg [4:0] row_select=5'b00001;
  reg [15:0] scaler=16'b0;
  wire machine_wait;
  wire machine_inte;
  wire machine_hlda;
  wire machine_rd;
  wire machine_wr;
  wire machine_stack;
  wire machine_intr;
  reg tx_async;

  always @(posedge clk) begin
	  scaler <= scaler + 1;
	  tx <= tx_async;
  end

  always @(posedge scaler[8]) begin
	 row_select <= {row_select[0], row_select[4:1]};
	 led_row <= row_select;
	 control_leds[0] <= 0;
	 control_leds[1] <= 0;
	 control_leds[2] <= machine_hlda;
	 control_leds[3] <= machine_wait;
	 control_leds[4] <= machine_inte;
	 control_leds[5] <= 0;
	 control_leds[6] <= 0;
	 control_leds[7] <= 0;
		case(row_select)
			5'b00001 :  led_col <= ~machine_addr[7:0]; 
			5'b00010 :  led_col <= ~machine_addr[15:8]; 	
			5'b00100 :  led_col <= ~machine_data[7:0]; 
			5'b01000 :  led_col <= ~machine_status[7:0]; 
			5'b10000 :  led_col <= ~control_leds[7:0]; 
		endcase
	end

  altair machine(.clk(clk),.reset(~resetn),.rx(rx),.tx(tx_async),.sync(sync), .mon_data(machine_data), .mon_addr(machine_addr), .mon_wait(machine_wait), .mon_inte(machine_inte), .mon_hlda(machine_hlda), .mon_sysctl(machine_status));

endmodule
