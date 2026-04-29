import global_enums::*;

module hex_display (
    input logic clk,
    input logic rst,
    input logic [9:0] pitch_period,
    input logic [9:0] target_lag,
    input mode_t mode,
    input logic [6:0] i_encoders [0:7],
    input logic i_btn,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5
);

hex_t note0, note1, note2, note3, note4;

logic display_state;
logic btn_prev;
always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
        display_state <= 1'b0;
        btn_prev      <= 1'b0;
    end else begin
        btn_prev <= i_btn;
        if (i_btn & ~btn_prev)
            display_state <= ~display_state;
    end
end

logic [9:0] lag_out;
nearest_note_lut nearest_note_lut (
    .in_lag(pitch_period),
    .nearest_note_lag(lag_out)
);

// Instantiate note_name_lut
note_name_lut u_pitch_period_lut (
    .nearest_note_lag(lag_out),
    .HEX2(note2),
    .HEX1(note1),
    .HEX0(note0)
);

note_name_lut u_target_lag_lut (
    .nearest_note_lag(target_lag),
    .HEX2(),
    .HEX1(note4),
    .HEX0(note3)
);

hex_t eff_mode;
always_comb begin
    case(mode)
        MUTE: eff_mode = NONE;
        PASSTHROUGH: eff_mode = P;
        AUTOTUNE: eff_mode = A;
        VOCODE: eff_mode = V;
        SYNTH: eff_mode = S;
        HARMONY: eff_mode = H;
        default: eff_mode = NONE;
    endcase
end

always_comb begin
    HEX0 = hex7_notes(NONE);
    HEX1 = hex7_notes(NONE);
    HEX2 = hex7_notes(NONE);
    HEX3 = hex7_notes(NONE);
    HEX4 = hex7_notes(NONE);
    HEX5 = hex7_notes(NONE);

    case(display_state)
        1'd0: begin
            // display mode, encoders
            HEX0 = hex7_notes(hex_t'(i_encoders[0][3:0]));
            HEX1 = hex7_notes(hex_t'(i_encoders[0][6:4]));
            HEX2 = hex7_notes(hex_t'(i_encoders[1][6:4]));
    
            HEX5 = hex7_notes(eff_mode);
        end
        1'b1: begin 
            // displays mode, detected pitch_period, target_note
            HEX0 = hex7_notes(note0);
            HEX1 = hex7_notes(note1);
            HEX2 = hex7_notes(note2);

            HEX3 = hex7_notes(note3);
            HEX4 = hex7_notes(note4);

            HEX5 = hex7_notes(eff_mode);
        end 
    endcase 
end

function automatic logic [6:0] hex7_notes(input hex_t val);
    case (val)
      ZERO:  hex7_notes = 7'b1000000;
      ONE:   hex7_notes = 7'b1111001;
      TWO:   hex7_notes = 7'b0100100;
      THREE: hex7_notes = 7'b0110000;
      FOUR:  hex7_notes = 7'b0011001;
      FIVE:  hex7_notes = 7'b0010010;
      SIX:   hex7_notes = 7'b0000010;
      SEVEN: hex7_notes = 7'b1111000;
      EIGHT: hex7_notes = 7'b0000000;
      NINE:  hex7_notes = 7'b0011000;
      A:     hex7_notes = 7'b0001000;
      B:     hex7_notes = 7'b0000011;
      C:     hex7_notes = 7'b1000110;
      D:     hex7_notes = 7'b0100001;
      E:     hex7_notes = 7'b0000110;
      F:     hex7_notes = 7'b0001110;
      V:     hex7_notes = 7'b1000001;
      P:     hex7_notes = 7'b0011000;

      // Optional patterns for G and S (customize if needed)
      G: hex7_notes = 7'b0000010;  // similar to '6'
      S: hex7_notes = 7'b0010010;  // similar to '5'
      H: hex7_notes = 7'b0001001;  // a,d off; b,c,e,f,g lit

      NONE: hex7_notes = 7'b1111111;

      default: hex7_notes = 7'b1111111;
    endcase
endfunction

endmodule
