`timescale 1ns / 1ps
`include "../fixed.sv"

// Simple smoke-test for the Hilbert FIR module.
//
// Drives a 440 Hz sine wave (fs=48kHz, normalised freq ≈ 0.0092, well inside
// the passband) and checks:
//   1. o_delayed exactly matches i_data from 31 samples ago.
//   2. o_hilbert has roughly unit gain (RMS comparable to o_delayed RMS).
//
// Prints every sample for visual inspection; look for o_hilbert ≈ cosine when
// o_delayed ≈ sine.
module hilbert_tb;
    localparam int  CLK_PERIOD = 10;
    localparam int  N_SAMPLES  = 150;
    localparam real PI   = 3.14159265358979;
    localparam real FREQ = 0.125;  // fs/8 = 6 kHz at 48 kHz, inside passband [0.05, 0.45]

    logic   clk, rst;
    fixed_t i_data, o_hilbert, o_delayed;
    logic   i_valid, o_valid;

    hilbert dut (.*);

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Ring buffer to check delayed output
    fixed_t input_q[N_SAMPLES];
    int     out_cnt;

    real rms_hil, rms_del;

    initial begin
        rst     = 1'b1;
        i_data  = '0;
        i_valid = 1'b0;
        out_cnt = 0;
        rms_hil = 0.0;
        rms_del = 0.0;
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        for (int s = 0; s < N_SAMPLES; s++) begin
            real    v;
            fixed_t sample;

            v      = $sin(2.0 * PI * FREQ * real'(s));
            sample = fixed_rtof(v);
            input_q[s] = sample;

            // Assert i_valid for exactly one cycle
            @(negedge clk);
            i_data  = sample;
            i_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i_valid = 1'b0;

            // Wait for this sample's output (33 cycles)
            do @(posedge clk); while (!o_valid);

            begin
                // --- delay check (skip first 31 outputs; buf_mem uninitialized) ---
                if (out_cnt >= 31) begin
                    fixed_t expected_del;
                    expected_del = input_q[out_cnt - 31];
                    if (o_delayed !== expected_del)
                        $display("DELAY FAIL s=%0d: want=0x%07h got=0x%07h",
                                 s, expected_del, o_delayed);
                end

                // --- accumulate RMS (skip first 63 samples for warmup) ---
                if (out_cnt >= 63) begin
                    real h, d;
                    h = fixed_ftor(o_hilbert);
                    d = fixed_ftor(o_delayed);
                    rms_hil += h * h;
                    rms_del += d * d;
                end

                $display("s=%3d  in=%7.4f  delayed=%7.4f  hilbert=%7.4f",
                         s, fixed_ftor(i_data), fixed_ftor(o_delayed),
                         fixed_ftor(o_hilbert));
                out_cnt++;
            end
        end

        begin
            int warmup_samples;
            real rms_ratio;
            warmup_samples = N_SAMPLES - 63;
            if (warmup_samples > 0) begin
                rms_hil = $sqrt(rms_hil / real'(warmup_samples));
                rms_del = $sqrt(rms_del / real'(warmup_samples));
                rms_ratio = (rms_del > 0.0) ? (rms_hil / rms_del) : 0.0;
                $display("\nRMS after warmup: hilbert=%.4f  delayed=%.4f  ratio=%.4f (expect ~1.0)",
                         rms_hil, rms_del, rms_ratio);
                if (rms_ratio < 0.8 || rms_ratio > 1.2)
                    $display("WARNING: RMS ratio outside [0.8, 1.2] — filter gain unexpected");
                else
                    $display("Gain check passed.");
            end
        end

        $display("Done. %0d samples processed.", N_SAMPLES);
        $finish;
    end
endmodule
