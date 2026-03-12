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
  input i_rd_en,
  input [DATA_WIDTH-1:0] i_wr_data,
  input i_inc_rd_ptr, // increment rd_ptr by 1
  input [9:0] i_rd_addr, // 0-1024, translated to real address in buffer
  output reg [DATA_WIDTH-1:0] o_rd_data,
  output reg o_data_vld
);
  localparam SEGMENT_SIZE = 256;
  localparam NUM_SEGMENTS = 5;
  localparam BUFFER_SIZE = SEGMENT_SIZE * NUM_SEGMENTS;
  localparam SEG4_BASE = 1024;

  logic [DATA_WIDTH-1:0] buffer [0:1279]; // 1280 data points, 16 bits per data point

  logic [10:0] wr_ptr, rd_ptr;

  always_ff @(posedge clk) begin
    if (rst) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
      o_rd_data <= '0;
      o_data_vld <= 0;
    end else begin
      o_data_vld <= 0;
      if (i_inc_rd_ptr) begin
        rd_ptr <= rd_ptr == SEG4_BASE ? 0 : rd_ptr + SEGMENT_SIZE;
      end
      if (i_wr_en) begin
        buffer[wr_ptr] <= i_wr_data;
        wr_ptr <= wr_ptr == BUFFER_SIZE - 1 ? 0 : wr_ptr + 1;
      end
      if (i_rd_en) begin
        o_rd_data <= buffer[(i_rd_addr + rd_ptr) >= BUFFER_SIZE ? (i_rd_addr + rd_ptr) - BUFFER_SIZE : (i_rd_addr + rd_ptr)];
        o_data_vld <= 1;
      end
    end
  end

endmodule