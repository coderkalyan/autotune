// Krumhansl-Schmuckler key detector. Accumulates per-pitch-class energy from
// note_on events with exponential decay, then periodically correlates against
// 24 pre-centered K-K profiles (12 major + 12 minor) and emits a 5-bit key id
// (0..11 = C..B major, 12..23 = C..B minor) plus a confidence-gated valid bit.
//
// Single shared multiplier (one DSP slice) is time-multiplexed across decay
// and correlation passes — same idiom as rtl/hysteresis.sv. Sub-Hz event rate
// at the input means a 1-deep pending latch is sufficient (no FIFO).
//
// Profiles are pre-centered so the dot product is invariant to a constant
// offset on x[]; no per-pass mean subtraction needed.

module key_detect #(
    // ---- Time bases (50 MHz fclk) ----
    parameter int DECAY_TICK_DIV   = 50_000,    // 1 kHz decay tick
    parameter int CORR_TICK_DIV    = 1_000_000, // 50 Hz correlation tick

    // ---- Datapath widths ----
    parameter int ACC_W            = 24,
    parameter int ALPHA_W          = 16,
    parameter int PROFILE_W        = 10,
    parameter int SCORE_W          = 40,
    parameter int ACTIVITY_W       = ACC_W + 4,

    // ---- Algorithm constants ----
    parameter logic [ALPHA_W-1:0]    ALPHA           = 16'hFFEB, // ~0.9995
    parameter logic [ACTIVITY_W-1:0] ACTIVITY_THRESH = 'd2048,
    parameter logic [SCORE_W-1:0]    MARGIN_THRESH   = 'd512,
    parameter int                    DWELL_COUNT     = 4
)(
    input  logic                       clk,
    input  logic                       rst,

    input  logic                       note_on_valid,
    input  logic [6:0]                 note_on_pitch,
    input  logic [6:0]                 note_on_velocity,

    output logic [4:0]                 key_id,
    output logic                       key_valid,
    output logic signed [SCORE_W-1:0]  top_score,
    output logic signed [SCORE_W-1:0]  second_score,
    output logic [ACTIVITY_W-1:0]      activity_out,
    output logic                       corr_done_pulse
);

  // ----------------------------------------------------------------
  // Profile ROM (24 keys * 16 slots, 10-bit signed Q1.9; pad to 16 so
  // {key_id[4:0], pc[3:0]} addresses cleanly without a multiply).
  // ----------------------------------------------------------------
  logic [PROFILE_W-1:0] profile_rom [384];
  initial $readmemh("key_profile_rom.mem", profile_rom);

  // ----------------------------------------------------------------
  // PC accumulator x[12], pending event latch, activity = sum(x).
  // ----------------------------------------------------------------
  logic [ACC_W-1:0] x [12];

  // pending event (1-deep)
  logic        pend_valid;
  logic [3:0]  pend_pc;
  logic [6:0]  pend_vel;

  // activity is just the running sum of x[]; recomputed combinationally each
  // cycle. 12 24-bit adds = small adder tree, no DSP.
  logic [ACTIVITY_W-1:0] activity;
  always_comb begin
    activity = '0;
    for (int i = 0; i < 12; i++) activity += {{(ACTIVITY_W-ACC_W){1'b0}}, x[i]};
  end
  assign activity_out = activity;

  // ----------------------------------------------------------------
  // pitch_class = note_on_pitch % 12  (cascade-subtract; pitch < 128)
  // ----------------------------------------------------------------
  logic [6:0] pc_red;
  always_comb begin
    pc_red = note_on_pitch;
    if (pc_red >= 7'd96) pc_red -= 7'd96;
    if (pc_red >= 7'd48) pc_red -= 7'd48;
    if (pc_red >= 7'd24) pc_red -= 7'd24;
    if (pc_red >= 7'd12) pc_red -= 7'd12;
  end
  logic [3:0] note_pc;
  assign note_pc = pc_red[3:0];

  // ----------------------------------------------------------------
  // Tick generators
  // ----------------------------------------------------------------
  localparam int DECAY_W = $clog2(DECAY_TICK_DIV);
  localparam int CORR_W  = $clog2(CORR_TICK_DIV);

  logic [DECAY_W-1:0] decay_div;
  logic [CORR_W-1:0]  corr_div;
  logic               decay_tick, corr_tick;

  always_ff @(posedge clk) begin
    if (rst) begin
      decay_div <= '0;
      corr_div  <= '0;
    end else begin
      decay_div <= (decay_div == DECAY_W'(DECAY_TICK_DIV - 1)) ? '0 : decay_div + 1'b1;
      corr_div  <= (corr_div  == CORR_W'(CORR_TICK_DIV  - 1)) ? '0 : corr_div  + 1'b1;
    end
  end
  assign decay_tick = (decay_div == '0);
  assign corr_tick  = (corr_div  == '0);

  // ----------------------------------------------------------------
  // FSM
  // ----------------------------------------------------------------
  typedef enum logic [2:0] {
    S_IDLE, S_DECAY, S_CORR, S_ARGMAX, S_HYST
  } state_t;
  state_t state, next_state;

  // Decay walk: 14 cycles total (1 fill + 12 muls + 1 drain).
  logic [3:0] decay_step;        // 0..13

  // Correlation walk: corr_k 0..23, corr_i 0..11. Pipeline lag of 2 cycles.
  // We use a single linear counter and decode k/i from it for clarity.
  logic [8:0] corr_step;         // 0..289
  logic [4:0] corr_k;
  logic [3:0] corr_i;
  assign corr_k = corr_step[8:4]; // approximate k decoder; see corr_addr below
  assign corr_i = corr_step[3:0];
  // NOTE: actual k/i derived via separate counters to avoid the divide; see
  // corr_k_r / corr_i_r below.

  logic [4:0] corr_k_r;
  logic [3:0] corr_i_r;
  logic       corr_last_i;       // i == 11
  assign corr_last_i = (corr_i_r == 4'd11);

  logic [4:0] argmax_step;       // 0..23

  // ----------------------------------------------------------------
  // Shared multiplier — 25 b signed × 17 b signed, registered product.
  // 25 b holds zero-extended unsigned x[i] (24 b -> 25 b sign+0).
  // 17 b holds zero-extended unsigned ALPHA (16 b -> 17 b sign+0) OR
  // sign-extended profile_rom entry (10 b -> 17 b).
  // ----------------------------------------------------------------
  logic signed [24:0] mul_a;
  logic signed [16:0] mul_b;
  logic signed [41:0] mul_prod;
  always_ff @(posedge clk) mul_prod <= mul_a * mul_b;

  // Convenience views of the registered product.
  // For decay: result = (unsigned_x * unsigned_alpha) >> 16, fits in 24 b.
  wire [ACC_W-1:0] decay_result = mul_prod[16 +: ACC_W];

  // ----------------------------------------------------------------
  // Score accumulators
  // ----------------------------------------------------------------
  logic signed [SCORE_W-1:0] score_acc;
  logic signed [SCORE_W-1:0] score [24];

  // ----------------------------------------------------------------
  // Argmax tracking
  // ----------------------------------------------------------------
  logic signed [SCORE_W-1:0] top_val, second_val;
  logic [4:0] top_idx, second_idx;

  // ----------------------------------------------------------------
  // Hysteresis state
  // ----------------------------------------------------------------
  logic [4:0]                       current_key;
  logic [4:0]                       last_challenger;
  logic [$clog2(DWELL_COUNT+1)-1:0] dwell_ctr;

  // ----------------------------------------------------------------
  // Drive multiplier operands per state.
  // ----------------------------------------------------------------
  // For DECAY step s in [0,11]: mul_a = x[s], mul_b = ALPHA.
  // For CORR  step (k,i):       mul_a = x[i], mul_b = profile_rom[{k,i}] sx.
  // Outside those: zero (unused, mul_prod is don't-care).
  logic signed [16:0] alpha_sx;
  assign alpha_sx = {1'b0, ALPHA};

  logic [PROFILE_W-1:0] prof_word;
  assign prof_word = profile_rom[{corr_k_r, corr_i_r}];
  logic signed [16:0] prof_sx;
  assign prof_sx = {{(17-PROFILE_W){prof_word[PROFILE_W-1]}}, prof_word};

  always_comb begin
    mul_a = '0;
    mul_b = '0;
    case (state)
      S_DECAY: begin
        if (decay_step < 4'd12) begin
          mul_a = $signed({1'b0, x[decay_step[3:0]]});
          mul_b = alpha_sx;
        end
      end
      S_CORR: begin
        mul_a = $signed({1'b0, x[corr_i_r]});
        mul_b = prof_sx;
      end
      default: ; // mul unused
    endcase
  end

  // ----------------------------------------------------------------
  // Sequential FSM + datapath
  // ----------------------------------------------------------------
  // Pending-event tracking: a note_on can land any cycle; latch it.
  // Drain when in IDLE (x[] is otherwise idle).
  always_ff @(posedge clk) begin
    if (rst) begin
      pend_valid <= 1'b0;
      pend_pc    <= 4'd0;
      pend_vel   <= 7'd0;
    end else begin
      // capture (last write wins on collision; sub-50 Hz so unlikely)
      if (note_on_valid && note_on_velocity != 7'd0) begin
        pend_valid <= 1'b1;
        pend_pc    <= note_pc;
        pend_vel   <= note_on_velocity;
      end
      // drain in IDLE (x[] not being modified there)
      if (state == S_IDLE && pend_valid) begin
        pend_valid <= 1'b0;
      end
    end
  end

  // x[] update: ingress (in IDLE) and decay (drain phase of S_DECAY).
  // Decay write-back lags the multiply by 2 cycles: at decay_step==s, mul
  // operand was x[s-1], product latched this cycle holds x[s-2]*α,
  // available next cycle. We use decay_step counter to align: when
  // decay_step is in [2..13], decay_result corresponds to x[decay_step-2].
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < 12; i++) x[i] <= '0;
    end else begin
      if (state == S_IDLE && pend_valid) begin
        x[pend_pc] <= x[pend_pc] + {{(ACC_W-7){1'b0}}, pend_vel};
      end
      // mul_prod has 1-cycle latency: at decay_step=s, mul_prod holds the
      // product of x[s-1]*alpha. So write back to x[s-1] for s in 1..12.
      if (state == S_DECAY && decay_step >= 4'd1 && decay_step <= 4'd12) begin
        x[decay_step - 4'd1] <= decay_result;
      end
    end
  end

  // FSM next-state.
  always_comb begin
    next_state = state;
    case (state)
      S_IDLE:
        if (corr_tick)       next_state = S_CORR;     // priority
        else if (decay_tick) next_state = S_DECAY;
      S_DECAY:
        // 12 operand drives (decay_step 0..11), final writeback at step 12.
        if (decay_step == 4'd12) next_state = S_IDLE;
      S_CORR:
        // 288 operand drives (24*12), final product lands at cycle 288.
        if (corr_step == 9'(24*12)) next_state = S_ARGMAX;
      S_ARGMAX:
        if (argmax_step == 5'd23) next_state = S_HYST;
      S_HYST:
        next_state = S_IDLE;
      default: next_state = S_IDLE;
    endcase
  end

  // FSM step counters and CORR k/i.
  always_ff @(posedge clk) begin
    if (rst) begin
      state         <= S_IDLE;
      decay_step    <= '0;
      corr_step     <= '0;
      corr_k_r      <= '0;
      corr_i_r      <= '0;
      argmax_step   <= '0;
    end else begin
      state <= next_state;

      // DECAY step counter
      if (state == S_DECAY) decay_step <= decay_step + 4'd1;
      else                  decay_step <= '0;

      // CORR step + (k,i) counters
      if (state == S_CORR) begin
        corr_step <= corr_step + 9'd1;
        if (corr_i_r == 4'd11) begin
          corr_i_r <= '0;
          corr_k_r <= corr_k_r + 5'd1;
        end else begin
          corr_i_r <= corr_i_r + 4'd1;
        end
      end else if (next_state == S_CORR) begin
        // priming: drive (k=0, i=0) on the first CORR cycle
        corr_step <= '0;
        corr_k_r  <= '0;
        corr_i_r  <= '0;
      end

      // ARGMAX step
      if (state == S_ARGMAX) argmax_step <= argmax_step + 5'd1;
      else                   argmax_step <= '0;
    end
  end

  // CORR score accumulation: mul_prod has a 1-cycle latency vs the operand
  // drive. At cycle T, operand mux drives (corr_k_r, corr_i_r); at T+1,
  // mul_prod holds that product. We register a 1-cycle-delayed copy of
  // (k_r, i_r, in_corr) and use those to address score[] / control accum.
  logic [4:0] corr_k_d1;
  logic [3:0] corr_i_d1;
  logic       corr_in_d1;

  always_ff @(posedge clk) begin
    if (rst) begin
      corr_k_d1  <= '0;
      corr_i_d1  <= '0;
      corr_in_d1 <= 1'b0;
      score_acc  <= '0;
      for (int k = 0; k < 24; k++) score[k] <= '0;
    end else begin
      corr_k_d1  <= corr_k_r;
      corr_i_d1  <= corr_i_r;
      corr_in_d1 <= (state == S_CORR);

      if (corr_in_d1) begin
        // mul_prod corresponds to (k_d1, i_d1).
        if (corr_i_d1 == 4'd0) begin
          score_acc <= mul_prod[SCORE_W-1:0];
        end else begin
          score_acc <= score_acc + mul_prod[SCORE_W-1:0];
        end
        if (corr_i_d1 == 4'd11) begin
          // Commit the final dot-product for this key.
          score[corr_k_d1] <= (score_acc + mul_prod[SCORE_W-1:0]);
        end
      end
    end
  end

  // Argmax sweep
  always_ff @(posedge clk) begin
    if (rst) begin
      top_val <= '0;
      top_idx <= '0;
      second_val <= '0;
      second_idx <= '0;
    end else begin
      if (state == S_ARGMAX) begin
        if (argmax_step == 5'd0) begin
          // Initialize with score[0]; second stays at -inf (use min signed)
          top_val    <= score[0];
          top_idx    <= 5'd0;
          second_val <= {1'b1, {(SCORE_W-1){1'b0}}};  // most-negative
          second_idx <= 5'd0;
        end else begin
          if (score[argmax_step] > top_val) begin
            second_val <= top_val;
            second_idx <= top_idx;
            top_val    <= score[argmax_step];
            top_idx    <= argmax_step;
          end else if (score[argmax_step] > second_val) begin
            second_val <= score[argmax_step];
            second_idx <= argmax_step;
          end
        end
      end
    end
  end

  // Hysteresis / commit
  logic signed [SCORE_W-1:0] margin;
  assign margin = top_val - second_val;

  always_ff @(posedge clk) begin
    if (rst) begin
      current_key     <= 5'd0;
      last_challenger <= 5'd0;
      dwell_ctr       <= '0;
      key_valid       <= 1'b0;
      corr_done_pulse <= 1'b0;
    end else begin
      corr_done_pulse <= (state == S_HYST);
      if (state == S_HYST) begin
        if (activity < ACTIVITY_THRESH) begin
          // Not enough recent material — hold last commit, hold dwell.
          dwell_ctr <= '0;
        end else if (margin < $signed({1'b0, MARGIN_THRESH})) begin
          // Ambiguous — don't commit either way.
          dwell_ctr <= '0;
        end else if (top_idx == current_key) begin
          // Already correct & confident. Confirm: latch key_valid.
          dwell_ctr <= '0;
          key_valid <= 1'b1;
        end else if (top_idx == last_challenger) begin
          if (dwell_ctr + 1 >= DWELL_COUNT[$clog2(DWELL_COUNT+1)-1:0]) begin
            current_key <= top_idx;
            key_valid   <= 1'b1;
            dwell_ctr   <= '0;
          end else begin
            dwell_ctr <= dwell_ctr + 1'b1;
          end
        end else begin
          last_challenger <= top_idx;
          dwell_ctr       <= 1;
        end
      end
    end
  end

  assign key_id       = current_key;
  assign top_score    = top_val;
  assign second_score = second_val;

endmodule
