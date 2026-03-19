`timescale 1ns/1ps
`include "../fixed.sv"

module f0_detect_tb;

    // --- Parameters ---
    localparam int WINDOW_SIZE = 1024;
    localparam int LAG_MIN     = 200;
    localparam int LAG_MAX     = 1024;
    localparam int WBITS       = $clog2(WINDOW_SIZE);

    // --- Signals ---
    logic               clk;
    logic               rst;
    logic               i_start;
    logic               i_valid;
    fmac_t             i_sample;
    
    wire                o_done;
    wire                o_valid;
    wire [WBITS-1:0]    o_period;

    // --- DUT Instantiation ---
    f0_detect #(
        .WINDOW_SIZE(WINDOW_SIZE),
        .LAG_MIN(LAG_MIN),
        .LAG_MAX(LAG_MAX)
    ) dut (.*);

    // --- Clock Generation ---
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz clock [cite: 89-90]

    // --- Stimulus Logic ---
    initial begin
        // 1. Initialization & Reset
        rst     = 1;
        i_start = 0;
        i_valid = 0;
        i_sample = '0;
        repeat(10) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // 2. Test Case 1: Valid Peak
        // Target Period: 300 samples (within LAG_MIN 200 to LAG_MAX 1024)
        // Decay: Slow enough that peak at 300 > 0.25 * peak at 0
        $display("--- Test 1: Valid Detection (Lag 300) ---");
        run_detection_test(300.0, 0.001); 

        // 3. Test Case 2: Rejected Peak (Threshold not met)
        // Target Period: 300 samples
        // Decay: Fast enough that peak at 300 < 0.25 * peak at 0 (exp(-0.006 * 300) approx 0.16)
        $display("\n--- Test 2: Threshold Rejection (Heavy Decay) ---");
        run_detection_test(300.0, 0.006);

        $display("\nAll test sequences finished.");
        $finish;
    end

    // --- Helper Task: Generate Decaying Cosine ---
    task automatic run_detection_test(
        input real target_lag,
        input real decay_constant
    );
        real sample_val;
        real angle;
        
        @(negedge clk);
        i_start = 1;
        @(negedge clk);
        i_start = 0;

        for (int n = 0; n < WINDOW_SIZE; n++) begin
            // Cosine wave: cos(2 * pi * n / target_lag)
            // Exponential Decay: e^(-decay * n)
            // Scaling: Using 2^32 to provide plenty of headroom in 48-bit fmac_t
            angle = (2.0 * 3.14159265 * real'(n)) / target_lag;
            sample_val = $cos(angle) * $exp(-decay_constant * real'(n));
            
            @(negedge clk);
            i_sample = fmac_t'(sample_val * 65536.0); 
            i_valid  = 1;
            @(negedge clk);
        end

        i_valid = 0;
        
        // Wait for POST state to finish
        wait(o_done);
        @(negedge clk);
        
        if (o_valid) begin
            $display("[RESULT] Valid Peak Detected at Period: %0d", o_period);
        end else begin
            $display("[RESULT] No Valid Peak Found (Threshold Rejection)");
        end
    endtask

endmodule
