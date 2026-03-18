`include "../fixed.sv"

module parallel_autocorrelate #(
    parameter STAMPS = 16,
    parameter STAMPS_ACTUAL = 1024 % STAMPS == 0 ? STAMPS : 16
)(
  input  i_clk,
  input  i_rst,
  // Memory write port (from external controller)

  input fixed_t i_x_data,                                   // global pointer (same for all parallel instances)
  input fixed_t i_y_data [0:STAMPS_ACTUAL-1],               // local pointer (different for 
                                                            // each parallel instance based on START_L and STEP)
  input i_en,                                               // pulse to start the entire sweep of all parallel instances  
  output [9:0] o_y_addr [0:STAMPS_ACTUAL-1],                // read addresses for circular buffer

  output o_single_done,                                     // done pulses when the autocorrelation result for 
                                                            // the lag corresponding to the ith parallel instance is ready
  output o_all_done,                                        // done pulse when the entire sweep for all lags and all parallel instances is complete
  output [53:0] o_results [0:(1024/STAMPS_ACTUAL)-1]   // autocorrelation results for each parallel 
                                                                          // instance (each instance corresponds to a different lag)

);

// ----------------------------------------------------------------
// Internal signals
// ----------------------------------------------------------------
logic [STAMPS_ACTUAL-1:0] single_done;
logic [STAMPS_ACTUAL-1:0] all_done;

assign o_single_done = &single_done;
assign o_all_done = &all_done;

// ----------------------------------------------------------------
// Generate STAMPS parallel instances of autocorrelate_top, 
// each sweeping over lags with a different offset (START_L) 
// and step size (STEP)
// ----------------------------------------------------------------
generate
  genvar i;
  for (i = 0; i < STAMPS_ACTUAL; i++) begin : AUTOCORRELATE_INSTANCES
    autocorrelate_top #(
      .WINDOW_BITS(10),
      .START_L(i),
      .STEP(STAMPS_ACTUAL)
    ) autocorrelate_inst (
      .clk(clk),
      .rst(rst),
      .x_data(i_x_data),
      .y_data(i_y_data[i]),
      .y_addr(o_y_addr[i]),
      .en(i_en),
      .results(o_results[i]),
      .single_done(single_done[i]),
      .all_done(all_done[i])
    );
  end
endgenerate 


endmodule 