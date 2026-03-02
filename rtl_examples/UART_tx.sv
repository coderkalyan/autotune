module UART_tx(
  input logic clk,
  input logic rst_n,
  input logic trmt,
  input logic [7:0] tx_data,
  output logic tx_done,
  output logic TX
);
  logic load, transmitting, set_done, shift;
  logic [12:0] baud_cnt;
  logic [8:0] tx_shft_reg;
  logic [3:0] bit_cnt;

  typedef enum logic {
    IDLE,
    TRANSMITTING
  } state_t;

  state_t state, next_state;

  // baud counter
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) baud_cnt <= '0;
    else if (load || shift) baud_cnt <= '0;
    else if (transmitting) baud_cnt <= baud_cnt + 1;
  end

  // shift register
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) tx_shft_reg <= '1;  // Initialize to all 1s so TX idles high
    else if (load) tx_shft_reg <= {tx_data, 1'b0};
    else if (shift) tx_shft_reg <= {1'b1, tx_shft_reg[8:1]};
  end

  assign TX = tx_shft_reg[0];

  // bit counter
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) bit_cnt <= '0;
    else if (load) bit_cnt <= '0;
    else if (shift) bit_cnt <= bit_cnt + 1;
  end

  // tx_done SR flop
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) tx_done <= '0;
    else if (set_done) tx_done <= '1;
    else if (load) tx_done <= '0;
  end

  // state register
  always_ff @(posedge clk, negedge rst_n) begin
    if (!rst_n) state <= IDLE;
    else state <= next_state;
  end

  always_comb begin
    next_state = state;
    load = '0;
    transmitting = '0;
    set_done = '0;
    shift = '0;
    case (state)
      IDLE: begin
        if (trmt) begin
          next_state = TRANSMITTING;
          load = '1;
        end
      end
      TRANSMITTING: begin
        transmitting = '1;
        if (baud_cnt == 13'd5207) begin
          shift = '1;
          if (bit_cnt == 4'd9) begin
            next_state = IDLE;
            set_done = '1;
          end
        end
      end
    endcase
  end

endmodule