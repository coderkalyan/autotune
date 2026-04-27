`timescale 1ns/1ps

`include "fixed.sv"

// Two cascaded 2nd-order IIR stages, matching the provided pseudocode:
//
//   w[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*w[n-1] - a2*w[n-2]
//   y[n] = c0*w[n] + c1*w[n-1] + c2*w[n-2] - d1*y[n-1] - d2*y[n-2]
//
// NOTE: stage 1's x inputs are stage 0's current output + its previous 2
// outputs (w[n], w[n-1], w[n-2]), NOT x[n-3..n-5]. i_x3..i_x5 are legacy
// ports kept for backward compatibility but are unused.
//
// Pipelined: 2-cycle latency from inputs to o_s0_data/o_s1_data.
//   cycle 0 (comb)  : stage 0 multiplies + sum + truncate
//   cycle 1 (reg)   : s0 result + delayed s1 operands; stage 1 mults + sum
//   cycle 2 (reg)   : registered o_s0_data and o_s1_data outputs
// Breaking s0 -> s1 chain removes the back-to-back DSP mult cascade that
// dominated the path. Output register on o_s1_data also lets downstream
// abs/asym_follow start from a flop instead of comb.
module bandpass_biquad (
    input  wire    clk,
    // Input data.
    input  fnorm_t i_x0,
    input  fnorm_t i_x1,
    input  fnorm_t i_x2,
    input  fnorm_t i_x3,  // unused (legacy)
    input  fnorm_t i_x4,  // unused (legacy)
    input  fnorm_t i_x5,  // unused (legacy)
    // History.
    input  fnorm_t i_s0_y1,
    input  fnorm_t i_s0_y2,
    input  fnorm_t i_s1_y1,
    input  fnorm_t i_s1_y2,
    // Stage 0 coefficients.
    input  fnorm_t i_s0_b0,
    input  fnorm_t i_s0_b1,
    input  fnorm_t i_s0_a1,
    input  fnorm_t i_s0_a2,
    // Stage 1 coefficients.
    input  fnorm_t i_s1_b0,
    input  fnorm_t i_s1_b1,
    input  fnorm_t i_s1_a1,
    input  fnorm_t i_s1_a2,
    // Registered outputs (2-cycle latency, both aligned).
    output fnorm_t o_s0_data,
    output fnorm_t o_s1_data
);
    // Stage 0 combinational result.
    fnorm_t s0_comb;
    biquad_stage s0 (
        .i_x0 (i_x0),
        .i_x1 (i_x1),
        .i_x2 (i_x2),
        .i_y1 (i_s0_y1),
        .i_y2 (i_s0_y2),
        .i_b0 (i_s0_b0),
        .i_b1 (i_s0_b1),
        .i_a1 (i_s0_a1),
        .i_a2 (i_s0_a2),
        .o_data (s0_comb)
    );

    // Pipeline register between s0 and s1. Also delay s1's other operands
    // (s0 history, s1 history, s1 coefs) by 1 cycle so they align with the
    // registered s0 result.
    fnorm_t s0_data_r;
    fnorm_t s0_y1_d, s0_y2_d;
    fnorm_t s1_y1_d, s1_y2_d;
    fnorm_t s1_b0_d, s1_b1_d, s1_a1_d, s1_a2_d;
    always_ff @(posedge clk) begin
        s0_data_r <= s0_comb;
        s0_y1_d   <= i_s0_y1;
        s0_y2_d   <= i_s0_y2;
        s1_y1_d   <= i_s1_y1;
        s1_y2_d   <= i_s1_y2;
        s1_b0_d   <= i_s1_b0;
        s1_b1_d   <= i_s1_b1;
        s1_a1_d   <= i_s1_a1;
        s1_a2_d   <= i_s1_a2;
    end

    // Stage 1 consumes registered s0 output (cascade across pipeline reg).
    fnorm_t s1_comb;
    biquad_stage s1 (
        .i_x0 (s0_data_r),
        .i_x1 (s0_y1_d),
        .i_x2 (s0_y2_d),
        .i_y1 (s1_y1_d),
        .i_y2 (s1_y2_d),
        .i_b0 (s1_b0_d),
        .i_b1 (s1_b1_d),
        .i_a1 (s1_a1_d),
        .i_a2 (s1_a2_d),
        .o_data (s1_comb)
    );

    // Output register on both stages. Registers o_s1_data so the downstream
    // abs+asym path starts from a flop (pulls abs out of the critical path).
    // Delays o_s0_data by an extra cycle so both outputs have the same
    // 2-cycle latency.
    fnorm_t s0_data_r2, s1_data_r;
    always_ff @(posedge clk) begin
        s0_data_r2 <= s0_data_r;
        s1_data_r  <= s1_comb;
    end

    assign o_s0_data = s0_data_r2;
    assign o_s1_data = s1_data_r;
endmodule
