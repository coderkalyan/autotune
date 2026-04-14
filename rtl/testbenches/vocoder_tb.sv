`timescale 1ns / 1ps
`include "../fixed.sv"

module vocoder_tb;
    // -------------------------
    // Clocking
    // -------------------------
    localparam int ClkHz      = 50000000;
    localparam int SampleHz   = 48000;
    localparam int ClkPeriod  = 20; // ns (50 MHz)

    // 50e6 / 48e3 = 1041.666... cycles/sample
    localparam int BaseCycles = ClkHz / SampleHz; // 1041
    localparam int RemCycles  = ClkHz % SampleHz; // 32000

    localparam int NSamples   = 2000; // ~41.7 ms at 48 kHz

    logic   clk;
    logic   rst;
    logic   i_valid;

    fixed_t o_data;
    audio_t o_raw;
    logic   o_valid;

    vocoder dut (.*);

    // 50 MHz clock
    initial begin
        clk = 1'b0;
        forever #(ClkPeriod / 2) clk = ~clk;
    end

    // Synchronous reset
    initial begin
        rst     = 1'b1;
        i_valid = 1'b0;
        repeat (10) @(posedge clk);
        rst <= 1'b0;
    end

    // -------------------------
    // 48 kHz i_valid pulse generator (1-cycle wide)
    // Uses a BASE/BASE+1 cycle dither so the long-term average is exact.
    // -------------------------
    int unsigned cycles_left;
    int unsigned frac_accum;
    int unsigned sample_count;

    always @(posedge clk) begin
        if (rst) begin
            i_valid      <= 1'b0;
            cycles_left  <= 0;
            frac_accum   <= 0;
            sample_count <= 0;
        end else begin
            if (sample_count >= NSamples) begin
                i_valid <= 1'b0;
            end else if (cycles_left == 0) begin
                int unsigned period_cycles;
                int unsigned next_frac;

                // Pulse i_valid for exactly one clk
                i_valid <= 1'b1;

                // Choose next period length
                period_cycles = BaseCycles;
                next_frac     = frac_accum + RemCycles;
                if (next_frac >= SampleHz) begin
                    next_frac     = next_frac - SampleHz;
                    period_cycles = BaseCycles + 1;
                end

                frac_accum <= next_frac;

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
        $dumpfile("vocoder_tb.vcd");
        // Dump only the slow-changing signals (avoid dumping clk to keep VCD small)
        $dumpvars(0, rst);
        $dumpvars(0, i_valid);
        $dumpvars(0, o_valid);
        $dumpvars(0, o_raw);
        $dumpvars(0, o_data);
        $dumpvars(0, dut.idx);

        // Helpful reminder about the ROM file lookup
        $display("NOTE: vocoder loads sawtooth.mem relative to the simulator working directory.");
        $display("      Run simulation from rtl/ (where sawtooth.mem exists)");
        $display("      or copy it into your sim working directory.");
    end

    // Print one line per output sample
    always @(posedge clk) begin
        #1;
        if (!rst && o_valid) begin
            $display(
                "t=%0t ns  sample=%0d  idx=%0d  o_raw=%0d  o_data=0x%07h",
                $time, sample_count, dut.idx, o_raw, o_data
            );
        end
    end

    // End sim after samples are produced
    initial begin
        wait (!rst);
        wait (sample_count >= NSamples);
        repeat (50) @(posedge clk);
        $finish;
    end

endmodule
