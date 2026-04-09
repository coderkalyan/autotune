`include "fixed.sv"

// Single-sideband (USB) modulator using a Hilbert-filter approach.
//
// SSB formula (upper sideband):
//   out[n] = x_delayed[n] * cos(phi[n]) - x_hilbert[n] * sin(phi[n])
//
// where x_delayed is the input delayed by 31 samples (Hilbert group delay)
// and x_hilbert is the Hilbert-transformed input.
//
// The carrier NCO runs free at 50 MHz and is latched at each i_valid so
// that the same phase is used when the Hilbert filter result is ready
// (~33 clock cycles later, well within one 48 kHz audio period).
//
// Output latency: 34 clock cycles after i_valid.
// Input frequencies must be in the Hilbert passband: [0.05, 0.45] * FS
// i.e. roughly 2.4 kHz – 21.6 kHz at 48 kHz.
module ssb (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    output fixed_t o_data,
    output logic   o_valid
);
    // ----------------------------------------------------------------
    // Free-running 50 MHz NCO
    // ----------------------------------------------------------------
    localparam real F0        = 440.0;
    localparam real FC        = 50.0e6;
    localparam real NCO_SCALE = 2.0 ** 28;
    localparam logic [27:0] INCREMENT = F0 * NCO_SCALE / FC;

    logic [27:0] phi;
    always_ff @(posedge clk) begin
        if (rst) phi <= '0;
        else     phi <= phi + INCREMENT;
    end

    // Latch the top 12 bits of phi (LUT address) at every audio sample.
    // phi_latch stays stable from i_valid until hil_valid (~33 cycles << one
    // audio period at 48 kHz ≈ 1041 cycles).
    logic [11:0] phi_latch;
    always_ff @(posedge clk) begin
        if (i_valid) phi_latch <= phi[27 -: 12];
    end

    // ----------------------------------------------------------------
    // Carrier sin and cos from the same 4096-entry table.
    // cos(x) = sin(x + π/2) = sin(x + 1024 table entries).
    // The sine module is combinational, so sin_val/cos_val update
    // immediately when phi_latch changes.
    // ----------------------------------------------------------------
    fixed_t sin_val, cos_val;
    sine #(.N(4096)) sin_lut (
        .clk    (clk),
        .rst    (rst),
        .i_index(phi_latch),
        .o_data (sin_val)
    );
    sine #(.N(4096)) cos_lut (
        .clk    (clk),
        .rst    (rst),
        .i_index(phi_latch + 12'd1024),
        .o_data (cos_val)
    );

    // ----------------------------------------------------------------
    // Hilbert FIR filter
    // ----------------------------------------------------------------
    fixed_t hil_hilbert, hil_delayed;
    logic   hil_valid;
    hilbert hilbert_inst (
        .clk      (clk),
        .rst      (rst),
        .i_data   (i_data),
        .i_valid  (i_valid),
        .o_hilbert(hil_hilbert),
        .o_delayed(hil_delayed),
        .o_valid  (hil_valid)
    );

    // ----------------------------------------------------------------
    // USB SSB output: delayed * cos - hilbert * sin
    // ----------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            o_valid <= 1'b0;
        end else begin
            o_valid <= hil_valid;
            if (hil_valid)
                o_data <= fixed_mul(hil_delayed, fixed_mul(cos_val, `FIXED_RTOF(500.0)))
                        - fixed_mul(hil_hilbert, fixed_mul(sin_val, `FIXED_RTOF(500.0)));
        end
    end

endmodule
