`timescale 1ns / 1ps

`include "fixed.sv"

module hanning #(
    parameter int N = 4096,
    parameter int B = $clog2(N)
) (
    input  wire              clk,
    input  wire              rst,
    input  wire    [B - 1:0] i_index,
    output fixed_t           o_data
);
  logic [31:0] rom[N];
  initial $readmemh("hanning.mem", rom);
  // initial $readmemh("/home/kalyan/Documents/school/ece554/autotune/rtl/hanning.mem", rom);

  always_comb o_data = fixed_t'(rom[i_index][26:0]);
endmodule
