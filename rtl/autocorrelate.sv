`include "fixed.sv"

module autocorrelate #(
    parameter int WINDOW_SIZE = 1024,
    parameter int WBITS = $clog2(WINDOW_SIZE)
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire    [WBITS - 1:0] i_lag,
    input  wire                  i_en,
    input  fixed_t               i_xdata,
    input  fixed_t               i_ydata,
    output logic   [WBITS - 1:0] o_yaddr,
    output fmac_t                o_result,
    output logic                 o_done
);
  // Cyclone V DSP has an internal 64-bit accumulator, which is sufficient
  // for our purposes. In the worst case, we have 1024 samples of 16-bit
  // fixed point (Q11.16) data, which yields 54 bit products. 1024 such
  // samples can yield an maximum increase of log2(1024) = 10 bits, exactly
  // fitting within the 64 bit accumulator without overflow.
  logic signed [       63:0] accum;
  logic        [WBITS - 1:0] counter;

  typedef enum logic [2:0] {
    IDLE,
    READ,
    ACCUMULATE,
    MASK,
    DONE
  } state_t;
  state_t state;

  always_ff @(posedge clk) begin
    if (rst) begin
      state  <= IDLE;
      o_done <= '0;
    end else begin
      o_done <= 0;  // default
      case (state)
        IDLE: begin
          if (i_en) begin
            accum   <= '0;
            o_done  <= '0;
            o_yaddr <= i_lag;
            state   <= READ;
          end
        end

        READ: begin
          counter <= '0;
          o_yaddr <= o_yaddr + 1;
          state   <= ACCUMULATE;
        end

        ACCUMULATE: begin
          accum   <= accum + fixed_mul_raw(i_xdata, i_ydata);
          o_yaddr <= o_yaddr + 1;

          if (counter == WBITS'(WINDOW_SIZE - 1)) state <= DONE;
          else begin
            counter <= counter + 1;

            if (o_yaddr == '0) state <= MASK;
          end
        end

        MASK: begin
          if (counter == WBITS'(WINDOW_SIZE - 1)) state <= DONE;
          else counter <= counter + 1;
        end

        DONE: begin
          o_result <= fmac_t'(accum[63:16]);
          o_done   <= 1'b1;
          state    <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end
endmodule
