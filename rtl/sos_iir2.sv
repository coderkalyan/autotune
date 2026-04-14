`timescale 1ns / 1ps

`include "fixed.sv"

// butterworth SOS 2nd-order IIR (biquad) stage in Direct Form I:
//
// y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
//
//
// Coefficients are fixed-point Q11.16 (fixed_t). a0 is assumed to be 1.
module sos_iir2 #(
    // When BANKS>1, the delay-line state is banked internally and selected
    // using i_bank. When BANKS==1, i_bank is ignored.
    parameter int BANKS  = 1,
    parameter int BANK_W = (BANKS <= 1) ? 1 : $clog2(BANKS)
) (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    input  logic [BANK_W-1:0] i_bank,
    input  fixed_t i_b0,
    input  fixed_t i_b1,
    input  fixed_t i_b2,
    input  fixed_t i_a1,
    input  fixed_t i_a2,
    output fixed_t o_data,
    output wire    o_valid
);
    // Delay elements (only advance on i_valid)
    fixed_t x_z1[BANKS], x_z2[BANKS];
    fixed_t y_z1[BANKS], y_z2[BANKS];

    // Wide accumulator for sum of products (Q??.32)
    logic signed [53:0] p_b0, p_b1, p_b2, p_a1, p_a2;
    logic signed [63:0] acc;
    fixed_t             y_next;

    fixed_t x_z1_sel, x_z2_sel;
    fixed_t y_z1_sel, y_z2_sel;

    always_comb begin
        x_z1_sel = x_z1[i_bank];
        x_z2_sel = x_z2[i_bank];
        y_z1_sel = y_z1[i_bank];
        y_z2_sel = y_z2[i_bank];


        p_b0 = fixed_mul_raw(i_b0, i_data-x_z2_sel);
        p_b1 = fixed_mul_raw(i_b1, x_z1_sel);
        p_b2 = fixed_mul_raw(i_b2, x_z2_sel);
        p_a1 = fixed_mul_raw(i_a1, y_z1_sel);
        p_a2 = fixed_mul_raw(i_a2, y_z2_sel);

        // Sign-extend each 54-bit product to 64 bits before summing.
        acc = {{10{p_b0[53]}}, p_b0}
            + {{10{p_b1[53]}}, p_b1}
            + {{10{p_b2[53]}}, p_b2}
            - {{10{p_a1[53]}}, p_a1}
            - {{10{p_a2[53]}}, p_a2};

        // Convert back to Q11.16 by dropping 16 fractional bits.
        y_next = fixed_t'(acc[16+:27]);
    end

    fixed_t y;
    integer bi;
    always_ff @(posedge clk) begin
        if (rst) begin
            for (bi = 0; bi < BANKS; bi++) begin
                x_z1[bi] <= '0;
                x_z2[bi] <= '0;
                y_z1[bi] <= '0;
                y_z2[bi] <= '0;
            end
            y <= '0;
        end else if (i_valid) begin
            x_z2[i_bank] <= x_z1[i_bank];
            x_z1[i_bank] <= i_data;

            y_z2[i_bank] <= y_z1[i_bank];
            y_z1[i_bank] <= y_next;
            y    <= y_next;
        end
    end

    logic valid;
    always_ff @(posedge clk) begin
        if (rst) valid <= 1'b0;
        else valid <= i_valid;
    end

    assign o_valid = valid;
    assign o_data  = y;
endmodule
