module memory #(
  parameter P24_BIT = 1,
  parameter int DATA_WIDTH = (P24_BIT ? 24 : 16),
  parameter int ADDR_WIDTH = 10
)(
  input  logic                  i_clk,
  input  logic                  i_wr_en,
  input  logic [DATA_WIDTH-1:0] i_data,
  input  logic [ADDR_WIDTH-1:0] i_wr_addr,
  input  logic [ADDR_WIDTH-1:0] i_rd_addr,
  output logic [DATA_WIDTH-1:0] o_data
);

  // Simple synchronous read/write memory model
  logic [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

  always_ff @(posedge i_clk) begin
    if (i_wr_en) begin
      mem[i_wr_addr] <= i_data;
    end
    o_data <= mem[i_rd_addr];
  end

endmodule
