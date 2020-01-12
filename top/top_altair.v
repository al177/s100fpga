module top
(
  input rx,
  output tx,
  output sync,
  output reg [4:0] led_row,
  output reg [7:0] led_col,
);
  wire clk;  

  SB_HFOSC #(.CLKHF_DIV("0b10")) u_SB_HFOSC(.CLKHFPU(1), .CLKHFEN(1), .CLKHF(clk));
	
  reg [5:0] reset_cnt = 0;
	wire resetn = &reset_cnt;

	always @(posedge clk) begin
		reset_cnt <= reset_cnt + !resetn;
	end
//  wire [7:0] led_col={led_col_7, led_col_6, led_col_5, led_col_4, led_col_3, led_col_2, led_col_1, led_col_0};

  reg [7:0] machine_data;
  reg [15:0] machine_addr;
  reg [7:0] control_leds=8'b00000000;
  reg [7:0] machine_status=8'b00000000;
  reg [4:0] row_select=5'b00001;
  reg [15:0] scaler=16'b0;
  wire machine_inta;
  wire machine_inte;
  

  always @(posedge clk) begin
	  scaler <= scaler + 1;
  end

  always @(posedge scaler[8]) begin
	 row_select <= {row_select[0], row_select[4:1]};
	 led_row <= row_select;
	 machine_status[0] <= ~machine_inta;
	 control_leds[4] <= machine_inte;
		case(row_select)
			5'b00001 : led_col <= ~machine_addr[7:0];	
			5'b00010 : led_col <= ~machine_addr[15:8];	
			5'b00100 : led_col <= ~machine_data[7:0];
			5'b01000 : led_col <= ~machine_status[7:0];
			5'b10000 : led_col <= ~control_leds[7:0];
		endcase

	end

  altair machine(.clk(clk),.reset(~resetn),.rx(rx),.tx(tx),.sync(sync), .mon_data(machine_data), .mon_addr(machine_addr), .mon_inta(machine_inta), .mon_inte(machine_inte));

endmodule
