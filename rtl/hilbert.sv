`include "fixed.sv"

// 63-tap FIR Hilbert transformer, time-multiplexed over 32 clock cycles.
//
// Only the 32 non-zero (even absolute-index) taps are computed; odd-index
// taps are identically zero for a Type-III Hilbert FIR.
//
// Outputs (asserted together on o_valid):
//   o_hilbert — Hilbert-transformed signal (≈ 90° phase shift)
//   o_delayed — input delayed by CENTER=31 samples (matching group delay)
//
// Latency: 33 clock cycles from i_valid to o_valid.
// The module processes one sample at a time; assert i_valid only when idle
// (i.e. after the previous o_valid, or before the first sample).
module hilbert (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    output fixed_t o_hilbert,
    output fixed_t o_delayed,
    output logic   o_valid
);
    localparam int NTAPS   = 63;
    localparam int NCOEFFS = 32;   // non-zero taps: h[0], h[2], ..., h[62]
    localparam int CENTER  = 31;   // group delay in samples

    // Pre-computed address offsets (kept as localparams for readability)
    localparam int DEL_OFFSET   = NTAPS - CENTER;   // = 32
    localparam int RD_STEP_BACK = NTAPS - 2;        // = 61  (subtract 2, wrap mod 63)

    // ----------------------------------------------------------------
    // Circular input sample buffer
    // ----------------------------------------------------------------
    fixed_t     buf_mem[NTAPS];
    logic [5:0] wptr;           // next write position, 0..62

    always_ff @(posedge clk) begin
        if (rst) begin
            wptr <= '0;
        end else if (i_valid) begin
            buf_mem[wptr] <= i_data;
            wptr <= (wptr == 6'(NTAPS - 1)) ? '0 : wptr + 6'd1;
        end
    end

    // ----------------------------------------------------------------
    // Coefficient ROM: coeffs[k] = h[2k] for k = 0..31
    // Loaded from hilbert.mem (32-bit hex entries, lower 27 bits = fixed_t)
    // ----------------------------------------------------------------
    logic [31:0] coeff_rom[NCOEFFS];
    initial $readmemh("hilbert.mem", coeff_rom);

    // ----------------------------------------------------------------
    // Delayed-sample address: the sample written CENTER positions ago.
    //   wptr points to the *next* write slot, so slot (wptr - CENTER)
    //   holds the sample from CENTER i_valid pulses ago.
    //   Equivalent: (wptr + DEL_OFFSET) % NTAPS.
    // ----------------------------------------------------------------
    logic [5:0] del_addr;
    always_comb
        del_addr = (wptr >= 6'(CENTER)) ? (wptr - 6'(CENTER))
                                        : (wptr + 6'(DEL_OFFSET));

    // ----------------------------------------------------------------
    // Time-multiplexed MAC state machine
    // ----------------------------------------------------------------
    typedef enum logic [1:0] { IDLE, MAC, FINISH } state_t;
    state_t state;

    logic [4:0] mac_cnt;       // 0..31
    logic [5:0] rd_ptr;        // read address into buf_mem, steps by -2 mod NTAPS
    fixed_t     acc;
    fixed_t     delayed_hold;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            o_valid <= 1'b0;
        end else begin
            o_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (i_valid) begin
                        // Latch the sample from CENTER positions ago.
                        // buf_mem[wptr] is being written this cycle (non-blocking),
                        // so del_addr (≠ wptr for CENTER>0) still holds the old value. ✓
                        delayed_hold <= buf_mem[del_addr];
                        acc          <= '0;
                        mac_cnt      <= '0;
                        // rd_ptr starts at wptr (tap-0 = current sample).
                        // The write buf_mem[wptr]<=i_data commits this cycle, so
                        // the first MAC read (next cycle) sees the fresh sample. ✓
                        rd_ptr       <= wptr;
                        state        <= MAC;
                    end
                end

                MAC: begin
                    acc     <= acc + fixed_mul(fixed_t'(coeff_rom[mac_cnt][26:0]),
                                              buf_mem[rd_ptr]);
                    // Advance rd_ptr backwards by 2 (mod NTAPS = 63)
                    rd_ptr  <= (rd_ptr >= 6'd2) ? (rd_ptr - 6'd2)
                                                : (rd_ptr + 6'(RD_STEP_BACK));
                    mac_cnt <= mac_cnt + 5'd1;
                    if (mac_cnt == 5'(NCOEFFS - 1)) state <= FINISH;
                end

                FINISH: begin
                    // acc now holds the completed 32-term dot product
                    o_hilbert <= acc;
                    o_delayed <= delayed_hold;
                    o_valid   <= 1'b1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
