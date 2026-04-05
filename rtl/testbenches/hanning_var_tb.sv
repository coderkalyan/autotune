`timescale 1ns/1ps
`include "../fixed.sv"

module hanning_var_tb;

    localparam int HANN_N     = 4096;
    localparam int CLK_PERIOD = 10;

    logic        clk;
    logic        rst;
    logic [9:0]  i_lag;
    logic [10:0] i_index;
    fixed_t      o_data_dut;
    fixed_t      o_data_ref;

    logic [11:0] expected_index;

    // DUT
    hanning_var dut (
        .clk    (clk),
        .rst    (rst),
        .i_lag  (i_lag),
        .i_index(i_index),
        .o_data (o_data_dut)
    );

    // Reference Hann LUT
    hanning #(
        .N(4096),
        .B(12)
    ) ref_hanning (
        .clk    (clk),
        .rst    (rst),
        .i_index(expected_index),
        .o_data (o_data_ref)
    );

    // Clock
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------
    // Expected mapping:
    //   lut_idx = i_index * 4096 / (2*i_lag)
    //
    // Valid index range:
    //   0 <= i_index < 2*i_lag
    // ------------------------------------------------------------
    function automatic int calc_expected_index(
        input int lag,
        input int idx
    );
        int denom;
        int tmp;
        begin
            denom = 2 * lag;

            if (denom <= 0) begin
                calc_expected_index = 0;
            end else begin
                tmp = (idx * HANN_N) / denom;

                if (tmp < 0)
                    tmp = 0;
                if (tmp > HANN_N-1)
                    tmp = HANN_N-1;

                calc_expected_index = tmp;
            end
        end
    endfunction

    task automatic check_one(
        input int lag,
        input int idx
    );
        int exp_idx;
        begin
            i_lag   = lag[9:0];
            i_index = idx[10:0];

            exp_idx = calc_expected_index(lag, idx);
            expected_index = exp_idx[11:0];

            // Wait for DUT/ref to settle
            @(posedge clk);
            @(posedge clk);

            // Optional direct internal index check
            if (dut.index_eff !== expected_index) begin
                $display("INDEX MISMATCH: lag=%0d idx=%0d dut.index_eff=%0d expected=%0d time=%0t",
                         lag, idx, dut.index_eff, exp_idx, $time);
                $fatal;
            end

            if (o_data_dut !== o_data_ref) begin
                $display("DATA MISMATCH: lag=%0d idx=%0d exp_idx=%0d dut_data=%0h ref_data=%0h time=%0t",
                         lag, idx, exp_idx, o_data_dut, o_data_ref, $time);
                $fatal;
            end
        end
    endtask

    task automatic sweep_lag(
        input int lag
    );
        int idx;
        int max_idx;
        int step;
        begin
            max_idx = 2*lag - 1;

            $display("---- Testing lag=%0d, valid index range 0..%0d ----", lag, max_idx);

            // edge and representative points
            check_one(lag, 0);

            if (max_idx >= 1) check_one(lag, 1);
            if (max_idx >= 2) check_one(lag, 2);

            check_one(lag, max_idx/4);
            check_one(lag, max_idx/2);
            check_one(lag, (3*max_idx)/4);
            check_one(lag, max_idx);

            // full sweep for small lags, sampled for large ones
            if (max_idx < 128) begin
                for (idx = 0; idx <= max_idx; idx++) begin
                    check_one(lag, idx);
                end
            end else begin
                step = max_idx / 32;
                if (step < 1) step = 1;

                for (idx = 0; idx <= max_idx; idx += step) begin
                    check_one(lag, idx);
                end

                if ((max_idx % step) != 0)
                    check_one(lag, max_idx);
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        i_lag = '0;
        i_index = '0;
        expected_index = '0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        // A range of lags
        sweep_lag(16);
        sweep_lag(32);
        sweep_lag(64);
        sweep_lag(128);
        sweep_lag(256);
        sweep_lag(480);
        sweep_lag(512);
        sweep_lag(960);
        sweep_lag(1023);

        $display("All hanning_var scaling checks passed.");
        $stop();
    end

endmodule