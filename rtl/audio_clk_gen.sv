`timescale 1ns/1ps

module audio_clk_gen #(
    parameter P24_BIT = 1
) (
    input logic i_clk_50M,
    input logic i_rst,
    output logic o_clk_12_28M,
    output logic o_clk_bit,
    output logic o_clk_100K
);

// PLL IP Instantiation 
// generate
//     if (24_BIT) begin : gen_24_bit
//         pll_mult_24_bit (
//             .refclk(i_clk_50M),
//             .i_rst(i_i_rst),
//             .outclk_0(o_clk_12_28M),
//             .outclk_1(o_clk_bit)
//         );
//     end 
//     else begin : gen_16_bit
//         pll_mult_16_bit (
//             .refclk(i_clk_50M),
//             .i_rst(i_i_rst),
//             .outclk_0(o_clk_12_28M),
//             .outclk_1(o_clk_bit)
//         );
//     end
// endgenerate

// TODO: the ip is not good for simulation, rather use the 
//       initial block below and comment out during synthesis

initial begin 
    o_clk_12_28M = 0;
    forever #40.69 o_clk_12_28M = ~o_clk_12_28M;
end

initial begin
    o_clk_bit = 0;
    forever #325.52 o_clk_bit = ~o_clk_bit;
end

// 100kHz Divider Logic 
localparam int I2C_TOGGLE = 250;

logic [7:0] i2c_cnt;

always_ff @(posedge i_clk_50M) begin
    if (i_rst) 
        i2c_cnt <= 0;
    else if (i2c_cnt == I2C_TOGGLE-1) 
        i2c_cnt <= 0;
    else 
        i2c_cnt <= i2c_cnt + 1;
end

always @(posedge i_clk_50M) begin 
    if (i_rst)
        o_clk_100K <= 1'b0;
    else if (i2c_cnt == I2C_TOGGLE-1)
        o_clk_100K <= ~o_clk_100K;
end


endmodule