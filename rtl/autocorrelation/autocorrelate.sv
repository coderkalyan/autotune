`include "fixed.sv"

module autocorrelate #(
    parameter int WINDOW_SIZE = 1024,
    parameter int WBITS = $clog2(WINDOW_SIZE)
) (
    input  wire                       clk,
    input  wire                       rst,
    input  wire         [WBITS - 1:0] i_lag,
    input  wire                       i_en,
    input  wire fixed_t               i_xdata,
    input  wire fixed_t               i_ydata,
    output logic        [WBITS - 1:0] o_yaddr,
    output fmac_t                     o_result,
    output logic                      o_done
);
  // It takes one cycle on startup for our pipeline to fill.
  logic [1:0] read_valid;
  always_ff @(posedge clk) begin
    if (i_rst)
      read_valid <= '0;
    else
      read_valid <= {i_en, read_valid[1]};
  end

  // Cyclone V DSP has an internal 64-bit accumulator, which is sufficient
  // for our purposes. In the worst case, we have 1024 samples of 16-bit
  // fixed point (Q11.16) data, which yields 54 bit products. 1024 such
  // samples can yield an maximum increase of log2(1024) = 10 bits, exactly
  // fitting within the 64 bit accumulator without overflow.
  logic signed [       63:0] accum;
  always_ff @(posedge clk) begin
    accum 
  end

  logic        [WBITS - 1:0] counter;

  always_ff @(posedge clk) begin
    if (rst) begin
      state      <= IDLE;
      counter    <= '0;
      mem_addr_1 <= '0;
      mem_addr_2 <= '0;
      mem_rd     <= 0;
      accum      <= '0;
      result     <= '0;
      o_done     <= 0;
    end else begin
      mem_rd <= 0;
      o_done <= 0;

      case (state)
        IDLE: begin
          if (en) begin
            counter <= '0;
            accum   <= '0;
            state   <= READ;
          end
        end

        READ: begin
          mem_addr_1 <= counter;
          mem_addr_2 <= counter + L;
          mem_rd     <= 1;
          state      <= ACCUMULATE;
        end

        ACCUMULATE: begin
          if (mem_data_valid) begin
            // Last valid pair: addr_2 reaches the end of the window
            if (counter + L == WBITS'(WINDOW_SIZE - 1)) begin
              result <= accum + $signed(mem_data_1) * $signed(mem_data_2);
              o_done <= 1;
              state  <= IDLE;
            end else begin
              accum   <= accum + $signed(mem_data_1) * $signed(mem_data_2);
              counter <= counter + 1;
              state   <= READ;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
