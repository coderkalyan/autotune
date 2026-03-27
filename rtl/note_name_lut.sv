import global_enums::*;

module note_name_lut (
    input  logic [9:0] nearest_note_lag,
    output hex_t       HEX2,
    output hex_t       HEX1,
    output hex_t       HEX0
);


    logic [14:0] HEXNOTE;   

    always_comb begin
        // HEXNOTE = {NONE, NONE, NONE};
        case (nearest_note_lag)
            10'd925 : HEXNOTE = {S   , G , ONE   };  // G#1
            10'd873 : HEXNOTE = {NONE, A , ONE   };  // A1
            10'd824 : HEXNOTE = {S   , A , ONE   };  // A#1
            10'd778 : HEXNOTE = {NONE, B , ONE   };  // B1
            10'd734 : HEXNOTE = {NONE, C , TWO   };  // C2
            10'd693 : HEXNOTE = {S   , C , TWO   };  // C#2
            10'd654 : HEXNOTE = {NONE, D , TWO   };  // D2
            10'd617 : HEXNOTE = {S   , D , TWO   };  // D#2
            10'd582 : HEXNOTE = {NONE, E , TWO   };  // E2
            10'd550 : HEXNOTE = {NONE, F , TWO   };  // F2
            10'd519 : HEXNOTE = {S   , F , TWO   };  // F#2
            10'd490 : HEXNOTE = {NONE, G , TWO   };  // G2
            10'd462 : HEXNOTE = {S   , G , TWO   };  // G#2
            10'd436 : HEXNOTE = {NONE, A , TWO   };  // A2
            10'd412 : HEXNOTE = {S   , A , TWO   };  // A#2
            10'd389 : HEXNOTE = {NONE, B , TWO   };  // B2
            10'd367 : HEXNOTE = {NONE, C , THREE };  // C3
            10'd346 : HEXNOTE = {S   , C , THREE };  // C#3
            10'd327 : HEXNOTE = {NONE, D , THREE };  // D3
            10'd309 : HEXNOTE = {S   , D , THREE };  // D#3
            10'd291 : HEXNOTE = {NONE, E , THREE };  // E3
            10'd275 : HEXNOTE = {NONE, F , THREE };  // F3
            10'd259 : HEXNOTE = {S   , F , THREE };  // F#3
            10'd245 : HEXNOTE = {NONE, G , THREE };  // G3
            10'd231 : HEXNOTE = {S   , G , THREE };  // G#3
            10'd218 : HEXNOTE = {NONE, A , THREE };  // A3
            10'd206 : HEXNOTE = {S   , A , THREE };  // A#3
            10'd194 : HEXNOTE = {NONE, B , THREE };  // B3
            10'd183 : HEXNOTE = {NONE, C , FOUR  };  // C4
            10'd173 : HEXNOTE = {S   , C , FOUR  };  // C#4
            10'd163 : HEXNOTE = {NONE, D , FOUR  };  // D4
            10'd154 : HEXNOTE = {S   , D , FOUR  };  // D#4
            10'd146 : HEXNOTE = {NONE, E , FOUR  };  // E4
            10'd137 : HEXNOTE = {NONE, F , FOUR  };  // F4
            10'd130 : HEXNOTE = {S   , F , FOUR  };  // F#4
            10'd122 : HEXNOTE = {NONE, G , FOUR  };  // G4
            10'd116 : HEXNOTE = {S   , G , FOUR  };  // G#4
            10'd109 : HEXNOTE = {NONE, A , FOUR  };  // A4
            10'd103 : HEXNOTE = {S   , A , FOUR  };  // A#4
            10'd97  : HEXNOTE = {NONE, B , FOUR  };  // B4
            10'd92  : HEXNOTE = {NONE, C , FIVE  };  // C5
            10'd87  : HEXNOTE = {S   , C , FIVE  };  // C#5
            10'd82  : HEXNOTE = {NONE, D , FIVE  };  // D5
            10'd77  : HEXNOTE = {S   , D , FIVE  };  // D#5
            10'd73  : HEXNOTE = {NONE, E , FIVE  };  // E5
            10'd69  : HEXNOTE = {NONE, F , FIVE  };  // F5
            10'd65  : HEXNOTE = {S   , F , FIVE  };  // F#5
            10'd61  : HEXNOTE = {NONE, G , FIVE  };  // G5
            10'd58  : HEXNOTE = {S   , G , FIVE  };  // G#5
            10'd55  : HEXNOTE = {NONE, A , FIVE  };  // A5
            10'd51  : HEXNOTE = {S   , A , FIVE  };  // A#5
            10'd49  : HEXNOTE = {NONE, B , FIVE  };  // B5
            10'd46  : HEXNOTE = {NONE, C , SIX   };  // C6
            10'd43  : HEXNOTE = {S   , C , SIX   };  // C#6
            10'd41  : HEXNOTE = {NONE, D , SIX   };  // D6
            10'd39  : HEXNOTE = {S   , D , SIX   };  // D#6
            10'd36  : HEXNOTE = {NONE, E , SIX   };  // E6
            10'd34  : HEXNOTE = {NONE, F , SIX   };  // F6
            10'd32  : HEXNOTE = {S   , F , SIX   };  // F#6
            10'd31  : HEXNOTE = {NONE, G , SIX   };  // G6
            10'd29  : HEXNOTE = {S   , G , SIX   };  // G#6
            10'd27  : HEXNOTE = {NONE, A , SIX   };  // A6
            10'd26  : HEXNOTE = {S   , A , SIX   };  // A#6
            10'd24  : HEXNOTE = {NONE, B , SIX   };  // B6
            default: HEXNOTE = {NONE, NONE, NONE};
        endcase
    end

    assign HEX2 = hex_t'(HEXNOTE[14:10]);
    assign HEX1 = hex_t'(HEXNOTE[9:5]);
    assign HEX0 = hex_t'(HEXNOTE[4:0]);

endmodule
