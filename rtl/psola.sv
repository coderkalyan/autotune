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
  localparam int NUM_CHANNELS = 2;
  logic [9:0] hann_pointers[NUM_CHANNELS];

  logic [7:0] counter;
  always_ff @(posedge clk) begin
    if (rst) begin
      counter <= 8'b0;
    end else if (i_valid) begin
      counter <= counter + 8'd1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      hann_pointers[0] <= 10'd0;
      hann_pointers[1] <= 10'd512;
    end else if (counter == 8'd0) begin
      hann_pointers[0] <= hann_pointers[0] + 10'd1;
      hann_pointers[1] <= hann_pointers[1] + 10'd1;

      // if (hann_pointers[0] == (i_lag << 1)) begin
      //   hann_pointers[0] <= 10'd0;
      // end
      //
      // if (hann_pointers[1] == (i_lag << 1)) begin
      //   hann_pointers[1] <= 10'd0;
      // end
    end
  end

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

  always_ff @(posedge clk)
    hann <= hann_comb;

  typedef enum logic {
    IDLE,
    BUSY
  } state_t;

  state_t state;
  logic [6:0] channel;
  fixed_t sample, acc;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin
          o_valid <= 1'b0;

          if (i_valid) begin
            state   <= BUSY;
            sample  <= i_data;
            acc  <= 0;
            channel <= 0;
          end
        end
        BUSY: begin
          // channel 0 is a pipeline prime cycle (hanning_var has 1-cycle latency);
          // accumulate on channels 1..NUM_CHANNELS, then output.
          if (channel < NUM_CHANNELS + 1) begin
            acc <= acc + fixed_mul(sample, hann);
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
    hann_index = (channel < NUM_CHANNELS) ? hann_pointers[channel] : hann_pointers[NUM_CHANNELS-1];
endmodule
