`timescale 1ns/1ps
`include "../fixed.sv"

module parallel_autocorrelate_tb();

  // --------------------------------------------------------------------------
  // Parameters
  // --------------------------------------------------------------------------
  localparam int STAMPS = 16;
  localparam int STAMPS_ACTUAL = (1024 % STAMPS == 0) ? STAMPS : 16;

  // --------------------------------------------------------------------------
  // DUT signals
  // --------------------------------------------------------------------------
  logic i_clk;
  logic i_rst;
  fixed_t i_x_data;
  fixed_t i_y_data [0:STAMPS_ACTUAL-1];
  logic i_en;

  logic [9:0] o_y_addr [0:STAMPS_ACTUAL-1];
  logic o_single_done;
  logic o_all_done;
  fmac_t o_results [0:STAMPS_ACTUAL-1];

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  parallel_autocorrelate #(
    .STAMPS(STAMPS),
    .SIM(1)
  ) dut (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_x_data(i_x_data),
    .i_y_data(i_y_data),
    .i_en(i_en),
    .o_y_addr(o_y_addr),
    .o_single_done(o_single_done),
    .o_all_done(o_all_done),
    .o_results(o_results)
  );

  // --------------------------------------------------------------------------
  // Clock generation
  // --------------------------------------------------------------------------
  initial begin
    i_clk = 1'b0;
    forever #5 i_clk = ~i_clk;   // 100 MHz clock
  end

  // --------------------------------------------------------------------------
  // Stimulus
  // --------------------------------------------------------------------------
  integer k;

  initial begin
    // Init
    i_rst    = 1'b1;
    i_en     = 1'b0;
    i_x_data = '0;

    // Hold reset
    repeat (5) @(posedge i_clk);
    i_rst <= 1'b0;

    // Give some dummy input values
    // These do not need to mean anything if your DUT internally generates dummy outputs

    // Start one sweep
    @(posedge i_clk);
    i_en <= 1'b1;
    @(posedge i_clk);
    i_en <= 1'b0;

    // Wait until the DUT says the full sweep is done
    while (!o_all_done) begin 
      if (o_single_done) begin
        $write("[%0t] ", $time);
        for (k = 0; k < STAMPS_ACTUAL; k++) begin
          $write("Stamp[%0d] = %0d ", k, o_results[k]);
        end
        $write("\n");
      end
      @(negedge i_clk);
    end

    $display("\n==============================================");
    $display("TB: o_all_done observed at time %0t", $time);
    $display("==============================================\n");

    repeat (10) @(posedge i_clk);
    $stop;
  end

endmodule