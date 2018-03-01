module top
(
  input rx,
  output tx,
  output sync
);
  wire clk;  

  SB_HFOSC #(.CLKHF_DIV("0b10")) u_SB_HFOSC(.CLKHFPU(1), .CLKHFEN(1), .CLKHF(clk));
	
  reg [5:0] reset_cnt = 0;
	wire resetn = &reset_cnt;

	always @(posedge clk) begin
		reset_cnt <= reset_cnt + !resetn;
	end

  zexall machine(.clk(clk),.reset(~resetn),.rx(rx),.tx(tx),.mreq_n(sync));

endmodule
