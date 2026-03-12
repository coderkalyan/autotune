// Circular buffer for incoming data from the ADC
// 256 data points per segment, 5 segments per buffer
// 16 bit depth per data point
// 11 bits needed to address 1280 data points
module circular_buffer #(
  parameter P24_BIT = 1,  
  parameter int DATA_WIDTH = (P24_BIT ? 24 : 16)
)(
  input clk,
  input rst,
  input i_wr_en,
  input [DATA_WIDTH-1:0] i_wr_data,
  input i_inc_rd_ptr, // increment rd_ptr by 1
  input [9:0] i_rd_addr, // 0-1024, translated to real address in buffer
  output reg [DATA_WIDTH-1:0] o_data
);
  localparam SEGMENT_SIZE = 256;
  localparam NUM_SEGMENTS = 5;
  localparam BUFFER_SIZE = SEGMENT_SIZE * NUM_SEGMENTS;
  localparam SEG4_BASE = 1024;
  
  logic [10:0] wr_ptr, rd_ptr, rd_addr;

  `ifdef SIM
  memory #(
    .P24_BIT(P24_BIT),
    .ADDR_WIDTH(11)
  ) memory_inst (
    .i_clk(clk),
    .i_data(i_wr_data),
    .i_wr_addr(wr_ptr),
    .i_rd_addr(rd_addr),
    .i_wr_en(i_wr_en),
    .o_data(o_data)
  );
  `else
  generate
    if (P24_BIT) begin
      bram_24_2k bram_24_2k_inst (
        .clock(clk),
        .data(i_wr_data),
        .rdaddress(rd_addr),
        .wraddress(wr_ptr),
        .wren(i_wr_en),
        .q(o_data)
      );
    end else begin
      bram_16_2k bram_16_2k_inst (
        .clock(clk),
        .data(i_wr_data),
        .rdaddress(rd_addr),
        .wraddress(wr_ptr),
        .wren(i_wr_en),
        .q(o_data)
      );
    end
  endgenerate
  `endif

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
    end else begin
      if (i_inc_rd_ptr) begin
        rd_ptr <= rd_ptr == SEG4_BASE ? 0 : rd_ptr + SEGMENT_SIZE;
      end
      if (i_wr_en) begin
        wr_ptr <= wr_ptr == BUFFER_SIZE - 1 ? 0 : wr_ptr + 1;
      end
    end
  end

  always_comb begin
    rd_addr = (i_rd_addr + rd_ptr) >= BUFFER_SIZE ? (i_rd_addr + rd_ptr) - BUFFER_SIZE : (i_rd_addr + rd_ptr);
  end

endmodule