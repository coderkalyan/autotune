`timescale 1ns / 1ps

`include "fixed.sv"

// Butterworth SOS 2nd-order IIR (biquad) stage in Direct Form I:
// y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
//
// Coefficients are fixed-point Q3.24 (fnorm_t). a0 is assumed to be 1.
module biquad_stage (
    // Input data.
    input  fnorm_t i_x0,
    input  fnorm_t i_x1,
    input  fnorm_t i_x2,
    // History.
    input  fnorm_t i_y1,
    input  fnorm_t i_y2,
    // Filter coefficients.
    input  fnorm_t i_b0,
    input  fnorm_t i_b1,
    input  fnorm_t i_a1,
    input  fnorm_t i_a2,
    // Combinational output.
    output fnorm_t o_data
);
    logic [53:0] p_b0b2, p_b1, p_a1, p_a2, acc;
    always_comb begin
        p_b0b2 = fnorm_mul_raw(i_b0, i_x0 + i_x2);
        p_b1 = fnorm_mul_raw(i_b1, i_x1);
        p_a1 = fnorm_mul_raw(i_a1, i_y1);
        p_a2 = fnorm_mul_raw(i_a2, i_y2);

        acc = p_b0b2 + p_b1 - p_a1 - p_a2;
        o_data = fnorm_mul_trunc(acc);
    end
endmodule
