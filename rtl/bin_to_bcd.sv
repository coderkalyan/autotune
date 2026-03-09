module bin_to_bcd (
    input [23:0] bin,
    output reg [31:0] bcd
);
    // Double Dabble algorithm
    integer i;

    always @(bin) begin
        bcd = 32'd0;
        for (i = 23; i >= 0; i = i - 1) begin
            // Add 3 to columns >= 5
            if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;
            if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;
            if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
            if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
            if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
            if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
            if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
            if (bcd[31:28] >= 5) bcd[31:28] = bcd[31:28] + 3;

            // Shift left one
            bcd = bcd << 1;
            bcd[0] = bin[i];
        end
    end
endmodule
