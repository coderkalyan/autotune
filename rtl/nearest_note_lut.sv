module nearest_note_lut (
    input  logic [9:0] in_lag,
    output logic [9:0] nearest_note_lag
);

    always_comb begin
        case (in_lag) inside
            [10'd900:10'd1023]: nearest_note_lag = 10'd925; // MIDI 32, ~51.91 Hz
            [10'd849:10'd899]: nearest_note_lag = 10'd873; // MIDI 33, ~55.00 Hz
            [10'd802:10'd848]: nearest_note_lag = 10'd824; // MIDI 34, ~58.27 Hz
            [10'd757:10'd801]: nearest_note_lag = 10'd778; // MIDI 35, ~61.74 Hz
            [10'd714:10'd756]: nearest_note_lag = 10'd734; // MIDI 36, ~65.41 Hz
            [10'd674:10'd713]: nearest_note_lag = 10'd693; // MIDI 37, ~69.30 Hz
            [10'd636:10'd673]: nearest_note_lag = 10'd654; // MIDI 38, ~73.42 Hz
            [10'd600:10'd635]: nearest_note_lag = 10'd617; // MIDI 39, ~77.78 Hz
            [10'd567:10'd599]: nearest_note_lag = 10'd582; // MIDI 40, ~82.41 Hz
            [10'd535:10'd566]: nearest_note_lag = 10'd550; // MIDI 41, ~87.31 Hz
            [10'd505:10'd534]: nearest_note_lag = 10'd519; // MIDI 42, ~92.50 Hz
            [10'd477:10'd504]: nearest_note_lag = 10'd490; // MIDI 43, ~98.00 Hz
            [10'd450:10'd476]: nearest_note_lag = 10'd462; // MIDI 44, ~103.83 Hz
            [10'd425:10'd449]: nearest_note_lag = 10'd436; // MIDI 45, ~110.00 Hz
            [10'd401:10'd424]: nearest_note_lag = 10'd412; // MIDI 46, ~116.54 Hz
            [10'd379:10'd400]: nearest_note_lag = 10'd389; // MIDI 47, ~123.47 Hz
            [10'd357:10'd378]: nearest_note_lag = 10'd367; // MIDI 48, ~130.81 Hz
            [10'd337:10'd356]: nearest_note_lag = 10'd346; // MIDI 49, ~138.59 Hz
            [10'd319:10'd336]: nearest_note_lag = 10'd327; // MIDI 50, ~146.83 Hz
            [10'd301:10'd318]: nearest_note_lag = 10'd309; // MIDI 51, ~155.56 Hz
            [10'd284:10'd300]: nearest_note_lag = 10'd291; // MIDI 52, ~164.81 Hz
            [10'd268:10'd283]: nearest_note_lag = 10'd275; // MIDI 53, ~174.61 Hz
            [10'd253:10'd267]: nearest_note_lag = 10'd259; // MIDI 54, ~185.00 Hz
            [10'd239:10'd252]: nearest_note_lag = 10'd245; // MIDI 55, ~196.00 Hz
            [10'd225:10'd238]: nearest_note_lag = 10'd231; // MIDI 56, ~207.65 Hz
            [10'd213:10'd224]: nearest_note_lag = 10'd218; // MIDI 57, ~220.00 Hz
            [10'd201:10'd212]: nearest_note_lag = 10'd206; // MIDI 58, ~233.08 Hz
            [10'd189:10'd200]: nearest_note_lag = 10'd194; // MIDI 59, ~246.94 Hz
            [10'd179:10'd188]: nearest_note_lag = 10'd183; // MIDI 60, ~261.63 Hz
            [10'd169:10'd178]: nearest_note_lag = 10'd173; // MIDI 61, ~277.18 Hz
            [10'd159:10'd168]: nearest_note_lag = 10'd163; // MIDI 62, ~293.66 Hz
            [10'd151:10'd158]: nearest_note_lag = 10'd154; // MIDI 63, ~311.13 Hz
            [10'd142:10'd150]: nearest_note_lag = 10'd146; // MIDI 64, ~329.63 Hz
            [10'd134:10'd141]: nearest_note_lag = 10'd137; // MIDI 65, ~349.23 Hz
            [10'd127:10'd133]: nearest_note_lag = 10'd130; // MIDI 66, ~369.99 Hz
            [10'd120:10'd126]: nearest_note_lag = 10'd122; // MIDI 67, ~392.00 Hz
            [10'd113:10'd119]: nearest_note_lag = 10'd116; // MIDI 68, ~415.30 Hz
            [10'd107:10'd112]: nearest_note_lag = 10'd109; // MIDI 69, ~440.00 Hz
            [10'd101:10'd106]: nearest_note_lag = 10'd103; // MIDI 70, ~466.16 Hz
            [10'd95:10'd100]: nearest_note_lag = 10'd97; // MIDI 71, ~493.88 Hz
            [10'd90:10'd94]: nearest_note_lag = 10'd92; // MIDI 72, ~523.25 Hz
            [10'd85:10'd89]: nearest_note_lag = 10'd87; // MIDI 73, ~554.37 Hz
            [10'd80:10'd84]: nearest_note_lag = 10'd82; // MIDI 74, ~587.33 Hz
            [10'd76:10'd79]: nearest_note_lag = 10'd77; // MIDI 75, ~622.25 Hz
            [10'd72:10'd75]: nearest_note_lag = 10'd73; // MIDI 76, ~659.26 Hz
            [10'd68:10'd71]: nearest_note_lag = 10'd69; // MIDI 77, ~698.46 Hz
            [10'd64:10'd67]: nearest_note_lag = 10'd65; // MIDI 78, ~739.99 Hz
            [10'd60:10'd63]: nearest_note_lag = 10'd61; // MIDI 79, ~783.99 Hz
            [10'd57:10'd59]: nearest_note_lag = 10'd58; // MIDI 80, ~830.61 Hz
            [10'd54:10'd56]: nearest_note_lag = 10'd55; // MIDI 81, ~880.00 Hz
            [10'd51:10'd53]: nearest_note_lag = 10'd51; // MIDI 82, ~932.33 Hz
            [10'd48:10'd50]: nearest_note_lag = 10'd49; // MIDI 83, ~987.77 Hz
            [10'd45:10'd47]: nearest_note_lag = 10'd46; // MIDI 84, ~1046.50 Hz
            [10'd43:10'd44]: nearest_note_lag = 10'd43; // MIDI 85, ~1108.73 Hz
            [10'd41:10'd42]: nearest_note_lag = 10'd41; // MIDI 86, ~1174.66 Hz
            [10'd38:10'd40]: nearest_note_lag = 10'd39; // MIDI 87, ~1244.51 Hz
            [10'd36:10'd37]: nearest_note_lag = 10'd36; // MIDI 88, ~1318.51 Hz
            [10'd34:10'd35]: nearest_note_lag = 10'd34; // MIDI 89, ~1396.91 Hz
            [10'd32:10'd33]: nearest_note_lag = 10'd32; // MIDI 90, ~1479.98 Hz
            [10'd31:10'd31]: nearest_note_lag = 10'd31; // MIDI 91, ~1567.98 Hz
            [10'd29:10'd30]: nearest_note_lag = 10'd29; // MIDI 92, ~1661.22 Hz
            [10'd27:10'd28]: nearest_note_lag = 10'd27; // MIDI 93, ~1760.00 Hz
            [10'd26:10'd26]: nearest_note_lag = 10'd26; // MIDI 94, ~1864.66 Hz
            [10'd0:10'd25]: nearest_note_lag = 10'd24; // MIDI 95, ~1975.53 Hz
            default: nearest_note_lag = 10'd24;
        endcase
    end

endmodule