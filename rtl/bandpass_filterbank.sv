`timescale 1ns / 1ps

`include "fixed.sv"

// Time-multiplexed bandpass filterbank.
//
// BANKS  = number of coefficient sets / independent filters.
//
// On each input sample strobe (i_valid), the module latches i_data and then
// spends BANKS clock cycles updating all BANKS filters for that
// sample. When finished, it pulses o_valid for 1 cycle.
//
// Coefficients are specified as pre-computed Q11.16 fixed_t parameter tables.
// Use py/gen_bandpass_coeffs.py to convert from floating-point.
module bandpass_filterbank #(
    parameter int BANKS = 1,
    parameter int BBITS = $clog2(BANKS)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  fnorm_t               i_data,
    input  wire                  i_valid,
    input  wire                  i_asym_follow,
    input  wire    [BBITS - 1:0] i_bank_start,
    input  wire    [BBITS - 1:0] i_bank_end,
    output fixed_t               o_data       [BANKS],
    output wire                  o_valid
);
  // Coefficient ROMs.
  logic [31:0] B0[BANKS], B1[BANKS], A1[BANKS], A2[BANKS];
  logic [31:0] C0[BANKS], C1[BANKS], D1[BANKS], D2[BANKS];
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

  // ----------------------------------------------------------------
  // Single-bank bandpass filter (time-multiplexing TBD for BANKS > 1).
  //
  // x history: x[n-1] .. x[n-5]  (5 registers).
  // y history: y[n-1], y[n-2] per stage (2 registers x 2 stages).
  // Current sample x[n] is the live input i_data.
  // ----------------------------------------------------------------
  fnorm_t x1_r, x2_r, x3_r, x4_r, x5_r;
  fnorm_t s0_y1_r, s0_y2_r, s1_y1_r, s1_y2_r;

  // Coefficient selects for bank 0.
  fnorm_t i_s0_b0, i_s0_b1, i_s0_a1, i_s0_a2;
  fnorm_t i_s1_b0, i_s1_b1, i_s1_a1, i_s1_a2;
  always_comb begin
    i_s0_b0 = fnorm_t'(B0[0][26:0]);
    i_s0_b1 = fnorm_t'(B1[0][26:0]);
    i_s0_a1 = fnorm_t'(A1[0][26:0]);
    i_s0_a2 = fnorm_t'(A2[0][26:0]);
    i_s1_b0 = fnorm_t'(C0[0][26:0]);
    i_s1_b1 = fnorm_t'(C1[0][26:0]);
    i_s1_a1 = fnorm_t'(D1[0][26:0]);
    i_s1_a2 = fnorm_t'(D2[0][26:0]);
  end

  fnorm_t o_s0_data, o_s1_data;
  bandpass_biquad u_biquad (
      .i_x0    (i_data),
      .i_x1    (x1_r),
      .i_x2    (x2_r),
      .i_x3    (x3_r),
      .i_x4    (x4_r),
      .i_x5    (x5_r),
      .i_s0_y1 (s0_y1_r),
      .i_s0_y2 (s0_y2_r),
      .i_s1_y1 (s1_y1_r),
      .i_s1_y2 (s1_y2_r),
      .i_s0_b0 (i_s0_b0),
      .i_s0_b1 (i_s0_b1),
      .i_s0_a1 (i_s0_a1),
      .i_s0_a2 (i_s0_a2),
      .i_s1_b0 (i_s1_b0),
      .i_s1_b1 (i_s1_b1),
      .i_s1_a1 (i_s1_a1),
      .i_s1_a2 (i_s1_a2),
      .o_s0_data(o_s0_data),
      .o_s1_data(o_s1_data)
  );

  // ----------------------------------------------------------------
  // History shift + output register. Output y[n] is combinationally
  // computed this cycle using prior state; we register it and pulse
  // o_valid one cycle after i_valid.
  // ----------------------------------------------------------------
  fnorm_t o_data_r;
  logic   o_valid_r;

  always_ff @(posedge clk) begin
    if (rst) begin
      x1_r <= '0;
      x2_r <= '0;
      x3_r <= '0;
      x4_r <= '0;
      x5_r <= '0;
      s0_y1_r <= '0;
      s0_y2_r <= '0;
      s1_y1_r <= '0;
      s1_y2_r <= '0;
      o_data_r <= '0;
      o_valid_r <= 1'b0;
    end else begin
      o_valid_r <= i_valid;
      if (i_valid) begin
        // Shift x history: x[n-5] <- x[n-4] <- ... <- x[n-1] <- x[n].
        x5_r <= x4_r;
        x4_r <= x3_r;
        x3_r <= x2_r;
        x2_r <= x1_r;
        x1_r <= i_data;

        // Shift y history per stage.
        s0_y2_r <= s0_y1_r;
        s0_y1_r <= o_s0_data;
        s1_y2_r <= s1_y1_r;
        s1_y1_r <= o_s1_data;

        // Register final-stage output.
        o_data_r <= o_s1_data;
      end
    end
  end

  assign o_valid    = o_valid_r;
  assign o_data[0]  = fixed_t'(o_data_r);
endmodule
