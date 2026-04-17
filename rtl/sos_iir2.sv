`timescale 1ns / 1ps

`include "fixed.sv"

// butterworth SOS 2nd-order IIR (biquad) stage in Direct Form I:
//
// y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
//
//
// Coefficients are fixed-point Q11.16 (fnorm_t). a0 is assumed to be 1.
module sos_iir2 #(
    // When BANKS>1, the delay-line state is banked internally and selected
    // using i_bank. When BANKS==1, i_bank is ignored.
    parameter int BANKS  = 1,
    parameter int BANK_W = (BANKS <= 1) ? 1 : $clog2(BANKS)
) (
    input  wire    clk,
    input  wire    rst,
    input  fnorm_t i_data,
    input  wire    i_valid,
    input  logic [BANK_W-1:0] i_bank,
    input  fnorm_t i_b0,
    input  fnorm_t i_b1,
    input  fnorm_t i_b2,
    input  fnorm_t i_a1,
    input  fnorm_t i_a2,
    output fnorm_t o_data,
    output wire    o_valid
);
    // Delay elements — 32-bit wide, no reset, for BRAM inference.
    logic [31:0] x_z1[BANKS], x_z2[BANKS];
    logic [31:0] y_z1[BANKS], y_z2[BANKS];

    // Stage 0 → Stage 1 pipeline: synchronous BRAM read + input capture
    logic                s1_valid;
    fnorm_t              s1_data;
    logic [BANK_W-1:0]   s1_bank;
    logic [31:0]         x_z1_rd, x_z2_rd, y_z1_rd, y_z2_rd;

    always_ff @(posedge clk) begin
        // Synchronous BRAM reads (always, no reset — BRAM pattern)
        x_z1_rd <= x_z1[i_bank];
        x_z2_rd <= x_z2[i_bank];
        y_z1_rd <= y_z1[i_bank];
        y_z2_rd <= y_z2[i_bank];

        // Pipeline registers
        if (rst)
            s1_valid <= 1'b0;
        else
            s1_valid <= i_valid;
        s1_data <= i_data;
        s1_bank <= i_bank;
    end

    // Stage 1: compute (combinational from registered BRAM data)
    logic signed [53:0] p_b0, p_b1, p_b2, p_a1, p_a2;
    logic signed [63:0] acc;
    fnorm_t             y_next;

    // FIXME: b2 optimization
    always_comb begin
        p_b0 = fnorm_mul_raw(i_b0, s1_data);
        p_b1 = fnorm_mul_raw(i_b1, fnorm_t'(x_z1_rd[26:0]));
        p_b2 = fnorm_mul_raw(i_b2, fnorm_t'(x_z2_rd[26:0]));
        p_a1 = fnorm_mul_raw(i_a1, fnorm_t'(y_z1_rd[26:0]));
        p_a2 = fnorm_mul_raw(i_a2, fnorm_t'(y_z2_rd[26:0]));

        acc = {{10{p_b0[53]}}, p_b0}
            + {{10{p_b1[53]}}, p_b1}
            + {{10{p_b2[53]}}, p_b2}
            - {{10{p_a1[53]}}, p_a1}
            - {{10{p_a2[53]}}, p_a2};

        y_next = fnorm_t'(acc[16+:27]);
    end

    // Stage 1 → output: BRAM write-back + output register
    fnorm_t y;
    always_ff @(posedge clk) begin
        if (s1_valid) begin
            x_z2[s1_bank] <= x_z1_rd;
            x_z1[s1_bank] <= {5'd0, s1_data};
            y_z2[s1_bank] <= y_z1_rd;
            y_z1[s1_bank] <= {5'd0, y_next};
        end

        if (rst)
            y <= '0;
        else if (s1_valid)
            y <= y_next;
    end

    logic valid;
    always_ff @(posedge clk) begin
        if (rst) valid <= 1'b0;
        else valid <= s1_valid;
    end

    assign o_valid = valid;
    assign o_data  = y;
endmodule
