`include "../fixed.sv"

module autocorrelate_top #(
  parameter WINDOW_BITS = 10,
  parameter START_L = 0,
  parameter STEP = 16,
  parameter SIM = 0
) (
  input  clk,
  input  rst,
  input fixed_t                  i_xdata,  //global pointer (same for all parallel instances)
  input fixed_t                  i_ydata,  //local pointer (different for each parallel instance based on START_L and STEP)
  output [WINDOW_BITS-1:0]       o_yaddr,
  // Pulse en=1 for one clock to start a full sweep with START_L and STEP
  input                          i_en,
  // results[L] holds the autocorrelation value at lag START_L + L*STEP after done is asserted
  output fmac_t                  o_result,
  output reg                     o_autocorr_en_ptr, // used for reseting global pointer at the start of a new sweep
  output reg                     o_single_done,
  output reg                     o_all_done
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
  fmac_t autocorr_result; 
  wire autocorr_done;

  always_ff @(posedge clk) begin
    if (rst) begin
      state       <= IDLE;
      current_L   <= START_L;
      o_autocorr_en_ptr <= 0;
      o_all_done    <= 0;
    end else begin
      o_autocorr_en_ptr <= 0;   // default: pulse only when TRIGGER fires
      o_all_done           <= 0;   

      case (state)
        // Wait for an en pulse, then start sweep from L=0
        IDLE: begin
          if (i_en) begin
            current_L <= START_L;
            state <= WAIT;
          end
        end
        // Wait for autocorrelate to finish, store result, then advance L
        WAIT: begin          
          if (current_L >= WINDOW_SIZE) begin
              state <= IDLE;
              o_all_done <= 1;       // Signal that the entire sweep is done
          end
          if (autocorr_done) begin
              o_result <= autocorr_result;
              current_L <= current_L + STEP;
              state     <= WAIT;
              o_autocorr_en_ptr <= (current_L + STEP < WINDOW_SIZE) ? 1 : 0; // pulse en for next lag if we haven't reached the end of the sweep
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign o_single_done = autocorr_done;

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
        .i_en( o_autocorr_en_ptr),
        .i_xdata(i_xdata),  //global pointer
        .i_ydata(i_ydata),  //local pointer
        .o_yaddr(o_yaddr),    //local pointer translated to memory address
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
        .i_en          ( o_autocorr_en_ptr || i_en),
        .i_xdata       (i_xdata),  //global pointer
        .i_ydata       (i_ydata),  //local pointer
        .o_yaddr       (o_yaddr),    //local pointer translated to memory address
        .o_result      (autocorr_result),
        .o_done        (autocorr_done)
      );
    end
  endgenerate

endmodule
