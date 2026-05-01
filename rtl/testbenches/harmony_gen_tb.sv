`timescale 1ns / 1ps
`include "../fixed.sv"

// Drives harmony_gen with an 8-note C-major fragment (60,62,64,65,67,65,64,62)
// and logs chord_state, harm{1,2}_semi-equivalent (back-derived), and the
// emitted Q11.16 reciprocal ratios to a CSV. chord_tick fires internally on
// midi_in change. Asserts ratios stay within plausible bounds [0.25, 4.0]
// in Q11.16.
module harmony_gen_tb;
  localparam int CLK_PERIOD = 10;

  logic        clk, rst;
  logic [3:0]  tonic;
  logic        mode;
  logic [6:0]  midi_in;
  logic        note_valid;
  fixed_t      harm1_ratio, harm2_ratio;
  logic        ratios_valid;
  logic [2:0]  chord_state;
  logic        in_scale;

  harmony_gen dut (
      .clk(clk),
      .rst(rst),
      .tonic(tonic),
      .mode(mode),
      .midi_in(midi_in),
      .note_valid(note_valid),
      .harm1_ratio(harm1_ratio),
      .harm2_ratio(harm2_ratio),
      .ratios_valid(ratios_valid),
      .o_chord_state(chord_state),
      .o_in_scale(in_scale)
  );

  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // Plausible-range bounds in Q11.16 (27-bit signed): 0.25..4.0
  localparam fixed_t RATIO_MIN = `FIXED_RTOF(0.25);
  localparam fixed_t RATIO_MAX = `FIXED_RTOF(4.0);

  int           csv;
  logic [6:0]   melody [0:7] = '{60, 62, 64, 65, 67, 65, 64, 62};

  initial begin
    csv = $fopen("harmony_gen_log.csv", "w");
    $fdisplay(csv, "tick,midi_in,chord_state,harm1_ratio_hex,harm2_ratio_hex,h1_real,h2_real");

    rst        = 1'b1;
    tonic      = 4'd0;   // C
    mode       = 1'b0;   // major
    midi_in    = 7'd0;
    note_valid = 1'b0;
    repeat (4) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    repeat (2) @(posedge clk);

    // Cycle through the melody multiple times to exercise the Markov FSM
    // for at least 16 chord ticks.
    for (int rep = 0; rep < 4; rep++) begin
      mode = (rep >= 2) ? 1'b1 : 1'b0;  // last two reps in C minor
      for (int i = 0; i < 8; i++) begin
        midi_in    <= melody[i];
        note_valid <= 1'b1;
        @(posedge clk);
        note_valid <= 1'b0;
        // wait a few cycles for outputs to settle and ratios_valid to pulse
        repeat (3) @(posedge clk);

        $fdisplay(csv, "%0d,%0d,%0d,%h,%h,%f,%f",
                  rep * 8 + i, midi_in, chord_state,
                  harm1_ratio, harm2_ratio,
                  `FIXED_FTOR(harm1_ratio), `FIXED_FTOR(harm2_ratio));

        // Range asserts (skip first sample after reset where outputs may be 0)
        if (rep > 0 || i > 0) begin
          assert (harm1_ratio >= RATIO_MIN && harm1_ratio <= RATIO_MAX)
            else $error("harm1_ratio %h out of range at i=%0d rep=%0d",
                        harm1_ratio, i, rep);
          assert (harm2_ratio >= RATIO_MIN && harm2_ratio <= RATIO_MAX)
            else $error("harm2_ratio %h out of range at i=%0d rep=%0d",
                        harm2_ratio, i, rep);
        end
      end
    end

    $fclose(csv);
    $display("harmony_gen_tb finished, log -> harmony_gen_log.csv");
    $finish;
  end

  initial begin
    #(CLK_PERIOD * 100000);
    $display("harmony_gen_tb timeout");
    $fatal;
  end

endmodule
