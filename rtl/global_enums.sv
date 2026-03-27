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
      NONE  = 5'h12
  } hex_t;
endpackage