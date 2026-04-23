`timescale 1ns / 1ps
`include "../fixed.sv"

// Visual (non self-checking) smoke-test for bandpass_filterbank.
//
// - 50 MHz clk
// - 48 kHz i_valid strobes (BASE/BASE+1 dither so long-term avg is exact)
// - Drives sine waves: first half in-band (band 0 is ~300-332 Hz -> 315 Hz),
//   second half well out of band (5000 Hz). Expect o_data passband response
//   and then near-zero output.
// - Dumps VCD for GTKWave.
module bandpass_filterbank_tb;
    // -------------------------
    // Clocking / sample timing
    // -------------------------
    localparam int ClkHz     = 50_000_000;
    localparam int SampleHz  = 48_000;
    localparam int ClkPeriod = 20;  // ns => 50 MHz

    // 50e6 / 48e3 = 1041.666... cycles/sample
    localparam int BaseCycles = ClkHz / SampleHz; // 1041
    localparam int RemCycles  = ClkHz % SampleHz; // 32000

    localparam int BANKS         = 1;
    localparam int NSamplesHalf  = 2400;          // 50 ms per frequency
    localparam int NSamples      = NSamplesHalf * 2;
    localparam int TailCycles    = 200;
    localparam int MaxTraceLines = 2 * NSamples;
    localparam int MaxSimCycles  = (NSamples * (BaseCycles + 2)) + TailCycles + 20000;

    // Test frequencies
    localparam real FreqInBand  = 315.0;   // inside band 0 (300-332 Hz)
    localparam real FreqOutBand = 5000.0;  // well above band 0

    // -------------------------
    // DUT I/O
    // -------------------------
    logic   clk;
    logic   rst;
    fnorm_t i_data;
    logic   i_valid;
    logic   i_asym_follow;

    fixed_t o_data[BANKS];
    logic   o_valid;

    bandpass_filterbank #(
        .BANKS(BANKS)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .i_data       (i_data),
        .i_valid      (i_valid),
        .i_asym_follow(i_asym_follow),
        .i_bank_start ('0),
        .i_bank_end   ('0),
        .o_data       (o_data),
        .o_valid      (o_valid)
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
        rst           = 1'b1;
        i_data        = '0;
        i_valid       = 1'b0;
        i_asym_follow = 1'b0;
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    // -------------------------
    // 48 kHz i_valid + sine sample generator
    // Two-phase test: first half in-band, second half out-of-band.
    // -------------------------
    int unsigned cycles_left;
    int unsigned frac_accum;
    int unsigned sample_count;
    int unsigned sim_cycles;
    int unsigned trace_lines;
    real         freq_hz;
    real         sine_real;
    int          sine_q24;

    always @(posedge clk) begin
        if (rst) begin
            i_valid      <= 1'b0;
            i_data       <= '0;
            cycles_left  <= 0;
            frac_accum   <= 0;
            sample_count <= 0;
            sim_cycles   <= 0;
            trace_lines  <= 0;
        end else begin
            sim_cycles <= sim_cycles + 1;
            if (sim_cycles > MaxSimCycles) begin
                $fatal(1,
                    "TB timeout: sample_count=%0d cycles_left=%0d o_valid=%0b",
                    sample_count, cycles_left, o_valid);
            end

            if (sample_count >= NSamples) begin
                i_valid <= 1'b0;
            end else if (cycles_left == 0) begin
                int unsigned period_cycles;
                int unsigned next_frac;

                // Pick frequency based on which half of the run we are in.
                freq_hz = (sample_count < NSamplesHalf) ? FreqInBand : FreqOutBand;

                // sin(2*pi*f*n/fs) in [-1,1]; scale to Q3.24.
                sine_real = $sin(2.0 * 3.14159265358979 * freq_hz *
                                 real'(sample_count) / real'(SampleHz));
                // 0.95 headroom to keep well under Q3.24 clip.
                sine_q24  = int'(sine_real * 0.5 * real'(1 << 24));
                i_data    <= fnorm_t'(sine_q24);

                i_valid <= 1'b1;

                if (sample_count == 0 || sample_count == NSamplesHalf) begin
                    $display("t=%0t ns  switching to freq=%0f Hz", $time, freq_hz);
                end

                // BASE or BASE+1 cycle period (dithered for 48 kHz avg).
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
    // Waveform dump
    // -------------------------
    initial begin
        $dumpfile("bandpass_filterbank_tb.vcd");
        $dumpvars(0, rst);
        $dumpvars(0, i_valid);
        $dumpvars(0, i_data);
        $dumpvars(0, o_valid);
        for (int b = 0; b < BANKS; b++) begin
            $dumpvars(0, o_data[b]);
        end
        // Internal visibility
        $dumpvars(0, dut.x1_r);
        $dumpvars(0, dut.x2_r);
        $dumpvars(0, dut.s0_y1_r);
        $dumpvars(0, dut.s0_y2_r);
        $dumpvars(0, dut.s1_y1_r);
        $dumpvars(0, dut.s1_y2_r);
        $dumpvars(0, dut.o_s0_data);
        $dumpvars(0, dut.o_s1_data);
    end

    // Console trace per output sample.
    always @(posedge clk) begin
        if (!rst && o_valid && (trace_lines < MaxTraceLines)) begin
            real in_r, out_r;
            // i_data is Q3.24 -> real; o_data is the fnorm_t result reinterpreted
            // as fixed_t (same 27-bit width, different scale). Treat as Q3.24
            // for display consistency (/ 2^24).
            in_r  = real'($signed(i_data))  / real'(1 << 24);
            out_r = real'($signed(o_data[0])) / real'(1 << 24);
            $display("t=%0t ns  n=%0d  in=%8.5f  y=%8.5f",
                     $time, sample_count, in_r, out_r);
            trace_lines <= trace_lines + 1;
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
