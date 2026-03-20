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
    BUSY,
    POST
  } state_t;

  state_t state;
  logic [WBITS - 1:0] counter, argmax;
  fmac_t max, r0;
  logic candidate;
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
            state     <= BUSY;
            counter   <= '0;
            max       <= '0;
            o_done    <= 1'b0;
            o_valid   <= 1'b0;
            candidate <= 1'b0;
          end
        end

        BUSY: begin
          if (i_valid) begin
            if (counter == '0) r0 <= i_sample;

            // Only look for peaks within LAG_MIN/LAG_MAX.
            if (counter >= LAG_MIN && counter <= LAG_MAX) begin
              if (i_sample > max) begin
                max       <= i_sample;
                argmax    <= counter;
                candidate <= 1'b1;
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
          o_valid  <= candidate && (max >= (r0 >> 2));
          state    <= IDLE;
        end

        default: state <= IDLE;
      endcase
    end
  end
endmodule
