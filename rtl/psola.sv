`include "fixed.sv"

module psola (
    input  wire    clk,
    input  wire    rst,
    input  wire    [9:0] i_lag,
    input  fixed_t i_data,
    input  wire    i_valid,
    output fixed_t o_data,
    output logic   o_valid
);
  localparam int HISTORY = 512;  // ~= MAX_LAG
  localparam int HBITS = $clog2(HISTORY);
  fixed_t history[HISTORY];
  logic [HBITS - 1:0] wptr;
  always_ff @(posedge clk) begin
    if (rst) begin
      wptr <= 0;
    end else if (i_valid) begin
      history[wptr] <= i_data;
      wptr          <= wptr + 1;
    end
  end

  localparam real PITCH_FACTOR = 1.9;  // 1.059463;  // 587.33 / 739.99;  // 4.0 / 3.0;
  localparam real ADVANCE = 1.0 / PITCH_FACTOR;

  fixed_t advance, grain_counter, next_grain_counter;

  always_comb begin
    advance = `FIXED_RTOF(ADVANCE);

    // Advance the grain counter by the specified amount, and then normalize.
    next_grain_counter = grain_counter + advance;
    next_grain_counter = fixed_t'({11'h0, next_grain_counter[15:0]});
  end

  fixed_t frac;
  assign frac = fixed_t'({11'h0, grain_counter[15:0]});

  fixed_t frac_lag, out_lag;
  assign frac_lag = fixed_mul(frac, fixed_t'({1'b0, i_lag, 16'h0}));
  assign out_lag  = fixed_mul(advance, fixed_t'({1'b0, i_lag, 16'h0}));

  localparam int NUM_CHANNELS = 16;
  localparam int CBITS = $clog2(NUM_CHANNELS);

  logic [        9:0] hann_ptrs    [NUM_CHANNELS];
  logic               active       [NUM_CHANNELS];
  logic               enqueue;
  logic [CBITS - 1:0] next_channel;
  logic [HBITS - 1:0] rptrs        [NUM_CHANNELS];

  genvar i;
  generate
    for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : g_channel
      always_ff @(posedge clk) begin
        if (rst) begin
          hann_ptrs[i] <= 0;
          active[i]    <= 1'b0;
          rptrs[i]     <= 0;
        end else begin
          // Increment all read pointers once per sample.
          if (i_valid) begin
            rptrs[i] <= rptrs[i] + 1;
          end

          // Increment all active channels.
          if (active[i] && i_valid) begin
            hann_ptrs[i] <= hann_ptrs[i] + 1;
          end

          if (enqueue && (next_channel == i)) begin
            // Start the next channel when enqueuing a grain.
            hann_ptrs[i] <= 0;
            active[i]    <= 1'b1;
            rptrs[i]     <= wptr - frac_lag[16+:10];
          end else if (hann_ptrs[i] == (i_lag << 1)) begin
            // Dequeue completed grains.
            active[i] <= 1'b0;
          end
        end
      end
    end
  endgenerate

  always_ff @(posedge clk) begin
    if (rst) begin
      next_channel <= 0;
    end else if (enqueue) begin
      next_channel <= next_channel + 1;
    end
  end

  logic [9:0] output_counter;
  always_ff @(posedge clk) begin
    if (rst) begin
      output_counter <= 10'd0;
    end else if (i_valid) begin
      output_counter <= (output_counter == out_lag[16+:10]) ? 0 : (output_counter + 1);
    end
  end

  assign enqueue = (output_counter == 0) && i_valid;

  always_ff @(posedge clk) begin
    if (rst) begin
      grain_counter <= 0;
    end else if (enqueue) begin
      grain_counter <= next_grain_counter;
    end
  end

  logic [9:0] hann_index;
  fixed_t hann;

  hanning_var hanning (
      .clk(clk),
      .rst(rst),
      .i_lag(i_lag),
      .i_index(hann_index),
      .o_data(hann)
  );

  typedef enum logic [1:0] {
    IDLE,
    PIPELINE,
    BUSY
  } state_t;

  // Debug only data for each channel.
  fixed_t channels[NUM_CHANNELS];

  state_t state;
  logic [CBITS:0] channel;
  fixed_t acc;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          o_valid <= 1'b0;

          if (i_valid) begin
            state <= PIPELINE;
            acc <= 0;
            channel <= 0;
          end
        end
        PIPELINE: begin
          state   <= BUSY;
          channel <= channel + 1;
        end
        BUSY: begin
          if (channel < NUM_CHANNELS + 1) begin
            if (active[channel-1]) begin
              acc <= acc + fixed_mul(history[rptrs[channel-1]], hann);
              channels[channel-1] <= fixed_mul(history[rptrs[channel-1]], hann);
            end

            channel <= channel + 1;
          end else begin
            state   <= IDLE;
            o_data  <= acc;
            o_valid <= 1'b1;
          end
        end
        default: state <= IDLE;
      endcase
    end
  end

  assign hann_index = hann_ptrs[channel];
endmodule
