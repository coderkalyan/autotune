module uart_rx (
  input wire clk,
  input wire rst,
  input wire RX,
  input wire [15:0] clk_div,
  input wire clr_rdy,
  output logic rdy,
  output logic [7:0] rx_data
);
  logic shift, start, receiving;
  logic [9:0] rx_shft_reg;
  logic [15:0] baud_cnt;
  logic [3:0] bit_cnt;
  logic set_rdy;

  logic rx_temp, rx_stable;

  typedef enum logic {
    IDLE,
    RECEIVING
  } state_t;

  state_t state, next_state;

  // rx metastability flip flop
  always_ff @(posedge clk) begin
    // need to preset the flops
    if (rst) begin
      rx_temp <= '1;
      rx_stable <= '1;
    end
    else begin
      rx_temp <= RX;
      rx_stable <= rx_temp;
    end
  end

  // shift register
  always_ff @(posedge clk) begin
    if (rst) rx_shft_reg <= '0;
    else if (shift) rx_shft_reg <= {rx_stable, rx_shft_reg[9:1]};
  end

  // baud counter
  always_ff @(posedge clk) begin
    if (rst) baud_cnt <= '0;
    else if (start) baud_cnt <= {1'b0, clk_div[15:1]};
    else if (shift) baud_cnt <= clk_div;
    else if (receiving) baud_cnt <= baud_cnt - 1;
  end

  // bit counter
  always_ff @(posedge clk) begin
    if (rst) bit_cnt <= '0;
    else if (start) bit_cnt <= '0;
    else if (shift) bit_cnt <= bit_cnt + 1;
  end

  // rdy SR flop
  always_ff @(posedge clk) begin
    if (rst) rdy <= '0;
    else if (start | clr_rdy) rdy <= '0;
    else if (set_rdy) rdy <= '1;
  end

  // state flop
  always_ff @(posedge clk) begin
    if (rst) state <= IDLE;
    else state <= next_state;
  end

  always_comb begin
    // initialize signals
    next_state = state;
    start = '0;
    receiving = '0;
    shift = '0;
    set_rdy = '0;

    case (state)
      IDLE: begin
        if (!rx_stable) begin
          start = '1;
          next_state = RECEIVING;
        end
      end
      RECEIVING: begin
        receiving = '1;  // Enable baud counter to decrement
        if (baud_cnt == 16'd0) begin
          shift = '1;
        end
        if (bit_cnt == 4'd10) begin
          next_state = IDLE;
          set_rdy = '1;
        end
      end
    endcase
  end

  // Assign rx_data from the shift register (8 data bits)
  assign rx_data = rx_shft_reg[8:1];

endmodule