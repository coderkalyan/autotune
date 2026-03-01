`timescale 1ns/1ps

module audio_clk_gen_tb;

  // -------------------------
  // TB clocks / reset
  // -------------------------
  logic i_clk_50M;
  logic i_rst;

  // DUT outputs
  logic o_clk_12_28M;
  logic o_clk_bit;
  logic o_clk_100K;

  // -------------------------
  // Instantiate DUT
  // -------------------------
  audio_clk_gen #(.P24_BIT(1)) dut (
    .i_clk_50M    (i_clk_50M),
    .i_rst        (i_rst),
    .o_clk_12_28M (o_clk_12_28M),
    .o_clk_bit    (o_clk_bit),
    .o_clk_100K   (o_clk_100K)
  );

  // 50 MHz clock (20 ns period)
  initial begin
    i_clk_50M = 1'b0;
    forever #10 i_clk_50M = ~i_clk_50M;
  end

  // Reset sequence
  initial begin
    i_rst = 1'b1;
    repeat (5) @(posedge i_clk_50M);
    i_rst = 1'b0;
  end

  // -------------------------
  // Helpers to measure periods
  // -------------------------
  task automatic measure_period_posedge(
    ref logic sig,
    output realtime period_ns
  );
    realtime t1, t2;
    @(posedge sig); t1 = $realtime;
    @(posedge sig); t2 = $realtime;
    period_ns = (t2 - t1);
  endtask

  // -------------------------
  // Expected timing (based on YOUR RTL delays/dividers)
  // -------------------------
  // Your RTL uses: #81.67 toggle for o_clk_12_28M, so full period = 2*81.67 ns
  localparam realtime EXP_T12_NS      = 2.0 * 81.67;       // ns
  localparam realtime EXP_TBIT_NS     = 2.0 * 651.89;      // ns

  // 48K divider: toggles every LRCLK_TOGGLE_COUNT posedges of o_clk_12_28M
  // => full period = 2 * LRCLK_TOGGLE_COUNT * T12
  localparam int      LRCLK_TOGGLE_COUNT = 128;
  localparam realtime EXP_T48K_NS     = 2.0 * LRCLK_TOGGLE_COUNT * EXP_T12_NS;

  // 400K output in your code toggles every I2C_TOGGLE cycles of 50 MHz
  // => full period = 2 * I2C_TOGGLE * 20 ns
  localparam int      I2C_TOGGLE      = 250;
  localparam realtime EXP_t100K_NS    = 2.0 * I2C_TOGGLE * 20.0; // ns

  // Tolerances (simulation scheduling/jitter)
  localparam realtime TOL_FAST_NS     = 1.0;   // for fast clocks
  localparam realtime TOL_SLOW_NS     = 50.0;  // for slower/divided clocks

  // -------------------------
  // Main checks
  // -------------------------
  initial begin
    realtime t12;
    realtime tbit;
    realtime t100;

    // Wait for reset deassertion
    @(negedge i_rst); 

    // Give a little time for internal clocks/dividers to settle
    repeat (10) @(posedge i_clk_50M);

    // Measure and check o_clk_12_28M
    measure_period_posedge(o_clk_12_28M, t12);

    // Measure and check o_clk_bit
    measure_period_posedge(o_clk_bit, tbit);

    // Measure and check o_clk_100K
    measure_period_posedge(o_clk_100K, t100);

    // Optional: print derived frequencies
    $display("Derived frequencies (approx):");
    $display("  o_clk_12_28M ~ %0.3f MHz", 1000.0 / t12);   // 1/ns -> GHz; 1000/t(ns) = MHz
    $display("  o_clk_bit    ~ %0.3f MHz", 1000.0 / tbit);
    $display("  o_clk_100K   ~ %0.3f kHz", 1_000_000.0 / t100); // 1e6/t(ns)=kHz

    $stop();

  end

endmodule