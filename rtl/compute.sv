`include "fixed.sv"

module compute #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE),
    parameter TESTBENCH = 0
) (
    input clk,
    input rst,
    input adc_en,
    input audio_t ldata,
    input audio_t rdata,
    input i_rxd,
    input fixed_t test_pitch_factor,   // for testing only, will be driven by SW in actual implementation
    output fixed_t psola_lf,
    output fixed_t psola_rf,
    output logic psola_valid,
    output logic [9:0] or_pitch_period,
    output logic or_pitch_valid,
    output logic o_pitch_done,
    output [6:0] HEX0,
    output [6:0] HEX1,
    output [6:0] HEX2,
    output [6:0] HEX3,
    output [6:0] HEX4,
    output [6:0] HEX5
);

// ----------------------------------------------------------------
// Internal Signals and logic
// ----------------------------------------------------------------

// Input data normalization
fixed_t lf, rf;
assign lf = `FIXED_ATOF(ldata);
assign rf = `FIXED_ATOF(rdata);

// Autocorrelation output 
logic [WBITS-1:0] pitch_period;
logic pitch_valid;

// LPF outputs (left and right channels)
fixed_t lpf_lf;
fixed_t lpf_rf;
logic lpf_done;

// Reciprocal of the pitch factor
fixed_t pitch_factor_recip;

// PSOLA output 
fixed_t psola_lf_real;
fixed_t psola_rf_real;

logic [9:0] r_pitch_period;
logic r_pitch_valid;

assign or_pitch_period = r_pitch_period;
assign or_pitch_valid = r_pitch_valid;


// ----------------------------------------------------------------
// Preprocessing
// ----------------------------------------------------------------
preprocessing #(
    .CHANNELS(0),    // default: 0 lpf left and right data; 1 lpf left channel only 
    .L_FC(10000),
    .R_FC(400)
) iPP (
    .clk(clk),
    .rst(rst),
    .i_lf(lf),
    .i_rf(rf),
    .i_en(adc_en),
    .o_lpf_lf(lpf_lf),
    .o_lpf_rf(lpf_rf),
    .o_lpf_valid(lpf_done)
);

// ----------------------------------------------------------------
// Pitch Detection
// ----------------------------------------------------------------
pitch_detection #(
    .WINDOW_SIZE(WINDOW_SIZE),
    .STAMPS(32)
) iPD (
    .clk(clk),
    .rst(rst),
    .i_wr_en(lpf_done),
    .i_proc_data(lpf_lf),
    .o_period(pitch_period),
    .o_valid(pitch_valid),
    .o_done(o_pitch_done)
);
always_ff @(posedge clk) begin
    if (rst) begin
        r_pitch_period <= '0;
        r_pitch_valid <= 1'b0;
    end else if (o_pitch_done) begin
        r_pitch_period <= pitch_period;
        r_pitch_valid <= pitch_valid;
    end
end

// ----------------------------------------------------------------
// Target Frequency 
// ----------------------------------------------------------------
target_freq #( 
    .WINDOW_SIZE(WINDOW_SIZE)
) iTF (
    .clk(clk),
    .rst(rst),
    .i_rxd(i_rxd),
    .i_period(pitch_period),
    .o_shift_ratio(pitch_factor_recip)
);


// ----------------------------------------------------------------
// PSOLA
// ----------------------------------------------------------------

fixed_t eff_pitch_factor;
assign eff_pitch_factor = TESTBENCH ? test_pitch_factor : pitch_factor_recip;
psola iPSOLA_L ( 
    .clk(clk),
    .rst(rst),
    .i_lag(r_pitch_period),
    .i_advance(eff_pitch_factor),
    .i_data(lf),
    .i_valid(adc_en),
    .o_data(psola_lf),
    .o_valid(psola_valid)
);

psola iPSOLA_R ( 
    .clk(clk),
    .rst(rst),
    .i_lag(r_pitch_period),
    .i_advance(eff_pitch_factor),
    .i_data(rf),
    .i_valid(adc_en),
    .o_data(psola_rf),
    .o_valid()
);


// ----------------------------------------------------------------
// Display Control
// ----------------------------------------------------------------
hex_display iHEX (
    .pitch_period(r_pitch_period),
    .HEX0(HEX0),
    .HEX1(HEX1),
    .HEX2(HEX2),
    .HEX3(HEX3),
    .HEX4(HEX4),
    .HEX5(HEX5)
);

endmodule