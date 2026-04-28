module hysteresis (
    input  wire       clk,
    input  wire       rst,
    input  wire       i_en,
    input  wire [9:0] i_period,
    output wire [9:0] o_period
);
  localparam real SMALL_UTHRESHOLD = 1.0057929410678534;  // 2.0 ** (10 / 1200);
  localparam real SMALL_LTHRESHOLD = 0.9942404238175473;  // 2.0 ** (-10 / 1200);
  localparam real LARGE_UTHRESHOLD = 1.029302236643492;  // 2.0 ** (50 / 1200);
  localparam real LARGE_LTHRESHOLD = 0.9715319411536059;  // 2.0 ** (-50 / 1200);
  localparam int MEDIUM_CONFIRM = 1;
  localparam int LARGE_CONFIRM = 2;

  fixed_t small_uthreshold, small_lthreshold;
  fixed_t large_uthreshold, large_lthreshold;
  assign small_uthreshold = `FIXED_RTOF(SMALL_UTHRESHOLD);
  assign small_lthreshold = `FIXED_RTOF(SMALL_LTHRESHOLD);
  assign large_uthreshold = `FIXED_RTOF(LARGE_UTHRESHOLD);
  assign large_lthreshold = `FIXED_RTOF(LARGE_LTHRESHOLD);

  fixed_t cur;
  assign cur = fixed_t'({9'h0, i_period, 8'h0});

  // ---------------------------------------------------------------------
  // Time-multiplexed multiplier
  // ---------------------------------------------------------------------
  // Hysteresis fires once per pitch-detect window (sub-kHz). Between
  // events there are tens of thousands of idle clocks, so the 6 distinct
  // products needed for the comparisons can share one DSP. The FSM walks
  // step 0..5 driving the shared multiplier, latches each product, then
  // commits the hysteresis decision on step 6 using the registered P0..P5.
  //
  //   P0 = accepted  * small_u   P3 = accepted  * large_l
  //   P1 = accepted  * small_l   P4 = candidate * large_u
  //   P2 = accepted  * large_u   P5 = candidate * large_l
  //
  // is_octave_up reuses P2/P3 by comparing against (cur << 1).
  fixed_t accepted, candidate, cur_snap;
  fixed_t p0, p1, p2, p3, p4, p5;

  logic [2:0] step;
  logic       busy;

  fixed_t op_a, op_b;
  always_comb begin
    op_a = accepted;
    op_b = small_uthreshold;
    case (step)
      3'd0: begin op_a = accepted;  op_b = small_uthreshold; end
      3'd1: begin op_a = accepted;  op_b = small_lthreshold; end
      3'd2: begin op_a = accepted;  op_b = large_uthreshold; end
      3'd3: begin op_a = accepted;  op_b = large_lthreshold; end
      3'd4: begin op_a = candidate; op_b = large_uthreshold; end
      3'd5: begin op_a = candidate; op_b = large_lthreshold; end
      default: ; // step 6/7: don't-care, products already latched
    endcase
  end
  fixed_t prod;
  assign prod = fixed_mul(op_a, op_b);

  // Comparisons computed on registered snapshots — valid at step 6.
  wire [26:0] cur_snap_dbl     = {cur_snap[25:0], 1'b0};
  wire        small_accept     = (cur_snap < p0) && (cur_snap > p1);
  wire        large_accept     = (cur_snap < p2) && (cur_snap > p3);
  wire        candidate_accept = (cur_snap < p4) && (cur_snap > p5);
  // Reused P2/P3: octave-up check is the same large-tolerance window
  // anchored on accepted, just compared against 2*cur instead of cur.
  wire        is_octave_up     = (cur_snap_dbl > p3) && (cur_snap_dbl < p2);

  logic [3:0] frames;
  always_ff @(posedge clk) begin
    if (rst) begin
      accepted  <= '0;
      candidate <= '0;
      frames    <= '0;
      step      <= 3'd0;
      busy      <= 1'b0;
    end else if (!busy) begin
      // Idle: wait for an enable pulse, snapshot inputs, kick off pass.
      if (i_en) begin
        busy     <= 1'b1;
        step     <= 3'd0;
        cur_snap <= cur;
      end
    end else begin
      // Walk steps 0..5 latching one product per cycle, then commit on 6.
      case (step)
        3'd0: p0 <= prod;
        3'd1: p1 <= prod;
        3'd2: p2 <= prod;
        3'd3: p3 <= prod;
        3'd4: p4 <= prod;
        3'd5: p5 <= prod;
        default: ;
      endcase

      if (step == 3'd6) begin
        // Same hysteresis decision logic as the original — operates on
        // cur_snap and the precomputed P0..P5 instead of inline mults.
        if (small_accept) begin
          accepted <= cur_snap;
          frames   <= 4'd0;
        end else if (large_accept) begin
          if (frames >= MEDIUM_CONFIRM) begin
            accepted <= cur_snap;
            frames   <= 4'd0;
          end else begin
            frames <= frames + 4'd1;
          end
        end else begin
          if (candidate_accept) begin
            frames <= frames + 4'd1;
          end else begin
            candidate <= cur_snap;
            frames    <= 4'd1;
          end

          if (frames >= LARGE_CONFIRM) begin
            accepted <= cur_snap;
            frames   <= 4'd0;
          end
        end

        busy <= 1'b0;
      end else begin
        step <= step + 3'd1;
      end
    end
  end

  assign o_period = accepted[8+:10];
endmodule
