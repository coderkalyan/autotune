`include "fixed.sv"
import global_enums::*;

/*
Streaming RMS normalization.

power[n] = power[n-1] - (power[n-1] >> K) + (x_scaled[n]^2 >> K)
   where x_scaled = i_data >>> 4  (prevents squaring overflow in Q11.16)

rms_q = sqrt(power_raw)  =>  rms_Q11 = rms_q << 12  (back to Q11.16 RMS of i_data)

gain = TARGET / rms_Q11   (sequential div, 2-cycle latency)
o_data = gain * i_data    (registered output)

Sequential IPs (sqrt_seq + div_seq) replace the old combinational sqrt and
the single-cycle (sqrt + reg) + comb div pipeline. To preserve numerical
equivalence per sample, i_data is delayed by 3 cycles to keep the same
gain-vs-data pairing as the original design.

Latency (autotune mode): 6 cycles input -> output (was 3). Bypass mode
unchanged (1 cycle).
*/

module normalization #(
    parameter SIM = 0
)(
    input  clk,
    input  rst,
    input  fixed_t i_data,
    input  mode_t  i_mode,
    input          i_valid,
    output fixed_t o_data,
    output logic   o_valid
);

localparam int     K       = 8;
localparam fixed_t TARGET  = `FIXED_RTOF(91.0);
localparam fixed_t MIN_RMS = 27'h40_0000; // 64.0 in Q11.16 — caps max gain at TARGET/MIN_RMS ≈ 1.42

// Squaring Logic
fixed_t x_scaled, x_sq;
assign x_scaled = i_data >>> 4;
assign x_sq     = fixed_mul(x_scaled, x_scaled);

// Mode reset and power calculation
logic signed [28:0] power;
mode_t mode_prev;
always_ff @(posedge clk) begin
    if (rst) begin
        power     <= '0;
        mode_prev <= i_mode;
    end else begin
        mode_prev <= i_mode;
        if (i_mode != mode_prev)
            power <= '0;
        else if (i_valid)
            power <= power - (power >>> K) + (29'(signed'(x_sq)) >>> K);
    end
end

// sqrt and div logic
logic [26:0] sqrt_radical;
logic [13:0] rms_q;        // sqrt_seq output (2-cycle latency from radical)
fixed_t      rms_Q11, rms_guarded, gain;
logic [42:0] gain_raw;

assign sqrt_radical = power[26:0];
assign rms_Q11      = fixed_t'(27'(rms_q) <<< 12);
assign rms_guarded  = (rms_Q11 < MIN_RMS) ? MIN_RMS : rms_Q11; //clamp so there is overflow protection

generate
    if (SIM) begin : g_sim
        // Mirror sqrt_seq's 2-cycle pipeline + div_seq's 2-cycle pipeline
        // so simulation latency matches synthesis exactly.
        logic [13:0] sqrt_q_comb;
        logic [13:0] sqrt_q_d1;
        always_comb sqrt_q_comb = 14'($sqrt(real'(sqrt_radical)));
        always_ff @(posedge clk) begin
            sqrt_q_d1 <= sqrt_q_comb;
            rms_q     <= sqrt_q_d1;
        end

        fixed_t gain_comb;
        fixed_t gain_d1;
        always_comb gain_comb = fixed_t'(real'({TARGET, 16'd0}) / real'(rms_guarded));
        always_ff @(posedge clk) begin
            gain_d1 <= gain_comb;
            gain    <= gain_d1;
        end
        assign gain_raw = '0;  // unused in sim
    end else begin : g_synth
        sqrt_seq iSQRT (
            .clk    (clk),
            .radical(sqrt_radical),
            .q      (rms_q),
            .remainder()
        );

        div_seq iDIV (
            .clock   (clk),
            .numer   ({TARGET, 16'd0}),
            .denom   (rms_guarded),
            .quotient(gain_raw),
            .remain  ()
        );
        assign gain = fixed_t'(gain_raw[26:0]);
    end
endgenerate

// i_data delay chain: 3 cycles to align with the +3-cycle latency added by
// going from (comb sqrt + 1 reg) + (comb div) to (sqrt_seq=2) + (div_seq=2).
// Keeps gain*i_data pairing numerically equivalent to original design.
fixed_t i_data_d1, i_data_d2, i_data_d3;
always_ff @(posedge clk) begin
    i_data_d1 <= i_data;
    i_data_d2 <= i_data_d1;
    i_data_d3 <= i_data_d2;
end

// Valid pipeline. Old design: o_valid = registered valid_d2 (i_valid delayed
// 3 cycles total). New design: 3 extra cycles of latency, so delay 6 total
// (5 stages of d-flops + the final output reg).
logic valid_d1, valid_d2, valid_d3, valid_d4, valid_d5;
always_ff @(posedge clk) begin
    if (rst) begin
        valid_d1 <= 1'b0;
        valid_d2 <= 1'b0;
        valid_d3 <= 1'b0;
        valid_d4 <= 1'b0;
        valid_d5 <= 1'b0;
        o_data   <= '0;
        o_valid  <= 1'b0;
    end else begin
        valid_d1 <= i_valid;
        valid_d2 <= valid_d1;
        valid_d3 <= valid_d2;
        valid_d4 <= valid_d3;
        valid_d5 <= valid_d4;
        // Bypass (VOCODE) preserves original 1-cycle latency. Autotune path
        // multiplies the now-2-cycle-latency `gain` by the 3-cycle-delayed
        // `i_data_d3`, so the per-sample (gain, data) pairing is identical
        // to the old (gain, data) pairing — just emitted 3 cycles later.
        o_data   <= (i_mode == VOCODE) ? i_data  : fixed_mul(gain, i_data_d3);
        o_valid  <= (i_mode == VOCODE) ? i_valid : valid_d5;
    end
end

endmodule
