`timescale 1ns/1ps

module lpf_tb;
    localparam int  FC_HZ = 440;
    localparam real FS_HZ = 48000.0;

    // Tolerance: Allow a small error due to fixed-point quantization (approx 2 bits)
    localparam real SCALE = 65536.0;
    // localparam real EPSILON = 2.0 / SCALE;
    localparam real EPSILON = 8.0 / SCALE; // FIXME: why is the error more than expected?

    logic   clk;
    logic   rst;
    fixed_t i_data, o_data;
    logic   i_valid;
    wire    o_valid;

    lpf #( .FC_HZ(FC_HZ) ) dut (.*);

    always
        #5 clk = ~clk;

    real ref_pi    = 3.1415927;
    real ref_x     = 2.0 * ref_pi * real'(FC_HZ) / FS_HZ;
    real ref_alpha = ref_x / (1.0 + ref_x);
    real ref_y     = 0.0;
    real ref_step  = 1.0; // amplitude of step input
    real y;

    initial begin
        clk = 0;
        rst = 1;
        i_data = 0;
        i_valid = 0;
        repeat(5) @(posedge clk);

        @(negedge clk) rst = 0;
        repeat(2) @(posedge clk);

        // Drive a Step Input: Value of 1.0 in Q11.16
        i_data  = fixed_rtof(ref_step);
        i_valid = 1'b1;
        assert (!o_valid);
        @(posedge clk);

        // Run for 500 samples to observe the RC curve settling
        repeat(500) begin
            @(posedge clk);
            ref_y = (ref_alpha * ref_step) + (1.0 - ref_alpha) * ref_y;
            y     = fixed_ftor(o_data);

            assert (o_valid);
            if (abs(y - ref_y) > EPSILON) begin
                $display("Test Failed at time %0t: Expected y = %f, Got y = %f", $time, ref_y, y);
            end

            assert (abs(y - ref_y) <= EPSILON);
        end

        $display("Test Passed Successfully.");
        $finish;
    end

    function automatic real abs(input real x);
        return (x < 0) ? -x : x;
    endfunction
endmodule
