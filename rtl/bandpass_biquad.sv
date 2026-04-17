`timescale 1ns/1ps

`include "fixed.sv"

// Two cascaded 2nd-order IIR stages, matching the provided pseudocode:
//
//   w[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*w[n-1] - a2*w[n-2]
//   y[n] = c0*w[n] + c1*w[n-1] + c2*w[n-2] - d1*y[n-1] - d2*y[n-2]
module bandpass_biquad (
    // Input data.
    input  fnorm_t i_x0,
    input  fnorm_t i_x1,
    input  fnorm_t i_x2,
    input  fnorm_t i_x3,
    input  fnorm_t i_x4,
    input  fnorm_t i_x5,
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
    // Combinational output.
    output fnorm_t o_s0_data,
    output fnorm_t o_s1_data
);
    biquad_stage s0 (
        .i_x0(i_x0),
        .i_x1(i_x1),
        .i_x2(i_x2),
        .i_y1(i_s0_y1),
        .i_y2(i_s0_y2),
        .i_b0(i_s0_b0),
        .i_b1(i_s0_b1),
        .i_a1(i_s0_a1),
        .i_a2(i_s0_a2),
        .o_data (o_s0_data)
    );

    biquad_stage s1 (
        .i_x0(i_x3),
        .i_x1(i_x4),
        .i_x2(i_x5),
        .i_y1(i_s1_y1),
        .i_y2(i_s1_y2),
        .i_b0(i_s1_b0),
        .i_b1(i_s1_b1),
        .i_a1(i_s1_a1),
        .i_a2(i_s1_a2),
        .o_data (o_s1_data)
    );
endmodule
