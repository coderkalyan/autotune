module autocorrelate #(
  parameter DATA_WIDTH = 16,
  parameter WINDOW_BITS = 10 // window size = 1024
) (
  input  clk,
  input  rst,
  input  [WINDOW_BITS-1:0]       L,
  input                          mem_data_valid,
  input                          en,
  input  signed [DATA_WIDTH-1:0] mem_data_1,
  input  signed [DATA_WIDTH-1:0] mem_data_2,
  output reg [WINDOW_BITS-1:0]   mem_addr_1,
  output reg [WINDOW_BITS-1:0]   mem_addr_2,
  output reg                     mem_rd,
  output reg signed [DATA_WIDTH*2-1:0] result,
  output reg                     done
);
  localparam WINDOW_SIZE = 2**WINDOW_BITS;

  typedef enum logic [1:0] {IDLE, READ, ACCUMULATE} state_t;
  state_t state;

  reg [WINDOW_BITS-1:0]          counter;
  reg signed [DATA_WIDTH*2-1:0]  accum;

  always_ff @(posedge clk) begin
    if (rst) begin
      state      <= IDLE;
      counter    <= '0;
      mem_addr_1 <= '0;
      mem_addr_2 <= '0;
      mem_rd     <= 0;
      accum      <= '0;
      result     <= '0;
      done       <= 0;
    end else begin
      mem_rd <= 0;
      done   <= 0;

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
            if (counter + L == WINDOW_BITS'(WINDOW_SIZE - 1)) begin
              result <= accum + $signed(mem_data_1) * $signed(mem_data_2);
              done   <= 1;
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
