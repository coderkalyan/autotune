`timescale 1ns/1ps

`include "../fixed.sv"

module autocorrelate_tb;

    // --- Parameters & Signals ---
    localparam int WINDOW_SIZE = 1024;
    localparam int WBITS       = $clog2(WINDOW_SIZE);

    logic               clk;
    logic               rst;
    logic [WBITS-1:0]   i_lag;
    logic               i_en;
    fixed_t             i_xdata;
    fixed_t             i_ydata;

    wire  [WBITS-1:0]   o_yaddr;
    wire  fmac_t        o_result;
    wire                o_done;

    // --- Memory Model ---
    // Stores 1024 samples of fixed_t data
    fixed_t memory [WINDOW_SIZE];
    logic [WBITS-1:0] x_addr;

    // --- Device Under Test ---
    autocorrelate #(
        .WINDOW_SIZE(WINDOW_SIZE)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .i_lag   (i_lag),
        .i_en    (i_en),
        .i_xdata (i_xdata),
        .i_ydata (i_ydata),
        .o_yaddr (o_yaddr),
        .o_result(o_result),
        .o_done  (o_done)
    );

    // --- Clock Generation ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Synchronous Memory Read Logic ---
    // Mimics a dual-port synchronous RAM.
    // Data appears one cycle after the address is presented.
    always_ff @(posedge clk) begin
        i_ydata <= memory[o_yaddr];
        i_xdata <= memory[x_addr];
    end

    // --- X-Address Tracking ---
    // The testbench increments x_addr sequentially when the DUT is active.
    // Based on the DUT state machine: x starts at 0 during ACCUMULATE.
    always_ff @(posedge clk) begin
        if (rst || i_en) begin
            x_addr <= '0;
        end else begin
            x_addr <= x_addr + 1;
        end
    end

    // --- Golden Reference Function ---
    // R[lag] = sum_{n=0}^{N-1} x[n] * x[n+lag]
    // Note: n+lag wraps around the 1024 window or clips depending on desired DSP behavior.
    // This implementation follows the DUT's internal loop structure
    function automatic fmac_t get_golden_result(logic [WBITS-1:0] lag);
        logic signed [63:0] accum = '0;
        for (int i = lag; i < WINDOW_SIZE; i++) begin
            accum = accum + fixed_mul_raw(memory[i - lag], memory[i]);
        end
        return fmac_t'(accum[63:16]);
    endfunction

    // --- Stimulus & Verification ---
    initial begin
        // 1. Initialization
        rst     = 1;
        i_en    = 0;
        i_lag   = 0;
        for (int i = 0; i < WINDOW_SIZE; i++) memory[i] = '0;
        repeat(5) @(posedge clk);
        rst = 0;

        // 2. Load Test Data: Ramp Pattern
        for (int i = 0; i < WINDOW_SIZE; i++) begin
            memory[i] = fixed_t'(i << 12); // Small values to avoid 64-bit overflow
        end

        // 3. Test various Lag values
        test_lag(0);    // Zero lag (Autocorrelation Peak)
        test_lag(10);   // Small lag
        test_lag(512);  // Large lag

        $display("\nAll tests completed.");
        $finish;
    end

    // Helper task to run a single lag test
    task automatic test_lag(input logic [WBITS-1:0] lag_val);
        fmac_t expected;
        i_lag = lag_val;

        @(negedge clk);
        i_en = 1;
        @(negedge clk);
        i_en = 0;

        // Wait for DUT to complete 1024 accumulations
        wait(o_done);

        expected = get_golden_result(lag_val);

        if (o_result === expected) begin
            $display("[PASS] Lag %0d: Got %h, Expected %h", lag_val, o_result, expected);
        end else begin
            $display("[FAIL] Lag %0d: Got %h, Expected %h", lag_val, o_result, expected);
        end

        @(posedge clk);
    endtask

endmodule
