`timescale 1ns / 1ps

`include "fixed.sv"

// Time-multiplexed bandpass filterbank.
//
// BANKS  = number of coefficient sets / independent filters.
// UNITS  = number of runtime "workers" (default 1) that iterate through BANKS.
//
// On each input sample strobe (i_valid), the module latches i_data and then
// spends ceil(BANKS/UNITS) clock cycles updating all BANKS filters for that
// sample. When finished, it pulses o_valid for 1 cycle.
//
// Coefficients are specified as `real` parameter tables for easy paste-in, and
// are converted to fixed_t (Q11.16) at compile time.
module bandpass_sosfilt_bank #(
    parameter int BANKS = 1,
    parameter int UNITS = 1,
    parameter bit ASYM_FOLLOW = 1'b0,

    // Stage 0 coefficients (x -> w)
    parameter real B0Table[BANKS] = '{default: 0.0},
    parameter real B1Table[BANKS] = '{default: 0.0},
    parameter real B2Table[BANKS] = '{default: 0.0},
    parameter real A1Table[BANKS] = '{default: 0.0},
    parameter real A2Table[BANKS] = '{default: 0.0},

    // Stage 1 coefficients (w -> y)
    parameter real C0Table[BANKS] = '{default: 0.0},
    parameter real C1Table[BANKS] = '{default: 0.0},
    parameter real C2Table[BANKS] = '{default: 0.0},
    parameter real D1Table[BANKS] = '{default: 0.0},
    parameter real D2Table[BANKS] = '{default: 0.0}
) (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    output fixed_t o_data [BANKS],
    output wire    o_valid
);
    localparam int BANKW = (BANKS <= 1) ? 1 : $clog2(BANKS);

    // ----------------------------------------------------------------
    // Compile-time fixed-point coefficient tables
    // ----------------------------------------------------------------
    wire fixed_t FB0[BANKS];
    wire fixed_t FB1[BANKS];
    wire fixed_t FB2[BANKS];
    wire fixed_t FA1[BANKS];
    wire fixed_t FA2[BANKS];

    wire fixed_t FC0[BANKS];
    wire fixed_t FC1[BANKS];
    wire fixed_t FC2[BANKS];
    wire fixed_t FD1[BANKS];
    wire fixed_t FD2[BANKS];

    genvar c;
    generate
        for (c = 0; c < BANKS; c++) begin : gen_coeff
            assign FB0[c] = `FIXED_RTOF(B0Table[c]);
            assign FB1[c] = `FIXED_RTOF(B1Table[c]);
            assign FB2[c] = `FIXED_RTOF(B2Table[c]);
            assign FA1[c] = `FIXED_RTOF(A1Table[c]);
            assign FA2[c] = `FIXED_RTOF(A2Table[c]);

            assign FC0[c] = `FIXED_RTOF(C0Table[c]);
            assign FC1[c] = `FIXED_RTOF(C1Table[c]);
            assign FC2[c] = `FIXED_RTOF(C2Table[c]);
            assign FD1[c] = `FIXED_RTOF(D1Table[c]);
            assign FD2[c] = `FIXED_RTOF(D2Table[c]);
        end
    endgenerate

    // (Optional) asymmetric envelope follower(s) are applied AFTER the bandpass
    // filter outputs, not on the raw input.

    // ----------------------------------------------------------------
    // Control: one-bank-at-a-time sequencing
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        WAITING,
        CALCULATING,
        DONE
    } state_t;
    state_t             state;

    fixed_t             x_hold;
    logic   [BANKW-1:0] bank_idx;
    logic               inflight;

    // Selected coefficients for current bank
    fixed_t i_b0, i_b1, i_b2, i_a1, i_a2;
    fixed_t i_c0, i_c1, i_c2, i_d1, i_d2;

    always_comb begin
        // Default: select by index (synthesizes to a mux)
        i_b0 = FB0[bank_idx];
        i_b1 = FB1[bank_idx];
        i_b2 = FB2[bank_idx];
        i_a1 = FA1[bank_idx];
        i_a2 = FA2[bank_idx];

        i_c0 = FC0[bank_idx];
        i_c1 = FC1[bank_idx];
        i_c2 = FC2[bank_idx];
        i_d1 = FD1[bank_idx];
        i_d2 = FD2[bank_idx];
    end

    // ----------------------------------------------------------------
    // Single shared filter instance (internal state is banked by i_bank)
    // ----------------------------------------------------------------
    logic   filt_i_valid;
    fixed_t filt_o_data;
    logic   filt_o_valid;

    bandpass_sosfilt #(
        .BANKS (BANKS),
        .BANK_W(BANKW)
    ) u_bandpass_sosfilt (
        .clk    (clk),
        .rst    (rst),
        .i_data (x_hold),
        .i_valid(filt_i_valid),
        .i_bank (bank_idx),
        .i_b0   (i_b0),
        .i_b1   (i_b1),
        .i_b2   (i_b2),
        .i_a1   (i_a1),
        .i_a2   (i_a2),
        .i_c0   (i_c0),
        .i_c1   (i_c1),
        .i_c2   (i_c2),
        .i_d1   (i_d1),
        .i_d2   (i_d2),
        .o_data (filt_o_data),
        .o_valid(filt_o_valid)
    );

    // ----------------------------------------------------------------
    // Optional post-processing: time-multiplexed asymmetric follower
    // (single datapath, banked internal state selected by i_bank)
    // ----------------------------------------------------------------
    wire fixed_t post_o_data;
    wire         post_o_valid;

    wire fixed_t asym_o_data;
    wire         asym_o_valid;

    generate
        if (ASYM_FOLLOW) begin : gen_asym_follow
            asym_follow #(
                .BANKS  (BANKS),
                .BANK_W (BANKW)
            ) u_asym_follow (
                .clk     (clk),
                .rst     (rst),
                .i_data  (filt_o_data),
                .i_valid (filt_o_valid),
                .i_bank  (bank_idx),
                .o_data  (asym_o_data),
                .o_valid (asym_o_valid)
            );

            assign post_o_data  = asym_o_data;
            assign post_o_valid = asym_o_valid;
        end else begin : gen_no_asym_follow
            assign asym_o_data   = '0;
            assign asym_o_valid  = 1'b0;
            assign post_o_data   = filt_o_data;
            assign post_o_valid  = filt_o_valid;
        end
    endgenerate

    // ----------------------------------------------------------------
    // FSM: WAITING -> CALCULATING (iterate banks) -> DONE (1-cycle pulse)
    // Assumes i_valid only asserted when idle (WAITING).
    // ----------------------------------------------------------------
    logic o_valid_r;
    assign o_valid = o_valid_r;

    integer ob;
    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= WAITING;
            o_valid_r    <= 1'b0;
            filt_i_valid <= 1'b0;
            x_hold       <= '0;
            bank_idx     <= '0;
            inflight     <= 1'b0;
            for (ob = 0; ob < BANKS; ob++) begin
                o_data[ob] <= '0;
            end
        end else begin
            // defaults (single-cycle pulses)
            o_valid_r    <= 1'b0;
            filt_i_valid <= 1'b0;

            case (state)
                WAITING: begin
                    inflight <= 1'b0;
                    if (i_valid) begin
                        x_hold   <= i_data;
                        bank_idx <= '0;
                        state    <= CALCULATING;
                    end
                end

                CALCULATING: begin
                    // Kick the current bank once, then wait for its output.
                    if (!inflight) begin
                        filt_i_valid <= 1'b1;
                        inflight     <= 1'b1;
                    end else if (post_o_valid) begin
                        o_data[bank_idx] <= post_o_data;
                        inflight         <= 1'b0;

                        if (bank_idx == (BANKS - 1)) begin
                            state <= DONE;
                        end else begin
                            bank_idx <= bank_idx + 1;
                        end
                    end
                end

                DONE: begin
                    o_valid_r <= 1'b1;
                    state     <= WAITING;
                end

                default: state <= WAITING;
            endcase
        end
    end

endmodule
