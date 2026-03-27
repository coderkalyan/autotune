module nearest_note_lut (
    input  logic [9:0] in_lag,
    output logic [9:0] nearest_note_lag
);

    always_comb begin
        // Threshold = floor(sqrt(lag[n] * lag[n-1])) — logarithmic midpoint between semitones.
        // Fs = 48000 Hz.  Ordered from largest lag (lowest pitch) to smallest.
         if (in_lag >= 10'd898)              nearest_note_lag = 10'd925; // MIDI 32  G#1    ~51.91 Hz
         else if (in_lag >= 10'd848)         nearest_note_lag = 10'd873; // MIDI 33  A1     ~55.00 Hz
         else if (in_lag >= 10'd800)         nearest_note_lag = 10'd824; // MIDI 34  A#1    ~58.27 Hz
         else if (in_lag >= 10'd755)         nearest_note_lag = 10'd778; // MIDI 35  B1     ~61.74 Hz
         else if (in_lag >= 10'd713)         nearest_note_lag = 10'd734; // MIDI 36  C2     ~65.41 Hz
         else if (in_lag >= 10'd673)         nearest_note_lag = 10'd693; // MIDI 37  C#2    ~69.30 Hz
         else if (in_lag >= 10'd635)         nearest_note_lag = 10'd654; // MIDI 38  D2     ~73.42 Hz
         else if (in_lag >= 10'd599)         nearest_note_lag = 10'd617; // MIDI 39  D#2    ~77.78 Hz
         else if (in_lag >= 10'd565)         nearest_note_lag = 10'd582; // MIDI 40  E2     ~82.41 Hz
         else if (in_lag >= 10'd534)         nearest_note_lag = 10'd550; // MIDI 41  F2     ~87.31 Hz
         else if (in_lag >= 10'd504)         nearest_note_lag = 10'd519; // MIDI 42  F#2    ~92.50 Hz
         else if (in_lag >= 10'd475)         nearest_note_lag = 10'd490; // MIDI 43  G2     ~98.00 Hz
         else if (in_lag >= 10'd448)         nearest_note_lag = 10'd462; // MIDI 44  G#2    ~103.83 Hz
         else if (in_lag >= 10'd423)         nearest_note_lag = 10'd436; // MIDI 45  A2     ~110.00 Hz
         else if (in_lag >= 10'd400)         nearest_note_lag = 10'd412; // MIDI 46  A#2    ~116.54 Hz
         else if (in_lag >= 10'd377)         nearest_note_lag = 10'd389; // MIDI 47  B2     ~123.47 Hz
         else if (in_lag >= 10'd356)         nearest_note_lag = 10'd367; // MIDI 48  C3     ~130.81 Hz
         else if (in_lag >= 10'd336)         nearest_note_lag = 10'd346; // MIDI 49  C#3    ~138.59 Hz
         else if (in_lag >= 10'd317)         nearest_note_lag = 10'd327; // MIDI 50  D3     ~146.83 Hz
         else if (in_lag >= 10'd299)         nearest_note_lag = 10'd309; // MIDI 51  D#3    ~155.56 Hz
         else if (in_lag >= 10'd282)         nearest_note_lag = 10'd291; // MIDI 52  E3     ~164.81 Hz
         else if (in_lag >= 10'd266)         nearest_note_lag = 10'd275; // MIDI 53  F3     ~174.61 Hz
         else if (in_lag >= 10'd251)         nearest_note_lag = 10'd259; // MIDI 54  F#3    ~185.00 Hz
         else if (in_lag >= 10'd237)         nearest_note_lag = 10'd245; // MIDI 55  G3     ~196.00 Hz
         else if (in_lag >= 10'd224)         nearest_note_lag = 10'd231; // MIDI 56  G#3    ~207.65 Hz
         else if (in_lag >= 10'd211)         nearest_note_lag = 10'd218; // MIDI 57  A3     ~220.00 Hz
         else if (in_lag >= 10'd199)         nearest_note_lag = 10'd206; // MIDI 58  A#3    ~233.08 Hz
         else if (in_lag >= 10'd188)         nearest_note_lag = 10'd194; // MIDI 59  B3     ~246.94 Hz
         else if (in_lag >= 10'd177)         nearest_note_lag = 10'd183; // MIDI 60  C4     ~261.63 Hz
         else if (in_lag >= 10'd167)         nearest_note_lag = 10'd173; // MIDI 61  C#4    ~277.18 Hz
         else if (in_lag >= 10'd158)         nearest_note_lag = 10'd163; // MIDI 62  D4     ~293.66 Hz
         else if (in_lag >= 10'd149)         nearest_note_lag = 10'd154; // MIDI 63  D#4    ~311.13 Hz
         else if (in_lag >= 10'd141)         nearest_note_lag = 10'd146; // MIDI 64  E4     ~329.63 Hz
         else if (in_lag >= 10'd133)         nearest_note_lag = 10'd137; // MIDI 65  F4     ~349.23 Hz
         else if (in_lag >= 10'd125)         nearest_note_lag = 10'd130; // MIDI 66  F#4    ~369.99 Hz
         else if (in_lag >= 10'd118)         nearest_note_lag = 10'd122; // MIDI 67  G4     ~392.00 Hz
         else if (in_lag >= 10'd112)         nearest_note_lag = 10'd116; // MIDI 68  G#4    ~415.30 Hz
         else if (in_lag >= 10'd105)         nearest_note_lag = 10'd109; // MIDI 69  A4     ~440.00 Hz
         else if (in_lag >= 10'd99)          nearest_note_lag = 10'd103; // MIDI 70  A#4    ~466.16 Hz
         else if (in_lag >= 10'd94)          nearest_note_lag = 10'd97; // MIDI 71  B4     ~493.88 Hz
         else if (in_lag >= 10'd89)          nearest_note_lag = 10'd92; // MIDI 72  C5     ~523.25 Hz
         else if (in_lag >= 10'd84)          nearest_note_lag = 10'd87; // MIDI 73  C#5    ~554.37 Hz
         else if (in_lag >= 10'd79)          nearest_note_lag = 10'd82; // MIDI 74  D5     ~587.33 Hz
         else if (in_lag >= 10'd74)          nearest_note_lag = 10'd77; // MIDI 75  D#5    ~622.25 Hz
         else if (in_lag >= 10'd70)          nearest_note_lag = 10'd73; // MIDI 76  E5     ~659.26 Hz
         else if (in_lag >= 10'd66)          nearest_note_lag = 10'd69; // MIDI 77  F5     ~698.46 Hz
         else if (in_lag >= 10'd62)          nearest_note_lag = 10'd65; // MIDI 78  F#5    ~739.99 Hz
         else if (in_lag >= 10'd59)          nearest_note_lag = 10'd61; // MIDI 79  G5     ~783.99 Hz
         else if (in_lag >= 10'd56)          nearest_note_lag = 10'd58; // MIDI 80  G#5    ~830.61 Hz
         else if (in_lag >= 10'd52)          nearest_note_lag = 10'd55; // MIDI 81  A5     ~880.00 Hz
         else if (in_lag >= 10'd49)          nearest_note_lag = 10'd51; // MIDI 82  A#5    ~932.33 Hz
         else if (in_lag >= 10'd47)          nearest_note_lag = 10'd49; // MIDI 83  B5     ~987.77 Hz
         else if (in_lag >= 10'd44)          nearest_note_lag = 10'd46; // MIDI 84  C6     ~1046.50 Hz
         else if (in_lag >= 10'd41)          nearest_note_lag = 10'd43; // MIDI 85  C#6    ~1108.73 Hz
         else if (in_lag >= 10'd39)          nearest_note_lag = 10'd41; // MIDI 86  D6     ~1174.66 Hz
         else if (in_lag >= 10'd37)          nearest_note_lag = 10'd39; // MIDI 87  D#6    ~1244.51 Hz
         else if (in_lag >= 10'd34)          nearest_note_lag = 10'd36; // MIDI 88  E6     ~1318.51 Hz
         else if (in_lag >= 10'd32)          nearest_note_lag = 10'd34; // MIDI 89  F6     ~1396.91 Hz
         else if (in_lag >= 10'd31)          nearest_note_lag = 10'd32; // MIDI 90  F#6    ~1479.98 Hz
         else if (in_lag >= 10'd29)          nearest_note_lag = 10'd31; // MIDI 91  G6     ~1567.98 Hz
         else if (in_lag >= 10'd27)          nearest_note_lag = 10'd29; // MIDI 92  G#6    ~1661.22 Hz
         else if (in_lag >= 10'd26)          nearest_note_lag = 10'd27; // MIDI 93  A6     ~1760.00 Hz
         else if (in_lag >= 10'd24)          nearest_note_lag = 10'd26; // MIDI 94  A#6    ~1864.66 Hz
         else if (in_lag >= 10'd23)          nearest_note_lag = 10'd24; // MIDI 95  B6     ~1975.53 Hz
        else                                 nearest_note_lag = 10'd24; // MIDI 95  B6 (above range)
    end


endmodule
