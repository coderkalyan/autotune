`timescale 1ns / 1ps
`include "../fixed.sv"

// Integration smoke-test for vocoder's internal bandpass_filterbank via
// band 0. Stimulus mirrors bandpass_filterbank_tb: 48 kHz sine, first half
// in-band (315 Hz, inside 300-332 Hz), second half out-of-band (5 kHz).
//
// Expected: o_vocode_bands[0] shows the same passband/stopband behavior
// observed in the direct filter TB — passband ringing up to ~unity, then
// decaying to near-zero once the stimulus switches out of band.
//
// Notes:
// - i_notes is driven to 0 so carrier synth contributes nothing and the
//   FSM still advances through its states; only the voice bandpass path
//   (bank 0) is being observed here.
// - vocoder uses fixed_t i_data while the filter is internally fnorm_t
//   (same 27-bit width, reinterpreted). To produce the same bit pattern
//   as the direct TB we scale sin() by 0.5 * 2^24.
module vocoder_band0_tb;
    // -------------------------
    // Clocking / sample timing
    // -------------------------
    localparam int ClkHz     = 50_000_000;
    localparam int SampleHz  = 48_000;
    localparam int ClkPeriod = 20;  // ns => 50 MHz

    // 50e6 / 48e3 = 1041.666... cycles/sample
    localparam int BaseCycles = ClkHz / SampleHz;  // 1041
    localparam int RemCycles  = ClkHz % SampleHz;  // 32000

    localparam int NSamplesHalf  = 7200;           // 150 ms per frequency
    localparam int NSamples      = NSamplesHalf * 2;
    localparam int TailCycles    = 4000;
    localparam int MaxTraceLines = 2 * NSamples;
    localparam int MaxSimCycles  = (NSamples * (BaseCycles + 2)) + TailCycles + 50000;

    localparam real FreqInBand  = 440.0;
    localparam real FreqOutBand = 10000.0;

    // -------------------------
    // DUT I/O
    // -------------------------
    logic           clk;
    logic           rst;
    fixed_t         i_data;
    logic           i_valid;
    logic [127:0]   i_notes;
    fixed_t         vocoder_o_data;
    fnorm_t         vocode_bands[32];
    logic           vocoder_o_valid;

    vocoder dut (
        .clk           (clk),
        .rst           (rst),
        .i_valid       (i_valid),
        .i_data        (i_data),
        .i_notes       (i_notes),
        .o_data        (vocoder_o_data),
        .o_vocode_bands(vocode_bands),
        .o_valid       (vocoder_o_valid)
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
        i_notes = 128'd1 << 69;     // no notes pressed => carrier synth contributes 0
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    // -------------------------
    // 48 kHz i_valid + sine sample generator
    // First half: 315 Hz (in-band). Second half: 5 kHz (out-of-band).
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
                    sample_count, cycles_left, vocoder_o_valid);
            end

            if (sample_count >= NSamples) begin
                i_valid <= 1'b0;
            end else if (cycles_left == 0) begin
                int unsigned period_cycles;
                int unsigned next_frac;

                freq_hz = (sample_count < NSamplesHalf) ? FreqInBand : FreqOutBand;

                sine_real = $sin(2.0 * 3.14159265358979 * freq_hz *
                                 real'(sample_count) / real'(SampleHz));
                // Same bit scaling as bandpass_filterbank_tb so the filter
                // sees identical stimulus.
                sine_q24  = int'(sine_real * 0.5 * real'(1 << 24));
                i_data    <= fixed_t'(sine_q24);

                i_valid <= 1'b1;

                if (sample_count == 0 || sample_count == NSamplesHalf) begin
                    $display("t=%0t ns  switching to freq=%0f Hz", $time, freq_hz);
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

    // -------------------------
    // Waveform dump
    // -------------------------
    initial begin
        $dumpfile("vocoder_band0_tb.vcd");
        $dumpvars(0, rst);
        $dumpvars(0, i_valid);
        $dumpvars(0, i_data);
        $dumpvars(0, vocoder_o_valid);
        $dumpvars(0, vocode_bands[0]);
        // Internal bandpass visibility
        $dumpvars(0, dut.bandpass.x1_r);
        $dumpvars(0, dut.bandpass.x2_r);
        $dumpvars(0, dut.bandpass.s0_y1_r);
        $dumpvars(0, dut.bandpass.s0_y2_r);
        $dumpvars(0, dut.bandpass.s1_y1_r);
        $dumpvars(0, dut.bandpass.s1_y2_r);
        $dumpvars(0, dut.bandpass.o_s0_data);
        $dumpvars(0, dut.bandpass.o_s1_data);
        $dumpvars(0, dut.bandpass_i_valid);
        $dumpvars(0, dut.bandpass_o_valid);
        $dumpvars(0, dut.state);
    end

    // Trace band 0 each time the vocoder's internal bandpass fires.
    always @(posedge clk) begin
        if (!rst && dut.bandpass_o_valid && (trace_lines < MaxTraceLines)) begin
            real in_r, b0_r;
            in_r = real'($signed(i_data))       / real'(1 << 24);
            b0_r = real'($signed(vocode_bands[0])) / real'(1 << 24);
            $display("t=%0t ns  n=%0d  in=%8.5f  band0=%8.5f",
                     $time, sample_count, in_r, b0_r);
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
