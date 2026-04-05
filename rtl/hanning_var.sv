`include "fixed.sv"

module hanning_var(
    input wire           clk,
    input wire           rst,
    input wire [9:0]     i_lag,
    input wire [9:0]    i_index, // worse case 2*490 indexes 
    output fixed_t       o_data
);

/*
    lut_idx[i] = i_index * 1024 / 2*i_lag
               = i_index * 512 / i_lag
    weff[i] = wlut[lut_idx[i]]
*/

localparam fixed_t LENGTH_FIXED = fixed_t'({1'b0,10'd512,16'd0}); 
logic [9:0] index_eff;
fixed_t lag_flipped;
fixed_t scaling_factor;
fixed_t index_fixed;
fixed_t index_fixed_reg;

assign index_fixed = fixed_t'({1'b0, i_index, 16'd0});

hanning #(
    .N(1024)
) hanning_inst (
    .clk(clk),
    .rst(rst),
    .i_index(index_eff),
    .o_data(o_data)
);

// LUT to perform reciprocal of i_lag
reciprocal_lut iRL(
    .target_lag(i_lag),  
    .fliped_target(lag_flipped)
);

// Multiplication to get the effective index for the hanning window
// Pipeline to prevent ripple through
always @(posedge clk) begin
    if (rst) begin
        scaling_factor <= 0;
        index_fixed_reg <= 0;
    end else begin
        scaling_factor <= fixed_mul(LENGTH_FIXED, lag_flipped);
        index_fixed_reg <= index_fixed;
    end
end

fixed_t index_mul;
assign index_mul = fixed_mul(index_fixed_reg, scaling_factor);
assign index_eff = index_mul[16 +: 10];

endmodule
