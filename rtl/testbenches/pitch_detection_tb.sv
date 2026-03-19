`timescale 1ns/1ps
`include "../fixed.sv"

module tb_pitch_detection;

// --------------------------------------------------------------------------
// Parameters
// --------------------------------------------------------------------------
localparam int STAMPS = 16;
localparam SINE = 1;

// --------------------------------------------------------------------------
// Signals
// --------------------------------------------------------------------------
logic i_clk;
logic i_rst;
logic i_wr_en;
fixed_t i_proc_data;
fmac_t expected [0:1023]; 
fixed_t window [0:1279]; // enough space for 1024 samples + 256 wraparound samples

// --------------------------------------------------------------------------
// DUT
// --------------------------------------------------------------------------
pitch_detection #(
    .STAMPS(STAMPS)
) dut (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_wr_en(i_wr_en),
    .i_proc_data(i_proc_data)
);

// --------------------------------------------------------------------------
// Clock Generation (100 MHz)
// --------------------------------------------------------------------------
initial begin
    i_clk = 0;
    forever #5 i_clk = ~i_clk;
end

// --------------------------------------------------------------------------
// Helper Tasks 
// --------------------------------------------------------------------------
task compute_autocorrelation;
  input  fixed_t input_vec   [0:1023];
  output fmac_t results     [0:1023];

  int lag, n;
  logic signed [63:0] acc;

  begin
    // initialize results
    for (lag = 0; lag < 1024; lag++) begin
      results[lag] = '0;
    end

    // compute autocorrelation
    for (lag = 0; lag < 1024; lag++) begin
      acc = '0;

      for (n = 0; n < 1024 - lag; n++) begin
        acc += input_vec[n] * input_vec[n + lag];
      end

      results[lag] = fmac_t'(acc[63:16]);
    end
  end
endtask

task generate_sine_60hz;
    input  int     num_samples;                    // how many samples to generate
    input  real    sample_rate_hz;                // e.g., 48000.0
    input  real    amplitude;                     // e.g., 1000.0
    output fixed_t out_vec [0:1279];              // output sample vector

    real t;
    real dt;
    real value;
    int i;

    begin
        dt = 1.0 / sample_rate_hz;

        // initialize whole vector
        for (i = 0; i < 1280; i++) begin
            out_vec[i] = '0;
        end

        // fill requested number of samples
        for (i = 0; i < num_samples && i < 1280; i++) begin
            t = i * dt;

            // 60 Hz sine wave
            value = amplitude * $sin(2.0 * 3.141592653589793 * 60.0 * t);

            out_vec[i] = fixed_t'($rtoi(value));
        end
    end
endtask

task apply_vector_1024;
  input fixed_t in_vec [0:1023];

  int i;

  begin
    // ensure clean start
    i_wr_en     = 0;
    i_proc_data = '0;
    @(posedge i_clk);

    // stream samples
    for (i = 0; i < 1024; i++) begin
      @(posedge i_clk);
      i_proc_data = in_vec[i];
      i_wr_en     = 1;
    end

    // deassert write
    @(posedge i_clk);
    i_wr_en     = 0;
    i_proc_data = '0;
  end
endtask

task apply_vector_256;
  input fixed_t in_vec [0:255];

  int i;

  begin
    // ensure clean start
    i_wr_en     = 0;
    i_proc_data = '0;
    @(posedge i_clk);

    // stream samples
    for (i = 0; i < 256; i++) begin
      @(posedge i_clk);
      i_proc_data = in_vec[i];
      i_wr_en     = 1;
    end

    // deassert write
    @(posedge i_clk);
    i_wr_en     = 0;
    i_proc_data = '0;
  end
endtask

task automatic measure_cycles_between_edges(
  ref logic clk,
  ref logic sig,
  input string name
);
  int count;

  begin
    // wait for first rising edge of signal
    @(posedge sig);

    count = 0;

    // count clock cycles until next rising edge
    while (1) begin
      @(posedge clk);
      count++;

      @(posedge sig) begin
        $display("[%0t] Cycles between %s rising edges = %0d", $time, name, count);
        break;
      end
    end
  end
endtask


// --------------------------------------------------------------------------
// Initial Stimulus
// --------------------------------------------------------------------------
integer j;
integer k;
initial begin
    // Initialize signals
    i_rst       = 1;
    i_wr_en     = 0;
    i_proc_data = '0;
    k = 0;

    // deassert reset after a few cycles
    repeat (5) @(posedge i_clk);
    i_rst = 0;

    if(SINE) begin 
      $display("Testing with 60 Hz sine wave input...");
      // Setup expected results
      generate_sine_60hz(1280, 48000.0, 1000.0, window);
      compute_autocorrelation(window[0:1023], expected);

      // Applying sine wave 
      apply_vector_1024(window[0:1023]);

    end else begin 
      $display("Testing with impulse input...");
      // Setup expected results
      for (int h= 0; h < 1280; h++) begin
        window[h] = '0;
      end
      window[0] = fixed_t'(1000); // impulse at n=0
      compute_autocorrelation(window[0:1023], expected);
      
      // Applying impulse 
      apply_vector_1024(window[0:1023]);
    end

    if (dut.enable !== 1'b1) begin
        $display("Error: enable signal did not go high after filling buffer w 1024 samples");
        $stop;
    end 
    @(posedge i_clk);
    if (dut.x_addr !== '0) begin
        $display("Error: x_addr did not reset after filling buffer w 1024 samples");
        $stop;
    end 

    
    while(!dut.all_done) begin 
        @(posedge dut.single_done) begin
            repeat (2)@(posedge i_clk);
            for (j = 0; j < STAMPS; j++) begin
                if (dut.results[j] !== expected[(k * STAMPS) + j]) begin
                    $display("ERROR: Did not receive expected results for iteration %d, stamp %d. Got %d, expected %d", k, j, dut.results[j], expected[(k * STAMPS) + j]);
                    $stop();
                end
            end
            k++;
        end
        @(posedge i_clk);
    end

    $display("WINDOW 1 RESULTS MATCH EXPECTED!");

    // Write additional 256 samples to trigger wraparound and test circular buffer logic
    if(SINE) begin 
      $display("Applying wraparound test samples...");
      // Setup expected results for wraparound test
      compute_autocorrelation(window[256:1279], expected);

      // Applying sine wave 
      apply_vector_256(window[1024:1279]);

    end else begin 
      $display("Applying wraparound test samples...");
      // Setup expected results for wraparound test
      compute_autocorrelation(window[256:1279], expected);;
      
      // Applying impulse 
      apply_vector_256(window[1024:1279]);
    end

    if (dut.enable !== 1'b1) begin
        $display("Error: enable signal did not go high after filling buffer w 1024 samples");
        $stop;
    end 
    @(posedge i_clk);
    if (dut.x_addr !== '0) begin
        $display("Error: x_addr did not reset after filling buffer w 1024 samples");
        $stop;
    end 

    k = 0; // reset k to check results for wraparound test
    while(!dut.all_done) begin 
        @(posedge dut.single_done) begin
            repeat (2)@(posedge i_clk);
            for (j = 0; j < STAMPS; j++) begin
                if (dut.results[j] !== expected[(k * STAMPS) + j]) begin
                    $display("ERROR: Did not receive expected results for iteration %d, stamp %d. Got %d, expected %d", k, j, dut.results[j], expected[(k * STAMPS) + j]);
                    $stop();
                end
            end
            k++;
        end
        @(posedge i_clk);
    end

    $display("WINDOW 2 RESULTS MATCH EXPECTED!");

    $display("YAHOO! ALL TESTS PASSED!");
    $stop;
end

endmodule