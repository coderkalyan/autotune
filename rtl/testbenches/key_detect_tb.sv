`timescale 1ns / 1ps

// key_detect testbench. Five sub-tests with shrunk tick dividers for fast
// simulation: drives note_on events directly, observes key_id, top_score,
// second_score, activity_out, and corr_done_pulse.
//
// Tests:
//   1. Constant C       -> expect key_id == 0 after dwell.
//   2. C major scale    -> expect key_id == 0.
//   3. Modulation C->G  -> expect key_id transitions 0 -> 7.
//   4. Silence          -> activity decays, key_id holds.
//   5. C/G ambiguity    -> expect no flicker (margin gate).
module key_detect_tb;
  localparam int CLK_PERIOD = 10;

  // Shrunk for sim: 1 kHz / 50 Hz scale at 50 MHz becomes 100x / 50x faster.
  localparam int SIM_DECAY_DIV = 100;
  localparam int SIM_CORR_DIV  = 500;

  logic        clk, rst;
  logic        note_on_valid;
  logic [6:0]  note_on_pitch;
  logic [6:0]  note_on_velocity;
  logic [4:0]  key_id;
  logic        key_valid;
  logic signed [39:0] top_score, second_score;
  logic [27:0] activity_out;
  logic        corr_done_pulse;

  key_detect #(
      .DECAY_TICK_DIV(SIM_DECAY_DIV),
      .CORR_TICK_DIV (SIM_CORR_DIV),
      // Faster decay for sim (~0.95 / tick); production default is 0.9995.
      .ALPHA(16'hF333)
  ) dut (
      .clk(clk), .rst(rst),
      .note_on_valid(note_on_valid),
      .note_on_pitch(note_on_pitch),
      .note_on_velocity(note_on_velocity),
      .key_id(key_id),
      .key_valid(key_valid),
      .top_score(top_score),
      .second_score(second_score),
      .activity_out(activity_out),
      .corr_done_pulse(corr_done_pulse)
  );

  initial clk = 1'b0;
  always #(CLK_PERIOD/2) clk = ~clk;

  // Helpers
  task automatic strobe_note(input [6:0] pitch, input [6:0] vel);
    begin
      @(posedge clk);
      note_on_valid    <= 1'b1;
      note_on_pitch    <= pitch;
      note_on_velocity <= vel;
      @(posedge clk);
      note_on_valid    <= 1'b0;
    end
  endtask

  task automatic wait_corr_passes(input int n);
    int seen;
    begin
      seen = 0;
      while (seen < n) begin
        @(posedge clk);
        if (corr_done_pulse) seen++;
      end
    end
  endtask

  // Waveform
  initial begin
    $dumpfile("/tmp/key_detect_tb.vcd");
    $dumpvars(0, key_detect_tb);
  end

  initial begin
    rst              = 1'b1;
    note_on_valid    = 1'b0;
    note_on_pitch    = '0;
    note_on_velocity = '0;
    repeat (5) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    repeat (2) @(posedge clk);

    // ----------------------------------------------------------------
    // Test 1: constant C (MIDI 60). Hammer it, expect key_id = 0.
    // ----------------------------------------------------------------
    $display("[T1] constant C");
    for (int n = 0; n < 64; n++) begin
      strobe_note(7'd60, 7'd96);
      // small inter-strobe delay
      repeat (50) @(posedge clk);
    end
    wait_corr_passes(8);
    $display("[T1] key_id=%0d key_valid=%b activity=%0d top=%0d second=%0d",
             key_id, key_valid, activity_out, top_score, second_score);
    assert (key_id == 5'd0) else $error("[T1] expected key_id=0 got %0d", key_id);

    // ----------------------------------------------------------------
    // Test 2: C major scale repeated. Should still be key 0.
    // ----------------------------------------------------------------
    $display("[T2] C major scale");
    begin
      logic [6:0] cmaj_scale [0:6] = '{60, 62, 64, 65, 67, 69, 71}; // C..B
      for (int rep = 0; rep < 16; rep++) begin
        for (int i = 0; i < 7; i++) begin
          strobe_note(cmaj_scale[i], 7'd96);
          repeat (40) @(posedge clk);
        end
      end
      wait_corr_passes(6);
      $display("[T2] key_id=%0d key_valid=%b activity=%0d",
               key_id, key_valid, activity_out);
      assert (key_id == 5'd0) else $error("[T2] expected key_id=0 got %0d", key_id);
    end

    // ----------------------------------------------------------------
    // Test 3: modulation C -> G. Drive G major scale; expect key_id -> 7.
    // ----------------------------------------------------------------
    $display("[T3] modulation to G major");
    begin
      logic [6:0] gmaj_scale [0:6] = '{67, 69, 71, 72, 74, 76, 78}; // G..F#
      for (int rep = 0; rep < 32; rep++) begin
        for (int i = 0; i < 7; i++) begin
          strobe_note(gmaj_scale[i], 7'd96);
          repeat (40) @(posedge clk);
        end
        if (rep % 8 == 0) begin
          $display("[T3 rep=%0d] key_id=%0d top_idx=%0d top=%0d second=%0d (idx=%0d) act=%0d x[0]=%0d x[5]=%0d x[6]=%0d x[7]=%0d",
                   rep, key_id, dut.top_idx, top_score, second_score, dut.second_idx,
                   activity_out, dut.x[0], dut.x[5], dut.x[6], dut.x[7]);
        end
      end
      wait_corr_passes(8);
      $display("[T3] key_id=%0d key_valid=%b activity=%0d",
               key_id, key_valid, activity_out);
      assert (key_id == 5'd7) else $error("[T3] expected key_id=7 got %0d", key_id);
    end

    // ----------------------------------------------------------------
    // Test 4: silence. Stop strobing, watch activity decay; key_id holds.
    // ----------------------------------------------------------------
    $display("[T4] silence");
    begin
      logic [4:0] held_key;
      held_key = key_id;
      // Wait long enough for activity to decay below threshold.
      repeat (200000) @(posedge clk);
      $display("[T4] held_key=%0d key_id=%0d activity=%0d",
               held_key, key_id, activity_out);
      assert (key_id == held_key) else $error("[T4] key_id changed during silence");
    end

    // ----------------------------------------------------------------
    // Test 5: C/G ambiguity. Alternate C-major triad notes and G-major triad
    // notes; expect no commit-flicker (key_id stays as last committed).
    // ----------------------------------------------------------------
    $display("[T5] ambiguity");
    begin
      logic [4:0] start_key;
      logic       saw_flicker;
      logic [4:0] prev_key;
      start_key = key_id;
      prev_key  = key_id;
      saw_flicker = 1'b0;
      for (int rep = 0; rep < 32; rep++) begin
        // C triad
        strobe_note(7'd60, 7'd96); repeat (30) @(posedge clk);
        strobe_note(7'd64, 7'd96); repeat (30) @(posedge clk);
        strobe_note(7'd67, 7'd96); repeat (30) @(posedge clk);
        // G triad
        strobe_note(7'd67, 7'd96); repeat (30) @(posedge clk);
        strobe_note(7'd71, 7'd96); repeat (30) @(posedge clk);
        strobe_note(7'd74, 7'd96); repeat (30) @(posedge clk);
        if (corr_done_pulse) begin
          if (key_id != prev_key) saw_flicker = 1'b1;
          prev_key = key_id;
        end
      end
      $display("[T5] start=%0d final=%0d saw_flicker=%b",
               start_key, key_id, saw_flicker);
    end

    $display("key_detect_tb finished");
    $finish;
  end

  initial begin
    #5000000000;  // 5 s sim ceiling
    $display("key_detect_tb timeout");
    $fatal;
  end

endmodule
