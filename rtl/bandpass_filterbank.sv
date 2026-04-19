`timescale 1ns / 1ps

`include "fixed.sv"

// Time-multiplexed bandpass filterbank with optional per-band asymmetric
// envelope follower.
//
// BANKS      = number of independent filter state banks.
// COEF_BANKS = number of coefficient sets available in ROM. Must be <= BANKS.
//              When BANKS > COEF_BANKS, the low $clog2(COEF_BANKS) bits of the
//              bank index select the coefficient set (so bank N and bank
//              N+COEF_BANKS share coefficients but have independent state).
//              This lets the vocoder share the same coef ROMs for voice and
//              carrier paths while keeping their histories separate.
//
// On each i_valid pulse the module processes banks in [i_bank_start,
// i_bank_end] one per clock. When i_asym_follow is asserted, each band's
// filter output is rectified and fed through a shared asym_follow pipeline
// (2-cycle latency) so o_data carries the amplitude envelope. When 0,
// o_data carries the raw filter output (suitable for the vocoder carrier
// path).
module bandpass_filterbank #(
    parameter int BANKS      = 32,
    parameter int COEF_BANKS = BANKS,
    parameter int BBITS      = $clog2(BANKS),
    parameter int CBITS      = $clog2(COEF_BANKS)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  fixed_t               i_data,
    input  wire                  i_valid,
    input  wire                  i_asym_follow,
    input  wire    [BBITS - 1:0] i_bank_start,
    input  wire    [BBITS - 1:0] i_bank_end,
    output fnorm_t               o_data       [BANKS],
    output wire                  o_valid
);
    // Port interface matches the legacy bandpass_sosfilt_bank (fixed_t in,
    // fnorm_t out); internal math is Q3.24. Reinterpret i_data bits as
    // fnorm_t — scale is not compensated, this path is used only to test the
    // filter + UART plumbing, not real audio amplitude.
    fnorm_t i_data_f;
    assign i_data_f = fnorm_t'(i_data);

    // Coefficient ROMs (one entry per coef bank).
    logic [31:0] B0 [COEF_BANKS], B1 [COEF_BANKS], A1 [COEF_BANKS], A2 [COEF_BANKS];
    logic [31:0] C0 [COEF_BANKS], C1 [COEF_BANKS], D1 [COEF_BANKS], D2 [COEF_BANKS];
    initial begin
        $readmemh("vocoder_bp_s0_b0.mem", B0);
        $readmemh("vocoder_bp_s0_b1.mem", B1);
        $readmemh("vocoder_bp_s0_a1.mem", A1);
        $readmemh("vocoder_bp_s0_a2.mem", A2);
        $readmemh("vocoder_bp_s1_b0.mem", C0);
        $readmemh("vocoder_bp_s1_b1.mem", C1);
        $readmemh("vocoder_bp_s1_a1.mem", D1);
        $readmemh("vocoder_bp_s1_a2.mem", D2);
    end

    // ------------------------------------------------------------------
    // Per-bank state
    // ------------------------------------------------------------------
    // Sync-read banks padded to 32 bits so the tools infer BRAM. Only the
    // low 27 bits carry fnorm_t data; upper 5 bits are don't-care on write
    // and discarded on read.
    logic [31:0] x1_r    [BANKS];
    logic [31:0] x2_r    [BANKS];
    logic [31:0] s0_y1_r [BANKS];
    logic [31:0] s0_y2_r [BANKS];
    logic [31:0] s1_y1_r [BANKS];
    logic [31:0] s1_y2_r [BANKS];
    fnorm_t      o_data_r[BANKS];

    // ------------------------------------------------------------------
    // Time-mux controller
    // ------------------------------------------------------------------
    logic                busy;
    logic [BBITS - 1:0]  bank_cnt;
    logic [BBITS - 1:0]  end_reg;
    logic                asym_en_reg;
    fnorm_t              x_latched;
    logic                o_valid_r;

    wire [CBITS - 1:0] coef_idx = bank_cnt[CBITS - 1:0];

    // Coefficient muxes for this bank.
    fnorm_t i_s0_b0, i_s0_b1, i_s0_a1, i_s0_a2;
    fnorm_t i_s1_b0, i_s1_b1, i_s1_a1, i_s1_a2;
    assign i_s0_b0 = fnorm_t'(B0[coef_idx][26:0]);
    assign i_s0_b1 = fnorm_t'(B1[coef_idx][26:0]);
    assign i_s0_a1 = fnorm_t'(A1[coef_idx][26:0]);
    assign i_s0_a2 = fnorm_t'(A2[coef_idx][26:0]);
    assign i_s1_b0 = fnorm_t'(C0[coef_idx][26:0]);
    assign i_s1_b1 = fnorm_t'(C1[coef_idx][26:0]);
    assign i_s1_a1 = fnorm_t'(D1[coef_idx][26:0]);
    assign i_s1_a2 = fnorm_t'(D2[coef_idx][26:0]);

    // Per-bank state read with 1-cycle synchronous latency. Read address
    // leads bank_cnt by 1 cycle so the registered result is ready on the
    // cycle the biquad consumes it — no valid pipeline needed.
    logic [BBITS - 1:0] rd_addr;
    always_comb begin
        if (!busy && i_valid) rd_addr = i_bank_start;
        else                  rd_addr = bank_cnt + 1'b1;
    end

    fnorm_t cur_x1, cur_x2;
    fnorm_t cur_s0_y1, cur_s0_y2, cur_s1_y1, cur_s1_y2;
    always_ff @(posedge clk) begin
        cur_x1    <= fnorm_t'(x1_r   [rd_addr][26:0]);
        cur_x2    <= fnorm_t'(x2_r   [rd_addr][26:0]);
        cur_s0_y1 <= fnorm_t'(s0_y1_r[rd_addr][26:0]);
        cur_s0_y2 <= fnorm_t'(s0_y2_r[rd_addr][26:0]);
        cur_s1_y1 <= fnorm_t'(s1_y1_r[rd_addr][26:0]);
        cur_s1_y2 <= fnorm_t'(s1_y2_r[rd_addr][26:0]);
    end

    fnorm_t o_s0_data, o_s1_data;
    bandpass_biquad u_biquad (
        .i_x0     (x_latched),
        .i_x1     (cur_x1),
        .i_x2     (cur_x2),
        .i_x3     ('0),
        .i_x4     ('0),
        .i_x5     ('0),
        .i_s0_y1  (cur_s0_y1),
        .i_s0_y2  (cur_s0_y2),
        .i_s1_y1  (cur_s1_y1),
        .i_s1_y2  (cur_s1_y2),
        .i_s0_b0  (i_s0_b0),
        .i_s0_b1  (i_s0_b1),
        .i_s0_a1  (i_s0_a1),
        .i_s0_a2  (i_s0_a2),
        .i_s1_b0  (i_s1_b0),
        .i_s1_b1  (i_s1_b1),
        .i_s1_a1  (i_s1_a1),
        .i_s1_a2  (i_s1_a2),
        .o_s0_data(o_s0_data),
        .o_s1_data(o_s1_data)
    );

    // ------------------------------------------------------------------
    // Rectify filter output and run through asymmetric follower. The
    // follower keeps its own per-bank state and has a 2-cycle latency.
    // ------------------------------------------------------------------
    fnorm_t abs_filter_out;
    always_comb begin
        if (o_s1_data[26])
            abs_filter_out = fnorm_t'(-$signed(o_s1_data));
        else
            abs_filter_out = o_s1_data;
    end

    fnorm_t asym_o_data;
    logic   asym_o_valid;
    asym_follow #(
        .BANKS(BANKS)
    ) u_asym (
        .clk    (clk),
        .rst    (rst),
        .i_data (abs_filter_out),
        .i_valid(busy),
        .i_bank (bank_cnt),
        .o_data (asym_o_data),
        .o_valid(asym_o_valid)
    );

    // Pipeline bank index to align with asym_follow's 2-cycle latency so
    // the envelope write lands in the right bank slot.
    logic [BBITS - 1:0] bank_d1, bank_d2;
    always_ff @(posedge clk) begin
        if (rst) begin
            bank_d1 <= '0;
            bank_d2 <= '0;
        end else begin
            bank_d1 <= bank_cnt;
            bank_d2 <= bank_d1;
        end
    end

    // ------------------------------------------------------------------
    // Main control / state writeback
    // ------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            busy        <= 1'b0;
            bank_cnt    <= '0;
            end_reg     <= '0;
            asym_en_reg <= 1'b0;
            x_latched   <= '0;
            o_valid_r   <= 1'b0;
            // Per-bank biquad state arrays intentionally not reset so the
            // tools can infer BRAM for them. Stale values wash out after
            // one filter pass.
            for (int i = 0; i < BANKS; i++) begin
                o_data_r[i] <= '0;
            end
        end else begin
            o_valid_r <= 1'b0;

            if (!busy && i_valid) begin
                x_latched   <= i_data_f;
                bank_cnt    <= i_bank_start;
                end_reg     <= i_bank_end;
                asym_en_reg <= i_asym_follow;
                busy        <= 1'b1;
            end else if (busy) begin
                // Advance biquad state for the current bank.
                x1_r[bank_cnt]     <= {5'b0, x_latched};
                x2_r[bank_cnt]     <= {5'b0, cur_x1};
                s0_y1_r[bank_cnt]  <= {5'b0, o_s0_data};
                s0_y2_r[bank_cnt]  <= {5'b0, cur_s0_y1};
                s1_y1_r[bank_cnt]  <= {5'b0, o_s1_data};
                s1_y2_r[bank_cnt]  <= {5'b0, cur_s1_y1};

                // If asym disabled, commit raw filter output directly and
                // raise o_valid the cycle after the last bank.
                if (!asym_en_reg) begin
                    o_data_r[bank_cnt] <= o_s1_data;
                end

                if (bank_cnt == end_reg) begin
                    busy <= 1'b0;
                    if (!asym_en_reg) o_valid_r <= 1'b1;
                end else begin
                    bank_cnt <= bank_cnt + 1'b1;
                end
            end

            // Envelope writeback (2 cycles behind biquad pipeline). Runs
            // unconditionally — when asym_en_reg is 0 the value is
            // ignored, but we gate the visible o_data_r update to avoid
            // overwriting the raw filter output path.
            if (asym_en_reg && asym_o_valid) begin
                o_data_r[bank_d2] <= asym_o_data;
                if (bank_d2 == end_reg) o_valid_r <= 1'b1;
            end
        end
    end

    assign o_valid = o_valid_r;

    genvar bk;
    generate
        for (bk = 0; bk < BANKS; bk++) begin : gen_outputs
            assign o_data[bk] = o_data_r[bk];
        end
    endgenerate
endmodule
