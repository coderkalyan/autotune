`timescale 1ns / 1ps
`include "../fixed.sv"

// Visual smoke-test for bandpass_filterbank.
//
// - Drives 50 MHz clk
// - Generates 48 kHz i_valid strobes (1 cycle wide) with BASE/BASE+1 dithering
//   so the long-term average is exact.
// - Feeds a sawtooth waveform using a phase accumulator.
// - Forces coefficient ROM signals instead of loading from .mem files.
// - Dumps a VCD so you can inspect i_data, o_data[*], and o_valid in GTKWave.
//
// Notes:
// - The DUT expects i_valid only when idle; this TB leaves lots of slack
//   between strobes, so that assumption holds.
// - Coefficient ROMs are forced with constant values for each bank.
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
    localparam int TailCycles = 200;
    localparam int MaxTraceLines = 256;
    localparam int MaxSimCycles = (NSamples * (BaseCycles + 2)) + TailCycles + 20000;

    // Sawtooth frequency (independent of SampleHz)
    localparam int SawHz = 440;
    localparam longint unsigned PhaseStepWide = (64'd4294967296 * SawHz) / SampleHz;
    localparam logic [31:0] PhaseStep = PhaseStepWide[31:0];

    logic   clk;
    logic   rst;
    fixed_t i_data;
    logic   i_valid;
    logic   i_asym_follow;
    logic   [$clog2(BANKS) - 1:0] i_bank_start;
    logic   [$clog2(BANKS) - 1:0] i_bank_end;

    fnorm_t o_data[BANKS];
    logic   o_valid;

    // -------------------------
    // Coefficients (forced in testbench instead of loaded from .mem)
    // -------------------------
    // Stage 0 implements a 1st-order IIR in biquad form:
    //   y[n] = (1-a)*x[n] + a*y[n-1]
    // achieved by setting a1 = -a and b0 = 1-a (others 0).
    // Different banks use different 'a' so the responses are visibly different.
    localparam real B0_VAL[BANKS] = '{0.10, 0.25, 0.50, 0.75};
    localparam real A1_VAL[BANKS] = '{-0.90, -0.75, -0.50, -0.25};

    bandpass_filterbank #(
        .BANKS      (BANKS),
        .COEF_BANKS (BANKS)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .i_data        (i_data),
        .i_valid       (i_valid),
        .i_asym_follow (i_asym_follow),
        .i_bank_start  (i_bank_start),
        .i_bank_end    (i_bank_end),
        .o_data        (o_data),
        .o_valid       (o_valid)
    );

    // -------------------------
    // Force coefficient ROMs with test values
    // -------------------------
    // Convert real coefficient values to fnorm_t (Q3.24) and force into ROM signals.
    // Stage 0: b0 coefficient (input)
    // Stage 0: b1 coefficient (always 0 for 1st-order IIR)
    // Stage 0: a1 coefficient (feedback)
    // Stage 0: a2 coefficient (always 0 for 1st-order IIR)
    // Stage 1: b0 coefficient (pass-through = 1.0)
    // Stage 1: b1 coefficient (always 0)
    // Stage 1: a1 coefficient (always 0)
    // Stage 1: a2 coefficient (always 0)
    initial begin
        for (int b = 0; b < BANKS; b++) begin
            // Convert real to fnorm_t (Q3.24 = 24 fractional bits)
            dut.B0[b] = {5'b0, fnorm_t'(B0_VAL[b] * real'(1 << 24))};
            dut.B1[b] = {5'b0, fnorm_t'(0)};
            dut.A1[b] = {5'b0, fnorm_t'(A1_VAL[b] * real'(1 << 24))};
            dut.A2[b] = {5'b0, fnorm_t'(0)};
            // Stage 1 is pass-through: b0=1.0, others=0
            dut.C0[b] = {5'b0, fnorm_t'(1.0 * real'(1 << 24))};
            dut.C1[b] = {5'b0, fnorm_t'(0)};
            dut.D1[b] = {5'b0, fnorm_t'(0)};
            dut.D2[b] = {5'b0, fnorm_t'(0)};
        end
    end

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
        if (PhaseStep == 0) begin
            $fatal(1, "PhaseStep computed as 0; check SawHz/SampleHz math");
        end
        rst          = 1'b1;
        i_data       = '0;
        i_valid      = 1'b0;
        i_asym_follow = 1'b0;
        i_bank_start = 0;
        i_bank_end   = BANKS - 1;
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    // -------------------------
    // 48 kHz i_valid + sawtooth sample generator
    // -------------------------
    int unsigned cycles_left;
    int unsigned frac_accum;
    int unsigned sample_count;
    int unsigned sim_cycles;
    int unsigned trace_lines;
    integer dump_b;

    logic [31:0] phase;
    audio_t      saw_audio;

    always @(posedge clk) begin
        if (rst) begin
            i_valid      <= 1'b0;
            i_data       <= '0;
            cycles_left  <= 0;
            frac_accum   <= 0;
            sample_count <= 0;
            sim_cycles   <= 0;
            trace_lines  <= 0;
            phase        <= '0;
            saw_audio    <= '0;
        end else begin
            sim_cycles <= sim_cycles + 1;
            if (sim_cycles > MaxSimCycles) begin
                $fatal(
                    1,
                    "TB timeout: sample_count=%0d cycles_left=%0d o_valid=%0b",
                    sample_count,
                    cycles_left,
                    o_valid
                );
            end
            if (sample_count >= NSamples) begin
                i_valid <= 1'b0;
            end else if (cycles_left == 0) begin
                int unsigned period_cycles;
                int unsigned next_frac;
                logic [31:0] next_phase;
                audio_t       next_saw;
                logic signed [15:0] saw_sample;

                // Advance phase one sample, then derive sawtooth sample.
                next_phase = phase + PhaseStep;
                saw_sample = $signed(next_phase[31:16]);
                next_saw   = audio_t'(saw_sample);
                phase      <= next_phase;
                saw_audio  <= next_saw;
                i_data     <= fixed_t'(saw_sample) <<< 10;
                if (sample_count < 8) begin
                    $display(
                        "gen n=%0d step=0x%08h phase=0x%08h saw=%0d i_data=%0d",
                        sample_count, PhaseStep, next_phase, next_saw,
                        fixed_t'(saw_sample) <<< 10
                    );
                end

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


    // // -------------------------
    // // Waveform dump + lightweight console trace
    // // -------------------------
    initial begin
        $dumpfile("bandpass_sosfilt_bank_tb.vcd");
        // Dump slow signals (skip clk to keep VCD small)
        $dumpvars(0, rst);
        $dumpvars(0, i_valid);
        $dumpvars(0, i_data);
        $dumpvars(0, o_valid);
        for (dump_b = 0; dump_b < BANKS; dump_b = dump_b + 1) begin
            $dumpvars(0, o_data[dump_b]);
        end
        // Internal DUT signal names can vary; keep dump list to stable I/O here.
    end

    // Print one line per output sample (one o_valid per input sample)
    // fnorm_t is Q3.24, so divide by 2^24 to convert to real
    always @(posedge clk) begin
        if (!rst && o_valid && (trace_lines < MaxTraceLines)) begin
            $write("t=%0t ns  in=%7.4f", $time, `FIXED_FTOR(i_data));
            for (int b = 0; b < BANKS; b++) begin
                real o_val;
                o_val = real'(o_data[b]) / real'(1 << 24);
                $write("  y[%0d]=%7.4f", b, o_val);
            end
            $write("\n");
            trace_lines <= trace_lines + 1;
            if (trace_lines + 1 == MaxTraceLines) begin
                $display("trace limit reached: %0d", MaxTraceLines);
            end
        end
    end

    initial begin
        wait (!rst);
        wait (sample_count >= NSamples);
        repeat (TailCycles) @(posedge clk);
        $display("TB done: sample_count=%0d sim_cycles=%0d", sample_count, sim_cycles);
        $finish;
    end

endmodule
