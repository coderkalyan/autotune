`timescale 1ns/1ps
`include "../fixed.sv"

module autocorrelate_top_tb;

  localparam int WINDOW_BITS = 10;
  localparam int START_L     = 15;
  localparam int STEP        = 16;
  localparam int SIM         = 1;

  localparam int NUM_RESULTS = (2**WINDOW_BITS) / STEP;

  logic clk;
  logic rst;
  logic en;

  fixed_t x_data;
  fixed_t y_data;

  logic [WINDOW_BITS-1:0] y_addr;
  fmac_t results [0:NUM_RESULTS-1];
  logic single_done;
  logic all_done;

  // DUT
  autocorrelate_top #(
    .WINDOW_BITS(WINDOW_BITS),
    .START_L(START_L),
    .STEP(STEP),
    .SIM(SIM)
  ) dut (
    .clk(clk),
    .rst(rst),
    .x_data(x_data),
    .y_data(y_data),
    .y_addr(y_addr),
    .en(en),
    .results(results),
    .single_done(single_done),
    .all_done(all_done)
  );

  // Clock: 10 ns period
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Pulse enable for one clock
  task automatic pulse_en;
    begin
      @(negedge clk);
      en = 1'b1;
      @(negedge clk);
      en = 1'b0;
    end
  endtask

  integer k;

  initial begin
    // Init
    rst    = 1'b1;
    en     = 1'b0;
    x_data = '0;
    y_data = '0;

    // Hold reset a few cycles
    repeat (4) @(negedge clk);
    rst = 1'b0;

    $display("[%0t] Reset released", $time);

    // Dummy data changes over time just to make waveforms less flat
    fork
      begin
        forever begin
          @(negedge clk);
          x_data <= x_data + fixed_t'(1);
          y_data <= y_data + fixed_t'(2);
        end
      end
    join_none

    // First sweep
    $display("[%0t] Starting first sweep", $time);
    pulse_en();

    // Wait long enough for the full run to complete
    wait (all_done == 1'b1);
    $display("[%0t] First sweep complete", $time);

    // Print results array once at end
    $display("----- Final results snapshot -----");
    for (k = 0; k < NUM_RESULTS; k++) begin
      $display("results[%0d] = %0d", k, results[k]);
    end

    repeat (10) @(posedge clk);
    $stop;
  end

endmodule