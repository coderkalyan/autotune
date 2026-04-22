`include "fixed.sv"
import global_enums::*;

module normalization #(
    parameter SIM = 0
)(
    input clk,
    input rst,
    input fixed_t i_data,
    input mode_t i_mode,
    input logic i_valid,
    output fixed_t o_data,
    output logic o_valid
);

// TODO: mode is currently not working, change so that everything resets when mode changes

/*
Calculate the RMS of the incoming signal

alpha = sets the time constant (how fast the RMS responds to level changes)
      = in (0,1)
      = since alpha is small, express as a right shift k 

k = log2(1/alpha)

power[n] = power[n-1] - (power[n-1] >> k) + (x[n]^2 >> k)

RMS[n] = sqrt( power[n] )

gain = target / RMS[n]

y[n] = gain * x[n]

*/

localparam K = 12; //gives a constant time of ~4096 samples (85ms)
//localparam fixed_t target = 27'h40_0000; //~18% of full scale sine RMS
localparam fixed_t target = 27'h5B_2800; 
//localparam fixed_t target = 27'hB5_B000; 
localparam MIN_RMS = 27'h40_0000; // small but non-zero Q11.16 value; overflow protection

// Module signals 
logic signed [28:0] y;
logic signed [28:0] y_prev;
fixed_t x_2;
logic [13:0] rms;
fixed_t gain;

// Square root Logic
always_ff @(posedge clk) begin 
    if (rst) 
        x_2 <= '0;
    else if (i_valid)
        x_2 <= fixed_mul(i_data, i_data);
end

// State Logic 
always_ff @(posedge clk) begin 
    if (rst)
        y_prev <= '0;
    else if (i_valid)
        y_prev <= y;
end

// Averaging Logic
logic signed [28:0] y_eff;
logic signed [28:0] x_eff;
assign y_eff = (y_prev >> K);
assign x_eff = (x_2 >> K);
assign y = y_prev - y_eff + x_eff;

generate
    if (SIM) begin
        real rms_guarded;
        always_comb begin
            rms  = $sqrt(real'(y) / 2.0**16) * 2.0**7;  // compute sqrt, convert Q11.16 input to real, result back to Q6.7
            rms_guarded = (real'(rms << 9) / 2.0**16 < real'(target) / 2.0**16) ?
                          (real'(target) / 2.0**16) :
                          (real'(rms << 9) / 2.0**16);
            gain = ((real'(target) / 2.0**16) / rms_guarded) * 2.0**16;
        end
    end else begin
        // RMS Logic
        sqrt irsm(
            .radical(y),
            .q(rms),
            .remainder()
        );

        // Gain Logic 
        div_2 idiv(
            .denom((rms << 9) < MIN_RMS ? MIN_RMS : (rms << 9)), // convert rms result Q6.7 to Q11.16
            .numer({target, 16'd0}),
            .quotient(gain),
            .remain()
        );
    end
endgenerate

// `ifdef SIM
//         real rms_guarded;
//         always_comb begin
//             rms  = $sqrt(real'(y) / 2.0**16) * 2.0**7;  // compute sqrt, convert Q11.16 input to real, result back to Q6.7
//             rms_guarded = (real'(rms << 9) / 2.0**16 < real'(MIN_RMS) / 2.0**16) ?
//                           (real'(MIN_RMS) / 2.0**16) :
//                           (real'(rms << 9) / 2.0**16);
//             gain = ((real'(target) / 2.0**16) / rms_guarded) * 2.0**16;
//         end
// `else
//         // RMS Logic
//         sqrt irsm(
//             .radical(y),
//             .q(rms),
//             .remainder()
//         );

//         // Gain Logic 
//         div_2 idiv(
//             .denom((rms << 9) < MIN_RMS ? MIN_RMS : (rms << 9)), // convert rms result Q6.7 to Q11.16
//             .numer({target, 16'd0}),
//             .quotient(gain),
//             .remain()
//         );
// `endif

// Output logic 
assign o_data = fixed_mul(gain, i_data);

logic valid_r, valid_r2;
always_ff @(posedge clk) begin 
    if (rst) begin
        valid_r <= 0;
        valid_r2 <= 0;
        o_valid <= 0;
    end else begin 
        valid_r <= i_valid;
        valid_r2 <= valid_r;
        o_valid <= valid_r2;
    end
end

endmodule