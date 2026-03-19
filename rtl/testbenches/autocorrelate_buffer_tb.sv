`timescale 1ns/1ps
`include "../fixed.sv"

module autocorrelate_buffer_tb;

    localparam int STAMPS = 16;
    
    // --- Signals ---
    logic         clk;
    logic         rst;
    logic         i_valid;
    fmac_t        i_results[STAMPS];
    wire          o_busy;
    wire          o_valid;
    wire fmac_t   o_sample;

    // --- DUT Instantiation ---
    autocorrelate_buffer #(
        .STAMPS(STAMPS)
    ) dut (.*);

    // --- Clock Generation ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Test Stimulus ---
    initial begin
        // 1. Initialization
        rst     = 1;
        i_valid = 0;
        for (int i = 0; i < STAMPS; i++) i_results[i] = '0;
        
        repeat(5) @(posedge clk);
        @(negedge clk) rst = 0;
        repeat(2) @(posedge clk);

        // 2. First Vector: Incremental Values (0x100, 0x200, etc.)
        $display("Sending Vector 1...");
        @(negedge clk);
        for (int i = 0; i < STAMPS; i++) begin
            i_results[i] = fmac_t'((i + 1) << 8); 
        end
        i_valid = 1;
        @(posedge clk);
        @(negedge clk) i_valid = 0;

        // Wait for the drip-feed to finish (STAMPS cycles)
        wait_for_idle();

        // 3. Second Vector: Pattern (0xAAAA, 0xBBBB, etc.)
        $display("Sending Vector 2...");
        @(negedge clk);
        for (int i = 0; i < STAMPS; i++) begin
            i_results[i] = fmac_t'(48'hAAAA_0000_0000 + i);
        end
        i_valid = 1;
        @(posedge clk);
        @(negedge clk) i_valid = 0;

        wait_for_idle();

        $display("Testbench Finished.");
        $finish;
    end

    // Helper task to monitor the drip-feed
    task automatic wait_for_idle();
        int count = 0;
        // Wait for o_valid to start or o_busy to clear
        while (!o_valid && count < 10) begin
            @(posedge clk);
            count++;
        end
        
        $display("Drip-feed started...");
        while (o_valid) begin
            $display("Time %0t | o_sample: %h", $time, o_sample);
            @(posedge clk);
        end
        $display("Drip-feed finished.\n");
    endtask

endmodule
