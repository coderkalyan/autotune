`timescale 1ns / 1ps
`include "../fixed.sv"

// Visual smoke-test for bandpass_sosfilt_bank.
//
// - Drives 50 MHz clk
// - Generates 48 kHz i_valid strobes (1 cycle wide) with BASE/BASE+1 dithering
//   so the long-term average is exact.
// - Feeds a sawtooth waveform using a phase accumulator.
// - Dumps a VCD so you can inspect i_data, o_data[*], and o_valid in GTKWave.
//
// Notes:
// - The DUT expects i_valid only when idle; this TB leaves lots of slack
//   between strobes, so that assumption holds.
module bandpass_sosfilt_bank_tb;
    // -------------------------
    // Clocking / sample timing
    // -------------------------
    localparam int ClkHz     = 50_000_000;
    localparam int SampleHz  = 48_000;
    localparam int ClkPeriod = 20;  // ns => 50 MHz

    // 50e6 / 48e3 = 1041.666... cycles/sample
    localparam int BaseCycles = ClkHz / SampleHz; // 1041
    localparam int RemCycles  = ClkHz % SampleHz; // 32000

    localparam int BANKS    = 4;
    localparam int NSamples = 2000; // ~41.7 ms at 48 kHz

    // Sawtooth frequency (independent of SampleHz)
    localparam int SawHz = 440;
    localparam longint unsigned PhaseStep = (longint'(SawHz) << 32) / SampleHz;

    logic   clk;
    logic   rst;
    fixed_t i_data;
    logic   i_valid;

    fixed_t o_data[BANKS];
    logic   o_valid;

    // -------------------------
    // Coefficients
    // -------------------------
    // Stage 0 implements a 1st-order IIR in biquad form:
    //   y[n] = (1-a)*x[n] + a*y[n-1]
    // achieved by setting a1 = -a and b0 = 1-a (others 0).
    // Different banks use different 'a' so the responses are visibly different.
    localparam real B0Table[BANKS] = '{0.10, 0.25, 0.50, 0.75};
    localparam real A1Table[BANKS] = '{-0.90, -0.75, -0.50, -0.25};

    // Stage 1 is pass-through (y=w)
    localparam real C0Table[BANKS] = '{default: 1.0};

    bandpass_sosfilt_bank #(
        .BANKS  (BANKS),
        .UNITS  (1),
        .B0Table(B0Table),
        .B1Table('{default: 0.0}),
        .B2Table('{default: 0.0}),
        .A1Table(A1Table),
        .A2Table('{default: 0.0}),
        .C0Table(C0Table),
        .C1Table('{default: 0.0}),
        .C2Table('{default: 0.0}),
        .D1Table('{default: 0.0}),
        .D2Table('{default: 0.0})
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .i_data (i_data),
        .i_valid(i_valid),
        .o_data (o_data),
        .o_valid(o_valid)
    );

    // -------------------------
    // 50 MHz clock
    // -------------------------
    initial begin
        clk = 1'b0;
        forever #(ClkPeriod / 2) clk = ~clk;
    end

    // -------------------------
    // Reset
    // -------------------------
    initial begin
        rst     = 1'b1;
        i_data  = '0;
        i_valid = 1'b0;
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    // -------------------------
    // 48 kHz i_valid + sawtooth sample generator
    // -------------------------
    int unsigned cycles_left;
    int unsigned frac_accum;
    int unsigned sample_count;

    logic [31:0] phase;
    audio_t      saw_audio;

    always_ff @(posedge clk) begin
        if (rst) begin
            i_valid      <= 1'b0;
            i_data       <= '0;
            cycles_left  <= 0;
            frac_accum   <= 0;
            sample_count <= 0;
            phase        <= '0;
            saw_audio    <= '0;
        end else begin
            if (sample_count >= NSamples) begin
                i_valid <= 1'b0;
            end else if (cycles_left == 0) begin
                int unsigned period_cycles;
                int unsigned next_frac;

                // Advance phase one sample, then derive sawtooth sample.
                phase     <= phase + logic'(PhaseStep[31:0]);
                saw_audio <= $signed(phase[31:16]) >>> 4; // scale down to avoid overflow
                i_data    <= `FIXED_ATOF(saw_audio);

                // Pulse i_valid for exactly one clk
                i_valid <= 1'b1;

                // Choose next period length (BASE or BASE+1)
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

    // -------------------------
    // Waveform dump + lightweight console trace
    // -------------------------
    initial begin
        $dumpfile("bandpass_sosfilt_bank_tb.vcd");
        // Dump slow signals (skip clk to keep VCD small)
        $dumpvars(0, rst);
        $dumpvars(0, i_valid);
        $dumpvars(0, i_data);
        $dumpvars(0, o_valid);
        for (int b = 0; b < BANKS; b++) begin
            $dumpvars(0, o_data[b]);
        end
        // Helpful internal visibility
        $dumpvars(0, dut.state);
        $dumpvars(0, dut.bank_idx);
        $dumpvars(0, dut.filt_i_valid);
        $dumpvars(0, dut.filt_o_valid);
    end

    // Print one line per output sample (one o_valid per input sample)
    always_ff @(posedge clk) begin
        if (!rst && o_valid) begin
            $write("t=%0t ns  in=%+7.4f", $time, `FIXED_FTOR(i_data));
            for (int b = 0; b < BANKS; b++) begin
                $write("  y[%0d]=%+7.4f", b, `FIXED_FTOR(o_data[b]));
            end
            $write("\n");
        end
    end

    initial begin
        wait (!rst);
        wait (sample_count >= NSamples);
        repeat (200) @(posedge clk);
        $finish;
    end

endmodule
