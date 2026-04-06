`timescale 1ns/1ps
`include "../fixed.sv"

module nearest_note_tb;

  parameter int W      = 10;
  parameter int NUM_RANDOM_TESTS = 5000;
  localparam real epsilon = 0.01; // Tolerance for floating-point comparison

  //--------------------------------------------------------------------------
  // DUT interface
  //--------------------------------------------------------------------------
  logic [W-1:0]     target_lag;
  logic [W-1:0]     actual_lag;
  fixed_t reciprocal_pitch_factor;

  //--------------------------------------------------------------------------
  // Instantiate DUT
  // Replace lag_to_reciprocal with your actual module name
  //--------------------------------------------------------------------------
  note_selection dut (
    .target_lag(target_lag),
    .actual_lag(actual_lag),
    .shift_ratio(reciprocal_pitch_factor)
  );

  //--------------------------------------------------------------------------
  // Reference model
  //--------------------------------------------------------------------------

  function automatic real ref_model (
    input logic [W-1:0] t_lag,
    input logic [W-1:0] a_lag
  );
    int unsigned sat_actual;

    begin
        if (t_lag > 2*a_lag)
            sat_actual = 2*a_lag;
        else if (t_lag < a_lag/2)
            sat_actual = a_lag/2;
        else
            sat_actual = t_lag;

        ref_model = real'(sat_actual) / real'(a_lag); // This is the reciprocal of the pitch factor
        
    end
  endfunction

  //--------------------------------------------------------------------------
  // Scoreboard task
  //--------------------------------------------------------------------------
  task automatic check_case(
    input logic [W-1:0] t_lag,
    input logic [W-1:0] a_lag
  );
    real expected;
    real actual;
    real diff;
    begin
      target_lag = t_lag;
      actual_lag = a_lag;

      #1; // allow combinational settle

      expected = ref_model(t_lag, a_lag);
      actual = ($itor(reciprocal_pitch_factor) / 65536.0); 

      diff = actual - expected;
      if (diff < 0.0)
        diff = -diff;

      if (diff > epsilon) begin
        $display("MISMATCH: target_lag=%0d actual_lag=%0d expected=%0f  got=%0f",
               t_lag, a_lag, expected, actual);
        $stop();
      end
    end
  endtask

  //--------------------------------------------------------------------------
  // Directed tests
  //--------------------------------------------------------------------------
  initial begin
    target_lag = '0;
    actual_lag = '0;

    for (int i = 48; i < 480; i++) begin
        for (int j = 1; j < 25; j++) begin
            target_lag = $rtoi(i*0.1*j);
            actual_lag = i;
            #1;
            if (target_lag >= 1023) begin 
                continue;
            end else begin
                check_case(i*0.1*j, i);
            end
        end
    end
    $display("MIDI NOTE TESTS PASSED!");

    target_lag = 0;

    // A4 Test (440 Hz)
    target_lag = 0;
    actual_lag = 100; // close to 440 but not exactly

    check_case(109, actual_lag);

    // A5 Test (880 Hz)
    target_lag = 0;
    actual_lag = 50; // close to 880 but not exactly

    check_case(55, actual_lag);


    $display("NEAREST NOTE TESTS PASSED!"); 

    $display("YAHOO! ALL TESTS PASSED!");
    $stop();
  end

endmodule