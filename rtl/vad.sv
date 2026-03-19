module vad #(
    parameter P24_BIT = 1,
    parameter K =  5,      // Essentially how snappy the envelope is
    parameter THRESHOLD = 2000,
    parameter DATA_WIDTH = P24_BIT ? 24 : 16
)(
    input logic i_clk,
    input logic i_rst,
    input logic new_data,
    input logic signed [DATA_WIDTH-1:0] i_data,
    output logic active
);

// Extract the signal envelope 
// y[n] = y[n-1] + (abs(x[n]) - y[n-1]) / 2^k
logic [DATA_WIDTH-1:0] magnitude;
logic signed [DATA_WIDTH:0] diff;
logic signed [DATA_WIDTH:0] y_eff;
logic [DATA_WIDTH-1:0] y_prev;
logic [DATA_WIDTH-1:0] y;

assign magnitude = i_data[DATA_WIDTH-1] ? -i_data : i_data;
assign diff = $signed({1'b0,magnitude}) - $signed({1'b0,y_prev});
assign y_eff = $signed({1'b0,y_prev}) + (diff >>> K);

always @(posedge i_clk) begin 
    if (i_rst) begin 
        y <= '0;
        y_prev <= '0;
    end else if (new_data) begin 
        y <= y_eff[DATA_WIDTH-1:0];
        y_prev <= y;
    end
end

// Detect places where envelope exceeds threshold
assign active = y >= THRESHOLD;

endmodule