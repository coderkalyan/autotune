`include "fixed.sv"
import global_enums::*;

/*
Streaming RMS normalization.

power[n] = power[n-1] - (power[n-1] >> K) + (x_scaled[n]^2 >> K)
   where x_scaled = i_data >>> 4  (prevents squaring overflow in Q11.16)

rms_q = sqrt(power_raw)  =>  rms_Q11 = rms_q << 12  (back to Q11.16 RMS of i_data)

gain = TARGET / rms_Q11   (combinational div, updates every cycle)
o_data = gain * i_data    (registered output)

Latency: 1 cycle (registered output).
*/

module normalization_2 #(
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
logic [13:0] rms_q;
logic [13:0] rms_qr;
fixed_t      rms_Q11, rms_guarded, gain;
logic [42:0] gain_raw;

assign sqrt_radical = power[26:0];
assign rms_Q11      = fixed_t'(27'(rms_qr) <<< 12);
assign rms_guarded  = (rms_Q11 < MIN_RMS) ? MIN_RMS : rms_Q11; //clamp so there is overflow protection

generate
    if (SIM) begin : g_sim
        always_comb rms_q = 14'($sqrt(real'(sqrt_radical)));
        always_comb gain  = fixed_t'(real'({TARGET, 16'd0}) / real'(rms_guarded));
    end else begin : g_synth
        sqrt iSQRT (
            .radical(sqrt_radical),
            .q(rms_q),
            .remainder()
        );

        always_ff @(posedge clk) begin
            if (rst)
                rms_qr <= '0;
            else
                rms_qr <= rms_q;
        end

        div_2 iDIV (
            .numer({TARGET, 16'd0}),
            .denom(rms_guarded),
            .quotient(gain_raw),
            .remain()
        );
        assign gain = fixed_t'(gain_raw[26:0]);
    end
endgenerate

// Output pipeline
// Pipeline depth from i_valid to o_data fully reflecting the new sample:
//   power reg (1) -> rms_qr reg (2) -> o_data reg (3) = 3 cycles
// Delay i_valid by 3 cycles so o_valid aligns with o_data.
logic valid_d1, valid_d2;
always_ff @(posedge clk) begin
    if (rst) begin
        valid_d1 <= '0;
        valid_d2 <= '0;
        o_data   <= '0;
        o_valid  <= '0;
    end else begin
        valid_d1 <= i_valid;
        valid_d2 <= valid_d1;
        o_data   <= (i_mode == VOCODE) ? i_data   : fixed_mul(gain, i_data);
        o_valid  <= (i_mode == VOCODE) ? i_valid  : valid_d2;
    end
end

endmodule
