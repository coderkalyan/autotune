`include "fixed.sv"
import global_enums::*;

module compute #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE),
    parameter TESTBENCH = 0
) (
    input wire clk,
    input wire rst,
    input wire adc_en,
    input audio_t i_ldata,
    input audio_t i_rdata,
    input wire i_rxd,
    input fixed_t test_pitch_factor,   // for testing only, will be driven by SW in actual implementation
    output fixed_t o_lf,
    output fixed_t o_rf,
    output logic o_valid,
    output logic [9:0] or_pitch_period,
    output logic or_pitch_valid,
    output logic o_pitch_done,
    output logic o_vad_active,
    output logic o_vad_voiced,
    output mode_t o_mode,
    output logic [9:0] o_target_lag,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5,
    output logic [32*27-1:0] o_vocode_bands_flat
);

  // ----------------------------------------------------------------
  // Internal Signals and logic
  // ----------------------------------------------------------------

  // Input data normalization
  fixed_t lf, rf;
  assign lf = `FIXED_ATOF(i_ldata);
  assign rf = `FIXED_ATOF(i_rdata);

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

  //target frequency outputs
  mode_t mode;
  logic [9:0] target_lag;

  logic [9:0] r_pitch_period;
  logic r_pitch_valid;

  assign or_pitch_period = r_pitch_period;
  assign or_pitch_valid  = r_pitch_valid;


  // ----------------------------------------------------------------
  // Preprocessing
  // ----------------------------------------------------------------
  preprocessing #(
      .CHANNELS(0),  // default: 0 lpf left and right data; 1 lpf left channel only 
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

  // Voice activation detection.
  logic vad_active, vad_voiced;
  vad #(
      // This window size is unrelated to the autocorrelation pipeline.
      .WINDOW_SIZE(480),
      .MAX_PERIODS(12)
  ) vad (
      .clk(clk),
      .rst(rst),
      .i_data(lf),
      .i_valid(adc_en),
      .i_sensitivity(encoders[1]),
      .o_active(vad_active),
      .o_voiced(vad_voiced)
  );

  assign o_vad_active = vad_active;
  assign o_vad_voiced = vad_voiced;

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
      r_pitch_valid  <= 1'b0;
    end else if (o_pitch_done) begin
      r_pitch_period <= pitch_period;
      r_pitch_valid  <= pitch_valid;
    end
  end

  // ----------------------------------------------------------------
  // MIDI Receiver
  // ----------------------------------------------------------------
  wire [127:0] notes;
  wire [  6:0] encoders[0:7];
  midi_receiver midi_receiver0 (
      .clk(clk),
      .rst(rst),
      .i_midi_rx(i_rxd),
      .o_notes(notes),
      .o_encoders(encoders),
      .o_mode(mode)
  );

  assign o_mode = mode;

  wire [6:0] note_number;
  priority_encoder_128 encoder (
      .in(notes),
      .out(note_number),
      .valid()
  );

  // ----------------------------------------------------------------
  // Frequency LUT
  // ----------------------------------------------------------------
  midi_lag_lut lut0 (
      .i_midi(note_number),
      .o_lag (target_lag)
  );

  // ----------------------------------------------------------------
  // Note Selection / Shift ratio
  // ----------------------------------------------------------------
  note_selection iNS (
      .any_note_pressed(|notes),
      .actual_lag(pitch_period),
      .target_lag(target_lag),
      .shift_ratio(pitch_factor_recip),
      .mode(mode),
      .o_target_lag(o_target_lag)
  );

  // ----------------------------------------------------------------
  // PSOLA
  // ----------------------------------------------------------------
  fixed_t eff_pitch_factor;
  assign eff_pitch_factor = TESTBENCH ? test_pitch_factor : pitch_factor_recip;
  fixed_t psola_lf, psola_rf;
  logic psola_valid;
  psola iPSOLA_L (
      .clk(clk),
      .rst(rst),
      .i_lag(r_pitch_period),
      .i_lag_valid(r_pitch_valid & vad_voiced),
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
      .i_lag_valid(r_pitch_valid & vad_voiced),
      .i_advance(eff_pitch_factor),
      .i_data(rf),
      .i_valid(adc_en),
      .o_data(psola_rf),
      .o_valid()
  );

  // ----------------------------------------------------------------
  // Vocoding
  // ----------------------------------------------------------------
  fixed_t vocode_data;
  logic   vocode_valid;
  fnorm_t vocode_bands [32];
  vocoder vocoder (
      .clk(clk),
      .rst(rst),
      .i_valid(adc_en),
      .i_data(lf),
      .i_notes(notes),
      .i_synth_bypass(mode == SYNTH),
      .o_data(vocode_data),
      .o_vocode_bands(vocode_bands),
      .o_valid(vocode_valid)
  );

  // Flatten unpacked array to packed bus for Quartus port compatibility
  genvar gi;
  generate
    for (gi = 0; gi < 32; gi++) begin : gen_flatten
      assign o_vocode_bands_flat[gi*27+:27] = vocode_bands[gi];
    end
  endgenerate


  // ----------------------------------------------------------------
  // Volume/Normalization
  // ----------------------------------------------------------------
  // Volume control via MIDI encoder 0 (logarithmic)
  // gain = volume / 2^VOL_SHIFT; midpoint (64) → gain 1.0, max (127) → ~2.0
  localparam int VOL_SHIFT = 6;
  wire [6:0] volume;
  log_volume_lut iVOL_LUT (
      .i_linear(encoders[0]),
      .o_log(volume)
  );

  fixed_t pre_lf, pre_rf;
  logic pre_valid;

  always_comb begin
    case (mode)
      MUTE: begin
        pre_lf = 0;
        pre_rf = 0;
        pre_valid = adc_en;
      end
      PASSTHROUGH: begin
        pre_lf = lf;
        pre_rf = rf;
        pre_valid = adc_en;
      end
      AUTOTUNE: begin
        pre_lf = psola_lf;
        pre_rf = psola_rf;
        pre_valid = psola_valid;
      end
      VOCODE: begin
        pre_lf = vocode_data;
        pre_rf = vocode_data;
        pre_valid = vocode_valid;
      end
      SYNTH: begin
        pre_lf = vocode_data;
        pre_rf = vocode_data;
        pre_valid = vocode_valid;
      end
      default: begin
        pre_lf = 0;
        pre_rf = 0;
        pre_valid = 0;
      end
    endcase
  end

  fixed_t post_lf, post_rf;
  logic post_valid;

  normalization iNORM1 (
    .clk(clk),
    .rst(rst),
    .i_data(pre_lf),
    .i_mode(mode),
    .i_valid(pre_valid),
    .o_data(post_lf),
    .o_valid(post_valid)
  );

  normalization iNORM2 (
    .clk(clk),
    .rst(rst),
    .i_data(pre_rf),
    .i_mode(mode),
    .i_valid(pre_valid),
    .o_data(post_rf),
    .o_valid()
  );

  fixed_t vol_gain;
  assign vol_gain = fixed_t'({1'b0, volume}) << (16 - VOL_SHIFT);
  // assign o_lf    = fixed_mul(pre_lf, vol_gain);
  // assign o_rf    = fixed_mul(pre_rf, vol_gain);
  // assign o_valid = pre_valid;
  assign o_lf    = fixed_mul(post_lf, vol_gain);
  assign o_rf    = fixed_mul(post_rf, vol_gain);
  assign o_valid = post_valid;
  

  // ----------------------------------------------------------------
  // Display Control
  // ----------------------------------------------------------------
  hex_display iHEX (
      .pitch_period(r_pitch_period),
      .target_lag(target_lag),
      .mode(mode),
      .i_encoders(encoders),
      .HEX0(HEX0),
      .HEX1(HEX1),
      .HEX2(HEX2),
      .HEX3(HEX3),
      .HEX4(HEX4),
      .HEX5(HEX5)
  );

endmodule
