`include "fixed.sv"

module note_selection (
    input [9:0] actual_lag,
    input [9:0] target_lag,
    output fmac_t shift_ratio
);

/*
Shift ratio = f(target) / f(actual) = lag(actual) / lag(target)
- TODO: may need to do some work to "clean" autocorrelation input
- Check if (lag(target) < lag(actual) * 2) & (lag(target) > lag(actual) * 0.5)
    - based on this saturate to target_sat
- Use a LUT to compute 1 / lag(target_eff), then multiply
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
reciprocal_lut (
    .target_lag(target_eff),
    .fliped_target(reciprocal)
);

// ----------------------------------------------------------------
// Nearest Note LUT
// ----------------------------------------------------------------
logic [9:0] nearest_note;
nearest_note_lut (
    .in_lag(actual_eff),
    .nearest_note_lag(nearest_note)
);

// ----------------------------------------------------------------
// Ratio Logic
// ----------------------------------------------------------------
fixed_t actual_fixed;

assign actual_fixed = fixed_t'({1'b0,actual_eff,16'd0});
assign shift_ratio = actual_fixed * reciprocal;
assign target_eff = (target_lag == 0) ? nearest_note : target_sat;


endmodule