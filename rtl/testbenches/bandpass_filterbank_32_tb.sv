`timescale 1ns / 1ps
`include "../fixed.sv"

// 32-bank bandpass_filterbank integration testbench. Drives a sequence of
// sine tones at 48 kHz, each targeting a different band, and prints the
// per-band peak magnitude at the end of each phase so different bands
// should "light up" for different stimuli.
//
// Bands are log-spaced 300 Hz .. 8 kHz (see py/vocoder_romgen.py). Stimuli
// frequencies are chosen to sit near the centers of well-separated bands:
//   320 Hz  -> band  ~0
//   1000 Hz -> band ~11
//   3000 Hz -> band ~22
//   6000 Hz -> band ~29
module bandpass_filterbank_32_tb;
    // ----------------------------------------------------------------
    // Clocking / sample timing
    // ----------------------------------------------------------------
    localparam int BANKS     = 32;
    localparam int ClkHz     = 50_000_000;
    localparam int SampleHz  = 48_000;
    localparam int ClkPeriod = 20;  // ns => 50 MHz

    // 50e6 / 48e3 = 1041.666... cycles/sample
    localparam int BaseCycles = ClkHz / SampleHz;  // 1041
    localparam int RemCycles  = ClkHz % SampleHz;  // 32000

    localparam int NPhases        = 4;
    localparam int NSamplesPhase  = 24000;  // 500 ms per freq (lets slow AM show)
    localparam int NSamplesTotal  = NSamplesPhase * NPhases;
    localparam int TailCycles     = 4000;
    localparam int MaxSimCycles   = (NSamplesTotal * (BaseCycles + 2)) + TailCycles + 500000;

    // Slow AM envelope: sine at AM_HZ with depth AM_DEPTH around AM_BIAS.
    // Final stimulus = carrier * (AM_BIAS + AM_DEPTH * sin(2π*AM_HZ*t)).
    // With AM_BIAS=0.55, AM_DEPTH=0.45 the envelope sweeps 0.10 .. 1.00.
    localparam real AM_HZ    = 3.0;
    localparam real AM_BIAS  = 0.55;
    localparam real AM_DEPTH = 0.45;

    // Stimulus frequencies, one per phase.
    real phase_freqs [NPhases];
    initial begin
        phase_freqs[0] = 320.0;
        phase_freqs[1] = 1000.0;
        phase_freqs[2] = 3000.0;
        phase_freqs[3] = 6000.0;
    end

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    logic   clk;
    logic   rst;
    fixed_t i_data;
    logic   i_valid;
    fnorm_t o_data [BANKS];
    logic   o_valid;

    bandpass_filterbank #(
        .BANKS(BANKS)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .i_data       (i_data),
        .i_valid      (i_valid),
        .i_asym_follow(1'b1),
        .i_bank_start (5'd0),
        .i_bank_end   (5'(BANKS - 1)),
        .o_data       (o_data),
        .o_valid      (o_valid)
    );

    // ----------------------------------------------------------------
    // 50 MHz clock
    // ----------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #(ClkPeriod / 2) clk = ~clk;
    end

    // ----------------------------------------------------------------
    // Reset
    // ----------------------------------------------------------------
    initial begin
        rst     = 1'b1;
        i_data  = '0;
        i_valid = 1'b0;
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    // ----------------------------------------------------------------
    // 48 kHz i_valid + per-phase sine sample generator
    // ----------------------------------------------------------------
    int unsigned cycles_left;
    int unsigned frac_accum;
    int unsigned sample_count;
    int unsigned phase_idx;
    int unsigned sim_cycles;
    real         freq_hz;
    real         sine_real;
    real         env_amp;
    int          sine_q24;

    always @(posedge clk) begin
        if (rst) begin
            i_valid      <= 1'b0;
            i_data       <= '0;
            cycles_left  <= 0;
            frac_accum   <= 0;
            sample_count <= 0;
            phase_idx    <= 0;
            sim_cycles   <= 0;
        end else begin
            sim_cycles <= sim_cycles + 1;
            if (sim_cycles > MaxSimCycles) begin
                $fatal(1,
                    "TB timeout: sample_count=%0d phase=%0d",
                    sample_count, phase_idx);
            end

            if (sample_count >= NSamplesTotal) begin
                i_valid <= 1'b0;
            end else if (cycles_left == 0) begin
                int unsigned period_cycles;
                int unsigned next_frac;
                int unsigned new_phase;

                new_phase = sample_count / NSamplesPhase;
                if (new_phase >= NPhases) new_phase = NPhases - 1;
                freq_hz = phase_freqs[new_phase];

                // Slow AM envelope so bands should visibly breathe.
                env_amp = AM_BIAS + AM_DEPTH *
                          $sin(2.0 * 3.14159265358979 * AM_HZ *
                               real'(sample_count) / real'(SampleHz));
                sine_real = env_amp *
                            $sin(2.0 * 3.14159265358979 * freq_hz *
                                 real'(sample_count) / real'(SampleHz));
                sine_q24  = int'(sine_real * 0.5 * real'(1 << 24));
                i_data    <= fixed_t'(sine_q24);
                i_valid   <= 1'b1;

                if (new_phase != phase_idx || sample_count == 0) begin
                    $display("t=%0t ns  phase=%0d switching to freq=%0f Hz",
                             $time, new_phase, freq_hz);
                    phase_idx <= new_phase;
                end

                period_cycles = BaseCycles;
                next_frac     = frac_accum + RemCycles;
                if (next_frac >= SampleHz) begin
                    next_frac     = next_frac - SampleHz;
                    period_cycles = BaseCycles + 1;
                end

                frac_accum   <= next_frac;
                cycles_left  <= period_cycles - 1;
                sample_count <= sample_count + 1;
            end else begin
                i_valid     <= 1'b0;
                cycles_left <= cycles_left - 1;
            end
        end
    end

    // ----------------------------------------------------------------
    // Per-bank peak tracking, reset at each phase boundary. Report at end
    // of each phase so the console log shows which bands respond to each
    // stimulus frequency.
    // ----------------------------------------------------------------
    real peak_abs [BANKS];
    int  last_phase;

    initial begin
        for (int k = 0; k < BANKS; k++) peak_abs[k] = 0.0;
        last_phase = 0;
    end

    always @(posedge clk) begin
        if (!rst && o_valid) begin
            for (int k = 0; k < BANKS; k++) begin
                real v;
                v = real'($signed(o_data[k])) / real'(1 << 24);
                if (v < 0.0) v = -v;
                if (v > peak_abs[k]) peak_abs[k] = v;
            end
        end
    end

    task automatic report_peaks(input int ph, input real f);
        int best_band;
        real best_val;
        best_band = 0;
        best_val  = 0.0;
        $display("---- phase %0d  freq=%0f Hz  per-band peak |y| ----", ph, f);
        for (int k = 0; k < BANKS; k++) begin
            $display("  band %2d : %8.5f", k, peak_abs[k]);
            if (peak_abs[k] > best_val) begin
                best_val  = peak_abs[k];
                best_band = k;
            end
        end
        $display("  => strongest band = %0d (peak=%0.5f)", best_band, best_val);
    endtask

    always @(posedge clk) begin
        if (!rst && phase_idx != last_phase) begin
            // Report the phase that just ended.
            report_peaks(last_phase, phase_freqs[last_phase]);
            for (int k = 0; k < BANKS; k++) peak_abs[k] = 0.0;
            last_phase <= phase_idx;
        end
    end

    // ----------------------------------------------------------------
    // Waveform dump
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("bandpass_filterbank_32_tb.vcd");
        $dumpvars(0, rst);
        $dumpvars(0, i_valid);
        $dumpvars(0, i_data);
        $dumpvars(0, o_valid);
        for (int k = 0; k < BANKS; k++) begin
            $dumpvars(0, o_data[k]);
        end
    end

    initial begin
        wait (!rst);
        wait (sample_count >= NSamplesTotal);
        repeat (TailCycles) @(posedge clk);
        // Report the final phase as well.
        report_peaks(NPhases - 1, phase_freqs[NPhases - 1]);
        $display("TB done: sample_count=%0d sim_cycles=%0d",
                 sample_count, sim_cycles);
        $finish;
    end

endmodule
