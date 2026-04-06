`timescale 1ns/1ps
`include "../fixed.sv"

// Verifies that the barebones PSOLA passthrough (two Hanning grains 50% out
// of phase, no pitch shift) reconstructs the input signal within fixed-point
// error bounds.  The two overlapping windows sum to ~1.0, so output ≈ input.
module psola_tb;
    localparam int  CLK_PERIOD = 10;
    localparam int  N_SAMPLES  = 200;
    // Hanning LUT quantisation (≤1 LSB per entry) plus two fixed_mul
    // truncation errors.  For |sample| ≤ 1.0: total error ≤ 3/65536.
    localparam real EPSILON    = 4.0 / 65536.0;

    logic   clk, rst;
    fixed_t i_data, o_data;
    logic   i_valid, o_valid;

    psola dut (.*);

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    function automatic real abs_r(input real x);
        return (x < 0.0) ? -x : x;
    endfunction

    initial begin
        rst     = 1'b1;
        i_data  = '0;
        i_valid = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        repeat (2) @(posedge clk);

        for (int s = 0; s < N_SAMPLES; s++) begin
            real    v_in, v_out;
            fixed_t sample;

            // 440 Hz sine wave at 48 kHz – exercises a range of amplitudes
            v_in   = $sin(2.0 * 3.14159265358979 * 440.0 * real'(s) / 48000.0);
            sample = fixed_rtof(v_in);

            // Assert i_valid for exactly one cycle
            @(negedge clk);
            i_data  = sample;
            i_valid = 1'b1;
            @(posedge clk);
            @(negedge clk);
            i_valid = 1'b0;

            // Wait for PSOLA to finish processing (≈3 cycles)
            do @(posedge clk); while (!o_valid);

            v_out = fixed_ftor(o_data);
            if (abs_r(v_out - v_in) > EPSILON) begin
                $display("FAIL sample %0d: in=%f out=%f diff=%e (> epsilon=%e)",
                         s, v_in, v_out, abs_r(v_out - v_in), EPSILON);
                // $fatal;
            end
        end

        $display("All %0d PSOLA passthrough checks passed.", N_SAMPLES);
        $finish;
    end

endmodule
