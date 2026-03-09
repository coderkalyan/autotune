`timescale 1ns/1ps

// Testbench for autocorrelate_top (full sweep version)
//
// Memory is 8 x 4-bit (WINDOW_BITS=3, DATA_WIDTH=4).
// For each test dataset, load_memory writes all 8 samples, then a
// single en pulse triggers autocorrelate_top to sweep L=0..7.
// After the top-level done pulse, every results[L] is checked
// against golden_ref(data, L) computed here in the testbench.
//
// Expected cycle budget per full sweep (L=0..7):
//   sum of 3*(8-L) per lag  +  1 TRIGGER cycle per lag
//   = 3*(8+7+6+5+4+3+2+1) + 8  =  116 cycles  ->  500 cycle timeout

module autocorrelate_tb;

  // ----------------------------------------------------------------
  // Parameters
  // ----------------------------------------------------------------
  localparam DATA_WIDTH  = 4;
  localparam WINDOW_BITS = 3;
  localparam WINDOW_SIZE = 2**WINDOW_BITS; // 8

  // ----------------------------------------------------------------
  // DUT signals
  // ----------------------------------------------------------------
  logic                           clk;
  logic                           rst;
  logic                           wr;
  logic [DATA_WIDTH-1:0]          data_in;
  logic [WINDOW_BITS-1:0]         wr_addr;
  logic                           en;
  logic signed [DATA_WIDTH*2-1:0] results [0:WINDOW_SIZE-1];
  logic                           done;

  // ----------------------------------------------------------------
  // DUT
  // ----------------------------------------------------------------
  autocorrelate_top #(
    .DATA_WIDTH (DATA_WIDTH),
    .WINDOW_BITS(WINDOW_BITS)
  ) dut (
    .clk    (clk),
    .rst    (rst),
    .wr     (wr),
    .data_in(data_in),
    .wr_addr(wr_addr),
    .en     (en),
    .results(results),
    .done   (done)
  );

  // ----------------------------------------------------------------
  // Clock  (10 ns period)
  // ----------------------------------------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // ----------------------------------------------------------------
  // Score keeping
  // ----------------------------------------------------------------
  int pass_count;
  int fail_count;

  // ----------------------------------------------------------------
  // Task: load_memory
  //   Writes data[0..WINDOW_SIZE-1] into the DUT's memory one entry
  //   per clock.  Drives control signals on negedge, memory latches
  //   on the following posedge.  Returns aligned to a negedge.
  // ----------------------------------------------------------------
  task automatic load_memory (
    input logic signed [DATA_WIDTH-1:0] data [0:WINDOW_SIZE-1]
  );
    @(negedge clk);
    for (int i = 0; i < WINDOW_SIZE; i++) begin
      wr      = 1;
      wr_addr = WINDOW_BITS'(i);
      data_in = data[i];
      @(posedge clk);
      @(negedge clk);
    end
    wr      = 0;
    data_in = '0;
    wr_addr = '0;
    @(posedge clk);   // one idle cycle after last write
    @(negedge clk);
  endtask

  // ----------------------------------------------------------------
  // Function: golden_ref
  //   R[lag] = sum_{n=0}^{N-lag-1}  x[n] * x[n+lag]
  //   Uses the same bit width as the DUT so overflow behaviour matches.
  // ----------------------------------------------------------------
  function automatic logic signed [DATA_WIDTH*2-1:0] golden_ref (
    input logic signed [DATA_WIDTH-1:0] data [0:WINDOW_SIZE-1],
    input int                            lag
  );
    logic signed [DATA_WIDTH*2-1:0] acc;
    acc = '0;
    for (int n = 0; n < WINDOW_SIZE - lag; n++)
      acc = acc + data[n] * data[n + lag];
    return acc;
  endfunction

  // ----------------------------------------------------------------
  // Task: run_and_check_all
  //   Loads a dataset, fires one en pulse, waits for the top-level
  //   done, then checks results[0..WINDOW_SIZE-1] against golden_ref.
  // ----------------------------------------------------------------
  task automatic run_and_check_all (
    input logic signed [DATA_WIDTH-1:0] data  [0:WINDOW_SIZE-1],
    input string                         label
  );
    logic timed_out;
    logic signed [DATA_WIDTH*2-1:0] expected;
    timed_out = 0;

    $display("\n--- %s ---", label);
    load_memory(data);

    // Pulse en for one clock
    en = 1;
    @(posedge clk);
    @(negedge clk);
    en = 0;

    // Wait for done (full sweep: ~116 cycles, timeout at 500)
    fork
      begin : wait_done
        @(posedge done);
      end
      begin : watch_timeout
        repeat (500) @(posedge clk);
        timed_out = 1;
      end
    join_any
    disable fork;

    if (timed_out) begin
      $display("[TIMEOUT]  %s", label);
      fail_count += WINDOW_SIZE;
    end else begin
      // Sample results on the following negedge for stability
      @(negedge clk);
      for (int l = 0; l < WINDOW_SIZE; l++) begin
        expected = golden_ref(data, l);
        if (results[l] === expected) begin
          $display("[PASS]  L=%0d  |  result = %4d  |  expected = %4d",
                   l, results[l], expected);
          pass_count++;
        end else begin
          $display("[FAIL]  L=%0d  |  result = %4d  |  expected = %4d",
                   l, results[l], expected);
          fail_count++;
        end
      end
    end
  endtask

  // ----------------------------------------------------------------
  // Stimulus
  // ----------------------------------------------------------------
  logic signed [DATA_WIDTH-1:0] test_data [0:WINDOW_SIZE-1];

  initial begin
    wr      = 0;
    data_in = '0;
    wr_addr = '0;
    en      = 0;
    pass_count = 0;
    fail_count = 0;

    // Reset for 4 cycles
    rst = 1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 0;
    @(posedge clk);
    @(negedge clk);

    // ---------------------------------------------------------------
    // Test 1: all 1s
    //   R[0]=8, R[1]=7, R[2]=6, ..., R[7]=1
    // ---------------------------------------------------------------
    test_data = '{ 4'sd1, 4'sd1, 4'sd1, 4'sd1,
                   4'sd1, 4'sd1, 4'sd1, 4'sd1 };
    run_and_check_all(test_data, "Test 1: data = [1, 1, 1, 1, 1, 1, 1, 1]");

    // ---------------------------------------------------------------
    // Test 2: ramp with wrap
    //   data = [1, 2, 3, 4, 5, 6, 7, 1]
    // ---------------------------------------------------------------
    test_data = '{ 4'sd1, 4'sd2, 4'sd3, 4'sd4,
                   4'sd5, 4'sd6, 4'sd7, 4'sd1 };
    run_and_check_all(test_data, "Test 2: data = [1, 2, 3, 4, 5, 6, 7, 1]");

    // ---------------------------------------------------------------
    // Test 3: alternating sign
    //   data = [3, -2, 1, -3, 2, -1, 3, -2]
    // ---------------------------------------------------------------
    test_data = '{ 4'sd3, 4'shE, 4'sd1, 4'shD,   // 3, -2, 1, -3
                   4'sd2, 4'shF, 4'sd3, 4'shE };  // 2, -1, 3, -2
    run_and_check_all(test_data, "Test 3: data = [3, -2, 1, -3, 2, -1, 3, -2]");

    // ---------------------------------------------------------------
    // Summary
    // ---------------------------------------------------------------
    $display("\n================================");
    $display("  %0d / %0d tests passed",
             pass_count, pass_count + fail_count);
    $display("================================\n");
    if (fail_count == 0)
      $display("ALL TESTS PASSED\n");
    else
      $display("*** %0d TEST(S) FAILED ***\n", fail_count);
    $finish;
  end

endmodule
