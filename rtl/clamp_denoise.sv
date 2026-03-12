`timescale 1ns/1ps

`include "fixed.sv"

module clamp_denoise (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  fixed_t i_amax,
    output fixed_t o_data
);
    localparam real    RATIO  = 0.3;
    localparam fixed_t FRATIO = `FIXED_RTOF(RATIO);
    localparam fixed_t FZERO  = fixed_t'(27'd0);

    // logic lt, gt;
    // always_comb lt = i_data < -cl;
    // always_comb gt = i_data > cl;

    fixed_t cl, y;
    always_comb begin
        cl = fixed_mul(FRATIO, i_amax);

        if (i_data > cl)
            y = i_data - cl;
        else if (i_data < -cl)
            y = i_data + cl;
        else
            y = FZERO;
    end

    assign o_data = y;
endmodule
