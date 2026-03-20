`timescale 1ns/1ps
`include "../fixed.sv"

module pitch_detection_all_tb();

// --------------------------------------------------------------------------
// Parameters
// --------------------------------------------------------------------------
localparam int WINDOW_SIZE = 1024;
localparam int STAMPS      = 16;
localparam int WBITS       = $clog2(WINDOW_SIZE);
localparam int SAMPLING_FREQ = 48_000;
localparam int TIMEOUT = 1_500_000_000; // 30 timeout at 50 MHz clock 
// --------------------------------------------------------------------------
// Signals
// --------------------------------------------------------------------------

// DUT Inputs
logic clk;
logic rst;
logic i_wr_en;
fixed_t i_proc_data;

// DUT Outputs
logic [WBITS-1:0] o_period;
logic o_valid;
logic o_done;


// --------------------------------------------------------------------------
// ADC input Model
// --------------------------------------------------------------------------
sine_source_48khz #(
    .CLK_HZ(50_000_000),
    .SAMPLE_HZ(48_000),
    .TONE_HZ(660.0),
    .AMPLITUDE(1000.0)
) src (
    .clk(clk),
    .rst(rst),
    .o_wr_en(i_wr_en),
    .o_data(i_proc_data)
);

// --------------------------------------------------------------------------
// DUT
// --------------------------------------------------------------------------
pitch_detection #(
    .WINDOW_SIZE(WINDOW_SIZE),
    .STAMPS(STAMPS)
) dut (
    .clk(clk),
    .rst(rst),
    .i_wr_en(i_wr_en),
    .i_proc_data(i_proc_data),
    .o_period(o_period),
    .o_valid(o_valid),
    .o_done(o_done)
);

// --------------------------------------------------------------------------
// Clock Generation (100 MHz)
// --------------------------------------------------------------------------
initial begin
    clk = 0;
    forever #10 clk = ~clk;
end

// --------------------------------------------------------------------------
// Helper Tasks 
// --------------------------------------------------------------------------


// --------------------------------------------------------------------------
// Initial Stimulus
// --------------------------------------------------------------------------
initial begin 
    // Initial Conditions 
    clk = 0;
    rst = 1;
    i_wr_en = 0;
    i_proc_data = '0;

    // deassert reset after a few cycles
    repeat (5) @(posedge clk);
    rst = 0;
    $display("Starting simulation...");

    fork
      begin : MAIN
        // Wait for the circular buffer to fill up and for the first valid output
        wait (dut.enable == 1); 
        $display("Circular Buffer fulled 1024 samples at %0t", $time);

        wait (o_done == 1);
        $display("Pitch detection done at %0t", $time);
        $display("Detected period: %0d samples", o_period);
        $display("Detected frequency: %0d Hz", SAMPLING_FREQ / o_period);

        $display("YAHOO! ALL TESTS PASSED!");
        $stop();
      end

      begin : TIMER
        repeat (6) begin 
            repeat (TIMEOUT) @(posedge clk);
        end
        $display("[%0t] ERROR: Timeout!", $time);
        $stop;
      end
    join_any

    $display("YAHOO! ALL TESTS PASSED!");
    $stop();
end 

endmodule 



module sine_source_48khz #(
    parameter int CLK_HZ      = 50_000_000,   // input clock frequency
    parameter int SAMPLE_HZ   = 48_000,        // ADC/sample rate
    parameter real TONE_HZ    = 60.0,          // sine frequency
    parameter real AMPLITUDE  = 1000.0         // sine amplitude in fixed_t units
)(
    input  logic   clk,
    input  logic   rst,

    output logic   o_wr_en,
    output fixed_t o_data
);

    localparam int CLKS_PER_SAMPLE = CLK_HZ / SAMPLE_HZ;
    localparam real TWO_PI = 6.28318530717958647692;

    int  clk_count;
    int  sample_index;
    real t;
    real sample_val;

    always_ff @(posedge clk) begin
        if (rst) begin
            clk_count    <= 0;
            sample_index <= 0;
            o_wr_en      <= 1'b0;
            o_data       <= '0;
        end else begin
            o_wr_en <= 1'b0;

            if (clk_count == CLKS_PER_SAMPLE - 1) begin
                clk_count <= 0;

                // Generate one new 48 kHz sample
                t          = sample_index / real'(SAMPLE_HZ);
                sample_val = AMPLITUDE * $sin(TWO_PI * TONE_HZ * t);

                o_data  <= fixed_t'($rtoi(sample_val));
                o_wr_en <= 1'b1;

                sample_index <= sample_index + 1;
            end else begin
                clk_count <= clk_count + 1;
            end
        end
    end

endmodule