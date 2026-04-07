module pitch_transmitter(
  input clk,
  input rst,
  input [9:0] pitch_period,
  input pitch_valid,
  output wire TX
);

typedef enum logic [1:0] {
  IDLE,
  SENDING_1,
  SENDING_2
} state_t;

state_t state, next_state;
logic tx_done, trmt;
logic [7:0] send_data;

uart_tx uart_tx_inst(
  .clk(clk),
  .rst(rst),
  .trmt(trmt),
  .tx_data(send_data),
  .clk_div(16'd1600),
  .tx_done(tx_done),
  .TX(TX)
);

always_ff @(posedge clk) begin
  if (rst) begin
    state <= IDLE;
  end
  else begin
    state <= next_state;
  end
end

always_comb begin
  next_state = state;
  send_data = '0;
  trmt = '0;
  case (state)
    IDLE: begin
      if (pitch_valid) begin
        next_state = SENDING_1;
        send_data = {1'b1, 1'b1, pitch_period[9:4]}; // { START, VALID, 6 MSB}
        trmt = 1'b1;
      end
      else begin
        trmt = 1'b0;
      end
    end
    SENDING_1: begin
      if (tx_done) begin
        next_state = SENDING_2;
        send_data = {1'b0, pitch_period[3:0], 3'b111}; // { STOP, 4 LSB, 3 don't cares }
        trmt = 1'b1;
      end
    end
    SENDING_2: begin
      if (tx_done) begin
        next_state = IDLE;
        trmt = 1'b0;
      end
    end
  endcase
end


endmodule;