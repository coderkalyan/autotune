`include "fixed.sv"

module psola (
    input  wire    clk,
    input  wire    rst,
    // input  wire    [9:0] i_lag,
    input  fixed_t i_data,
    input  wire    i_valid,
    output fixed_t o_data,
    output logic   o_valid
);
  logic [7:0] counter;
  always_ff @(posedge clk) begin
    if (rst) begin
      counter <= 8'b0;
    end else if (i_valid) begin
      counter <= counter + 8'd1;
    end
  end

  logic valid;
  // assign valid = counter == 8'd0;
  assign valid = i_valid;

  localparam int NUM_CHANNELS = 16;
  localparam int CBITS = $clog2(NUM_CHANNELS);

  logic [        9:0] hann_ptrs    [NUM_CHANNELS];
  logic               active       [NUM_CHANNELS];
  logic               enqueue;
  logic [CBITS - 1:0] next_channel;

  genvar i;
  generate
    for (i = 0; i < NUM_CHANNELS; i = i + 1) begin : g_channel
      always_ff @(posedge clk) begin
        if (rst) begin
          hann_ptrs[i] <= 0;
          active[i]    <= 1'b0;
        end else begin
          // Increment all active channels.
          if (active[i] && valid) begin
            hann_ptrs[i] <= hann_ptrs[i] + 1;
          end

          if (enqueue && (next_channel == i)) begin
            // Start the next channel when enqueuing a grain.
            hann_ptrs[i] <= 0;
            active[i]    <= 1'b1;
          end else if (hann_ptrs[i] == 10'd1023) begin
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
    end else if (valid) begin
      output_counter <= (output_counter == 10'd511) ? 0 : (output_counter + 1);
    end
  end

  assign enqueue = (output_counter == 0) && (valid);

  logic [9:0] hann_index;
  fixed_t hann;

  // hanning_var hanning (
  //     .clk(clk),
  //     .rst(rst),
  //     .i_lag(i_lag),
  //     .i_index(hann_index),
  //     .o_data(hann)
  // );

  fixed_t hann_comb;
  hanning #(
      .N(1024)
  ) hanning (
      .clk(clk),
      .rst(rst),
      .i_index(hann_index),
      .o_data(hann_comb)
  );

  always_ff @(posedge clk) hann <= hann_comb;

  typedef enum logic [1:0] {
    IDLE,
    PIPELINE,
    BUSY
  } state_t;

  state_t state;
  logic [CBITS:0] channel;
  fixed_t sample, acc;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          o_valid <= 1'b0;

          if (i_valid) begin
            state <= PIPELINE;
            sample <= i_data;
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
              acc <= acc + fixed_mul(sample, hann);
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

  // Clamp to valid pointer range; past NUM_CHANNELS the pipeline is already
  // loaded so the value doesn't matter.
  always_comb
    hann_index = (channel < NUM_CHANNELS) ? hann_ptrs[channel] : hann_ptrs[NUM_CHANNELS-1];
endmodule
