`timescale 1ns/1ps

`include "fixed.sv"

module lpf #(
    parameter int FC_HZ = 1300
) (
    input  wire    clk,
    input  wire    rst,
    input  fixed_t i_data,
    input  wire    i_valid,
    output fixed_t o_data,
    output wire    o_valid
);
    localparam real FS_HZ = 48000.0;
    localparam real PI = 3.1415927;
    localparam real X = 2.0 * PI * real'(FC_HZ) / FS_HZ;
    localparam real ALPHA = X / (1.0 + X);

    localparam fixed_t FONE   = `FIXED_RTOF(1.0);
    localparam fixed_t FALPHA = `FIXED_RTOF(ALPHA);

    // y[n] = alpha * x[n] + (1 - alpha) * y[n-1]
    logic signed [53:0] x;
    fixed_t y;
    always_comb x = fixed_mul_raw(FALPHA, i_data) + fixed_mul_raw(FONE - FALPHA, y);

    always_ff @(posedge clk) begin
        if (rst)
            y <= '0;
        else if (i_valid)
            y <= fixed_t'(x[16 +: 27]);
    end

    logic valid;
    always_ff @(posedge clk) begin
        if (rst)
            valid <= '0;
        else
            valid <= i_valid;
    end

    assign o_valid = valid;
    assign o_data  = y;
endmodule
