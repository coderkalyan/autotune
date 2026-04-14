`timescale 1ns/1ps

`include "../fixed.sv"

module vocoder_tb;
    // 50 MHz clock → 20 ns period
    localparam int CLK_PERIOD  = 20;
    // 48 kHz audio rate: 50_000_000 / 48_000 ≈ 1042 clock cycles per sample
    localparam int AUDIO_DIV   = 256; // 1042;
    // Samples to collect per test — 512 covers one full period of the lowest
    // supported note (G#2 ≈ 104 Hz → ~462 samples at 48 kHz)
    localparam int N_SAMPLES   = 512;

    logic         clk;
    logic         rst;
    logic         i_valid;
    logic [127:0] i_notes;
    fixed_t       o_data;
    audio_t       o_raw;
    logic         o_valid;

    vocoder dut (.*);

    always #(CLK_PERIOD / 2) clk = ~clk;

    // Generate i_valid as a single-cycle pulse every AUDIO_DIV clock cycles
    int audio_ctr;
    always_ff @(posedge clk) begin
        if (rst) begin
            audio_ctr <= 0;
            i_valid   <= 1'b0;
        end else begin
            if (audio_ctr == AUDIO_DIV - 1) begin
                audio_ctr <= 0;
                i_valid   <= 1'b1;
            end else begin
                audio_ctr <= audio_ctr + 1;
                i_valid   <= 1'b0;
            end
        end
    end

    // Collect N_SAMPLES output samples then return
    task automatic collect_samples(input string label);
        int count;
        count = 0;
        $display("[%0t] %s", $time, label);
        while (count < N_SAMPLES) begin
            @(posedge clk);
            if (o_valid) begin
                $display("  sample[%0d] = %0d", count, $signed(o_data));
                count++;
            end
        end
    endtask

    initial begin
        clk     = 0;
        rst     = 1;
        i_notes = 128'd0;

        repeat (4) @(posedge clk);
        @(negedge clk) rst = 0;
        repeat (2) @(posedge clk);

        // --- Test 1: single note A4 (MIDI 69, 440 Hz — ~109 samples/period) ---
        i_notes = 128'd1 << 69;
        collect_samples("A4 (MIDI 69, 440 Hz)");

        // --- Test 2: single note G#2 (MIDI 44, ~104 Hz — ~463 samples/period) ---
        i_notes = 128'd1 << 44;
        collect_samples("G#2 (MIDI 44, ~104 Hz)");

        // --- Test 3: C major chord (C4=60, E4=64, G4=67) ---
        i_notes = (128'd1 << 60) | (128'd1 << 64) | (128'd1 << 67);
        collect_samples("C major chord (MIDI 60+64+67)");

        // --- Test 4: all 40 supported notes (MIDI 44-83) ---
        begin
            logic [127:0] all_notes = 128'd0;
            for (int n = 44; n < 84; n++) all_notes[n] = 1'b1;
            i_notes = all_notes;
        end
        collect_samples("All 40 supported notes (MIDI 44-83)");

        $display("[%0t] Done.", $time);
        $finish;
    end

    initial begin
        $dumpfile("vocoder_tb.vcd");
        $dumpvars(0, vocoder_tb);
    end
endmodule
