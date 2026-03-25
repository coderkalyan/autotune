module midi_freq_lut (
    input [6:0] note,
    output reg [9:0] frequency
);

/*
    NOTE: We are only able to detect from 100hz-1000hz (48-480 lags).
    Afterwards PSOLA has the capability to shift +/- 1 octave.

    + 1 octave = f * 2
    - 1 octave = f / 2

    Therefore our LUT need the capability to detect 50-2000hz (24-960 lag).
    Any frequencies above or below these threshold will saturate.
*/
    always @(*) begin
        case (note)
            7'd0: lag = 10'd960;
            7'd1: lag = 10'd960;
            7'd2: lag = 10'd960;
            7'd3: lag = 10'd960;
            7'd4: lag = 10'd960;
            7'd5: lag = 10'd960;
            7'd6: lag = 10'd960;
            7'd7: lag = 10'd960;
            7'd8: lag = 10'd960;
            7'd9: lag = 10'd960;
            7'd10: lag = 10'd960;
            7'd11: lag = 10'd960;
            7'd12: lag = 10'd960;
            7'd13: lag = 10'd960;
            7'd14: lag = 10'd960;
            7'd15: lag = 10'd960;
            7'd16: lag = 10'd960;
            7'd17: lag = 10'd960;
            7'd18: lag = 10'd960;
            7'd19: lag = 10'd960;
            7'd20: lag = 10'd960;
            7'd21: lag = 10'd960;
            7'd22: lag = 10'd960;
            7'd23: lag = 10'd960;
            7'd24: lag = 10'd960;
            7'd25: lag = 10'd960;
            7'd26: lag = 10'd960;
            7'd27: lag = 10'd960;
            7'd28: lag = 10'd960;
            7'd29: lag = 10'd960;
            7'd30: lag = 10'd960;
            7'd31: lag = 10'd960;
            7'd32: lag = 10'd925;
            7'd33: lag = 10'd873;
            7'd34: lag = 10'd824;
            7'd35: lag = 10'd778;
            7'd36: lag = 10'd734;
            7'd37: lag = 10'd693;
            7'd38: lag = 10'd654;
            7'd39: lag = 10'd617;
            7'd40: lag = 10'd582;
            7'd41: lag = 10'd550;
            7'd42: lag = 10'd519;
            7'd43: lag = 10'd490;
            7'd44: lag = 10'd462;
            7'd45: lag = 10'd436;
            7'd46: lag = 10'd412;
            7'd47: lag = 10'd389;
            7'd48: lag = 10'd367;
            7'd49: lag = 10'd346;
            7'd50: lag = 10'd327;
            7'd51: lag = 10'd309;
            7'd52: lag = 10'd291;
            7'd53: lag = 10'd275;
            7'd54: lag = 10'd259;
            7'd55: lag = 10'd245;
            7'd56: lag = 10'd231;
            7'd57: lag = 10'd218;
            7'd58: lag = 10'd206;
            7'd59: lag = 10'd194;
            7'd60: lag = 10'd183;
            7'd61: lag = 10'd173;
            7'd62: lag = 10'd163;
            7'd63: lag = 10'd154;
            7'd64: lag = 10'd146;
            7'd65: lag = 10'd137;
            7'd66: lag = 10'd130;
            7'd67: lag = 10'd122;
            7'd68: lag = 10'd116;
            7'd69: lag = 10'd109;
            7'd70: lag = 10'd103;
            7'd71: lag = 10'd97;
            7'd72: lag = 10'd92;
            7'd73: lag = 10'd87;
            7'd74: lag = 10'd82;
            7'd75: lag = 10'd77;
            7'd76: lag = 10'd73;
            7'd77: lag = 10'd69;
            7'd78: lag = 10'd65;
            7'd79: lag = 10'd61;
            7'd80: lag = 10'd58;
            7'd81: lag = 10'd55;
            7'd82: lag = 10'd51;
            7'd83: lag = 10'd49;
            7'd84: lag = 10'd46;
            7'd85: lag = 10'd43;
            7'd86: lag = 10'd41;
            7'd87: lag = 10'd39;
            7'd88: lag = 10'd36;
            7'd89: lag = 10'd34;
            7'd90: lag = 10'd32;
            7'd91: lag = 10'd31;
            7'd92: lag = 10'd29;
            7'd93: lag = 10'd27;
            7'd94: lag = 10'd26;
            7'd95: lag = 10'd24;
            7'd96: lag = 10'd24;
            7'd97: lag = 10'd24;
            7'd98: lag = 10'd24;
            7'd99: lag = 10'd24;
            7'd100: lag = 10'd24;
            7'd101: lag = 10'd24;
            7'd102: lag = 10'd24;
            7'd103: lag = 10'd24;
            7'd104: lag = 10'd24;
            7'd105: lag = 10'd24;
            7'd106: lag = 10'd24;
            7'd107: lag = 10'd24;
            7'd108: lag = 10'd24;
            7'd109: lag = 10'd24;
            7'd110: lag = 10'd24;
            7'd111: lag = 10'd24;
            7'd112: lag = 10'd24;
            7'd113: lag = 10'd24;
            7'd114: lag = 10'd24;
            7'd115: lag = 10'd24;
            7'd116: lag = 10'd24;
            7'd117: lag = 10'd24;
            7'd118: lag = 10'd24;
            7'd119: lag = 10'd24;
            7'd120: lag = 10'd24;
            7'd121: lag = 10'd24;
            7'd122: lag = 10'd24;
            7'd123: lag = 10'd24;
            7'd124: lag = 10'd24;
            7'd125: lag = 10'd24;
            7'd126: lag = 10'd24;
            7'd127: lag = 10'd24;
            default: lag = 10'd0; // Default to a impossible value
        endcase
    end

endmodule
