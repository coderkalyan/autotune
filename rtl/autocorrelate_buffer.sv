`include "fixed.sv"

// Buffer for results from the toplevel autocorrelation module.
// Autocorrelation results are not globally buffered, but streamed into the
// pitch detection pipeline. However, since multiple lag values are calculated
// in parallel, this module buffers a vector of adjacent lag values and
// drip-feeds them to the peak detector.
module autocorrelate_buffer #(
    parameter int STAMPS = 16
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        i_valid,
    input  wire fmac_t i_results[STAMPS],
    output logic       o_busy,
    output logic       o_valid,
    output fmac_t      o_sample
);
  localparam int SBITS = $clog2(STAMPS);
  typedef enum logic {
    IDLE,
    BUSY
  } state_t;

  state_t state;
  logic [SBITS - 1:0] counter;
  fmac_t buffer[STAMPS];
  int i;
  always_ff @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      o_busy  <= 1'b0;
      o_valid <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          o_busy   <= 1'b0;
          o_valid  <= 1'b0;
          o_sample <= 'x;

          if (i_valid) begin
            // Latch in entire results vector.
            for (i = 0; i < STAMPS; i = i + 1) buffer[i] <= i_results[i];

            state   <= BUSY;
            counter <= '0;
            o_busy  <= 1'b1;
          end
        end

        BUSY: begin
          o_sample <= buffer[counter];
          o_valid  <= 1'b1;

          if (counter == SBITS'(STAMPS - 1)) begin
            state <= IDLE;
          end else begin
            counter <= counter + 1;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end
endmodule
