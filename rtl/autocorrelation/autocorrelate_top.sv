module autocorrelate_top #(
  parameter DATA_WIDTH  = 4,
  parameter WINDOW_BITS = 3
) (
  input  clk,
  input  rst,
  // Memory write port (from external controller)
  input                          wr,
  input  [DATA_WIDTH-1:0]        data_in,
  input  [WINDOW_BITS-1:0]       wr_addr,
  // Pulse en=1 for one clock to start a full sweep over L = 0..WINDOW_SIZE-1
  input                          en,
  // results[L] holds the autocorrelation value at lag L after done is asserted
  output reg signed [DATA_WIDTH*2-1:0] results [0:2**WINDOW_BITS-1],
  output reg                     done
);

  localparam WINDOW_SIZE = 2**WINDOW_BITS;

  wire                          mem_data_valid;
  wire                          mem_rd;
  wire [WINDOW_BITS-1:0]        mem_addr_1;
  wire [WINDOW_BITS-1:0]        mem_addr_2;
  wire signed [DATA_WIDTH-1:0]  data_out_1;
  wire signed [DATA_WIDTH-1:0]  data_out_2;

  // When writing, external wr_addr drives addr_1; reads use autocorrelate's output
  wire [WINDOW_BITS-1:0] addr_1 = wr ? wr_addr : mem_addr_1;

  // ----------------------------------------------------------------
  // Iteration FSM: sweeps current_L from 0 to WINDOW_SIZE-1,
  // firing autocorrelate once per lag and collecting results
  // ----------------------------------------------------------------
  typedef enum logic [1:0] {IDLE, TRIGGER, WAIT} state_t;
  state_t state;

  reg [WINDOW_BITS-1:0]         current_L;
  reg                           autocorr_en;
  wire signed [DATA_WIDTH*2-1:0] autocorr_result;
  wire                           autocorr_done;

  always_ff @(posedge clk) begin
    if (rst) begin
      state       <= IDLE;
      current_L   <= '0;
      autocorr_en <= 0;
      done        <= 0;
    end else begin
      autocorr_en <= 0;   // default: pulse only when TRIGGER fires
      done        <= 0;

      case (state)
        // Wait for an en pulse, then start sweep from L=0
        IDLE: begin
          if (en) begin
            current_L <= '0;
            state     <= TRIGGER;
          end
        end

        // Assert en to autocorrelate for exactly one cycle with current_L
        TRIGGER: begin
          autocorr_en <= 1;
          state       <= WAIT;
        end

        // Wait for autocorrelate to finish, store result, then advance L
        WAIT: begin
          if (autocorr_done) begin
            results[current_L] <= autocorr_result;
            if (current_L == WINDOW_BITS'(WINDOW_SIZE - 1)) begin
              done  <= 1;
              state <= IDLE;
            end else begin
              current_L <= current_L + 1;
              state     <= TRIGGER;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  // ----------------------------------------------------------------
  // Memory
  // ----------------------------------------------------------------
  memory #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(WINDOW_BITS)
  ) memory_inst (
    .clk       (clk),
    .wr        (wr),
    .rd        (mem_rd),
    .data_in   (data_in),
    .addr_1    (addr_1),
    .addr_2    (mem_addr_2),
    .data_out_1(data_out_1),
    .data_out_2(data_out_2),
    .data_valid(mem_data_valid)
  );

  // ----------------------------------------------------------------
  // Autocorrelate (single-lag engine)
  // ----------------------------------------------------------------
  autocorrelate #(
    .DATA_WIDTH (DATA_WIDTH),
    .WINDOW_BITS(WINDOW_BITS)
  ) autocorrelate_inst (
    .clk           (clk),
    .rst           (rst),
    .L             (current_L),
    .mem_data_valid(mem_data_valid),
    .en            (autocorr_en),
    .mem_data_1    (data_out_1),
    .mem_data_2    (data_out_2),
    .mem_addr_1    (mem_addr_1),
    .mem_addr_2    (mem_addr_2),
    .mem_rd        (mem_rd),
    .result        (autocorr_result),
    .done          (autocorr_done)
  );

endmodule
