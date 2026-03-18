`timescale 1ns/1ps

module clamp_denoise_tb;
    // Parameters and fixed-point constants
    localparam real SCALE = 65536.0;
    localparam real TOLERANCE = 2.0 / SCALE;
    localparam real REF_RATIO = 0.3;

    logic   clk;
    logic   rst;
    fixed_t i_data, i_amax, o_data;

    // DUT Instance
    clamp_denoise dut (
        .clk(clk),
        .rst(rst),
        .i_data(i_data),
        .i_amax(i_amax),
        .o_data(o_data)
    );

    // Clock Generation
    always #5 clk = ~clk;

    // Reference Model Function
    function automatic real ref_clamp(real data, real amax);
        real threshold = REF_RATIO * amax;
        if (data > threshold)
            return data - threshold;
        else if (data < -threshold)
            return data + threshold;
        else
            return 0.0;
    endfunction

    real test_val, test_max, expected_y, actual_y;

    initial begin
        // Initialize
        clk = 0;
        rst = 1;
        i_data = 0;
        i_amax = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Starting Clamp Denoise Test...");

        // Test Case 1: Positive value above threshold
        // data=1.0, max=1.0 -> threshold=0.3 -> expected=0.7
        drive_test(1.0, 1.0);

        // Test Case 2: Positive value below threshold
        // data=0.2, max=1.0 -> threshold=0.3 -> expected=0.0
        drive_test(0.2, 1.0);

        // Test Case 3: Negative value below (more negative) threshold
        // data=-1.0, max=1.0 -> threshold=0.3 -> expected=-0.7
        drive_test(-1.0, 1.0);

        // Test Case 4: Negative value above threshold
        // data=-0.1, max=1.0 -> threshold=0.3 -> expected=0.0
        drive_test(-0.1, 1.0);

        // Test Case 5: Large Amplitude Max
        // data=5.0, max=10.0 -> threshold=3.0 -> expected=2.0
        drive_test(5.0, 10.0);

        $display("All Clamp Tests Passed Successfully.");
        $finish;
    end

    // Helper task to drive signals and check results
    task drive_test(input real d, input real m);
        begin
            i_data = `FIXED_RTOF(d);
            i_amax = `FIXED_RTOF(m);

            // Combination logic, so we can check after a small delta or next posedge
            #1;

            expected_y = ref_clamp(d, m);
            actual_y   = `FIXED_FTOR(o_data);

            if (abs(actual_y - expected_y) > TOLERANCE) begin
                $display("ERROR: Data=%f, Max=%f | Expected=%f, Got=%f", d, m, expected_y, actual_y);
                $fatal;
            end else begin
                $display("PASS: Data=%0.3f, Max=%0.3f | Out=%0.3f", d, m, actual_y);
            end
            @(posedge clk);
        end
    endtask

    function automatic real abs(input real x);
        return (x < 0) ? -x : x;
    endfunction

endmodule
