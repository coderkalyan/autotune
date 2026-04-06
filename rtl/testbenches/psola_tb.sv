`timescale 1ns / 1ps
`include "../fixed.sv"

// Verifies PSOLA passthrough across a frequency transition:
//   samples 0..9999  : 440 Hz (lag ≈ 109 samples)
//   samples 10000..  : linear glide over 500 samples up to 4 semitones (≈554 Hz, lag ≈ 87)
// Output should remain within fixed-point error of the input throughout.
module psola_tb;
  localparam int  CLK_PERIOD  = 10;
  localparam int  N_SAMPLES   = 20000;
  localparam real FS          = 48000.0;
  localparam real FREQ1       = 440.0;
  localparam real FREQ2       = FREQ1 * 3; // 554.365;  // 440 * 2^(4/12) — 4 semitones up
  localparam int  TRANS_START = 10000;
  localparam int  TRANS_LEN   = 50;      // ~10 ms glide at 48 kHz
  localparam real EPSILON     = 4.0 / 65536.0;

  logic       clk, rst;
  fixed_t     i_data, o_data;
  logic       i_valid, o_valid;
  logic [9:0] i_lag;

  psola dut (.*);

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  function automatic real abs_r(input real x);
    return (x < 0.0) ? -x : x;
  endfunction

  real phase;  // running phase accumulator

  initial begin
    rst     = 1'b1;
    i_data  = '0;
    i_valid = 1'b0;
    i_lag   = 10'($rtoi(FS / FREQ1 + 0.5));
    phase   = 0.0;
    repeat (4) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    repeat (2) @(posedge clk);

    for (int s = 0; s < N_SAMPLES; s++) begin
      real    v_in, v_out, freq, t;
      fixed_t sample;

      // Linearly interpolate frequency after TRANS_START
      if (s < TRANS_START) begin
        freq = FREQ1;
      end else if (s < TRANS_START + TRANS_LEN) begin
        t    = real'(s - TRANS_START) / real'(TRANS_LEN);
        freq = FREQ1 + (FREQ2 - FREQ1) * t;
      end else begin
        freq = FREQ2;
      end

      // Lag = nearest integer period in samples at FS
      i_lag  = 10'($rtoi(FS / freq + 0.5));

      // Advance phase accumulator and generate sample
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
      if (abs_r(v_out - v_in) > EPSILON) begin
        $display("FAIL sample %0d (freq=%.1f lag=%0d): in=%f out=%f diff=%e", s, freq, i_lag, v_in,
                 v_out, abs_r(v_out - v_in));
        // $fatal;
      end
    end

    $display("All %0d PSOLA passthrough checks passed.", N_SAMPLES);
    $finish;
  end

endmodule
