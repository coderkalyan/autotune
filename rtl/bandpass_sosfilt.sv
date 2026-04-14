`timescale 1ns/1ps

`include "fixed.sv"

// Two cascaded 2nd-order IIR stages, matching the provided pseudocode:
//
//   w[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*w[n-1] - a2*w[n-2]
//   y[n] = c0*w[n] + c1*w[n-1] + c2*w[n-2] - d1*y[n-1] - d2*y[n-2]
//
module bandpass_sosfilt #(
    parameter int BANKS  = 1,
    parameter int BANK_W = (BANKS <= 1) ? 1 : $clog2(BANKS)
) (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    input  logic [BANK_W-1:0] i_bank,
    // Stage 0 (x -> w) coefficients
    input  fixed_t i_b0,
    input  fixed_t i_b1,
    input  fixed_t i_b2,
    input  fixed_t i_a1,
    input  fixed_t i_a2,
    // Stage 1 (w -> y) coefficients
    input  fixed_t i_c0,
    input  fixed_t i_c1,
    input  fixed_t i_c2,
    input  fixed_t i_d1,
    input  fixed_t i_d2,
    output fixed_t o_data,
    output wire    o_valid
);
    fixed_t w;
    logic   w_valid;

    sos_iir2 #(
        .BANKS  (BANKS),
        .BANK_W (BANK_W)
    ) stage_w (
        .clk    (clk),
        .rst    (rst),
        .i_data (i_data),
        .i_valid(i_valid),
        .i_bank (i_bank),
        .i_b0   (i_b0),
        .i_b1   (i_b1),
        .i_b2   (i_b2),
        .i_a1   (i_a1),
        .i_a2   (i_a2),
        .o_data (w),
        .o_valid(w_valid)
    );

    sos_iir2 #(
        .BANKS  (BANKS),
        .BANK_W (BANK_W)
    ) stage_y (
        .clk    (clk),
        .rst    (rst),
        .i_data (w),
        .i_valid(w_valid),
        .i_bank (i_bank),
        .i_b0   (i_c0),
        .i_b1   (i_c1),
        .i_b2   (i_c2),
        .i_a1   (i_d1),
        .i_a2   (i_d2),
        .o_data (o_data),
        .o_valid(o_valid)
    );
endmodule
