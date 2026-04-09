import global_enums::*;

module midi_receiver (
  input  logic clk,
  input  logic rst,
  input  logic midi_rx,
  output logic       note_on_trigger,
  output logic [6:0] note_number,
  output logic [6:0] velocity,
  output mode_t      mode
);

  localparam logic [15:0] CLK_DIV = 16'd1600; // 50 MHz / 31250 baud

  logic       rdy;
  logic       clr_rdy;
  logic [7:0] rx_data;
  logic [3:0] ms_nybble;

  logic       pending_note_on;
  logic [6:0] pending_note_number;

  typedef enum logic [1:0] {
    BYTE_1,
    BYTE_2,
    BYTE_3
  } state_t;

  state_t state;

  assign ms_nybble = rx_data[7:4];
  assign clr_rdy   = rdy;

  uart_rx uart_rx_inst (
    .clk(clk),
    .rst(rst),
    .RX(midi_rx),
    .clk_div(CLK_DIV),
    .clr_rdy(clr_rdy),
    .rdy(rdy),
    .rx_data(rx_data)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      state               <= BYTE_1;
      note_on_trigger     <= 1'b0;
      note_number         <= 7'd0;
      velocity            <= 7'd0;
      pending_note_on     <= 1'b0;
      pending_note_number <= 7'd0;
      mode                <= NA;
    end else begin
      // default: pulse for one cycle only
      note_on_trigger <= 1'b0;

      if (rdy) begin
        case (state)
          BYTE_1: begin
            // MIDI status byte
            if (ms_nybble == 4'h9) begin
              // NOTE ON
              pending_note_on <= 1'b1;
              state <= BYTE_2;
            end else if (ms_nybble == 4'h8) begin
              // NOTE OFF
              pending_note_on <= 1'b0;
              state <= BYTE_2;
            end else begin
              // unsupported message, ignore
              pending_note_on <= 1'b0;
              state <= BYTE_1;
            end
          end

          BYTE_2: begin
            // note number
            pending_note_number <= rx_data[6:0];
            state <= BYTE_3;
          end

          BYTE_3: begin
            // velocity
            state <= BYTE_1;

            // Only act on real NOTE ON events
            // MIDI note_on with velocity 0 is equivalent to note_off
            if (pending_note_on && (rx_data[6:0] != 7'd0)) begin
              if (pending_note_number == 7'd44) begin
                // Toggle AUTOTUNE
                if (mode == AUTOTUNE)
                  mode <= NA;
                else
                  mode <= AUTOTUNE;

              end else if (pending_note_number == 7'd45) begin
                // Toggle VOCODE
                if (mode == VOCODE)
                  mode <= NA;
                else
                  mode <= VOCODE;

              end else begin
                // Normal note
                note_number     <= pending_note_number;
                velocity        <= rx_data[6:0];
                note_on_trigger <= 1'b1;
              end
            end
            // NOTE OFF does nothing for mode
          end

          default: begin
            state <= BYTE_1;
          end
        endcase
      end
    end
  end

endmodule