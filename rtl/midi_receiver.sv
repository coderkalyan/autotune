import global_enums::*;

module midi_receiver (
    input  logic          clk,
    input  logic          rst,
    input  logic          i_midi_rx,
    output logic  [127:0] o_notes,
    output logic  [6:0]   o_encoders [0:7],
    output mode_t         o_mode
);
  localparam logic [15:0] CLK_DIV = 16'd1600;  // 50 MHz / 31250 baud

  typedef enum logic [2:0] {
    STATUS,
    NOTE_NUMBER,
    NOTE_VELOCITY,
    NOTE_PROCESS,
    CTRL_NUMBER,
    CTRL_VALUE,
    CTRL_PROCESS
  } state_t;

  logic       rdy;
  logic       clr_rdy;
  logic [7:0] rx_data;
  assign clr_rdy = rdy;
  uart_rx uart_rx_inst (
      .clk(clk),
      .rst(rst),
      .RX(i_midi_rx),
      .clk_div(CLK_DIV),
      .clr_rdy(clr_rdy),
      .rdy(rdy),
      .rx_data(rx_data)
  );

  logic [3:0] channel;
  logic [6:0] note, velocity;
  logic           on_off;
  state_t         state;
  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= STATUS;
      o_notes <= '0;
      o_mode  <= MUTE;
    end else begin
      case (state)
        // MIDI status byte.
        STATUS: begin
          if (rdy) begin
            case (rx_data[7:4])
              // Note on.
              4'h9: begin
                channel <= rx_data[3:0];
                on_off  <= 1'b1;
                state   <= NOTE_NUMBER;
              end
              // Note off.
              4'h8: begin
                channel <= rx_data[3:0];
                on_off  <= 1'b0;
                state   <= NOTE_NUMBER;
              end
              // Control change.
              4'hB: begin
                channel <= rx_data[3:0];
                state   <= CTRL_NUMBER;
              end
              default: state <= STATUS;
            endcase
          end
        end

        // Note number.
        NOTE_NUMBER: begin
          if (rdy) begin
            note  <= rx_data[6:0];
            state <= NOTE_VELOCITY;
          end
        end

        // Note velocity.
        NOTE_VELOCITY: begin
          if (rdy) begin
            velocity <= rx_data[6:0];
            state <= NOTE_PROCESS;
          end
        end

        // Process note numbers.
        NOTE_PROCESS: begin
          case (channel)
            // Channel 0: keys
            4'h0: begin
              // NOTE: Supports both note on/off messages and velocity 0
              // as stop conditions.
              o_notes[note] <= !((on_off == 1'b0) || (velocity == 6'd0));
            end

            // Channel 9: pads
            4'h9: begin
              // NOTE: Pad range from 0x24 - 0x33.
              case (note)
                7'h28: o_mode <= MUTE;
                7'h29: o_mode <= PASSTHROUGH;
                7'h2a: o_mode <= AUTOTUNE;
                7'h2b: o_mode <= VOCODE;
                7'h2c: o_mode <= SYNTH;
                default: begin
                  // Unsupported pad, ignore.
                end
              endcase
            end

            default: begin
              // Unsupported channel, ignore.
            end
          endcase

          state <= STATUS;
        end

        // Control (encoder) number.
        CTRL_NUMBER: begin
          if (rdy) begin
            note  <= rx_data[6:0];
            state <= CTRL_VALUE;
          end
        end

        // Control (encoder) velocity.
        CTRL_VALUE: begin
          if (rdy) begin
            velocity <= rx_data[6:0];
            state <= CTRL_PROCESS;
          end
        end

        // Process controllers (encoders).
        CTRL_PROCESS: begin
          case (channel)
            // Channel 0: encoders
            4'h0: begin
              o_encoders[note - 6'h15] <= velocity;
            end

            default: begin
              // Unsupported channel, ignore.
            end
          endcase

          state <= STATUS;
        end

        default: begin
          state <= STATUS;
        end
      endcase
    end
  end
endmodule
