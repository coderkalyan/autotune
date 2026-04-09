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
  localparam int MEDIUM_CONFIRM = 2;
  localparam int LARGE_CONFIRM = 4;
  localparam int OCTAVE_CONFIRM = 10;
  localparam int APPROX = 10;

  fixed_t small_uthreshold, small_lthreshold;
  fixed_t large_uthreshold, large_lthreshold;
  assign small_uthreshold = `FIXED_RTOF(SMALL_UTHRESHOLD);
  assign small_lthreshold = `FIXED_RTOF(SMALL_LTHRESHOLD);
  assign large_uthreshold = `FIXED_RTOF(LARGE_UTHRESHOLD);
  assign large_lthreshold = `FIXED_RTOF(LARGE_LTHRESHOLD);


  fixed_t cur, accepted, candidate;
  assign cur = fixed_t'({9'h0, i_period, 8'h0});

  wire small_accept = (cur < fixed_mul(
      accepted, small_uthreshold
  )) || (cur > fixed_mul(
      accepted, small_lthreshold
  ));

  wire large_accept = (cur < fixed_mul(
      accepted, large_uthreshold
  )) || (cur > fixed_mul(
      accepted, large_lthreshold
  ));

  wire candidate_accept = (cur < fixed_mul(
      candidate, large_uthreshold
  )) || (cur > fixed_mul(
      candidate, large_lthreshold
  ));

  fixed_t cur_dbl;
  assign cur_dbl = {cur[25:0], 1'b0};

  wire is_octave_up = (cur_dbl > fixed_mul(accepted, large_lthreshold))
                   && (cur_dbl < fixed_mul(accepted, large_uthreshold));

  logic [3:0] frames;
  always_ff @(posedge clk) begin
    if (rst) begin
      accepted  <= '0;
      candidate <= '0;
    end else if (i_en) begin
      if (small_accept && !is_octave_up) begin
        accepted <= cur;
        frames   <= 4'd0;
      end else if (large_accept && !is_octave_up) begin
        if (frames >= MEDIUM_CONFIRM) begin
          accepted <= cur;
          frames   <= 4'd0;
        end else begin
          frames <= frames + 4'd1;
        end
      end else begin
        if (candidate_accept) begin
          frames <= frames + 4'd1;
        end else begin
          candidate <= cur;
          frames <= 4'd1;
        end

        if (frames >= (is_octave_up ? OCTAVE_CONFIRM : LARGE_CONFIRM)) begin
          accepted <= cur;
          frames   <= 4'd0;
        end
      end
    end
  end

  assign o_period = accepted[8+:10];
endmodule
