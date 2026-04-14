`include "fixed.sv"
import global_enums::*;

module compute #(
    parameter WINDOW_SIZE = 1024,
    parameter WBITS = $clog2(WINDOW_SIZE),
    parameter TESTBENCH = 0
) (
    input clk,
    input rst,
    input adc_en,
    input audio_t i_ldata,
    input audio_t i_rdata,
    input i_rxd,
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
      .actual_lag(pitch_period),
      .target_lag(target_lag),
      .shift_ratio(pitch_factor_recip),
      .mode(mode)
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

  fixed_t vocode_data;
  logic   vocode_valid;
  vocoder vocoder (
      .clk(clk),
      .rst(rst),
      .i_valid(adc_en),
      .i_notes(notes),
      .o_data(vocode_data),
      .o_raw(),
      .o_valid(vocode_valid)
  );

  always_comb begin
    case (mode)
      MUTE: begin
        // Mute output but clock DAC with ADC clock.
        o_lf = 0;
        o_rf = 0;
        o_valid = adc_en;
      end
      PASSTHROUGH: begin
        o_lf = lf;
        o_rf = rf;
        o_valid = adc_en;
      end
      AUTOTUNE: begin
        o_lf = psola_lf;
        o_rf = psola_rf;
        o_valid = psola_valid;
      end
      VOCODE: begin
        o_lf = vocode_data;
        o_rf = vocode_data;
        o_valid = vocode_valid;
      end
      default: begin
        // Should not reach this case, mute output and don't clock DAC.
        o_lf = 0;
        o_rf = 0;
        o_valid = 0;
      end
    endcase
  end

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
