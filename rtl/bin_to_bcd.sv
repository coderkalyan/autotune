module bin_to_bcd (
    input  [26:0] freq_q1116,
    output reg [23:0] bcd
);
    // Extract integer Hz part: bits [26:16] (11 bits, unsigned, 0-1023)
    wire [10:0] int_part  = freq_q1116[26:16];

    // Extract 2 fractional decimal digits (0-99):
    // frac_dec = floor(frac_bits * 100 / 65536)
    wire [31:0] frac_product = {16'd0, freq_q1116[15:0]} * 32'd100;
    wire [6:0]  frac_dec     = frac_product[22:16];

    always @(*) begin
        bcd[23:20] = int_part / 1000;
        bcd[19:16] = (int_part % 1000) / 100;
        bcd[15:12] = (int_part % 100) / 10;
        bcd[11:8]  = int_part % 10;
        bcd[7:4]   = frac_dec / 10;
        bcd[3:0]   = frac_dec % 10;
    end
endmodule
