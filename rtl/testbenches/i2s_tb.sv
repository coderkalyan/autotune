`timescale 1ns / 1ps

module i2s_tb;

  // Local Param 
  localparam P24_BIT = 0;
  localparam int Tsck = P24_BIT ? 434.02 : 651.04;
  localparam int DATA_WIDTH = P24_BIT ? 24 : 16;

	// Inputs
	logic bit_clk;
	logic [DATA_WIDTH-1:0] data_in;
	logic rst;
	logic enable;

	// Outputs
	logic DATA;
	logic WS;
	logic send_over;
	
	logic [DATA_WIDTH-1:0] L_DATA;
  	logic [DATA_WIDTH-1:0] R_DATA;
	logic recv_over;

	// Instantiate the Unit Under Test (UUT)
	i2s_transmitter #(
    .P24_BIT(P24_BIT) 
 	) iTM(
		.i_sck(bit_clk), 
		.i_data(data_in), 
		.i_rst(rst),  
		.o_sd(DATA),         
		.o_ws(WS),            
		.o_send_over(send_over)
	);
	
	i2s_receiver #(
    .P24_BIT(P24_BIT) 
    ) iREC(
		.i_rst(rst),         
	  .i_sck(bit_clk),         
		.i_ws(WS),           
		.i_sd(DATA),          
		.o_left_data(L_DATA), 
		.o_right_data(R_DATA),
		.o_recv_over(recv_over)
    );

 	// -------------------------
	// Helpers to measure periods
  	// -------------------------
    task automatic measure_period_posedge(
    	ref logic sig,
    	output realtime period_ns
  	);
    	realtime t1, t2;
    	@(posedge sig); t1 = $realtime;
    	@(posedge sig); t2 = $realtime;
    	period_ns = (t2 - t1);
  	endtask

	initial begin
		// Initialize Inputs
		realtime ws_period;
		bit_clk = 0;
		data_in = 0;
		rst = 1;
		
		// Wait 100 ns for global reset to finish
		#100;
		@(negedge bit_clk);
		rst = 0;


		// SEND SEQUENCE 1 //
		data_in = 16'b1010_0101_1010_0101;
			
		@(posedge send_over);
		data_in = 16'b0101_1010_0101_1010;

		// Waiting for first receive ack
		@(posedge recv_over); 

		// Setup data for second sequence
		@(posedge send_over) data_in = 16'h0000;

		// Waiting for final receive ack
		@(posedge recv_over); 
		if (L_DATA !== 16'b1010_0101_1010_0101) begin 
		$display("ERROR: Did not receive the expected value for LEFT. Actual: %h Expected: %h", L_DATA, 16'b1010_0101_1010_0101);
		$stop();
		end
		if (R_DATA !== 16'b0101_1010_0101_1010) begin 
		$display("ERROR: Did not receive the expected value for RIGHT. Actual: %h Expected: %h", R_DATA, 16'b0101_1010_0101_1010);
		$stop();
		end

		// SEND SEQUENCE 2 //
		@(posedge send_over);
			data_in = 16'h1111;

		repeat (2) @(posedge recv_over); 
		if (L_DATA !== 16'h000) begin 
		$display("ERROR: Did not receive the expected value for LEFT. Actual: %h Expected: %h", L_DATA, 16'h0000);
		$stop();
		end
		if (R_DATA !== 16'h1111) begin 
		$display("ERROR: Did not receive the expected value for RIGHT. Actual: %h Expected: %h", R_DATA, 16'h1111);
		$stop();
		end

		measure_period_posedge(WS, ws_period);
		$display("WS Period ~ %0.3f kHz", 1_000_000.0 / ws_period); // 1e6/t(ns)=kHz

		$display("YAHOO! ALL TESTS PASSED");
		$stop();
        
	end
	
	always #(Tsck/2) bit_clk = ~bit_clk;
      
endmodule