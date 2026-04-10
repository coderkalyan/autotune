import global_enums::*;
`include "fixed.sv"

module note_selection (
    input [9:0] actual_lag,
    input [9:0] target_lag,
    input mode_t mode,
    output fixed_t shift_ratio
);

/*
Shift ratio = 1 / PF
            = 1 / (f(target) / f(actual))
            = f(actual) / f(target) 
            = lag(new) / lag(actual)
            = lag(new) * 1 / lag(actual)
            


- TODO:
- Use a LUT to compute 1 / lag(actual_eff), then multiply
*/

// TODO: temporary variable in case need to do some smoothing on actual_lag input 
logic [9:0] actual_eff, target_sat, target_eff;
assign actual_eff = actual_lag;

// ----------------------------------------------------------------
// Saturation Logic
// ----------------------------------------------------------------
always_comb begin 
    if (target_lag > (actual_eff << 1))
        target_sat = actual_eff << 1;
    else if (target_lag < (actual_eff >> 1))
        target_sat = actual_eff >> 1;
    else 
        target_sat = target_lag;
end

// ----------------------------------------------------------------
// Reciprocal LUT
// ----------------------------------------------------------------
fixed_t reciprocal;
reciprocal_lut iRL(
    .target_lag(actual_eff),
    .fliped_target(reciprocal)
);

// ----------------------------------------------------------------
// Nearest Note LUT
// ----------------------------------------------------------------
logic [9:0] nearest_note;
nearest_note_lut iNNL(
    .in_lag(actual_eff),
    .nearest_note_lag(nearest_note)
);

// ----------------------------------------------------------------
// Ratio Logic
// ----------------------------------------------------------------
fixed_t target_fixed;

assign target_fixed = fixed_t'({1'b0,target_eff,16'd0});
assign shift_ratio = fixed_mul(target_fixed, reciprocal);

always_comb begin
    case (mode)
        PASSTHROUGH: target_eff = actual_eff;
        AUTOTUNE: target_eff = nearest_note;
        VOCODE: target_eff = target_sat;
        default: target_eff = actual_eff; // default to passthrough
    endcase
end
endmodule
