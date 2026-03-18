module midi_receiver (
  input logic clk,
  input logic rst,
  input logic midi_rx,
  output reg note_on_trigger,
  output reg [6:0] note_number,
  output reg [6:0] velocity
);

  localparam [15:0] CLK_DIV = 16'd1600; // 50MHz / 31250 = 1600

  logic rdy;
  logic clr_rdy;
  logic [7:0] rx_data;
  logic [3:0] ms_nybble;
  logic [3:0] ls_nybble;

  uart_rx uart_rx_inst (
    .clk(clk),
    .rst(rst),
    .RX(midi_rx),
    .clk_div(CLK_DIV),
    .clr_rdy(clr_rdy),
    .rdy(rdy),
    .rx_data(rx_data)
  );

  typedef enum logic [1:0] {
    BYTE_1,
    BYTE_2,
    BYTE_3
  } state_t;

  state_t state;

  assign ms_nybble = rx_data[7:4];
  assign ls_nybble = rx_data[3:0];
  assign clr_rdy = rdy; // Automatically clear ready signal when data is available

  // https://learn.sparkfun.com/tutorials/midi-tutorial/all#messages
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= BYTE_1;
      note_on_trigger <= '0;
      note_number <= '0;
      velocity <= '0;
    end else if (rdy) begin
      case (state)
        BYTE_1: begin
          // Process Status Byte
          // 1st nybble is status byte
          if (ms_nybble == 4'h8) begin // NOTE OFF
            note_on_trigger <= '0;
            state <= BYTE_2;
          end else if (ms_nybble == 4'h9) begin // NOTE ON
            note_on_trigger <= '1;
            state <= BYTE_2;
          end
          // 2nd nybble is channel number (irrelevant for now)
        end
        BYTE_2: begin
          note_number <= rx_data[6:0];
          state <= BYTE_3;
        end
        BYTE_3: begin
          velocity <= rx_data[6:0];
          state <= BYTE_1;
        end
      endcase
    end
  end

endmodule
