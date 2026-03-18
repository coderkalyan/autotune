`include "../fixed.sv"

module autocorrelate_top #(
  parameter WINDOW_BITS = 10,
  parameter START_L = 0,
  parameter STEP = 16,
  parameter SIM = 0
) (
  input  clk,
  input  rst,
  input fixed_t                  x_data,  //global pointer (same for all parallel instances)
  input fixed_t                  y_data,  //local pointer (different for each parallel instance based on START_L and STEP)
  output [WINDOW_BITS-1:0]       y_addr,
  // Pulse en=1 for one clock to start a full sweep with START_L and STEP
  input                          en,
  // results[L] holds the autocorrelation value at lag START_L + L*STEP after done is asserted
  output fmac_t     results [0:(2**WINDOW_BITS / STEP)-1],
  output reg                     single_done,
  output reg                     all_done
);

  localparam WINDOW_SIZE = 2**WINDOW_BITS;

  // ----------------------------------------------------------------
  // Iteration FSM: sweeps current_L from 0 to WINDOW_SIZE-1,
  // firing autocorrelate once per lag and collecting results
  // ----------------------------------------------------------------
  typedef enum logic [1:0] {IDLE, TRIGGER, WAIT} state_t;
  state_t state;

  reg [$clog2(WINDOW_SIZE + STEP)-1:0] current_L; // needs enough bits to hold WINDOW_SIZE + STEP 
                                                          // for the final increment after the last lag
  reg autocorr_en;
  fmac_t autocorr_result; 
  wire autocorr_done;
  logic [$clog2(WINDOW_SIZE / STEP)-1:0] res_idx;

  always_ff @(posedge clk) begin
    if (rst) begin
      state       <= IDLE;
      current_L   <= START_L;
      autocorr_en <= 0;
      all_done    <= 0;
      res_idx     <= 0;
    end else begin
      autocorr_en <= 0;   // default: pulse only when TRIGGER fires
      all_done           <= 0;   

      case (state)
        // Wait for an en pulse, then start sweep from L=0
        IDLE: begin
          res_idx <= 0;
          if (en) begin
            current_L <= START_L;
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
            results[res_idx] <= autocorr_result;
            res_idx <= res_idx + 1;
            if (current_L >= WINDOW_SIZE) begin
              state <= IDLE;
              all_done <= 1;       // Signal that the entire sweep is done
            end else begin
              current_L <= current_L + STEP;
              state     <= TRIGGER;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign single_done = autocorr_done;

  // ----------------------------------------------------------------
  // Autocorrelate (single-lag engine)
  // ----------------------------------------------------------------
  generate
    if (SIM) begin 
      autocorrelation_sim_mod #(
        .WBITS(WINDOW_BITS)
      ) autocorrelate_inst (
        .clk(clk),
        .rst(rst),
        .i_lag(current_L[WINDOW_BITS-1:0]),
        .i_en(autocorr_en),
        .i_xdata(x_data),  //global pointer
        .i_ydata(y_data),  //local pointer
        .o_yaddr(y_addr),    //local pointer translated to memory address
        .o_result(autocorr_result),
        .o_done(autocorr_done)
      );
    end else begin 
      autocorrelate #(
        .WINDOW_SIZE(WINDOW_SIZE)
      ) autocorrelate_inst (
        .clk           (clk),
        .rst           (rst),
        .i_lag         (current_L[WINDOW_BITS-1:0]), // autocorrelate only needs the lower WINDOW_BITS of current_L for addressing
        .i_en          (autocorr_en),
        .i_xdata       (x_data),  //global pointer
        .i_ydata       (y_data),  //local pointer
        .o_ydata       (y_addr),    //local pointer translated to memory address
        .o_result      (autocorr_result),
        .o_done        (autocorr_done)
      );
    end
  endgenerate

endmodule
