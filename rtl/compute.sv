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
    input logic i_btn,
    output logic [6:0] HEX0,
    output logic [6:0] HEX1,
    output logic [6:0] HEX2,
    output logic [6:0] HEX3,
    output logic [6:0] HEX4,
    output logic [6:0] HEX5,
    output logic [32*27-1:0] o_vocode_bands_flat,
    // Harmony / key telemetry
    output logic [6:0] o_melody_midi,
    output logic [6:0] o_held_midi,
    output logic       o_any_note_pressed,
    output logic [3:0] o_harm_tonic,
    output logic       o_harm_mode,
    output logic [2:0] o_chord_state,
    output logic       o_in_scale,
    output logic [6:0] o_harm1_midi,
    output logic [6:0] o_harm2_midi,
    output fixed_t     o_pitch_factor_recip
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

  // Reciprocal of the pitch factor. Registered output of note_selection
  // (splits the two cascaded 27x27 mults on the o_notes -> output_counter
  // critical path). MIDI updates at kHz, so 1-cycle latency is inaudible.
  fixed_t pitch_factor_recip_w;
  fixed_t pitch_factor_recip;
  always_ff @(posedge clk) pitch_factor_recip <= pitch_factor_recip_w;
  assign o_pitch_factor_recip = pitch_factor_recip;

  // PSOLA output 
  fixed_t psola_lf_real;
  fixed_t psola_rf_real;

  //target frequency outputs
  mode_t mode;
  logic [9:0] target_lag;

  logic [9:0] r_pitch_period;
  logic r_pitch_valid;

  assign or_pitch_period = r_pitch_period;
  assign or_pitch_valid = r_pitch_valid;


  // ----------------------------------------------------------------
  // Preprocessing
  // ----------------------------------------------------------------
  // preprocessing disabled — pass through
  assign lpf_lf = lf;
  assign lpf_rf = rf;
  assign lpf_done = adc_en;

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
      .STAMPS(16)
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
      .shift_ratio(pitch_factor_recip_w),
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
  // Vocal stacking — Markov harmony generator + two harmony PSOLA voices
  // ----------------------------------------------------------------
  // melody_midi: held key if any pressed, else nearest MIDI from detected lag.
  // The held-key branch mirrors note_selection's `any_note_pressed` gate. The
  // detected branch rides on `pitch_period`, which is already hysteresis-stable
  // inside pitch_detection, so a downstream change-detect doesn't chatter.
  wire [6:0] detected_midi;
  lag_to_midi_lut iL2M (
      .i_lag (pitch_period),
      .o_midi(detected_midi)
  );

  wire [6:0] melody_midi;
  assign melody_midi = (|notes) ? note_number : detected_midi;

  // Encoder 2 picks the harmony key:
  //   0..11  -> C..B major
  //   12..23 -> C..B minor
  //   24+    -> clamp to C major
  logic [3:0] harm_tonic;
  logic       harm_mode;
  always_comb begin
    if (encoders[2] < 7'd12) begin
      harm_tonic = encoders[2][3:0];
      harm_mode  = 1'b0;
    end else if (encoders[2] < 7'd24) begin
      harm_tonic = 4'(encoders[2] - 7'd12);
      harm_mode  = 1'b1;
    end else begin
      harm_tonic = 4'd0;
      harm_mode  = 1'b0;
    end
  end

  // harm{1,2}_ratio are Q11.16 reciprocals; multiply with eff_pitch_factor to
  // get each harmony's PSOLA i_advance.
  fixed_t harm1_ratio, harm2_ratio;
  logic [2:0] harm_chord_state;
  logic       harm_in_scale;
  logic signed [7:0] harm1_semi, harm2_semi;
  harmony_gen iHARM (
      .clk(clk),
      .rst(rst),
      .tonic(harm_tonic),
      .mode(harm_mode),
      .midi_in(melody_midi),
      .note_valid(1'b1),  // free-running; harmony_gen edge-detects internally
      .harm1_ratio(harm1_ratio),
      .harm2_ratio(harm2_ratio),
      .ratios_valid(),
      .o_chord_state(harm_chord_state),
      .o_in_scale(harm_in_scale),
      .o_harm1_semi(harm1_semi),
      .o_harm2_semi(harm2_semi)
  );

  // Compute harmony MIDI = melody_midi + semitone offset, saturated to [0,127].
  function automatic logic [6:0] sat_midi(input logic [6:0] base, input logic signed [7:0] semi);
    logic signed [9:0] s;
    s = $signed({2'b00, base}) + $signed({{2{semi[7]}}, semi});
    if (s < 0)         sat_midi = 7'd0;
    else if (s > 127)  sat_midi = 7'd127;
    else               sat_midi = s[6:0];
  endfunction

  assign o_melody_midi      = melody_midi;
  assign o_held_midi        = note_number;
  assign o_any_note_pressed = |notes;
  assign o_harm_tonic       = harm_tonic;
  assign o_harm_mode        = harm_mode;
  assign o_chord_state      = harm_chord_state;
  assign o_in_scale         = harm_in_scale;
  assign o_harm1_midi       = sat_midi(melody_midi, harm1_semi);
  assign o_harm2_midi       = sat_midi(melody_midi, harm2_semi);

  fixed_t harm_h1_advance, harm_h2_advance;
  assign harm_h1_advance = fixed_mul(eff_pitch_factor, harm1_ratio);
  assign harm_h2_advance = fixed_mul(eff_pitch_factor, harm2_ratio);

  fixed_t psola_lf_h1, psola_rf_h1;
  fixed_t psola_lf_h2, psola_rf_h2;

  psola iPSOLA_L_H1 (
      .clk(clk),
      .rst(rst),
      .i_lag(r_pitch_period),
      .i_lag_valid(r_pitch_valid & vad_voiced),
      .i_advance(harm_h1_advance),
      .i_data(lf),
      .i_valid(adc_en),
      .o_data(psola_lf_h1),
      .o_valid()
  );

  psola iPSOLA_R_H1 (
      .clk(clk),
      .rst(rst),
      .i_lag(r_pitch_period),
      .i_lag_valid(r_pitch_valid & vad_voiced),
      .i_advance(harm_h1_advance),
      .i_data(rf),
      .i_valid(adc_en),
      .o_data(psola_rf_h1),
      .o_valid()
  );

  psola iPSOLA_L_H2 (
      .clk(clk),
      .rst(rst),
      .i_lag(r_pitch_period),
      .i_lag_valid(r_pitch_valid & vad_voiced),
      .i_advance(harm_h2_advance),
      .i_data(lf),
      .i_valid(adc_en),
      .o_data(psola_lf_h2),
      .o_valid()
  );

  psola iPSOLA_R_H2 (
      .clk(clk),
      .rst(rst),
      .i_lag(r_pitch_period),
      .i_lag_valid(r_pitch_valid & vad_voiced),
      .i_advance(harm_h2_advance),
      .i_data(rf),
      .i_valid(adc_en),
      .o_data(psola_rf_h2),
      .o_valid()
  );

  // Stacked mix: root unity, harmonies at 1/2. May exceed full-scale; OK.
  fixed_t stack_lf, stack_rf;
  assign stack_lf = psola_lf + (psola_lf_h1 >>> 0) + (psola_lf_h2 >>> 0);
  assign stack_rf = psola_rf + (psola_rf_h1 >>> 0) + (psola_rf_h2 >>> 0);

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
        // Root only, no harmonies.
        pre_lf = psola_lf;
        pre_rf = psola_rf;
        pre_valid = psola_valid;
      end
      HARMONY: begin
        // Root + Markov-driven harmony stack.
        pre_lf = stack_lf;
        pre_rf = stack_rf;
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

  // assign post_valid = pre_valid;
  // assign post_lf = pre_lf;
  // assign post_rf = pre_rf;

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

  fixed_t vol_gain, vol_gain_base;
  // In VOCODE mode, normalization is bypassed (see normalization.sv) so the
  // vocoded signal sits below the level of the other modes. Apply an extra
  // left-shift to boost it — no DSP needed.
  localparam int VOCODE_BOOST_SHIFT = 2;  // 2x boost
  assign vol_gain_base = fixed_t'({1'b0, volume}) << (16 - VOL_SHIFT);
  assign vol_gain      = (mode == VOCODE) ? (vol_gain_base << VOCODE_BOOST_SHIFT) : vol_gain_base;
  // assign o_lf    = fixed_mul(pre_lf, vol_gain);
  // assign o_rf    = fixed_mul(pre_rf, vol_gain);
  // assign o_valid = pre_valid;
  assign o_lf          = fixed_mul(post_lf, vol_gain);
  assign o_rf          = fixed_mul(post_rf, vol_gain);
  assign o_valid       = post_valid;


  // ----------------------------------------------------------------
  // Display Control
  // ----------------------------------------------------------------
  hex_display iHEX (
      .clk(clk),
      .rst(rst),
      .pitch_period(r_pitch_period),
      .target_lag(target_lag),
      .mode(mode),
      .i_encoders(encoders),
      .i_btn(i_btn),
      .HEX0(HEX0),
      .HEX1(HEX1),
      .HEX2(HEX2),
      .HEX3(HEX3),
      .HEX4(HEX4),
      .HEX5(HEX5)
  );

endmodule
