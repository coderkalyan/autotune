`timescale 1ns / 1ps

`include "fixed.sv"
// `default_nettype none

module asym_follow #(
    parameter int BANKS = 1,
    parameter int BANK_W = (BANKS <= 1) ? 1 : $clog2(BANKS),
    parameter int ATTACK_MS = 3,
    parameter int RELEASE_MS = 100
) (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    input  logic [BANK_W-1:0] i_bank,
    output fixed_t o_data,
    output wire    o_valid
);
    // Pre-computed for ATTACK_MS=3, RELEASE_MS=100, FS=48000 Hz:
    //   ALPHA_ATTACK  = 1 - exp(-1 / (ATTACK_MS  * 1e-3 * 48000)) = 0.006920387509683934
    //   ALPHA_RELEASE = 1 - exp(-1 / (RELEASE_MS * 1e-3 * 48000)) = 0.0002083116334513635
    localparam fixed_t FONE           = 27'h0010000;  // 1.0 in Q11.16
    localparam fixed_t FALPHA_ATTACK  = 27'h00001c6;  // ~0.00693 in Q11.16
    localparam fixed_t FALPHA_RELEASE = 27'h000000e;  // ~0.000214 in Q11.16

    /*
    Causal asymmetric envelope follower.
 
    Uses a fast alpha on rising edges (attack) and a slow alpha on falling
    edges (release). Input x should already be rectified (abs of band signal).
 
      alpha = 1 - exp(-1 / (t_ms * 1e-3 * fs))   [exact bilinear form]
 
    This is the same single-pole IIR as an RC lowpass, but the coefficient
    switches each sample depending on whether the signal is rising or falling.
    */
    /*
            ┌─ α_attack   if x[n] > y[n-1]    (envelope is rising)
    α[n] = ─┤
            └─ α_release  if x[n] ≤ y[n-1]   (envelope is falling)

    y[n] = α[n] * x[n] + (1 - α[n]) * y[n-1] 

    */
  // 32-bit wide, no reset — BRAM inference.
  logic [31:0] y_state[BANKS];

  // Stage 0 → Stage 1: synchronous BRAM read + input capture
  logic              s1_valid;
  fixed_t            s1_data;
  logic [BANK_W-1:0] s1_bank;
  logic [31:0]       y_state_rd;

  always_ff @(posedge clk) begin
    y_state_rd <= y_state[i_bank];

    if (rst)
      s1_valid <= 1'b0;
    else
      s1_valid <= i_valid;
    s1_data <= i_data;
    s1_bank <= i_bank;
  end

  // Stage 1: compute (combinational from registered BRAM data)
  fixed_t y_sel;
  fixed_t alpha;
  logic signed [53:0] x;
  fixed_t y_next;

  always_comb begin
    y_sel  = fixed_t'(y_state_rd[26:0]);
    alpha  = (s1_data > y_sel) ? FALPHA_ATTACK : FALPHA_RELEASE;
    x      = fixed_mul_raw(alpha, s1_data) + fixed_mul_raw(FONE - alpha, y_sel);
    y_next = fixed_t'(x[16+:27]);
  end

  // Stage 1 → output: BRAM write-back + output register
  fixed_t y_out;
  always_ff @(posedge clk) begin
    if (s1_valid)
      y_state[s1_bank] <= {5'd0, y_next};

    if (rst)
      y_out <= '0;
    else if (s1_valid)
      y_out <= y_next;
  end

  logic valid;
  always_ff @(posedge clk) begin
    if (rst) valid <= 1'b0;
    else valid <= s1_valid;
  end

  assign o_valid = valid;
  assign o_data  = y_out;
endmodule
