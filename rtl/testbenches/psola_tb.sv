`timescale 1ns / 1ps
`include "../fixed.sv"

// Drives PSOLA with two input-frequency segments, each with a mid-segment
// pitch-factor update, to exercise both upward and downward pitch shifting.
//
//   samples 0..4999   : 440 Hz,  pitch_factor = 1.2  (up ~3.2 semitones)
//   samples 5000..9999 : 440 Hz,  pitch_factor = 0.9  (down ~1.9 semitones)
//   samples 10000..14999: ~1320 Hz, pitch_factor = 1.3  (up ~4.5 semitones)
//   samples 15000..19999: ~1320 Hz, pitch_factor = 0.95 (down ~0.9 semitones)
//
// i_advance = 1 / pitch_factor; values < 1 pitch up, > 1 pitch down.
module psola_tb;
  localparam int  CLK_PERIOD  = 10;
  localparam int  N_SAMPLES   = 20000;
  localparam real FS          = 48000.0;
  localparam real FREQ1       = 440.0;
  localparam real FREQ2       = FREQ1 * 3;  // ~1320 Hz
  localparam int  TRANS_START = 10000;
  localparam int  TRANS_LEN   = 50;

  // Pitch factors — two per frequency segment, one > 1 and one < 1.
  localparam real PF_S1A = 1.5;   // segment 1 first half  (pitch up)
  localparam real PF_S1B = 0.7;   // segment 1 second half (pitch down)
  localparam real PF_S2A = 1.3;   // segment 2 first half  (pitch up)
  localparam real PF_S2B = 0.95;  // segment 2 second half (pitch down)

  logic       clk, rst;
  fixed_t     i_data, o_data, i_advance;
  logic       i_valid, o_valid;
  logic [9:0] i_lag;

  psola dut (.*);

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  real phase;

  initial begin
    rst       = 1'b1;
    i_data    = '0;
    i_valid   = 1'b0;
    i_lag     = 10'($rtoi(FS / FREQ1 + 0.5));
    i_advance = fixed_rtof(1.0 / PF_S1A);
    phase     = 0.0;
    repeat (4) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    repeat (2) @(posedge clk);

    for (int s = 0; s < N_SAMPLES; s++) begin
      real    v_in, v_out, freq, t, pitch_factor;
      fixed_t sample;

      // --- pitch factor: update once in the middle of each segment ---
      if (s < TRANS_START / 2)
        pitch_factor = PF_S1A;
      else if (s < TRANS_START)
        pitch_factor = PF_S1B;
      else if (s < TRANS_START + (N_SAMPLES - TRANS_START) / 2)
        pitch_factor = PF_S2A;
      else
        pitch_factor = PF_S2B;

      i_advance = fixed_rtof(1.0 / pitch_factor);

      // --- input frequency: linear glide at TRANS_START ---
      if (s < TRANS_START) begin
        freq = FREQ1;
      end else if (s < TRANS_START + TRANS_LEN) begin
        t    = real'(s - TRANS_START) / real'(TRANS_LEN);
        freq = FREQ1 + (FREQ2 - FREQ1) * t;
      end else begin
        freq = FREQ2;
      end

      i_lag  = 10'($rtoi(FS / freq + 0.5));
      v_in   = $sin(phase);
      phase += 2.0 * 3.14159265358979 * freq / FS;
      sample = fixed_rtof(v_in);

      // Assert i_valid for exactly one cycle
      @(negedge clk);
      i_data  = sample;
      i_valid = 1'b1;
      @(posedge clk);
      @(negedge clk);
      i_valid = 1'b0;

      // Wait for PSOLA to finish processing
      do @(posedge clk); while (!o_valid);

      v_out = fixed_ftor(o_data);
      $display("s=%5d freq=%7.1f pf=%.2f lag=%3d in=%8.5f out=%8.5f", s, freq, pitch_factor,
               i_lag, v_in, v_out);
    end

    $display("Done.");
    $finish;
  end

endmodule
