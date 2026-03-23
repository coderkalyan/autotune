`include "fixed.sv"

module preprocessing #(
    parameter CHANNELS = 0,   // choose if we should use lpf both, or single channel
    parameter L_FC = 10000,
    parameter R_FC = 400
)(
    input clk,
    input rst,
    input fixed_t i_lf,
    input fixed_t i_rf,
    input i_en,
    output fixed_t o_lpf_lf,
    output fixed_t o_lpf_rf,
    output o_lpf_valid
);

// --- Internal Signals: Left Channel ---
fixed_t lpf_lf_s1, lpf_lf_s2;  // Intermediate stage outputs
logic v_l_s1, v_l_s2;  // Intermediate valid signals

// --- Internal Signals: Right Channel ---
fixed_t lpf_rf_s1, lpf_rf_s2;  // Intermediate stage outputs
logic v_r_s1, v_r_s2;  // Intermediate valid signals


// ----------------------------------------------------------------
// Right Channel Determination
// ----------------------------------------------------------------
generate 
    if (CHANNELS == 0) begin 
        // When defaulted, generate both left and right channels
        lpf #(
            .FC_HZ(R_FC)
        ) lpf_r_inst1 (
            .clk(clk),
            .rst(rst),
            .i_data(i_rf), 
            .i_valid(i_en), 
            .o_data(lpf_rf_s1), 
            .o_valid(v_r_s1) 
        );

        lpf #(
            .FC_HZ(R_FC)
        ) lpf_r_inst2 (
            .clk(clk),
            .rst(rst),
            .i_data(lpf_rf_s1), 
            .i_valid(v_r_s1),
            .o_data(lpf_rf_s2), 
            .o_valid(v_r_s2) 
        );

        lpf #(
            .FC_HZ(R_FC)
        ) lpf_r_inst3 (
            .clk    (clk),
            .rst    (rst),
            .i_data (lpf_rf_s2), 
            .i_valid(v_r_s2), 
            .o_data (o_lpf_rf),
            .o_valid()            // Final Right Output (valid is redundant)
        );
    end 
endgenerate 

// ----------------------------------------------------------------
// Left Channel
// ----------------------------------------------------------------
lpf #(
      .FC_HZ(L_FC)
  ) lpf_l_inst1 (
      .clk(clk),
      .rst(rst), 
      .i_data(i_lf), 
      .i_valid(i_en),
      .o_data(lpf_lf_s1), 
      .o_valid(v_l_s1) 
  );

  lpf #(
      .FC_HZ(L_FC)
  ) lpf_l_inst2 (
      .clk(clk),
      .rst(rst),
      .i_data(lpf_lf_s1), 
      .i_valid(v_l_s1), 
      .o_data(lpf_lf_s2), 
      .o_valid(v_l_s2) 
  );

  lpf #(
      .FC_HZ(L_FC)
  ) lpf_l_inst3 (
      .clk(clk),
      .rst(rst),
      .i_data(lpf_lf_s2), 
      .i_valid(v_l_s2), 
      .o_data(o_lpf_lf),
      .o_valid(o_lpf_lf_valid)  
  );

endmodule