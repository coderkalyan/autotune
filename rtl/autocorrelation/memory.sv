module memory #(
  parameter DATA_WIDTH = 16,
  parameter ADDR_WIDTH = 10
)(
  input clk,
  input wr,
  input rd,
  input [DATA_WIDTH-1:0] data_in,
  input [ADDR_WIDTH-1:0] addr_1, // writes to addr_1 only, not addr_2
  input [ADDR_WIDTH-1:0] addr_2,
  output [DATA_WIDTH-1:0] reg data_out_1,
  output [DATA_WIDTH-1:0] reg data_out_2,
  output reg data_valid
);

logic [DATA_WIDTH-1:0] mem [0:2**ADDR_WIDTH-1];

always_ff @(posedge clk) begin
  data_valid <= 0;
  if (wr) begin
    mem[addr_1] <= data_in;
  end
  if (rd) begin
    data_out_1 <= mem[addr_1];
    data_out_2 <= mem[addr_2];
    data_valid <= 1;
  end
end

endmodule