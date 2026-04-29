package global_enums;

  // Other functions/tasks can also be defined here
typedef enum logic [4:0] {
      ZERO  = 5'h00,
      ONE   = 5'h01,
      TWO   = 5'h02,
      THREE = 5'h03,
      FOUR  = 5'h04,
      FIVE  = 5'h05,
      SIX   = 5'h06,
      SEVEN = 5'h07,
      EIGHT = 5'h08,
      NINE  = 5'h09,
      A     = 5'h0A,
      B     = 5'h0B,
      C     = 5'h0C,
      D     = 5'h0D,
      E     = 5'h0E,
      F     = 5'h0F,

      // extra symbols
      G     = 5'h10,
      S     = 5'h11,
      NONE  = 5'h12,
      V     = 5'h13,
      P     = 5'h14,
      H     = 5'h15
  } hex_t;

typedef enum logic [2:0] {
  MUTE = 3'b000,
  PASSTHROUGH = 3'b001,
  AUTOTUNE = 3'b010,
  VOCODE = 3'b011,
  SYNTH = 3'b100,
  HARMONY = 3'b101
} mode_t;

endpackage

