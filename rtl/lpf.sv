module lpf #(
    parameter int FC_HZ = 1300
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [26:0] i_data,
    input  wire        i_valid,
    output wire [26:0] o_data,
    output wire        o_valid
);
    localparam real FS_HZ = 48000.0;
    localparam real PI = 3.1415927;
    localparam real X = 2.0 * PI * real'(FC_HZ) / FS_HZ;
    localparam real ALPHA = X / (1.0 + X);

    localparam logic [26:0] alpha = ALPHA * real'(1 << 16);
    localparam logic [26:0] one   = 1 << 16;

    logic [53:0] x;
    logic [26:0] y;
    always_comb x = (alpha * i_data + (one - alpha) * y);
    always_ff @(posedge clk) begin
        if (rst)
            y <= '0;
        else if (i_valid)
            y <= x[16 +: 27];
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
