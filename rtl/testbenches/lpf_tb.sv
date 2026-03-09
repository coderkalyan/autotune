`timescale 1ns / 1ps

module lpf_tb;

  // Parameters
  localparam int CLK_PERIOD = 20;  // 50MHz
  localparam int FC_HZ = 1300;
  localparam real FS_HZ = 48000.0;

  // Fixed-point scaling (Q11.16)
  localparam real SCALE = 65536.0;
  localparam real TOLERANCE = 0.05;  // 5% error allowed due to quantization

  // Signals
  logic        clk = 0;
  logic        rst;
  logic [26:0] i_data;
  logic        i_valid;
  wire  [26:0] o_data;
  wire         o_valid;

  // Instantiate DUT
  lpf #(.FC_HZ(FC_HZ)) dut (.*);

  // Clock Generation
  always #(CLK_PERIOD / 2) clk = ~clk;

  // --- Golden Model Reference ---
  real ref_alpha = (2.0 * 3.1415927 * FC_HZ / FS_HZ) / (1.0 + (2.0 * 3.1415927 * FC_HZ / FS_HZ));
  real expected_y = 0;
  real actual_y_real;

  // --- Test Stimulus ---
  initial begin
    rst = 1;
    i_data = 0;
    i_valid = 0;
    repeat (5) @(posedge clk);
    rst = 0;
    @(posedge clk);

    $display("--- Starting Step Response Test ---");
    // Apply a Step Input: Value of 1.0 in Q11.16
    apply_input(1.0 * SCALE);

    repeat (1000) begin
      @(posedge clk);
      if (o_valid) begin
        check_output();
      end
    end

    $display("--- Test Completed ---");
    $finish;
  end

  // Task to drive input
  task apply_input(input logic [26:0] val);
    i_data  <= val;
    i_valid <= 1;
  endtask

  // --- Checking Logic ---
  task check_output();
    // $display("%d %d", i_data, o_data);
    // Calculate Golden Model in Real (Floating Point)
    expected_y = (ref_alpha * $itor($signed(i_data)) / SCALE) + (1.0 - ref_alpha) * expected_y;

    // Convert DUT output to Real
    actual_y_real = $itor($signed(o_data)) / SCALE;

    // Verification
    if (abs(expected_y - actual_y_real) > TOLERANCE) begin
      $error("Mismatch! Time: %0t | Expected: %f | Actual: %f", $time, expected_y, actual_y_real);
    end
  endtask

  function real abs(real val);
    return (val < 0) ? -val : val;
  endfunction

endmodule
