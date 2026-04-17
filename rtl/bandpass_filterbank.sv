`timescale 1ns / 1ps

`include "fixed.sv"

// Time-multiplexed bandpass filterbank.
//
// BANKS      = number of independent filter state banks.
// COEF_BANKS = number of coefficient sets available in ROM. Must be <= BANKS.
//              When BANKS > COEF_BANKS, the low $clog2(COEF_BANKS) bits of the
//              bank index select the coefficient set (so bank N and bank
//              N+COEF_BANKS share coefficients but have independent state).
//              This lets the vocoder share the same coef ROMs for voice and
//              carrier paths while keeping their histories separate.
//
// On each i_valid pulse the module processes banks in [i_bank_start,
// i_bank_end] one per clock, then pulses o_valid for one cycle.
// Coefficients per stage: b0, b1, a1, a2 (b2 == b0 for butter bandpass, so
// biquad_stage computes b0*(x0+x2) + b1*x1 - a1*y1 - a2*y2).
module bandpass_filterbank #(
    parameter int BANKS      = 32,
    parameter int COEF_BANKS = BANKS,
    parameter int BBITS      = $clog2(BANKS),
    parameter int CBITS      = $clog2(COEF_BANKS)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  fixed_t               i_data,
    input  wire                  i_valid,
    input  wire                  i_asym_follow,
    input  wire    [BBITS - 1:0] i_bank_start,
    input  wire    [BBITS - 1:0] i_bank_end,
    output fnorm_t               o_data       [BANKS],
    output wire                  o_valid
);
    // Port interface matches the legacy bandpass_sosfilt_bank (fixed_t in,
    // fnorm_t out); internal math is Q3.24. Reinterpret i_data bits as
    // fnorm_t — scale is not compensated, this path is used only to test the
    // filter + UART plumbing, not real audio amplitude.
    fnorm_t i_data_f;
    assign i_data_f = fnorm_t'(i_data);

    // Coefficient ROMs (one entry per coef bank).
    logic [31:0] B0 [COEF_BANKS], B1 [COEF_BANKS], A1 [COEF_BANKS], A2 [COEF_BANKS];
    logic [31:0] C0 [COEF_BANKS], C1 [COEF_BANKS], D1 [COEF_BANKS], D2 [COEF_BANKS];
    initial begin
        $readmemh("vocoder_bp_s0_b0.mem", B0);
        $readmemh("vocoder_bp_s0_b1.mem", B1);
        $readmemh("vocoder_bp_s0_a1.mem", A1);
        $readmemh("vocoder_bp_s0_a2.mem", A2);
        $readmemh("vocoder_bp_s1_b0.mem", C0);
        $readmemh("vocoder_bp_s1_b1.mem", C1);
        $readmemh("vocoder_bp_s1_a1.mem", D1);
        $readmemh("vocoder_bp_s1_a2.mem", D2);
    end

    // ------------------------------------------------------------------
    // Per-bank state
    // ------------------------------------------------------------------
    fnorm_t x1_r    [BANKS];
    fnorm_t x2_r    [BANKS];
    fnorm_t s0_y1_r [BANKS];
    fnorm_t s0_y2_r [BANKS];
    fnorm_t s1_y1_r [BANKS];
    fnorm_t s1_y2_r [BANKS];
    fnorm_t o_data_r[BANKS];

    // ------------------------------------------------------------------
    // Time-mux controller
    // ------------------------------------------------------------------
    logic                busy;
    logic [BBITS - 1:0]  bank_cnt;
    logic [BBITS - 1:0]  end_reg;
    fnorm_t              x_latched;
    logic                o_valid_r;

    wire [CBITS - 1:0] coef_idx = bank_cnt[CBITS - 1:0];

    // Coefficient muxes for this bank.
    fnorm_t i_s0_b0, i_s0_b1, i_s0_a1, i_s0_a2;
    fnorm_t i_s1_b0, i_s1_b1, i_s1_a1, i_s1_a2;
    assign i_s0_b0 = fnorm_t'(B0[coef_idx][26:0]);
    assign i_s0_b1 = fnorm_t'(B1[coef_idx][26:0]);
    assign i_s0_a1 = fnorm_t'(A1[coef_idx][26:0]);
    assign i_s0_a2 = fnorm_t'(A2[coef_idx][26:0]);
    assign i_s1_b0 = fnorm_t'(C0[coef_idx][26:0]);
    assign i_s1_b1 = fnorm_t'(C1[coef_idx][26:0]);
    assign i_s1_a1 = fnorm_t'(D1[coef_idx][26:0]);
    assign i_s1_a2 = fnorm_t'(D2[coef_idx][26:0]);

    // Current-bank state reads (array-indexed into module port).
    fnorm_t cur_x1, cur_x2;
    fnorm_t cur_s0_y1, cur_s0_y2, cur_s1_y1, cur_s1_y2;
    assign cur_x1    = x1_r[bank_cnt];
    assign cur_x2    = x2_r[bank_cnt];
    assign cur_s0_y1 = s0_y1_r[bank_cnt];
    assign cur_s0_y2 = s0_y2_r[bank_cnt];
    assign cur_s1_y1 = s1_y1_r[bank_cnt];
    assign cur_s1_y2 = s1_y2_r[bank_cnt];

    fnorm_t o_s0_data, o_s1_data;
    bandpass_biquad u_biquad (
        .i_x0     (x_latched),
        .i_x1     (cur_x1),
        .i_x2     (cur_x2),
        .i_x3     ('0),
        .i_x4     ('0),
        .i_x5     ('0),
        .i_s0_y1  (cur_s0_y1),
        .i_s0_y2  (cur_s0_y2),
        .i_s1_y1  (cur_s1_y1),
        .i_s1_y2  (cur_s1_y2),
        .i_s0_b0  (i_s0_b0),
        .i_s0_b1  (i_s0_b1),
        .i_s0_a1  (i_s0_a1),
        .i_s0_a2  (i_s0_a2),
        .i_s1_b0  (i_s1_b0),
        .i_s1_b1  (i_s1_b1),
        .i_s1_a1  (i_s1_a1),
        .i_s1_a2  (i_s1_a2),
        .o_s0_data(o_s0_data),
        .o_s1_data(o_s1_data)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            busy      <= 1'b0;
            bank_cnt  <= '0;
            end_reg   <= '0;
            x_latched <= '0;
            o_valid_r <= 1'b0;
            for (int i = 0; i < BANKS; i++) begin
                x1_r[i]     <= '0;
                x2_r[i]     <= '0;
                s0_y1_r[i]  <= '0;
                s0_y2_r[i]  <= '0;
                s1_y1_r[i]  <= '0;
                s1_y2_r[i]  <= '0;
                o_data_r[i] <= '0;
            end
        end else begin
            o_valid_r <= 1'b0;

            if (!busy && i_valid) begin
                x_latched <= i_data_f;
                bank_cnt  <= i_bank_start;
                end_reg   <= i_bank_end;
                busy      <= 1'b1;
            end else if (busy) begin
                // Advance state for the current bank.
                x1_r[bank_cnt]     <= x_latched;
                x2_r[bank_cnt]     <= cur_x1;
                s0_y1_r[bank_cnt]  <= o_s0_data;
                s0_y2_r[bank_cnt]  <= cur_s0_y1;
                s1_y1_r[bank_cnt]  <= o_s1_data;
                s1_y2_r[bank_cnt]  <= cur_s1_y1;
                o_data_r[bank_cnt] <= o_s1_data;

                if (bank_cnt == end_reg) begin
                    busy      <= 1'b0;
                    o_valid_r <= 1'b1;
                end else begin
                    bank_cnt <= bank_cnt + 1'b1;
                end
            end
        end
    end

    assign o_valid = o_valid_r;

    genvar bk;
    generate
        for (bk = 0; bk < BANKS; bk++) begin : gen_outputs
            assign o_data[bk] = o_data_r[bk];
        end
    endgenerate
endmodule
