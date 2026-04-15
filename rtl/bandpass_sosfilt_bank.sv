`timescale 1ns / 1ps

`include "fixed.sv"

// Time-multiplexed bandpass filterbank.
//
// BANKS  = number of coefficient sets / independent filters.
//
// On each input sample strobe (i_valid), the module latches i_data and then
// spends BANKS clock cycles updating all BANKS filters for that
// sample. When finished, it pulses o_valid for 1 cycle.
//
// Coefficients are specified as pre-computed Q11.16 fixed_t parameter tables.
// Use py/gen_bandpass_coeffs.py to convert from floating-point.
module bandpass_sosfilt_bank #(
    parameter int BANKS = 1,
    parameter int BBITS = $clog2(BANKS),

    // Stage 0 coefficients (x -> w)
    parameter fixed_t B0Table[BANKS] = '{default: '0},
    parameter fixed_t B1Table[BANKS] = '{default: '0},
    parameter fixed_t B2Table[BANKS] = '{default: '0},
    parameter fixed_t A1Table[BANKS] = '{default: '0},
    parameter fixed_t A2Table[BANKS] = '{default: '0},

    // Stage 1 coefficients (w -> y)
    parameter fixed_t C0Table[BANKS] = '{default: '0},
    parameter fixed_t C1Table[BANKS] = '{default: '0},
    parameter fixed_t C2Table[BANKS] = '{default: '0},
    parameter fixed_t D1Table[BANKS] = '{default: '0},
    parameter fixed_t D2Table[BANKS] = '{default: '0}
) (
    input  wire                  clk,
    input  wire                  rst,
    input  fixed_t               i_data,
    input  wire                  i_valid,
    input  wire                  i_asym_follow,
    input  wire    [BBITS - 1:0] i_bank_start,
    input  wire    [BBITS - 1:0] i_bank_end,
    output fixed_t               o_data       [BANKS],
    output wire                  o_valid
);
  localparam int BANKW = (BANKS <= 1) ? 1 : $clog2(BANKS);

  // Coefficient tables are passed as pre-computed fixed_t values,
  // used directly via B0Table[idx] etc. below.

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
    i_b0 = B0Table[bank_idx];
    i_b1 = B1Table[bank_idx];
    i_b2 = B2Table[bank_idx];
    i_a1 = A1Table[bank_idx];
    i_a2 = A2Table[bank_idx];

    i_c0 = C0Table[bank_idx];
    i_c1 = C1Table[bank_idx];
    i_c2 = C2Table[bank_idx];
    i_d1 = D1Table[bank_idx];
    i_d2 = D2Table[bank_idx];
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
  fixed_t post_o_data;
  wire    post_o_valid;

  fixed_t asym_o_data;
  wire    asym_o_valid;

  // generate
  //     if (ASYM_FOLLOW) begin : gen_asym_follow
  //         asym_follow #(
  //             .BANKS  (BANKS),
  //             .BANK_W (BANKW)
  //         ) u_asym_follow (
  //             .clk     (clk),
  //             .rst     (rst),
  //             .i_data  (filt_o_data),
  //             .i_valid (filt_o_valid),
  //             .i_bank  (bank_idx),
  //             .o_data  (asym_o_data),
  //             .o_valid (asym_o_valid)
  //         );
  //
  //         assign post_o_data  = asym_o_data;
  //         assign post_o_valid = asym_o_valid;
  //     end else begin : gen_no_asym_follow
  //         assign asym_o_data   = '0;
  //         assign asym_o_valid  = 1'b0;
  //         assign post_o_data   = filt_o_data;
  //         assign post_o_valid  = filt_o_valid;
  //     end
  // endgenerate

  asym_follow #(
      .BANKS (BANKS),
      .BANK_W(BANKW)
  ) u_asym_follow (
      .clk    (clk),
      .rst    (rst),
      .i_data (fixed_abs(filt_o_data)),
      .i_valid(filt_o_valid),
      .i_bank (bank_idx),
      .o_data (asym_o_data),
      .o_valid(asym_o_valid)
  );

  always_comb begin
    if (i_asym_follow) begin
      post_o_data  = asym_o_data;
      post_o_valid = asym_o_valid;
    end else begin
      post_o_data  = filt_o_data;
      post_o_valid = filt_o_valid;
    end
  end

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
            bank_idx <= i_bank_start;
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

            if (bank_idx == i_bank_end) begin
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
