`timescale 1ns/1ps
`include "../fixed.sv"

module normalization_tb;
    import global_enums::*;

    localparam real PI      = 3.14159265358979;
    localparam real FS_HZ   = 48000.0;
    localparam real FREQ_HZ = 440.0;

    logic   clk, rst;
    fixed_t i_data;
    mode_t  i_mode;
    logic   i_valid;
    fixed_t o_data;
    logic   o_valid;

    real amp;

    normalization_2 #(.SIM(1)) dut (.*);

    always #5 clk = ~clk;

    initial begin
        clk = 0; rst = 1; i_data = 0; i_valid = 0; i_mode = PASSTHROUGH;
        repeat(5) @(posedge clk);
        @(negedge clk) rst = 0;

        for (int i = 0; ; i++) begin
            @(negedge clk);
            i_valid = (i % 5 == 0) ? 1 : 0;
            if (i_valid) begin
                amp = ($time >= 1000000) ? (($time >= 2000000) ? 90.0 : 128.0) : 282.0;
                i_data = `FIXED_RTOF(amp * $sin(2.0 * PI * FREQ_HZ / FS_HZ * i));
            end
        end
    end

endmodule
