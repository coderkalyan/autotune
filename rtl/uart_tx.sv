module UART_tx (
	input clk,				//clock
	input rst_n,			//active low reset
	input tmrt,				//signal to initate transmission
	input [7:0] tx_data,    //data to transmit
	output reg tx_done,		//flag asserted when transmission is done
	output TX				//bit currently being transmitted
);

// STATE MACHINE DECLARATIONS //
typedef enum reg {IDLE, SHIFT} state_t;
state_t state, nxt_state;  //curr state and next state for state machine
logic init, transmitting, set_done; // State machine outputs

// MUX AND COMBINATIONAL LOGIC SIGNALS //
logic shift;
localparam BAUD_RATE = 12'd1600; // 50_000_000 / 31250 baud = 1600 clks per bit
logic [1:0] sel;
logic [1:0] baud_sel;
logic [11:0] baud_cnt;
logic [3:0] bit_cnt;
logic [8:0] tx_shift_reg;

//dataflow for select vectors
assign sel = {init, shift};
assign baud_sel = { {init | shift}, transmitting };


//bit counter flip flop
always_ff@(posedge clk) begin
	if(sel[1])
		bit_cnt <= 0; //reset when init asserted
	else if (sel[0]) 
		bit_cnt <= bit_cnt + 1; //inc each time bit is shifted
	//hold operation is implicit
end

//dataflow to determine when a shift is valid
assign shift = baud_cnt == BAUD_RATE;

//baud count "timer" flip flop
always_ff@(posedge clk) begin
	if(baud_sel[1]) 
		baud_cnt <= 0; //reset when shift or init is asserted
	else if(baud_sel[0])
		baud_cnt <= baud_cnt + 1; 
	//hold operation is implicit
end

//shift register flip-flip 
always_ff@(posedge clk) begin
	if(!rst_n) 
		tx_shift_reg <= {9{1'b1}}; //active low set; bc UART output 1 while idle
	else if (sel[1]) 
		tx_shift_reg <= {tx_data, 1'b0}; //load in start bit and data when init asserted
	else if (sel[0]) 
		tx_shift_reg <= {1'b1, tx_shift_reg[8:1]}; //load a 1 into msb as bits are shifted out
	//hold operation is implicit
end

//dataflow output for bit shifter out 
assign TX = tx_shift_reg[0];

//output flag flip flop 
always_ff@(posedge clk) begin 
	if (!rst_n) 
		tx_done <= 0; //active low reset
	else if (init) 
		tx_done <= 0;  //clear the previous flag when new process starts
	else if (set_done) 
		tx_done <= 1;  //pulse flag high when transmission complete
	else
		tx_done <= 0;
	//hold operation is implicit
end

//state machine flip flop
always_ff@(posedge clk) begin
	if(!rst_n)
		state <= IDLE;
	else
		state <= nxt_state;
end

//combinational logic for state machine transitions 
always_comb begin 
	// default outputs
	nxt_state = state;
	init = 0;
	set_done = 0;
	transmitting = 0;

	case(state)	
		IDLE: 
			if (tmrt) begin
				init = 1;
				transmitting = 1;
				nxt_state = SHIFT;
			end
		SHIFT: 
			if (bit_cnt == 4'd10) begin 
				set_done = 1;
				nxt_state = IDLE;
			end 
			else 	// transmits each bit until 10 bits are transmitted
				transmitting = 1;	
	endcase
end


endmodule 
