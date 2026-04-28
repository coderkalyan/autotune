`include "fixed.sv"

module f0_detect #(
    parameter int WINDOW_SIZE = 1024,
    parameter int LAG_MIN = 48,
    parameter int LAG_MAX = 480,
    parameter int WBITS = $clog2(WINDOW_SIZE)
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 i_start,
    input  wire                 i_valid,
    input  fmac_t               i_sample,
    output logic                o_done,
    output logic                o_valid,
    output logic  [WBITS - 1:0] o_period
);
  typedef enum logic [1:0] {
    IDLE,
    ZERO,
    BUSY,
    POST
  } state_t;

  state_t state;
  logic [WBITS - 1:0] counter, argmax;
  fmac_t max, r0;
  logic candidate;

  // Compare normalized autocorrelation:
  // i_sample / cur_overlap > max_raw / best_overlap
  // <=> i_sample * best_overlap > max_raw * cur_overlap
  // note: added biasing to prevent small lags from being over boosted

  // TODO: this currently does not take advantage of our 27 bit multiplies
  //       may want to refactor to use those block more efficiently

  logic [WBITS:0] cur_overlap, best_overlap;
  logic signed [63:0] best_score;
  localparam NORM_BIAS = 256;

  assign cur_overlap  = WINDOW_SIZE - counter;
  assign best_overlap = WINDOW_SIZE - argmax;

  // ---------------------------------------------------------------------
  // Shared-DSP multiplier (M1 + M4)
  // ---------------------------------------------------------------------
  // M1 (cur_score) only fires in BUSY; M4 (rhs) only fires in POST. Mux
  // operands by state and reuse one DSP. cur_score / rhs are aliases of
  // shared_prod — the comparison against them is state-gated, so each
  // alias is only meaningful in its own state.
  fmac_t              shared_a;
  logic [WBITS+1:0]   shared_b;      // 12-bit, always non-negative
  logic signed [63:0] shared_prod;
  always_comb begin
    if (state == POST) begin
      shared_a = $signed(r0) >>> 2;
      shared_b = {1'b0, best_overlap};
    end else begin
      shared_a = i_sample;
      shared_b = {1'b0, best_overlap} + (WBITS+2)'(NORM_BIAS);
    end
  end
  assign shared_prod = $signed(shared_a) * $signed({1'b0, shared_b});
  wire signed [63:0] cur_score = shared_prod;
  wire signed [63:0] rhs       = shared_prod;

  // M2 stays separate — runs concurrently with M1 in BUSY.
  assign best_score = $signed(max) * $signed({1'b0, cur_overlap + NORM_BIAS});

  // M3: max * WINDOW_SIZE collapses to a shift since WINDOW_SIZE is a
  // power-of-two parameter. No DSP.
  // max / (1024-lag) >= (r0 / 1024) * alpha
  // <=> max * 1024 >= (r0 * alpha) * (1024-lag)
  logic signed [63:0] lhs;
  assign lhs = 64'(signed'(max)) <<< $clog2(WINDOW_SIZE);


  wire lt = i_sample < fmac_t'(0);
  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      o_done  <= 1'b0;
      o_valid <= 1'b0;
      counter <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (i_start) begin
            state     <= ZERO;
            counter   <= '0;
            max       <= '0;
            o_done    <= 1'b0;
            o_valid   <= 1'b0;
            candidate <= 1'b0;
          end
        end

        ZERO: begin
          if (i_valid) begin
            if (counter == '0) r0 <= i_sample;

            counter <= counter + 1;

            // Check for a zero crossing before starting argmax.
            if (i_sample < fmac_t'(0))
              state <= BUSY;
          end
        end

        BUSY: begin
          if (i_valid) begin
            // Use normalized values to account for lesser overlapping samples.
            if (counter >= LAG_MIN && counter <= LAG_MAX) begin
              if (!candidate) begin
                max       <= i_sample;
                argmax    <= counter;
                candidate <= 1'b1;
              end else if (cur_score > best_score) begin
                max    <= i_sample;
                argmax <= counter;
              end
            end

            counter <= counter + 1;
            if (counter == WBITS'(WINDOW_SIZE - 1)) begin
              state <= POST;
            end
          end
        end

        POST: begin
          o_period <= argmax;
          o_done   <= 1'b1;
          //o_valid  <= candidate && (max >= (r0 >> 2));
          o_valid  <= candidate && (lhs >= rhs);
          state    <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end
endmodule
