import global_enums::*;

module hex_display (
    input logic [9:0] pitch_period,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5
);

hex_t note0, note1, note2;

logic [9:0] lag_out;
nearest_note_lut nearest_note_lut (
    .in_lag(pitch_period),
    .nearest_note_lag(lag_out)
);

// Instantiate note_name_lut
note_name_lut u_note_name_lut (
    .nearest_note_lag(lag_out),
    .HEX2(note2),
    .HEX1(note1),
    .HEX0(note0)
);

always_comb begin
    // HEX0 = hex7(pitch_period[3:0]);
    // HEX1 = hex7(pitch_period[7:4]);
    // HEX2 = hex7(pitch_period[9:8]);

    // HEX0 = hex7(lag_out[3:0]);
    // HEX1 = hex7(lag_out[7:4]);
    // HEX2 = hex7(lag_out[9:8]);

    HEX0 = hex7_notes(note0);
    HEX1 = hex7_notes(note1);
    HEX2 = hex7_notes(note2);

    // HEX0 = hex7(bcd_freq[3:0]);    // hundredths Hz
    // HEX1 = hex7(bcd_freq[7:4]);    // tenths Hz^M
    // HEX2 = hex7(bcd_freq[11:8]);   // ones Hz^M
    // HEX3 = hex7(bcd_freq[15:12]);  // tens Hz^M
    // HEX4 = hex7(bcd_freq[19:16]);  // hundreds Hz^M
    // HEX5 = hex7(bcd_freq[23:20]);  // thousands Hz^M
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

      // Optional patterns for G and S (customize if needed)
      G: hex7_notes = 7'b0000010;  // similar to '6'
      S: hex7_notes = 7'b0010010;  // similar to '5'

      NONE: hex7_notes = 7'b1111111;

      default: hex7_notes = 7'b1111111;
    endcase
endfunction

endmodule